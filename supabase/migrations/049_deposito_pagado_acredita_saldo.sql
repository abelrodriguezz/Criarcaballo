-- ============================================================
-- MIGRACIÓN 049: marcar un depósito como pagado ahora SÍ acredita el
-- saldo de inversión (por el monto exacto del depósito)
-- Pegar en Supabase → SQL Editor → Run (después de 001-048)
--
-- Aclaración del usuario: como las cuentas nuevas arrancan en $0
-- (migración 044), el flujo real es: el usuario deposita (por fuera de
-- la plataforma, a la wallet mostrada) → registra el depósito en la
-- app → el admin ve la notificación en /depositos → confirma que el
-- dinero llegó de verdad → lo marca "pagado" → RECIÉN AHÍ se le acredita
-- ese monto exacto a su saldo_virtual. Antes "pagado" solo cambiaba el
-- badge, no tocaba el saldo.
--
-- La validación de "un depósito por usuario en toda su existencia" ya
-- existe desde la migración 026 (constraint UNIQUE en usuario_id) — no
-- hace falta agregar nada ahí, ya está.
--
-- Nueva RPC (reemplaza el UPDATE directo que hacía
-- BotonPagoDeposito.tsx): marca el depósito Y ajusta el saldo en la
-- misma transacción (todo o nada), con "for update" para que dos admins
-- tocando el mismo depósito a la vez no puedan acreditar el saldo dos
-- veces.
--
-- Nota: si un admin marca "pagado" y luego se arrepiente y lo vuelve a
-- "pendiente", se le RESTA ese monto al saldo (con greatest(0, ...) para
-- no dejarlo negativo) — si el usuario ya operó con ese dinero, esto
-- simplemente le baja el saldo actual hasta el límite de lo que le
-- queda, no revierte las operaciones ya hechas. Usar el des-marcado con
-- cuidado, igual que ya aplica para admin_agregar_saldo.
-- ============================================================

create or replace function public.admin_alternar_pago_deposito(p_deposito_id uuid)
returns public.depositos_simulados as $$
declare
  v_admin_id uuid := auth.uid();
  v_deposito public.depositos_simulados;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un deposito como pagado.';
  end if;

  select * into v_deposito
  from public.depositos_simulados
  where id = p_deposito_id
  for update;

  if v_deposito.id is null then
    raise exception 'Deposito no encontrado.';
  end if;

  if v_deposito.pagado then
    update public.depositos_simulados
    set pagado = false, pagado_en = null, pagado_por = null
    where id = p_deposito_id
    returning * into v_deposito;

    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - v_deposito.monto),
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  else
    update public.depositos_simulados
    set pagado = true, pagado_en = now(), pagado_por = v_admin_id
    where id = p_deposito_id
    returning * into v_deposito;

    update public.saldo_virtual
    set saldo_usd = saldo_usd + v_deposito.monto,
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  end if;

  return v_deposito;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_alternar_pago_deposito(uuid) from public, anon;
grant execute on function public.admin_alternar_pago_deposito(uuid) to authenticated;
