-- ============================================================
-- MIGRACIÓN 016: Resultado de señales (TP/SL)
-- Pegar en Supabase → SQL Editor → Run (después de 001-015)
--
-- Antes solo existía "estado" (activa/cerrada/cancelada), sin distinguir
-- SI se cerró por dar en el take profit, en el stop loss, o por otra
-- razón. Esta columna separa eso, para poder mostrar "Señales recientes"
-- vs "Señales que tocaron TP o SL" como dos secciones distintas.
-- ============================================================

alter table public.senales
  add column resultado text check (resultado in ('tp', 'sl') or resultado is null);
