-- ============================================================
-- MIGRACIÓN 005: es_admin() debe exigir cuenta activa
-- Pegar en Supabase → SQL Editor → Run (después de 001, 002, 003 y 004)
--
-- Bug corregido: antes, desactivar a un admin (activo = false) no le
-- quitaba realmente los privilegios de admin a nivel de base de datos —
-- solo lo sacaba de un par de pantallas protegidas. Como todas las
-- políticas de señales, noticias, config_portada, pick_del_dia y
-- mensajes_soporte dependen de es_admin(), este único cambio corrige el
-- problema en todos lados a la vez.
-- ============================================================

create or replace function public.es_admin()
returns boolean as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid() and role = 'admin' and activo = true
  );
$$ language sql security definer;
