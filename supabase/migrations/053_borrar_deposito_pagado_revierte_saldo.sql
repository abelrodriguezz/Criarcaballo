-- ============================================================
-- MIGRACIÓN 053: borrar un depósito ya pagado también revierte el saldo
-- Pegar en Supabase → SQL Editor → Run (después de 001-052)
--
-- Hallazgo del QA (2026-09-25): borrar un depósito ya pagado desde
-- Gestión de usuarios (BotonEliminarAdmin.tsx, ya existía) no le
-- restaba el saldo que se le había acreditado, Y además liberaba el
-- constraint UNIQUE(usuario_id) — el usuario podía volver a registrar
-- un depósito y que se lo pagaran otra vez.
--
-- Fix: un trigger AFTER DELETE que, si el depósito borrado estaba
-- pagado, hace exactamente lo mismo que ya hace "revertir a pendiente"
-- en admin_alternar_pago_deposito (migración 050): resta el monto del
-- saldo (con greatest(0, ...)) y borra la comisión de referido
-- correspondiente si seguía sin pagar. Uno pagado al invitador no se
-- toca, mismo criterio de siempre.
-- ============================================================

create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
begin
  if old.pagado then
    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;

    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists on_deposito_borrado_revertir_saldo on public.depositos_simulados;
create trigger on_deposito_borrado_revertir_saldo
  after delete on public.depositos_simulados
  for each row
  execute procedure public.revertir_saldo_al_borrar_deposito();
