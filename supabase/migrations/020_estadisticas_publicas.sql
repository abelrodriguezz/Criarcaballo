-- ============================================================
-- MIGRACIÓN 020: Estadísticas públicas de la portada
-- Pegar en Supabase → SQL Editor → Run (después de 001-019)
--
-- La portada (/) muestra conteos reales (operaciones simuladas, señales
-- publicadas, usuarios registrados) para un visitante ANÓNIMO — pero las
-- políticas RLS de "usuarios" y "operaciones_simuladas" solo dejan ver
-- las propias filas (o todas, si sos admin). Sin esta función, cualquiera
-- que no haya iniciado sesión ve "0" en vez del conteo real, porque RLS
-- filtra todo antes de que el SELECT llegue a contar nada.
--
-- Esta función solo expone TOTALES agregados (nunca filas ni datos
-- individuales), así que es seguro que la lea cualquiera, con o sin
-- sesión.
-- ============================================================

create or replace function public.estadisticas_publicas()
returns table (
  operaciones bigint,
  senales bigint,
  usuarios bigint
) as $$
  select
    (select count(*) from public.operaciones_simuladas),
    (select count(*) from public.senales),
    (select count(*) from public.usuarios);
$$ language sql security definer stable;

grant execute on function public.estadisticas_publicas() to anon, authenticated;
