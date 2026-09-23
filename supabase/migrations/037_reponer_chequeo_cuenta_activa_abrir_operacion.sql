-- ============================================================
-- MIGRACIÓN 037: repone el chequeo de cuenta activa en abrir_operacion,
-- perdido sin querer en la migración 032
-- Pegar en Supabase → SQL Editor → Run (después de 001-036)
--
-- Encontrado en QA de Fase 2 (perfil y datos personales), al revisar de
-- dónde sale el saldo que se muestra en /perfil: la migración 021 agregó
-- a abrir_operacion() la validación "if v_activo is not true then raise
-- exception 'Tu cuenta está desactivada.'" — motivada por el mismo
-- razonamiento que ya protege a mensajes_soporte y favoritos (una cuenta
-- desactivada solo lo está de verdad si también lo está a nivel de base,
-- no solo en las páginas de Next.js).
--
-- La migración 030 reescribió cerrar_operacion/admin_cerrar_operacion pero
-- no tocó abrir_operacion. La migración 032 sí volvió a escribir
-- abrir_operacion completa (para forzar el monto al saldo íntegro) —y al
-- hacerlo con un "create or replace" partiendo de una copia vieja del
-- cuerpo de la función, se le perdió por completo la variable v_activo y
-- su chequeo. Quedó re-verificado contra la base real: con la anon key y
-- una sesión de un usuario con activo=false, el RPC abrir_operacion
-- completaba sin error y abría la operación igual, saltándose por
-- completo el estado de la cuenta — el mismo tipo de bypass que la
-- migración 021 ya había cerrado para el resto de la escritura de datos.
--
-- Fix: se repone el chequeo, sin tocar nada más del comportamiento de la
-- migración 032 (sigue operando siempre con el saldo completo).
-- ============================================================

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
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

revoke execute on function public.abrir_operacion(text, text, numeric, numeric, text) from public, anon;
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text) to authenticated;
