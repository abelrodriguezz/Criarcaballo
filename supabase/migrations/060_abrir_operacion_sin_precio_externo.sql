-- ============================================================
-- MIGRACIÓN 060: abrir una operación ya no depende de ningún precio
-- externo (ni Binance ni ningún otro) — el precio de entrada lo fija el
-- admin al cerrar
-- Pegar en Supabase → SQL Editor → Run (después de 001-059)
--
-- Pedido explícito del usuario (2026-09-27/28): el pick del día ahora puede
-- ser CUALQUIER activo (acciones, forex, materias primas — no solo cripto,
-- ver AdminPickForm.tsx sin validación de Binance). Pero abrir_operacion()
-- seguía yendo a buscar el precio en vivo a Binance (paperTrading.ts,
-- obtenerPrecioCripto) para fijar precio_entrada -- eso fallaba con
-- "No se pudo obtener el precio de GOLDUSD" para cualquier pick que no
-- fuera un par real de Binance.
--
-- Desde la migración 056, el precio de entrada YA NO es autoritativo al
-- abrir: el admin lo reemplaza por completo al cerrar (recalcula cantidad
-- y ganancia desde cero con SU precio de entrada, no con el capturado al
-- abrir). O sea que ir a buscar un precio en vivo al abrir era trabajo que
-- ya no servía para nada al final -- se elimina esa dependencia entera.
--
-- precio_entrada y cantidad pasan a ser NULLABLE: en el momento de abrir
-- se guardan como null (todavía no hay un precio de verdad), y
-- admin_cerrar_operacion (migración 056) los llena con los valores reales
-- al cerrar. Nunca se leen los valores viejos de open-time en el cierre
-- (solo usa monto_usado y tipo), así que esto no afecta el cálculo de
-- ganancias en absoluto.
-- ============================================================

alter table public.operaciones_simuladas
  alter column precio_entrada drop not null,
  alter column cantidad drop not null;

drop function if exists public.abrir_operacion(text, text, numeric, numeric, text);

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
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  -- precio_entrada y cantidad quedan en null: el admin los fija al cerrar
  -- (admin_cerrar_operacion, migración 056), que recalcula todo desde cero
  -- sin leer estos valores. monto_usado sí queda fijo desde ya, es lo que
  -- ese usuario invirtió y lo que usa el cierre para calcular su ganancia.
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

revoke execute on function public.abrir_operacion(text, text, numeric, text) from public, anon;
grant execute on function public.abrir_operacion(text, text, numeric, text) to authenticated;
