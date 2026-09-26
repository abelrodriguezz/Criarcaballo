-- ============================================================
-- MIGRACIÓN 051: totales del dashboard del admin sumados en la base
-- Pegar en Supabase → SQL Editor → Run (después de 001-050)
--
-- Encontrado en QA (2026-09-25): /perfil del admin traía TODAS las filas
-- de saldo_virtual (y de ganancias de hoy) y las sumaba en JS. PostgREST
-- corta cualquier select en 1000 filas (max_rows de Supabase) sin avisar,
-- así que con más de 1000 usuarios el "Total en cuentas de inversión"
-- habría salido más bajo de lo real, en silencio. Se suma aquí.
--
-- security invoker: respeta la RLS de siempre (el admin ve todas las
-- filas; si un usuario normal la llamara, solo sumaría las suyas).
-- ============================================================

create or replace function public.admin_totales_dashboard(
  p_inicio timestamptz,
  p_fin timestamptz
)
returns table (total_cuentas numeric, total_a_pagar_hoy numeric)
language sql
stable
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
  select
    (select coalesce(sum(saldo_usd), 0) from public.saldo_virtual),
    (select coalesce(sum(monto), 0)
       from public.ganancias_concursos
      where origen = 'trade'
        and pagado = false
        and created_at >= p_inicio
        and created_at < p_fin);
$$;

revoke all on function public.admin_totales_dashboard(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_totales_dashboard(timestamptz, timestamptz) to authenticated;
