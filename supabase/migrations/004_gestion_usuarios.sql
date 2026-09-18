-- ============================================================
-- MIGRACIÓN 004: Gestión de usuarios (activar/desactivar)
-- Pegar en Supabase → SQL Editor → Run (después de 001, 002 y 003)
-- ============================================================

alter table public.usuarios
  add column activo boolean not null default true;

-- La política de UPDATE que ya existía solo dejaba a cada quien editar su
-- propio registro. Se reemplaza para que el admin también pueda actualizar
-- (activar/desactivar, cambiar rol) el registro de cualquier usuario.
drop policy if exists "cada usuario edita su propio registro" on public.usuarios;

create policy "cada usuario edita el suyo, admin edita cualquiera"
  on public.usuarios for update
  using (auth.uid() = id or public.es_admin());
