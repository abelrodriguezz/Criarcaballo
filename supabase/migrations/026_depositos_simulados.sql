-- ============================================================
-- MIGRACIÓN 026: Registro del depósito simulado (una vez por usuario)
-- Pegar en Supabase → SQL Editor → Run (después de 001-025)
--
-- El botón "Depositar (simulación)" del perfil no movía ni guardaba nada
-- — solo mostraba un mensaje. Ahora sí queda registrado para que el admin
-- lo vea en Gestión de usuarios. El unique(usuario_id) es lo que impone
-- "una sola simulación por usuario": un segundo intento de insertar falla
-- solo, sin necesitar lógica aparte — para repetirla, el admin borra la
-- fila y el usuario puede volver a intentarlo.
-- ============================================================

create table public.depositos_simulados (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  monto numeric not null check (monto > 0),
  wallet_mostrada text,
  created_at timestamptz not null default now(),
  constraint depositos_simulados_usuario_id_key unique (usuario_id)
);

create index on public.depositos_simulados (usuario_id);

alter table public.depositos_simulados enable row level security;

-- Lectura: el propio usuario ve la suya, el admin ve todas.
create policy "usuario ve su deposito simulado, admin ve todos"
  on public.depositos_simulados for select
  using (usuario_id = auth.uid() or public.es_admin());

-- El propio usuario registra su única simulación (el unique de arriba
-- bloquea la segunda). Un admin no necesita insertar aquí.
create policy "usuario registra su propia simulacion"
  on public.depositos_simulados for insert
  with check (usuario_id = auth.uid() and not public.es_admin());

-- Solo el admin puede eliminarla (para permitir que el usuario repita).
create policy "solo admin elimina simulacion"
  on public.depositos_simulados for delete
  using (public.es_admin());
