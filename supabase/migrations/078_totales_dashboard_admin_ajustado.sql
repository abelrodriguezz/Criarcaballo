-- ============================================================
-- MIGRACIÓN 078: ajusta admin_totales_dashboard (migración 051)
-- Pegar en Supabase → SQL Editor → Run (después de 001-077)
--
-- Tres decisiones del dueño del proyecto tras el QA de Perfil de admin
-- (2026-09-29):
--
-- 1) "Total a pagar hoy" solo sumaba ganancias con origen='trade' — deja
--    fuera bonos de concurso y comisiones de referido. Ahora suma
--    cualquier origen, siempre que siga sin pagar.
--
-- 2) La fecha usada para "hoy" no coincidía con la de Reportes (migración
--    074): el dashboard usaba ganancias_concursos.created_at (el momento
--    real en que se registró la fila) y Reportes usa
--    operaciones_simuladas.cerrado_en (la hora de cierre que el admin
--    escribe a mano, que puede quedar en el pasado). Ahora las dos
--    pantallas usan el mismo criterio: para ganancias de trade (tienen
--    operacion_id), se usa el cerrado_en de esa operación; para las que no
--    vienen de una operación (concurso, referido — no tienen operacion_id),
--    se sigue usando su propio created_at, que es lo único que tiene
--    sentido para ellas.
--
-- 3) "Total en cuentas" sumaba TODAS las filas de saldo_virtual, incluida
--    la del propio admin (que no opera, ese número no significa nada) y
--    las de cuentas desactivadas (que sí se mantienen, no se excluyen).
--    Ahora excluye únicamente las cuentas con role='admin'.
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
    (select coalesce(sum(sv.saldo_usd), 0)
       from public.saldo_virtual sv
       join public.usuarios u on u.id = sv.usuario_id
      where u.role <> 'admin'),
    (select coalesce(sum(g.monto), 0)
       from public.ganancias_concursos g
       left join public.operaciones_simuladas o on o.id = g.operacion_id
      where g.pagado = false
        and coalesce(o.cerrado_en, g.created_at) >= p_inicio
        and coalesce(o.cerrado_en, g.created_at) < p_fin);
$$;
