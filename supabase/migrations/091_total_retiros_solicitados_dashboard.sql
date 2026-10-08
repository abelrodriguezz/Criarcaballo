-- ============================================================
-- MIGRACIÓN 091: agrega "Retiros solicitados" al dashboard del admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-090)
--
-- Pedido del dueño del proyecto (2026-10-08): en /perfil (vista de admin),
-- debajo de "Ganancias de hoy sin pagar", agregar cuánto dinero suman las
-- solicitudes de retiro PENDIENTES — para que el admin vea de un vistazo
-- cuánto le han pedido retirar sin tener que entrar a /retiros.
--
-- Se extiende admin_totales_dashboard (migración 078) con una tercera
-- columna, mismo patrón de "security invoker" (el admin ya tiene SELECT
-- sobre solicitudes_retiro vía RLS, migración 041 — no hace falta
-- definer).
-- ============================================================

-- create or replace no permite cambiar las columnas de salida de una
-- función existente ("cannot change return type") — hay que borrarla y
-- volver a crearla.
drop function if exists public.admin_totales_dashboard(timestamptz, timestamptz);

create function public.admin_totales_dashboard(
  p_inicio timestamptz,
  p_fin timestamptz
)
returns table (
  total_cuentas numeric,
  total_a_pagar_hoy numeric,
  total_retiros_solicitados numeric
)
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
        and coalesce(o.cerrado_en, g.created_at) < p_fin),
    (select coalesce(sum(sr.monto), 0)
       from public.solicitudes_retiro sr
      where sr.estado = 'pendiente');
$$;
