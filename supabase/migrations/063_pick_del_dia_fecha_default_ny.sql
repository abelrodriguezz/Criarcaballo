-- ============================================================
-- MIGRACIÓN 063: el valor por defecto de pick_del_dia.fecha es el día de
-- Nueva York, no el día UTC
-- Pegar en Supabase → SQL Editor → Run (después de 001-062)
--
-- Hallazgo de QA (2026-09-28): desde la migración 062 el pick "vigente" es
-- el que tiene fecha = hoy en Nueva York. Pero la columna seguía con
-- `default current_date`, y la base corre en UTC: cualquier pick insertado
-- sin fecha explícita (desde el SQL Editor, un script de soporte, etc.)
-- entre las 8pm y medianoche hora de NY (7pm-medianoche en invierno)
-- quedaba fechado MAÑANA y no aparecía como vigente hoy. La pantalla de
-- admin (AdminPickForm) ya manda la fecha NY explícita, esto cubre el
-- resto de los caminos.
-- ============================================================

alter table public.pick_del_dia
  alter column fecha set default ((now() at time zone 'America/New_York')::date);
