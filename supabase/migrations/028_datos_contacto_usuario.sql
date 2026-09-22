-- ============================================================
-- MIGRACIÓN 028: nombre y teléfono de contacto (opcionales)
-- Pegar en Supabase → SQL Editor → Run (después de 001-027)
--
-- El registro nunca pidió nombre ni apellido (decisión ya tomada desde la
-- migración 006: el formulario de alta se mantiene mínimo — email y
-- contraseña — y todo lo demás se completa después en Perfil, igual que
-- la wallet). Se agregan estas dos columnas nullable; ninguna es
-- obligatoria. No hace falta tocar proteger_columnas_sensibles_usuarios()
-- porque esa función es una lista negra — cualquier columna que no esté
-- ahí ya se puede autoeditar bajo la política de RLS existente
-- ("cada usuario edita el suyo, admin edita cualquiera").
-- ============================================================

alter table public.usuarios
  add column nombre text,
  add column telefono text;

-- Topes de largo por si alguien llama la API directo saltándose el
-- formulario — sin esto, nada impide guardar un texto de varios MB.
alter table public.usuarios
  add constraint nombre_largo_razonable
  check (nombre is null or length(nombre) <= 100);

alter table public.usuarios
  add constraint telefono_largo_razonable
  check (telefono is null or length(telefono) <= 30);
