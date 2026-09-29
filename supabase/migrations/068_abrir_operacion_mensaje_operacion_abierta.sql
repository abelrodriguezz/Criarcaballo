-- ============================================================
-- MIGRACIÓN 068: abrir_operacion avisa "ya tienes una operación abierta"
-- en vez de "saldo insuficiente" cuando el usuario ya tiene una abierta
-- Pegar en Supabase → SQL Editor → Run (después de 001-067)
--
-- Bug encontrado en QA de Trade del día (2026-09-29): abrir una operación
-- usa SIEMPRE el saldo completo (migración 032), así que después de abrir
-- una el saldo queda en $0. El chequeo de saldo iba ANTES del de
-- "operación abierta", por lo que un segundo intento (otra pestaña, doble
-- clic tardío, página vieja) siempre respondía "Saldo virtual
-- insuficiente." -- el usuario pensaba que había perdido su dinero en vez
-- de entender que ya tiene una operación en curso. El chequeo de
-- "operación abierta" nunca llegaba a ejecutarse en la práctica.
--
-- Arreglo: mismo cuerpo que la 065, solo se invierte el orden -- primero
-- se bloquea la fila de saldo (igual que antes, para serializar
-- peticiones simultáneas del mismo usuario), después se revisa si ya hay
-- una operación abierta, y recién después el saldo. El mensaje ya no dice
-- "Ciérrala primero": el usuario no puede cerrar operaciones, las liquida
-- el admin en bloque.
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
  v_pick text;
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

  select activo into v_pick
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    -- Valores inválidos (vacío, "abc", "25:00", días fuera de 1-7, tipos
    -- raros) caen al valor por defecto de ESE campo en vez de reventar el
    -- cast -- la misma regla que normalizarHorario() en
    -- lib/config-horario-mercado.ts, para que la UI y la base nunca
    -- discrepen sobre si el mercado está abierto.
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

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  -- Antes del chequeo de saldo: con una operación abierta el saldo SIEMPRE
  -- está en $0 (se usa completo), así que al revés este mensaje nunca salía.
  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Podrás abrir otra cuando el admin cierre la sesión.';
  end if;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
