-- ============================================================
-- MIGRACIÓN 009: Estado de pago de ganancias
-- Pegar en Supabase → SQL Editor → Run (después de 001-008)
--
-- Antes, toda fila en ganancias_concursos representaba un premio ya
-- pagado por fuera. Ahora una ganancia nace "pendiente" y el admin la
-- marca como "pagada" cuando efectivamente transfiere el USDT a la
-- wallet del usuario. El saldo pendiente que ve el usuario es la suma
-- de sus ganancias con pagado = false.
-- ============================================================

alter table public.ganancias_concursos
  add column pagado boolean not null default false,
  add column pagado_en timestamptz;

-- Las ganancias registradas antes de esta migración ya se habían
-- pagado por fuera de la plataforma (así funcionaba el flujo hasta
-- ahora), así que se marcan como pagadas para no alterar saldos ya
-- liquidados.
update public.ganancias_concursos
set pagado = true,
    pagado_en = created_at
where pagado = false;
