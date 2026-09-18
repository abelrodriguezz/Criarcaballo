-- ============================================================
-- MIGRACIÓN 003: Chat de soporte (usuario <-> admin)
-- Pegar en Supabase → SQL Editor → Run (después de 001 y 002)
-- ============================================================

create table public.mensajes_soporte (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios(id) on delete cascade, -- dueño de la conversación (el usuario, no el admin)
  remitente_id uuid not null references public.usuarios(id), -- quién escribió este mensaje puntual
  contenido text not null,
  -- leido_admin: ¿algún admin ya vio este mensaje? Solo es relevante para
  -- mensajes escritos por el usuario (los del admin nacen ya "leídos" por admin).
  leido_admin boolean not null default false,
  -- leido_usuario: ¿el usuario ya vio este mensaje? Solo relevante para
  -- mensajes escritos por el admin (los del usuario nacen ya "leídos" por él mismo).
  leido_usuario boolean not null default false,
  created_at timestamptz not null default now()
);

create index on public.mensajes_soporte (usuario_id, created_at);

alter table public.mensajes_soporte enable row level security;

-- Lectura: el dueño de la conversación, o cualquier admin.
create policy "usuario ve su conversacion, admin ve todas"
  on public.mensajes_soporte for select
  using (usuario_id = auth.uid() or public.es_admin());

-- Escritura: solo puedes enviar como tú mismo, y solo en tu propia
-- conversación (si eres usuario normal) o en cualquiera (si eres admin).
create policy "enviar mensaje propio, en conversacion propia o si es admin"
  on public.mensajes_soporte for insert
  with check (
    remitente_id = auth.uid()
    and (usuario_id = auth.uid() or public.es_admin())
  );

-- Actualización: para marcar mensajes como leídos.
create policy "marcar como leido en conversacion propia o si es admin"
  on public.mensajes_soporte for update
  using (usuario_id = auth.uid() or public.es_admin());

-- Habilita Realtime para esta tabla (mensajes nuevos llegan sin recargar).
alter publication supabase_realtime add table public.mensajes_soporte;
