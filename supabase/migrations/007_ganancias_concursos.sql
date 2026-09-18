-- ============================================================
-- MIGRACIÓN 007: Ganancias de concursos
-- Pegar en Supabase → SQL Editor → Run (después de 001-006)
--
-- Historial de premios pagados manualmente por el admin (vía la wallet
-- registrada en el perfil). No mueve dinero real dentro de la plataforma
-- — solo deja constancia de lo que ya se pagó por fuera, para que el
-- usuario lo vea reflejado.
-- ============================================================

create table public.ganancias_concursos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  monto numeric not null check (monto > 0),
  concepto text, -- ej. "Concurso de trading — enero 2026"
  creado_por uuid references public.usuarios(id),
  created_at timestamptz not null default now()
);

create index on public.ganancias_concursos (usuario_id, created_at);

alter table public.ganancias_concursos enable row level security;

-- Lectura: el propio usuario ve las suyas, el admin ve todas.
create policy "usuario ve sus ganancias, admin ve todas"
  on public.ganancias_concursos for select
  using (usuario_id = auth.uid() or public.es_admin());

-- Solo el admin puede agregar, editar o eliminar entradas.
create policy "solo admin agrega ganancias"
  on public.ganancias_concursos for insert
  with check (public.es_admin());

create policy "solo admin edita ganancias"
  on public.ganancias_concursos for update
  using (public.es_admin());

create policy "solo admin elimina ganancias"
  on public.ganancias_concursos for delete
  using (public.es_admin());
