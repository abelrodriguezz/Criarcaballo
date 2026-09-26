-- ============================================================
-- MIGRACIÓN 048: estado "pagado" en depósitos (separado de "revisado")
-- Pegar en Supabase → SQL Editor → Run (después de 001-047)
--
-- "revisado_por_admin" (migración 047) solo dice que el admin YA VIO el
-- depósito — no que ya le acreditó el saldo correspondiente a mano en
-- Gestión de usuarios. Se agrega un estado separado para eso, mismo
-- patrón que ya usan ganancias_concursos y solicitudes_retiro
-- (pagado/pagado_en/pagado_por).
-- ============================================================

alter table public.depositos_simulados
  add column if not exists pagado boolean not null default false,
  add column if not exists pagado_en timestamptz,
  add column if not exists pagado_por uuid references public.usuarios(id);

-- La policy de UPDATE de la migración 047 ya es "solo admin, cualquier
-- columna" (using/with check es_admin()), así que estas columnas nuevas
-- quedan cubiertas sin necesitar una policy aparte.
