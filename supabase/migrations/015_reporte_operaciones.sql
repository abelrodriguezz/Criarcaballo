-- ============================================================
-- MIGRACIÓN 015: Reporte de operaciones por día (admin)
-- Pegar en Supabase → SQL Editor → Run (después de 001-014)
--
-- Agrega, por usuario, cuántas operaciones abrió y su ganancia/pérdida
-- neta (solo de las cerradas) dentro de un rango de fechas — usado por
-- la pantalla /usuarios/reportes para saber quién operó un día dado y
-- quién no.
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
    coalesce(sum(ganancia_perdida) filter (where estado = 'cerrada'), 0) as ganancia_neta
  from public.operaciones_simuladas
  where public.es_admin()
    and created_at >= p_inicio
    and created_at <= p_fin
  group by usuario_id;
$$ language sql security definer stable;

grant execute on function public.reporte_operaciones_por_dia(timestamptz, timestamptz) to authenticated;
