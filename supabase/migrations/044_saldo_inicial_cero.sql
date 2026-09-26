-- ============================================================
-- MIGRACIÓN 044: el saldo de inversión inicial pasa de $10,000 a $0
-- Pegar en Supabase → SQL Editor → Run (después de 001-043)
--
-- Decisión del usuario (2026-09-25): un usuario nuevo ya no arranca con
-- saldo automático. El admin se lo asigna a mano cuando corresponda,
-- usando admin_agregar_saldo() (ya existe, migraciones 013/019/038) desde
-- Gestión de usuarios. "Depositar (simulación)" se queda exactamente
-- igual que hoy — sigue siendo solo un registro informativo para la
-- comisión de referidos, no acredita saldo.
--
-- Solo afecta a cuentas NUEVAS. No se toca el saldo de nadie que ya
-- exista.
-- ============================================================

alter table public.saldo_virtual
  alter column saldo_usd set default 0;

create or replace function public.handle_new_user_saldo()
returns trigger as $$
begin
  insert into public.saldo_virtual (usuario_id, saldo_usd)
  values (new.id, 0);
  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
