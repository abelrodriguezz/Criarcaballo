-- ============================================================
-- MIGRACIÓN 082: un usuario solo puede operar cada pick UNA vez
-- Pegar en Supabase → SQL Editor → Run (después de 001-081)
--
-- Hallazgo del dueño del proyecto (2026-09-30): abrir_operacion solo
-- comparaba el SÍMBOLO del pick vigente (p.ej. "SPACE X"), nunca un id de
-- pick concreto. admin_cerrar_operacion siempre devuelve el capital
-- invertido a saldo_virtual (gane o pierda la operación, migración 030).
-- Resultado: si el admin cierra la sesión y no borra/cambia el pick de
-- inmediato, el usuario recupera su saldo completo y puede volver a abrir
-- otra operación sobre EL MISMO pick, cobrando la misma señal una y otra
-- vez mientras el pick siga vigente.
--
-- Arreglo: cada operación ahora guarda el id exacto del pick con el que se
-- abrió (pick_id). abrir_operacion bloquea una nueva apertura si el
-- usuario YA tiene cualquier operación (abierta o cerrada) con ese mismo
-- pick_id -- no depende de que el admin se acuerde de borrar el pick.
-- ============================================================

alter table public.operaciones_simuladas
  add column if not exists pick_id uuid references public.pick_del_dia(id) on delete set null;

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

  select id, activo into v_pick_id, v_pick_activo
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1;

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

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Podrás abrir otra cuando el admin cierre la sesión.';
  end if;

  -- El núcleo del arreglo: ya se operó este pick (abierta o cerrada), sin
  -- importar que el admin haya devuelto el saldo al cerrarla.
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
