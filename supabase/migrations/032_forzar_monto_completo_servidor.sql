-- ============================================================
-- MIGRACIÓN 032: abrir_operacion ignora el monto recibido y siempre usa
-- el saldo completo — cierra la superficie de ataque, no solo la UI
-- Pegar en Supabase → SQL Editor → Run (después de 001-031)
--
-- El campo de monto en el formulario ya era de solo lectura (sesión
-- anterior), pero eso es cosmético: cualquiera podía llamar el RPC o la
-- Server Action directo con un p_monto distinto al saldo completo. La
-- auditoría de hoy confirmó que era explotable (aunque de severidad baja,
-- sin forma de perjudicar al usuario ni a la plataforma) y recomendó
-- cerrarlo de raíz: se deja el parámetro p_monto en la firma para no
-- tener que tocar la Server Action que la llama, pero su valor ya NO se
-- usa para nada — la cantidad y el monto_usado siempre salen del saldo
-- real en saldo_virtual, leído aquí mismo con bloqueo de fila.
--
-- Se repite el `set search_path` fijo a propósito: la migración 030 lo
-- había perdido sin querer al reescribir esta función con
-- "create or replace" (create or replace NO conserva la config anterior),
-- y la auditoría de hoy lo encontró y ya lo corrigió en la 031. Esta
-- migración también reescribe la función, así que hay que repetirlo aquí
-- para no volver a perderlo.
-- ============================================================

drop function if exists public.abrir_operacion(text, text, numeric, numeric, text);

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric, -- ya no se usa: se opera siempre con el saldo completo
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_cantidad numeric;
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

  if p_precio is null or p_precio = 'NaN'::numeric or p_precio <= 0 then
    raise exception 'No se pudo determinar un precio de entrada válido.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
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

  select trading_habilitado into v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

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

  v_cantidad := v_saldo / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, p_precio, v_cantidad, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke execute on function public.abrir_operacion(text, text, numeric, numeric, text) from public;
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text) to authenticated;
