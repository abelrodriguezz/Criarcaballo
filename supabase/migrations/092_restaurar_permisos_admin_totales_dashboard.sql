-- ============================================================
-- MIGRACIÓN 092: restaura los permisos de admin_totales_dashboard
-- Pegar en Supabase → SQL Editor → Run (después de 001-091)
--
-- QA 2026-10-08: la migración 091 hizo DROP FUNCTION + CREATE FUNCTION
-- (necesario para cambiar las columnas de salida). Un DROP borra también
-- los GRANT/REVOKE de la función, y el CREATE nuevo vuelve a los
-- privilegios por defecto de Supabase: EXECUTE para PUBLIC y anon. Eso
-- deshizo en silencio el "revoke ... from public, anon" de la migración
-- 051. Verificado en producción tras la 091:
--   proacl = {=X/postgres, anon=X/postgres, authenticated=X/postgres, ...}
--
-- Impacto real: bajo (la función es security invoker, así que un anónimo
-- o un usuario normal solo obtiene lo que su propia RLS le deja ver — en
-- la práctica ceros o sus propios datos), pero es una regresión del
-- endurecimiento de la 051 y se restaura igual.
-- ============================================================

revoke all on function public.admin_totales_dashboard(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_totales_dashboard(timestamptz, timestamptz)
  to authenticated;
