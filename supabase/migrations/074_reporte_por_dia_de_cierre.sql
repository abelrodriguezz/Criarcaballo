-- ============================================================
-- MIGRACIÓN 074: el reporte diario cuenta por el día en que la operación
-- se CIERRA (cerrado_en), no por el día en que se abrió (created_at)
-- Pegar en Supabase → SQL Editor → Run (después de 001-073)
--
-- QA de "Reportes" (2026-09-28) encontró que reporte_operaciones_por_dia
-- (migración 015) agrupaba por created_at: una operación abierta un día y
-- cerrada al siguiente contaba (y pagaba) en el reporte del día de
-- apertura, no del día en que el admin la liquidó de verdad. Decisión del
-- dueño del proyecto: el reporte debe reflejar el día de cierre, que es
-- cuando el resultado queda definitivo. Solo se cuentan operaciones
-- CERRADAS (una abierta sin resolver no tiene ganancia que reportar).
-- ============================================================

create or replace function public.reporte_operaciones_por_dia(
  p_inicio timestamptz,
  p_fin timestamptz
) returns table (
  usuario_id uuid,
  num_operaciones bigint,
  ganancia_neta numeric
) as $$
  select
    usuario_id,
    count(*) as num_operaciones,
    coalesce(sum(ganancia_perdida), 0) as ganancia_neta
  from public.operaciones_simuladas
  where public.es_admin()
    and estado = 'cerrada'
    and cerrado_en >= p_inicio
    and cerrado_en <= p_fin
  group by usuario_id;
$$ language sql security definer stable
   set search_path = pg_catalog, public, pg_temp;
