-- ============================================================
-- MIGRACIÓN 023: campos en inglés para contenido real (no "chrome")
-- Pegar en Supabase → SQL Editor → Run (después de la migración 022)
-- ============================================================

-- La traducción ES/EN de la interfaz (nav, botones, etiquetas) ya cubre
-- toda la app, pero el CONTENIDO que escribe el admin — la razón de una
-- señal, el título/resumen de una noticia — seguía solo en el idioma en
-- que se escribió. Mismo patrón que config_portada (hero/nosotros):
-- columna "_en" opcional, con fallback al texto en español si el admin
-- no la llenó (nunca se muestra vacío ni se inventa una traducción).

alter table public.senales
  add column razon_en text;

alter table public.noticias
  add column titulo_en text,
  add column resumen_en text;
