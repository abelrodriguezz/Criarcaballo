-- ============================================================
-- MIGRACIÓN 089: abrir_operacion bloquea la fila del pick mientras abre
-- Pegar en Supabase → SQL Editor → Run (después de 001-088)
--
-- Hallazgo de QA (2026-10-05, sobre la migración 088): abrir_operacion
-- leía el nombre del pick SIN bloquear la fila. Si el admin renombraba el
-- pick (admin_editar_pick_del_dia) y confirmaba justo entre esa lectura y
-- el INSERT de la operación, el renombrado en cascada ya había corrido y
-- no veía la operación nueva, que quedaba guardada con el nombre VIEJO.
-- Resultado: el formulario de "cerrar todas las operaciones" (agrupa por
-- texto `activo`) mostraba dos grupos para la misma señal. Reproducido de
-- forma determinista en QA (sesión A estacionada en el lock de saldo,
-- sesión B renombra y confirma → operación con nombre viejo).
--
-- Arreglo: la lectura del pick es ahora `for share`. Un renombrado en
-- curso espera a que termine la apertura (y entonces su cascada SÍ ve la
-- operación nueva), o la apertura espera al renombrado y lee el nombre
-- nuevo (y rechaza el símbolo viejo con "Ese activo no es el pick del día
-- vigente.", igual que antes). Además el lock del saldo se toma ANTES que
-- el del pick, en el mismo orden que admin_cerrar_operacion (saldo → pick),
-- para que las dos funciones no puedan bloquearse mutuamente (deadlock).
--
-- Fuera de esos dos cambios, la función es idéntica a la de la 082.
-- ============================================================

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick_id uuid;
  v_pick_activo text;
  v_horario jsonb;
  v_apertura time;
  v_cierre time;
  v_dias_habiles int[];
  v_abierto_siempre boolean;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  -- Orden de locks: saldo primero, pick después (ver cabecera).
  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  select id, activo into v_pick_id, v_pick_activo
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1
  for share;

  if v_pick_id is null or upper(v_pick_activo) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    v_abierto_siempre := coalesce(v_horario->>'abierto_siempre' = 'true', false);

    if not v_abierto_siempre then
      v_apertura := case
        when v_horario->>'apertura' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'apertura')::time
        else time '09:30'
      end;
      v_cierre := case
        when v_horario->>'cierre' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'cierre')::time
        else time '16:00'
      end;
      v_dias_habiles := coalesce(
        (
          select array_agg(distinct d::int)
          from jsonb_array_elements_text(
            case when jsonb_typeof(v_horario->'dias') = 'array'
              then v_horario->'dias' else '[]'::jsonb end
          ) d
          where d ~ '^[1-7]$'
        ),
        array[1, 2, 3, 4, 5]
      );

      v_hora_ny := (now() at time zone 'America/New_York')::time;
      v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));

      if not (v_dia_semana_ny = any(v_dias_habiles))
         or v_hora_ny < v_apertura
         or v_hora_ny >= v_cierre then
        raise exception 'El mercado está cerrado en este momento.';
      end if;
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Podrás abrir otra cuando el admin cierre la sesión.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and pick_id = v_pick_id
  ) then
    raise exception 'Ya operaste el pick de hoy. Espera a que el admin publique uno nuevo.';
  end if;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado, pick_id
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta', v_pick_id
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
