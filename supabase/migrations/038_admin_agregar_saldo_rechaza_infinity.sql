-- ============================================================
-- MIGRACIÓN 038: admin_agregar_saldo rechaza también Infinity/-Infinity
-- Pegar en Supabase → SQL Editor → Run (después de 001-037)
--
-- La QA de Fase 6 (gestión de usuarios / reportes) encontró que
-- admin_agregar_saldo (013, endurecida en 019 contra 'NaN') seguía
-- aceptando p_monto = 'Infinity' llamando al RPC directo (con la sola
-- anon key, sesión de admin). El chequeo existente solo comparaba contra
-- 0 y 'NaN'::numeric, y 'Infinity' pasa ambas: no es igual a 0 ni a NaN.
-- saldo_virtual.saldo_usd es un numeric sin CHECK ni tope (a diferencia
-- de depositos_simulados.monto, ya blindado en la migración 027 con el
-- mismo problema), así que el saldo del usuario quedaba en 'Infinity' de
-- forma irrecuperable por este mismo RPC: greatest(0, Infinity + X) es
-- Infinity para cualquier X finito, así que ni siquiera restar arregla
-- el número — hay que corregirlo a mano en la base.
--
-- Arreglo, mismo patrón que la migración 027: en vez de comparar contra
-- valores especiales uno por uno, se exige que el monto cumpla un rango
-- finito. 'NaN' y 'Infinity'/'-Infinity' fallan cualquier comparación de
-- rango (evaluar a FALSE), así que quedan cubiertos sin necesidad de
-- casos especiales adicionales.
-- ============================================================

create or replace function public.admin_agregar_saldo(
  p_usuario_id uuid,
  p_monto numeric
) returns public.saldo_virtual as $$
declare
  v_saldo public.saldo_virtual;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede ajustar el saldo de otro usuario.';
  end if;

  -- p_monto <> 0 además del rango: 'NaN' no es estrictamente mayor ni
  -- menor que ningún límite (la comparación da FALSE), así que el BETWEEN
  -- ya lo descarta, pero se deja el chequeo explícito por claridad con la
  -- versión anterior. Infinity/-Infinity quedan fuera del rango.
  if p_monto is null
     or p_monto = 0
     or p_monto = 'NaN'::numeric
     or p_monto < -100000000
     or p_monto > 100000000
  then
    raise exception 'El monto debe ser un número finito y distinto de cero.';
  end if;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + p_monto),
      actualizado_en = now()
  where usuario_id = p_usuario_id
  returning * into v_saldo;

  if v_saldo.usuario_id is null then
    raise exception 'Este usuario no tiene saldo virtual inicializado.';
  end if;

  return v_saldo;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_agregar_saldo(uuid, numeric) from public, anon;
grant execute on function public.admin_agregar_saldo(uuid, numeric) to authenticated;
