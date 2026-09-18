-- ============================================================
-- ESQUEMA INICIAL: Plataforma de Mercado + Señales + Paper Trading
-- Pegar este archivo completo en Supabase → SQL Editor → Run
-- ============================================================

-- 1. Tabla de usuarios (extiende auth.users de Supabase)
create table public.usuarios (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now()
);

-- Crea automáticamente el registro en "usuarios" cuando alguien se registra
create function public.handle_new_user()
returns trigger as $$
begin
  insert into public.usuarios (id, email, role)
  values (new.id, new.email, 'user');
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. Señales / Análisis
create table public.senales (
  id uuid primary key default gen_random_uuid(),
  par text not null,
  tipo text not null check (tipo in ('compra', 'venta')),
  entrada numeric not null,
  stop_loss numeric,
  take_profit numeric,
  razon text,
  estado text not null default 'activa' check (estado in ('activa', 'cerrada', 'cancelada')),
  creado_por uuid references public.usuarios(id),
  created_at timestamptz not null default now()
);

-- 3. Noticias
create table public.noticias (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  resumen text,
  url_fuente text,
  destacada boolean not null default false,
  created_at timestamptz not null default now()
);

-- 4. Configuración de portada (editable por admin, sin tocar código)
create table public.config_portada (
  id uuid primary key default gen_random_uuid(),
  clave text unique not null,
  valor jsonb not null
);

-- 5. Favoritos del usuario
create table public.favoritos (
  usuario_id uuid references public.usuarios(id) on delete cascade,
  activo text not null,
  created_at timestamptz not null default now(),
  primary key (usuario_id, activo)
);

-- 6. Saldo virtual (paper trading)
create table public.saldo_virtual (
  usuario_id uuid primary key references public.usuarios(id) on delete cascade,
  saldo_usd numeric not null default 10000,
  actualizado_en timestamptz not null default now()
);

-- Crea saldo virtual inicial automáticamente al registrarse
create function public.handle_new_user_saldo()
returns trigger as $$
begin
  insert into public.saldo_virtual (usuario_id, saldo_usd)
  values (new.id, 10000);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_usuario_created_saldo
  after insert on public.usuarios
  for each row execute procedure public.handle_new_user_saldo();

-- 7. Operaciones simuladas (paper trading)
create table public.operaciones_simuladas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references public.usuarios(id) on delete cascade,
  activo text not null,
  tipo text not null check (tipo in ('compra', 'venta')),
  precio_entrada numeric not null,
  cantidad numeric not null,
  monto_usado numeric not null,
  precio_salida numeric,
  ganancia_perdida numeric,
  estado text not null default 'abierta' check (estado in ('abierta', 'cerrada')),
  created_at timestamptz not null default now(),
  cerrado_en timestamptz
);

-- 8. Pick del día (paper trading)
create table public.pick_del_dia (
  id uuid primary key default gen_random_uuid(),
  activo text not null,
  fecha date not null default current_date,
  nota_admin text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- ROW LEVEL SECURITY (RLS): activar en todas las tablas
-- ============================================================
alter table public.usuarios enable row level security;
alter table public.senales enable row level security;
alter table public.noticias enable row level security;
alter table public.config_portada enable row level security;
alter table public.favoritos enable row level security;
alter table public.saldo_virtual enable row level security;
alter table public.operaciones_simuladas enable row level security;
alter table public.pick_del_dia enable row level security;

-- Función helper: ¿el usuario actual es admin?
create function public.es_admin()
returns boolean as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid() and role = 'admin'
  );
$$ language sql security definer;

-- --- usuarios ---
create policy "cada usuario ve su propio registro, admin ve todos"
  on public.usuarios for select
  using (auth.uid() = id or public.es_admin());

create policy "cada usuario edita su propio registro"
  on public.usuarios for update
  using (auth.uid() = id);

-- --- senales: lectura pública, escritura solo admin ---
create policy "cualquiera puede leer señales"
  on public.senales for select
  using (true);

create policy "solo admin escribe señales"
  on public.senales for insert
  with check (public.es_admin());

create policy "solo admin edita señales"
  on public.senales for update
  using (public.es_admin());

create policy "solo admin elimina señales"
  on public.senales for delete
  using (public.es_admin());

-- --- noticias: lectura pública, escritura solo admin ---
create policy "cualquiera puede leer noticias"
  on public.noticias for select
  using (true);

create policy "solo admin escribe noticias"
  on public.noticias for insert
  with check (public.es_admin());

create policy "solo admin edita noticias"
  on public.noticias for update
  using (public.es_admin());

create policy "solo admin elimina noticias"
  on public.noticias for delete
  using (public.es_admin());

-- --- config_portada: lectura pública, escritura solo admin ---
create policy "cualquiera puede leer config"
  on public.config_portada for select
  using (true);

create policy "solo admin escribe config"
  on public.config_portada for insert
  with check (public.es_admin());

create policy "solo admin edita config"
  on public.config_portada for update
  using (public.es_admin());

-- --- favoritos: cada usuario ve/edita solo los suyos ---
create policy "usuario ve sus propios favoritos"
  on public.favoritos for select
  using (auth.uid() = usuario_id);

create policy "usuario agrega sus propios favoritos"
  on public.favoritos for insert
  with check (auth.uid() = usuario_id);

create policy "usuario elimina sus propios favoritos"
  on public.favoritos for delete
  using (auth.uid() = usuario_id);

-- --- saldo_virtual: cada usuario ve/edita solo el suyo ---
create policy "usuario ve su propio saldo"
  on public.saldo_virtual for select
  using (auth.uid() = usuario_id);

create policy "usuario actualiza su propio saldo"
  on public.saldo_virtual for update
  using (auth.uid() = usuario_id);

-- --- operaciones_simuladas: cada usuario ve/crea/edita solo las suyas ---
create policy "usuario ve sus propias operaciones"
  on public.operaciones_simuladas for select
  using (auth.uid() = usuario_id);

create policy "usuario crea sus propias operaciones"
  on public.operaciones_simuladas for insert
  with check (auth.uid() = usuario_id);

create policy "usuario cierra sus propias operaciones"
  on public.operaciones_simuladas for update
  using (auth.uid() = usuario_id);

-- --- pick_del_dia: lectura pública, escritura solo admin ---
create policy "cualquiera puede leer el pick del dia"
  on public.pick_del_dia for select
  using (true);

create policy "solo admin define el pick del dia"
  on public.pick_del_dia for insert
  with check (public.es_admin());

create policy "solo admin edita el pick del dia"
  on public.pick_del_dia for update
  using (public.es_admin());

-- ============================================================
-- Para convertir tu propio usuario en admin, después de registrarte
-- ejecuta esto una vez (cambia el correo):
--
-- update public.usuarios set role = 'admin' where email = 'tu@correo.com';
-- ============================================================
