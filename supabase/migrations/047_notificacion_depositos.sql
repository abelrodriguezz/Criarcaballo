-- ============================================================
-- MIGRACIÓN 047: notificación de depósitos nuevos para el admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-046)
--
-- Hoy los depósitos simulados solo se veían sueltos, uno por fila, dentro
-- de Gestión de usuarios — no había ni una cola centralizada ni forma de
-- saber cuáles son "nuevos" sin haber entrado a revisar cada usuario.
-- Mismo patrón que ya existe para mensajes de soporte (leido_admin): un
-- booleano que se marca true al visitar la pantalla nueva /depositos, y
-- un badge que cuenta los que siguen en false.
-- ============================================================

alter table public.depositos_simulados
  add column if not exists revisado_por_admin boolean not null default false;

create index if not exists depositos_simulados_sin_revisar
  on public.depositos_simulados (revisado_por_admin)
  where revisado_por_admin = false;

-- La tabla nunca tuvo policy de UPDATE (no hacía falta hasta ahora) —
-- sin esto, RLS deniega por defecto y el admin no podría marcar nada
-- como revisado.
create policy "solo admin marca depositos como revisados"
  on public.depositos_simulados for update
  using (public.es_admin())
  with check (public.es_admin());
