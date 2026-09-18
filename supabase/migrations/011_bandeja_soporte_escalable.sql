-- ============================================================
-- MIGRACIÓN 011: Bandeja de soporte escalable
-- Pegar en Supabase → SQL Editor → Run (después de 001-010)
--
-- La página /soporte (vista admin) traía TODOS los mensajes de TODAS las
-- conversaciones de la plataforma (sin límite) solo para calcular, en
-- JavaScript, cuántos no leídos hay por usuario. Con cientos/miles de
-- mensajes acumulados esto ya es notorio en cada carga de la página. Esta
-- función hace la agregación en la base de datos (aprovechando el índice
-- que ya existe en mensajes_soporte(usuario_id, created_at)) y devuelve
-- solo una fila por conversación.
-- ============================================================

create or replace function public.listar_conversaciones_soporte()
returns table (
  usuario_id uuid,
  email text,
  no_leidos bigint,
  primer_no_leido timestamptz,
  ultimo_mensaje timestamptz
) as $$
  select
    m.usuario_id,
    u.email,
    count(*) filter (where not m.leido_admin) as no_leidos,
    min(m.created_at) filter (where not m.leido_admin) as primer_no_leido,
    max(m.created_at) as ultimo_mensaje
  from public.mensajes_soporte m
  join public.usuarios u on u.id = m.usuario_id
  where public.es_admin()
  group by m.usuario_id, u.email;
$$ language sql security definer stable;

grant execute on function public.listar_conversaciones_soporte() to authenticated;
