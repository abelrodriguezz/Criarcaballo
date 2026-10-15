-- ============================================================
-- BUNDLE: las 102 migraciones de mercado-app, concatenadas en
-- orden numerico correcto (001 a 104).
-- Generado automaticamente -- no editar a mano, se regenera desde cero.
--
-- COMO USAR: pegar este archivo COMPLETO en Supabase -> SQL Editor -> Run,
-- contra un proyecto de Supabase NUEVO Y VACIO. Si da un error que NO sea
-- "ya existe" / "already exists", parar ahi, copiar el mensaje completo y
-- en que migracion (buscar el "=== MIGRACION NNN ===" mas cercano arriba
-- del error) y consultarlo antes de seguir.
--
-- OJO -- UNA MIGRACION DE ACA ADENTRO (100) NECESITA UN CAMBIO A MANO:
-- la migracion de "cron de cierre automatico de senales" trae hardcodeada
-- la URL del servidor de desarrollo (criarcaballo-production.up.railway.app).
-- Busca la linea que dice "url := 'https://criarcaballo-production..."
-- mas abajo en este mismo archivo (esta cerca del final) y cambiala por
-- tu propio dominio de Railway ANTES de correr este script. Si todavia
-- no tenes el dominio de Railway porque es tu primera vez desplegando,
-- corre este script igual (el resto de la app funciona bien sin esto),
-- y despues volve a correr SOLO ese bloque (es el paso 6 del checklist
-- de lanzamiento) con la URL correcta una vez que la tengas.
-- ============================================================


-- ============================================================
-- === MIGRACION 001 (001_esquema_inicial.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 002 (002_comunidad.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 002: Comunidad — código de invitación y referidos
-- Pegar en Supabase → SQL Editor → Run (después de la migración 001)
-- ============================================================

-- 1. Nuevas columnas en usuarios
alter table public.usuarios
  add column codigo_invitacion text unique,
  add column invitado_por uuid references public.usuarios(id);

-- 2. Reemplaza la función que crea el registro en "usuarios" al registrarse,
--    para que también genere el código de invitación y registre quién invitó
--    (si el registro llegó con ?ref=CODIGO).
create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
begin
  -- Genera un código corto y prácticamente único (8 caracteres)
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  -- Si el registro trae un código de referido en los metadatos, lo busca
  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por)
  values (new.id, new.email, 'user', codigo_nuevo, id_invitador);

  return new;
end;
$$ language plpgsql security definer;

-- 3. Función para contar cuántos usuarios ha invitado la persona actual,
--    SIN exponer los datos (email, etc.) de esos usuarios al front-end.
create function public.contar_invitados()
returns integer as $$
  select count(*)::int
  from public.usuarios
  where invitado_por = auth.uid();
$$ language sql security definer;

-- Por defecto Postgres ya da EXECUTE a todos los roles, pero se deja
-- explícito por si el proyecto tiene privilegios por defecto revocados.
grant execute on function public.contar_invitados() to authenticated;

-- ============================================================
-- Nota: los usuarios que ya existían antes de esta migración no tendrán
-- codigo_invitacion. Para generarles uno manualmente:
--
-- update public.usuarios
-- set codigo_invitacion = upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))
-- where codigo_invitacion is null;
-- ============================================================

-- ============================================================
-- === MIGRACION 003 (003_chat_soporte.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 004 (004_gestion_usuarios.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 005 (005_fix_es_admin_activo.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 005: es_admin() debe exigir cuenta activa
-- Pegar en Supabase → SQL Editor → Run (después de 001, 002, 003 y 004)
--
-- Bug corregido: antes, desactivar a un admin (activo = false) no le
-- quitaba realmente los privilegios de admin a nivel de base de datos —
-- solo lo sacaba de un par de pantallas protegidas. Como todas las
-- políticas de señales, noticias, config_portada, pick_del_dia y
-- mensajes_soporte dependen de es_admin(), este único cambio corrige el
-- problema en todos lados a la vez.
-- ============================================================

create or replace function public.es_admin()
returns boolean as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid() and role = 'admin' and activo = true
  );
$$ language sql security definer;

-- ============================================================
-- === MIGRACION 006 (006_wallet_recompensas.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 006: Wallet USDT (ERC20) para recompensas de concursos
-- Pegar en Supabase → SQL Editor → Run (después de 001-005)
--
-- Solo almacena la dirección para que el admin pague manualmente las
-- recompensas de concursos — no habilita depósitos ni retiros dentro
-- de la plataforma.
-- ============================================================

alter table public.usuarios
  add column wallet_usdt_erc20 text;

-- Valida el formato básico de una dirección ERC20 (0x + 40 caracteres hex)
-- para evitar que se guarde algo claramente inválido por error de tipeo.
alter table public.usuarios
  add constraint wallet_usdt_erc20_formato
  check (
    wallet_usdt_erc20 is null
    or wallet_usdt_erc20 ~ '^0x[a-fA-F0-9]{40}$'
  );

-- Se agrega también al alta automática de usuario, por si en el futuro se
-- quiere volver a ofrecer el campo directo en el registro (hoy el
-- formulario de registro lo deja para completar después en Perfil).
create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20)
  values (new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial);

  return new;
end;
$$ language plpgsql security definer;

-- ============================================================
-- === MIGRACION 007 (007_ganancias_concursos.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 008 (008_id_corto.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 008: ID corto por usuario
-- Pegar en Supabase → SQL Editor → Run (después de 001-007)
--
-- Un número corto (empieza en 100000) que cada usuario puede dar por chat
-- o decir en voz alta, en vez del UUID interno (36 caracteres, impráctico).
-- ============================================================

create sequence public.usuarios_id_corto_seq start with 100000 increment by 1;

alter table public.usuarios
  add column id_corto integer unique;

-- Actualiza el alta automática de usuario para que también asigne el ID corto.
create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20, id_corto)
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    nextval('public.usuarios_id_corto_seq')
  );

  return new;
end;
$$ language plpgsql security definer;

-- Le asigna un ID corto a los usuarios que ya existían antes de esta migración.
update public.usuarios
set id_corto = nextval('public.usuarios_id_corto_seq')
where id_corto is null;

-- ============================================================
-- === MIGRACION 009 (009_estado_pago_ganancias.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 010 (010_qa_seguridad_validaciones.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 010: Arreglos de seguridad y validación (auditoría QA)
-- Pegar en Supabase → SQL Editor → Run (después de 001-009)
--
-- Resume varios huecos encontrados en una auditoría de código:
--
-- 1) La política de UPDATE de "usuarios" no tenía "with check", así que
--    cualquier usuario autenticado podía llamar
--    supabase.from('usuarios').update({role:'admin', activo:true}) sobre
--    su propia fila desde el navegador y auto-ascenderse a admin. Se
--    corrige con un trigger que exige ser admin para tocar role/activo,
--    y que impide dejar el sistema sin ningún admin activo.
--
-- 2) Por el mismo motivo, "saldo_virtual" y "operaciones_simuladas" se
--    podían editar directo desde el cliente (RLS solo validaba el dueño
--    de la fila, no el valor). Un usuario podía ponerse saldo_usd en
--    999,999,999 a mano. Se revocan esas políticas de UPDATE/INSERT y se
--    mueve la lógica de abrir/cerrar operaciones a funciones SECURITY
--    DEFINER (abrir_operacion / cerrar_operacion) que validan todo en
--    una sola transacción atómica — esto también elimina la condición de
--    carrera de abrir dos operaciones a la vez con doble clic.
--
-- 3) Constraints que solo existían en el formulario (cliente), no en la
--    base de datos: señales con entrada <= 0, noticias con título vacío.
--
-- 4) Trazabilidad de quién marcó una ganancia como pagada.
--
-- 5) Límite de longitud en mensajes de chat (no existía ninguno).
-- ============================================================

-- --- 1) Proteger role/activo en "usuarios" ---

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
begin
  if (new.role is distinct from old.role or new.activo is distinct from old.activo)
     and not public.es_admin() then
    raise exception 'Solo un admin puede cambiar el rol o el estado de una cuenta.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists antes_de_editar_usuario on public.usuarios;
create trigger antes_de_editar_usuario
  before update on public.usuarios
  for each row execute procedure public.proteger_columnas_sensibles_usuarios();

-- --- 2) saldo_virtual / operaciones_simuladas: mover a RPC atómico ---

-- Ya nadie debe poder hacer update directo desde el cliente a estas
-- tablas — todo pasa por las funciones de abajo, que sí corren con
-- privilegios elevados y validan cada regla de negocio.
drop policy if exists "usuario actualiza su propio saldo" on public.saldo_virtual;
drop policy if exists "usuario crea sus propias operaciones" on public.operaciones_simuladas;
drop policy if exists "usuario cierra sus propias operaciones" on public.operaciones_simuladas;

-- Respaldo a nivel de base de datos: nunca más de una operación abierta
-- por usuario, ni siquiera si algo llama a estas tablas por fuera de la
-- función (defensa en profundidad).
create unique index if not exists operaciones_una_abierta_por_usuario
  on public.operaciones_simuladas (usuario_id)
  where estado = 'abierta';

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a cero.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  -- Bloquea la fila de saldo del usuario: si dos solicitudes llegan casi
  -- juntas, la segunda espera a que la primera termine, así que no puede
  -- haber doble apertura ni doble descuento del mismo saldo.
  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo < p_monto then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := p_monto / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, p_activo, p_tipo, p_precio, v_cantidad, p_monto, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = saldo_usd - p_monto, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

create or replace function public.cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id
    and usuario_id = v_usuario_id
    and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - v_operacion.precio_entrada) * v_operacion.cantidad
    else (v_operacion.precio_entrada - p_precio_salida) * v_operacion.cantidad
  end;
  -- Igual que antes: la pérdida máxima de una simulación se limita al
  -- monto arriesgado, no es una cuenta de margen real.
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = now()
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado + v_ganancia),
      actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

grant execute on function public.abrir_operacion(text, text, numeric, numeric) to authenticated;
grant execute on function public.cerrar_operacion(uuid, numeric) to authenticated;

-- --- 3) Constraints que solo vivían en el formulario ---

alter table public.senales
  add constraint senales_entrada_positiva check (entrada > 0),
  add constraint senales_par_no_vacio check (length(trim(par)) > 0);

alter table public.noticias
  add constraint noticias_titulo_no_vacio check (length(trim(titulo)) > 0);

-- --- 4) Trazabilidad de pagos de ganancias ---

alter table public.ganancias_concursos
  add column pagado_por uuid references public.usuarios(id);

-- --- 5) Límite de longitud en mensajes de chat ---

alter table public.mensajes_soporte
  add constraint mensajes_soporte_longitud check (length(contenido) <= 2000);

-- ============================================================
-- === MIGRACION 011 (011_bandeja_soporte_escalable.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 011: Bandeja de soporte escalable
-- Pegar en Supabase → SQL Editor → Run (después de 001-010)
--
-- La página /soporte (vista admin) traía TODOS los mensajes de TODAS las
-- conversaciones de la plataforma (sin límite) solo para calcular, en
-- JavaScript, cuántos no leídos hay por usuario. Con cientos/miles de
-- mensajes acumulados esto ya es notorio en cada carga de la página. Esta
-- función hace la agregación en la base de datos (aprovechando el índice
-- que ya existe en mensajes_soporte(usuario_id, created_at)) y devuelve
-- solo una fila por conversación.
-- ============================================================

create or replace function public.listar_conversaciones_soporte()
returns table (
  usuario_id uuid,
  email text,
  no_leidos bigint,
  primer_no_leido timestamptz,
  ultimo_mensaje timestamptz
) as $$
  select
    m.usuario_id,
    u.email,
    count(*) filter (where not m.leido_admin) as no_leidos,
    min(m.created_at) filter (where not m.leido_admin) as primer_no_leido,
    max(m.created_at) as ultimo_mensaje
  from public.mensajes_soporte m
  join public.usuarios u on u.id = m.usuario_id
  where public.es_admin()
  group by m.usuario_id, u.email;
$$ language sql security definer stable;

grant execute on function public.listar_conversaciones_soporte() to authenticated;

-- ============================================================
-- === MIGRACION 012 (012_trading_habilitado_y_panel_admin.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 012: Permiso de trading por usuario + datos para el panel admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-011)
--
-- Agrega una columna para que el admin pueda impedirle a un usuario
-- puntual que opere (paper trading) sin tener que desactivarle toda la
-- cuenta. Protegida igual que "role"/"activo" (solo un admin puede
-- tocarla) y reforzada dentro de abrir_operacion() para que no se pueda
-- saltar llamando el RPC directo.
-- ============================================================

alter table public.usuarios
  add column trading_habilitado boolean not null default true;

-- --- Extiende el trigger de columnas sensibles (migración 010) ---

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
begin
  if (new.role is distinct from old.role
      or new.activo is distinct from old.activo
      or new.trading_habilitado is distinct from old.trading_habilitado)
     and not public.es_admin() then
    raise exception 'Solo un admin puede cambiar el rol, el estado o el permiso de trading de una cuenta.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- --- Extiende abrir_operacion (migración 010) para respetar el permiso ---

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a cero.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select trading_habilitado into v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo < p_monto then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := p_monto / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, p_activo, p_tipo, p_precio, v_cantidad, p_monto, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = saldo_usd - p_monto, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

-- ============================================================
-- === MIGRACION 013 (013_admin_ajusta_saldo.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 013: Admin puede ajustar el saldo virtual de un usuario
-- Pegar en Supabase → SQL Editor → Run (después de 001-012)
--
-- Desde la migración 010, nadie puede hacer UPDATE directo a
-- saldo_virtual (solo los RPC abrir_operacion/cerrar_operacion, que
-- siempre operan sobre auth.uid() — el propio usuario). Esta función es
-- la única forma de que un admin le sume o reste saldo virtual a OTRO
-- usuario (ej. para corregir un error o darle más saldo de práctica).
-- ============================================================

create or replace function public.admin_agregar_saldo(
  p_usuario_id uuid,
  p_monto numeric
) returns public.saldo_virtual as $$
declare
  v_saldo public.saldo_virtual;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede ajustar el saldo de otro usuario.';
  end if;
  if p_monto is null or p_monto = 0 then
    raise exception 'El monto debe ser distinto de cero.';
  end if;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + p_monto),
      actualizado_en = now()
  where usuario_id = p_usuario_id
  returning * into v_saldo;

  if v_saldo.usuario_id is null then
    raise exception 'Este usuario no tiene saldo virtual inicializado.';
  end if;

  return v_saldo;
end;
$$ language plpgsql security definer;

grant execute on function public.admin_agregar_saldo(uuid, numeric) to authenticated;

-- ============================================================
-- === MIGRACION 014 (014_horario_mercado_y_cierre_admin.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 014: Horario de mercado (NYSE) + admin puede cerrar
-- operaciones de cualquier usuario
-- Pegar en Supabase → SQL Editor → Run (después de 001-013)
-- ============================================================

-- --- Reforzar abrir_operacion: horario de la bolsa de Nueva York ---
-- Lunes a viernes, 9:30am-4:00pm hora de Nueva York. Los admins pueden
-- operar a cualquier hora. Esto es defensa en profundidad — la UI ya
-- deshabilita el botón, pero esto evita que alguien la salte llamando el
-- RPC directo fuera de horario.
create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a cero.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  select trading_habilitado into v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo < p_monto then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := p_monto / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, p_activo, p_tipo, p_precio, v_cantidad, p_monto, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = saldo_usd - p_monto, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

-- --- Nueva función: admin cierra la operación de CUALQUIER usuario ---
-- (cerrar_operacion de la migración 010 solo permite cerrar la propia,
-- vía auth.uid() — esta es la versión para el botón masivo del admin).
create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - v_operacion.precio_entrada) * v_operacion.cantidad
    else (v_operacion.precio_entrada - p_precio_salida) * v_operacion.cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = now()
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado + v_ganancia),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

grant execute on function public.admin_cerrar_operacion(uuid, numeric) to authenticated;

-- ============================================================
-- === MIGRACION 015 (015_reporte_operaciones.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 015: Reporte de operaciones por día (admin)
-- Pegar en Supabase → SQL Editor → Run (después de 001-014)
--
-- Agrega, por usuario, cuántas operaciones abrió y su ganancia/pérdida
-- neta (solo de las cerradas) dentro de un rango de fechas — usado por
-- la pantalla /usuarios/reportes para saber quién operó un día dado y
-- quién no.
-- ============================================================

create or replace function public.reporte_operaciones_por_dia(
  p_inicio timestamptz,
  p_fin timestamptz
) returns table (
  usuario_id uuid,
  num_operaciones bigint,
  ganancia_neta numeric
) as $$
  select
    usuario_id,
    count(*) as num_operaciones,
    coalesce(sum(ganancia_perdida) filter (where estado = 'cerrada'), 0) as ganancia_neta
  from public.operaciones_simuladas
  where public.es_admin()
    and created_at >= p_inicio
    and created_at <= p_fin
  group by usuario_id;
$$ language sql security definer stable;

grant execute on function public.reporte_operaciones_por_dia(timestamptz, timestamptz) to authenticated;

-- ============================================================
-- === MIGRACION 016 (016_senales_resultado.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 017 (017_solo_admin_cierra_operaciones.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 017: Solo el admin puede cerrar operaciones
-- Pegar en Supabase → SQL Editor → Run (después de 001-016)
--
-- El producto cambió: los usuarios abren su operación pero ya NO pueden
-- cerrarla ellos mismos — la sesión completa se liquida cuando el admin
-- usa "Cerrar todas las operaciones" con el precio que él defina. Se
-- quitó el botón individual del lado del código; esto lo refuerza en la
-- base de datos por si alguien llama cerrar_operacion() directo.
-- ============================================================

create or replace function public.cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar operaciones. Espera a que se liquide la sesión.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id
    and usuario_id = v_usuario_id
    and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - v_operacion.precio_entrada) * v_operacion.cantidad
    else (v_operacion.precio_entrada - p_precio_salida) * v_operacion.cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = now()
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado + v_ganancia),
      actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

-- ============================================================
-- === MIGRACION 018 (018_cierre_automatico_senales.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 018: Cierre automático de señales por TP/SL
-- Pegar en Supabase → SQL Editor → Run (después de 001-017)
--
-- Agrega dónde/cuándo se cerró la señal (precio exacto, % de resultado,
-- fecha) y una función que cualquier sesión (incluso sin ser admin)
-- puede llamar para marcar el cierre automático — la lógica de "¿de
-- verdad tocó el nivel?" vive en el código de Next.js (compara contra
-- las velas de Binance), esta función solo aplica el resultado ya
-- decidido, evitando que las políticas de "solo admin edita señales"
-- bloqueen el cierre automático cuando quien visita la página no es admin.
-- ============================================================

alter table public.senales
  add column precio_cierre numeric,
  add column porcentaje_resultado numeric,
  add column cerrado_en timestamptz;

create or replace function public.cerrar_senal_automatica(
  p_senal_id uuid,
  p_resultado text,
  p_precio_cierre numeric,
  p_porcentaje numeric
) returns void as $$
  update public.senales
  set estado = 'cerrada',
      resultado = p_resultado,
      precio_cierre = p_precio_cierre,
      porcentaje_resultado = p_porcentaje,
      cerrado_en = now()
  where id = p_senal_id
    and estado = 'activa'
    and p_resultado in ('tp', 'sl');
$$ language sql security definer;

grant execute on function public.cerrar_senal_automatica(uuid, text, numeric, numeric) to authenticated, anon;

-- ============================================================
-- === MIGRACION 019 (019_integridad_dinero_y_senales.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 019: Integridad de dinero, permisos del admin y
-- cierre automático de señales a prueba de manipulación
-- Pegar en Supabase → SQL Editor → Run (después de 001-018)
--
-- Auditoría independiente sobre el trabajo de las migraciones 010-018.
-- Corrige cinco cosas, de más grave a menos:
--
-- 1) EL ADMIN NO PODÍA VER NI CERRAR LAS OPERACIONES DE NADIE MÁS.
--    operaciones_simuladas y saldo_virtual solo tenían la política de
--    SELECT "auth.uid() = usuario_id" — nunca se agregó la variante
--    "o es_admin()" que sí tienen usuarios, ganancias_concursos y
--    mensajes_soporte. Consecuencias reales en producción:
--      · "Cerrar todas las operaciones abiertas" (/reto-del-dia) leía la
--        lista de operaciones abiertas con la sesión del admin, así que
--        RLS se la filtraba a las SUYAS: cerraba su propia operación y
--        ninguna de los demás usuarios, reportando "0 cerradas".
--      · /usuarios/[id] mostraba siempre "$0.00" de saldo virtual y
--        "todavía no ha abierto ninguna operación" para cualquier
--        usuario que no fuera el propio admin.
--    No se detectó antes porque la base de prueba tenía un solo usuario
--    (el admin), y consigo mismo el filtro de RLS es invisible.
--
-- 2) EL PRECIO DE ENTRADA DE UNA OPERACIÓN VENÍA DEL CLIENTE.
--    abrir_operacion() recibía p_precio y lo guardaba tal cual, y estaba
--    otorgada a "authenticated": cualquier usuario logueado podía abrir
--    la consola del navegador y llamar
--      supabase.rpc('abrir_operacion', {p_activo:'BTCUSDT', p_tipo:'compra',
--                                       p_precio: 0.01, p_monto: 10000})
--    con lo que cantidad = monto/precio = 1.000.000 BTC y, al liquidar el
--    admin la sesión, su "ganancia" era de miles de millones — arruinando
--    el ranking que decide los premios reales en USDT. El server action
--    de Next.js sí consultaba el precio en Binance, pero eso no servía de
--    nada porque el RPC se podía llamar directo saltándose el action.
--    Se corrige exigiendo un secreto que solo conoce el servidor de
--    Next.js (nunca llega al navegador), guardado en una tabla que ni
--    anon ni authenticated pueden leer.
--
-- 3) CUALQUIERA PODÍA FALSIFICAR EL RESULTADO DE UNA SEÑAL.
--    cerrar_senal_automatica() estaba otorgada a anon y aceptaba
--    resultado, precio de cierre y porcentaje como parámetros libres: con
--    la anon key (que viaja en el bundle del navegador) se podía marcar
--    cualquier señal como "TP tocado +900%". El historial de señales es
--    justo el activo de credibilidad del producto. Ahora la función
--    calcula ella misma el precio de cierre y el porcentaje desde la fila
--    de la señal (entrada/TP/SL ya guardados) y exige el mismo secreto de
--    servidor, así que solo el código de Next.js puede dispararla.
--
-- 4) VALIDACIONES NUMÉRICAS QUE FALTABAN.
--    · abrir_operacion: p_precio podía ser 0 (división por cero) o NULL.
--    · p_monto podía llegar como 'NaN' (en numeric de Postgres, NaN NO es
--      <= 0, así que pasaba el filtro) y dejaba el saldo del usuario en
--      NaN de forma permanente.
--    · cerrar_operacion / admin_cerrar_operacion no validaban el precio
--      de salida.
--    · admin_agregar_saldo aceptaba NaN.
--    · abrir_operacion no verificaba que el activo fuera el pick del día
--      vigente (solo lo hacía el server action, saltable igual que el
--      precio).
--
-- 5) SEÑALES CON TP/SL DEL LADO EQUIVOCADO.
--    Nada impedía publicar una señal de compra con el take profit POR
--    DEBAJO de la entrada. El cierre automático por velas la daba por
--    "TP tocado" en la primera vela revisada, con porcentaje negativo.
--    Se agrega un check en la base de datos.
-- ============================================================

-- ------------------------------------------------------------
-- 1) El admin puede leer operaciones y saldos de cualquier usuario
-- ------------------------------------------------------------
-- Las políticas permisivas se combinan con OR, así que esto no le abre
-- nada a un usuario normal: sigue viendo solo lo suyo.

drop policy if exists "admin ve todas las operaciones" on public.operaciones_simuladas;
create policy "admin ve todas las operaciones"
  on public.operaciones_simuladas for select
  using (public.es_admin());

drop policy if exists "admin ve todos los saldos" on public.saldo_virtual;
create policy "admin ve todos los saldos"
  on public.saldo_virtual for select
  using (public.es_admin());

-- ------------------------------------------------------------
-- 2) Secreto compartido servidor Next.js <-> Postgres
-- ------------------------------------------------------------
-- Tabla con RLS activada y SIN ninguna política: eso significa que anon y
-- authenticated no pueden leer ni escribir NADA aquí (RLS sin políticas
-- deniega todo). Solo las funciones SECURITY DEFINER de abajo, que corren
-- como el dueño de la tabla, pueden consultarla.

create table if not exists public.config_servidor (
  clave text primary key,
  valor text not null,
  actualizado_en timestamptz not null default now()
);

alter table public.config_servidor enable row level security;
revoke all on public.config_servidor from anon, authenticated;

-- El valor real NO va escrito aquí: este archivo se versiona y se entrega
-- con el proyecto, así que un secreto literal en esta línea es un secreto
-- público (así estaba hasta la migración 021, y por eso hubo que rotarlo).
-- Se inserta un marcador inválido para que la app falle de forma ruidosa
-- hasta que se genere el valor real y se guarde en los DOS lados:
--
--   1) node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
--   2) en .env.local (TRADING_SERVER_SECRET) y en la base:
--        update public.config_servidor
--        set valor = 'EL_VALOR_GENERADO', actualizado_en = now()
--        where clave = 'trading_server_secret';
insert into public.config_servidor (clave, valor)
values ('trading_server_secret', 'FALTA-ROTAR-ESTE-SECRETO')
on conflict (clave) do nothing;

create or replace function public.secreto_servidor_ok(p_secreto text)
returns boolean as $$
  select p_secreto is not null
     and exists (
       select 1 from public.config_servidor
       where clave = 'trading_server_secret'
         and valor = p_secreto
     );
$$ language sql security definer stable;

revoke execute on function public.secreto_servidor_ok(text) from public;

-- ------------------------------------------------------------
-- 3) abrir_operacion: exige secreto de servidor + valida todo
-- ------------------------------------------------------------
-- Se DROPEA la versión de 4 argumentos antes de crear la nueva: si solo
-- se hiciera "create or replace" con un argumento más, Postgres dejaría
-- las dos conviviendo como sobrecargas y la vieja (vulnerable) seguiría
-- siendo llamable desde el navegador.

drop function if exists public.abrir_operacion(text, text, numeric, numeric);

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric,
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  -- El precio de entrada define la cantidad comprada y por lo tanto toda
  -- la ganancia; no puede venir de un cliente. Este secreto solo existe
  -- en el entorno del servidor de Next.js (TRADING_SERVER_SECRET), nunca
  -- en el bundle del navegador.
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  -- Ojo: en numeric de Postgres, 'NaN' NO cumple "<= 0" (NaN se ordena
  -- por encima de cualquier número), así que hay que descartarlo aparte o
  -- se cuela y deja el saldo del usuario en NaN para siempre.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a cero.';
  end if;
  if p_precio is null or p_precio = 'NaN'::numeric or p_precio <= 0 then
    raise exception 'No se pudo determinar un precio de entrada válido.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  -- El activo tiene que ser el pick del día vigente (mismo chequeo que
  -- hace el server action, repetido aquí para que no se pueda saltar).
  select activo into v_pick
  from public.pick_del_dia
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  select trading_habilitado into v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo < p_monto then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := p_monto / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, p_precio, v_cantidad, p_monto, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = saldo_usd - p_monto, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

revoke execute on function public.abrir_operacion(text, text, numeric, numeric, text) from public;
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text) to authenticated;

-- ------------------------------------------------------------
-- 4) Precio de salida validado al cerrar (usuario y admin)
-- ------------------------------------------------------------

create or replace function public.cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar operaciones. Espera a que se liquide la sesión.';
  end if;
  if p_precio_salida is null
     or p_precio_salida = 'NaN'::numeric
     or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id
    and usuario_id = v_usuario_id
    and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - v_operacion.precio_entrada) * v_operacion.cantidad
    else (v_operacion.precio_entrada - p_precio_salida) * v_operacion.cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = now()
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado + v_ganancia),
      actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;
  if p_precio_salida is null
     or p_precio_salida = 'NaN'::numeric
     or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - v_operacion.precio_entrada) * v_operacion.cantidad
    else (v_operacion.precio_entrada - p_precio_salida) * v_operacion.cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = now()
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado + v_ganancia),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

revoke execute on function public.cerrar_operacion(uuid, numeric) from public;
grant execute on function public.cerrar_operacion(uuid, numeric) to authenticated;
revoke execute on function public.admin_cerrar_operacion(uuid, numeric) from public;
grant execute on function public.admin_cerrar_operacion(uuid, numeric) to authenticated;

-- ------------------------------------------------------------
-- 5) admin_agregar_saldo: descartar NaN
-- ------------------------------------------------------------

create or replace function public.admin_agregar_saldo(
  p_usuario_id uuid,
  p_monto numeric
) returns public.saldo_virtual as $$
declare
  v_saldo public.saldo_virtual;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede ajustar el saldo de otro usuario.';
  end if;
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto = 0 then
    raise exception 'El monto debe ser un número distinto de cero.';
  end if;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + p_monto),
      actualizado_en = now()
  where usuario_id = p_usuario_id
  returning * into v_saldo;

  if v_saldo.usuario_id is null then
    raise exception 'Este usuario no tiene saldo virtual inicializado.';
  end if;

  return v_saldo;
end;
$$ language plpgsql security definer;

revoke execute on function public.admin_agregar_saldo(uuid, numeric) from public;
grant execute on function public.admin_agregar_saldo(uuid, numeric) to authenticated;

-- ------------------------------------------------------------
-- 6) cerrar_senal_automatica: no acepta precios ni porcentajes del cliente
-- ------------------------------------------------------------
-- La decisión de "¿tocó TP o SL?" sigue viniendo del código de Next.js
-- (es el único que puede leer las velas de Binance), pero el precio de
-- cierre y el porcentaje los calcula ahora la propia base de datos desde
-- entrada/take_profit/stop_loss, así que no hay forma de inyectar un
-- "+900%" falso. Además exige el secreto de servidor.

drop function if exists public.cerrar_senal_automatica(uuid, text, numeric, numeric);

create or replace function public.cerrar_senal_automatica(
  p_senal_id uuid,
  p_resultado text,
  p_secreto text
) returns void as $$
declare
  v_senal public.senales;
  v_precio numeric;
  v_porcentaje numeric;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Solo la aplicación puede cerrar señales automáticamente.';
  end if;
  if p_resultado not in ('tp', 'sl') then
    raise exception 'Resultado inválido.';
  end if;

  select * into v_senal
  from public.senales
  where id = p_senal_id and estado = 'activa' and resultado is null
  for update;

  if v_senal.id is null then
    return; -- ya estaba cerrada: no es un error, solo no hay nada que hacer
  end if;

  v_precio := case when p_resultado = 'tp'
                   then v_senal.take_profit
                   else v_senal.stop_loss end;

  if v_precio is null then
    raise exception 'La señal no tiene definido ese nivel.';
  end if;

  v_porcentaje := case
    when v_senal.tipo = 'compra'
      then ((v_precio - v_senal.entrada) / v_senal.entrada) * 100
    else ((v_senal.entrada - v_precio) / v_senal.entrada) * 100
  end;

  update public.senales
  set estado = 'cerrada',
      resultado = p_resultado,
      precio_cierre = v_precio,
      porcentaje_resultado = v_porcentaje,
      cerrado_en = now()
  where id = p_senal_id;
end;
$$ language plpgsql security definer;

revoke execute on function public.cerrar_senal_automatica(uuid, text, text) from public;
-- Se mantiene el grant a anon: el chequeo corre en un Server Component de
-- Next.js que puede estar sirviendo a un visitante sin sesión, pero ahora
-- lo que autoriza de verdad es el secreto, no el rol.
grant execute on function public.cerrar_senal_automatica(uuid, text, text) to authenticated, anon;

-- ------------------------------------------------------------
-- 7) TP/SL tienen que estar del lado correcto de la entrada
-- ------------------------------------------------------------
-- En una compra se gana hacia arriba: TP > entrada > SL. En una venta al
-- revés. Sin esto, una señal mal tipeada se cerraba sola como "TP tocado"
-- en la primera vela revisada, con un porcentaje negativo.

alter table public.senales
  drop constraint if exists senales_niveles_coherentes;

alter table public.senales
  add constraint senales_niveles_coherentes check (
    (
      tipo = 'compra'
      and (take_profit is null or take_profit > entrada)
      and (stop_loss is null or stop_loss < entrada)
    )
    or (
      tipo = 'venta'
      and (take_profit is null or take_profit < entrada)
      and (stop_loss is null or stop_loss > entrada)
    )
  );

-- Nota: se verificó contra los datos reales antes de aplicarlo — todas
-- las señales existentes ya cumplen, así que el constraint entra
-- validado. Si en otra instalación hubiera históricos con los niveles
-- invertidos, agregarlo con "not valid" y luego "validate constraint".

-- ============================================================
-- === MIGRACION 020 (020_estadisticas_publicas.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 020: Estadísticas públicas de la portada
-- Pegar en Supabase → SQL Editor → Run (después de 001-019)
--
-- La portada (/) muestra conteos reales (operaciones simuladas, señales
-- publicadas, usuarios registrados) para un visitante ANÓNIMO — pero las
-- políticas RLS de "usuarios" y "operaciones_simuladas" solo dejan ver
-- las propias filas (o todas, si sos admin). Sin esta función, cualquiera
-- que no haya iniciado sesión ve "0" en vez del conteo real, porque RLS
-- filtra todo antes de que el SELECT llegue a contar nada.
--
-- Esta función solo expone TOTALES agregados (nunca filas ni datos
-- individuales), así que es seguro que la lea cualquiera, con o sin
-- sesión.
-- ============================================================

create or replace function public.estadisticas_publicas()
returns table (
  operaciones bigint,
  senales bigint,
  usuarios bigint
) as $$
  select
    (select count(*) from public.operaciones_simuladas),
    (select count(*) from public.senales),
    (select count(*) from public.usuarios);
$$ language sql security definer stable;

grant execute on function public.estadisticas_publicas() to anon, authenticated;

-- ============================================================
-- === MIGRACION 021 (021_endurecimiento_permisos_y_columnas.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 021: Endurecimiento de permisos de RPC, columnas
-- inmutables y sanitización de URLs
-- Pegar en Supabase → SQL Editor → Run (después de 001-020)
--
-- Segunda auditoría de seguridad independiente sobre las migraciones
-- 001-020. Corrige, de más grave a menos:
--
-- 1) EL VALIDADOR DEL SECRETO DE SERVIDOR ERA INVOCABLE DESDE EL NAVEGADOR.
--    La migración 019 creó public.secreto_servidor_ok(text) y le hizo
--    "revoke execute ... from public", pero eso NO alcanza en Supabase:
--    el proyecto tiene privilegios por defecto que otorgan EXECUTE
--    explícitamente a los roles `anon` y `authenticated` sobre toda
--    función nueva del esquema public. Revocarle a PUBLIC no toca esos
--    grants nominales, así que la función quedó expuesta en la API REST.
--    Verificado contra la base real: con la anon key (que viaja en el
--    bundle del navegador) y SIN NINGUNA SESIÓN se podía llamar
--      supabase.rpc('secreto_servidor_ok', {p_secreto: '...'})
--    y recibir true/false. Eso convierte al secreto compartido —la única
--    barrera que impide abrir operaciones con precio inventado (bug #2 de
--    la migración 019) y falsificar el resultado de una señal (bug #3)—
--    en un oráculo verificable: cualquiera puede confirmar un candidato
--    sin límite de intentos, y confirmar de inmediato el que aparece
--    escrito en el propio archivo de la migración 019 (ver punto 6).
--    Se revoca EXECUTE de anon/authenticated/PUBLIC: la función solo la
--    necesitan las otras funciones SECURITY DEFINER, que corren como
--    `postgres` y no pasan por estos grants.
--    Por el mismo motivo se le quita el EXECUTE a `anon` a las funciones
--    que exigen sesión o rol admin, y a PUBLIC a las funciones de trigger
--    (handle_new_user, handle_new_user_saldo,
--    proteger_columnas_sensibles_usuarios), que nunca deben poder
--    invocarse como RPC.
--
-- 2) UN USUARIO PODÍA REESCRIBIR MENSAJES YA ENVIADOS.
--    La política UPDATE de mensajes_soporte solo comprobaba de quién es la
--    conversación, no QUÉ columna se estaba cambiando. La app solo marca
--    mensajes como leídos, pero con la anon key un usuario podía hacer
--      supabase.from('mensajes_soporte').update({contenido: '...'})
--    sobre CUALQUIER mensaje de su conversación — incluidas las respuestas
--    del admin. Verificado contra la base real. Riesgo: repudio y
--    fabricación de evidencia ("el soporte me autorizó X"), justo en el
--    canal que respalda pagos de premios en USDT. Se agrega un trigger que
--    congela todas las columnas salvo los dos flags de leído.
--
-- 3) UN USUARIO PODÍA CAMBIAR SU PROPIO EMAIL, CÓDIGO DE INVITACIÓN,
--    ID CORTO E INVITADO_POR.
--    El trigger de la migración 010/012 solo protege role, activo y
--    trading_habilitado; la política UPDATE de `usuarios` no tiene
--    "with check" por columna, así que el resto de la fila quedaba
--    escribible por su dueño. Verificado contra la base real: un usuario
--    normal cambió el email de su fila a "soporte@trade4u.test". Ese email
--    es lo que el admin ve en /usuarios, /usuarios/[id], la bandeja de
--    soporte y el CSV de reportes, o sea que servía para suplantar al
--    equipo frente al propio admin. id_corto y codigo_invitacion permiten
--    lo mismo con el identificador que el usuario "dice en voz alta", e
--    invitado_por falsea el conteo de referidos. Se extiende el trigger
--    para congelar esas columnas salvo para un admin. El único campo que
--    un usuario normal puede seguir editando de su fila es
--    wallet_usdt_erc20, que es el propósito del formulario de Perfil.
--
-- 4) SECURITY DEFINER SIN search_path FIJO.
--    Ninguna de las funciones fijaba search_path (lint
--    `function_search_path_mutable` de Supabase). Hoy no es explotable en
--    este proyecto —ni anon ni authenticated tienen CREATE sobre el
--    esquema public, verificado— pero es una bomba de tiempo: basta con
--    que alguien otorgue ese permiso más adelante para que se pueda
--    secuestrar la resolución de nombres dentro de funciones que corren
--    como `postgres`. Se fija en todas.
--
-- 5) noticias.url_fuente ACEPTABA CUALQUIER TEXTO.
--    Ese valor se renderiza como href en la portada (ticker) y en
--    /noticias. Un valor "javascript:..." es XSS almacenado para todos los
--    visitantes, incluido el admin. Se restringe a http/https en la base
--    (el front además lo sanea al renderizar, defensa en profundidad).
--
-- 6) EL SECRETO DE SERVIDOR ESTABA ESCRITO EN TEXTO PLANO EN LA MIGRACIÓN
--    019, que se versiona y se entrega con el proyecto. Se quitó de ese
--    archivo y el valor se rota fuera de git (ver nota al final).
--
-- 7) TRUNCATE/TRIGGER/REFERENCES otorgados a anon/authenticated.
--    Son parte del "grant all" por defecto de Supabase. PostgREST nunca
--    los usa, pero TRUNCATE en particular NO respeta RLS, así que
--    cualquier vía futura de SQL con esos roles podría vaciar tablas de
--    dinero saltándose todas las políticas. Se revocan.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Permisos de ejecución de funciones
-- ------------------------------------------------------------

-- El validador del secreto: nadie externo debe poder invocarlo. Las
-- funciones que lo usan son SECURITY DEFINER y corren como su dueño, así
-- que siguen pudiendo llamarlo aunque el rol de la sesión no pueda.
revoke all on function public.secreto_servidor_ok(text) from public, anon, authenticated;

-- Funciones de trigger: no son RPC, jamás deben exponerse en la API.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.handle_new_user_saldo() from public, anon, authenticated;
revoke all on function public.proteger_columnas_sensibles_usuarios()
  from public, anon, authenticated;

-- Funciones que exigen sesión o rol admin: `anon` no tiene nada que hacer
-- ahí (ya fallaban dentro, pero no hace falta ni dejarlas invocables).
revoke all on function public.abrir_operacion(text, text, numeric, numeric, text) from anon;
revoke all on function public.cerrar_operacion(uuid, numeric) from anon;
revoke all on function public.admin_cerrar_operacion(uuid, numeric) from anon;
revoke all on function public.admin_agregar_saldo(uuid, numeric) from anon;
revoke all on function public.contar_invitados() from public, anon;
revoke all on function public.listar_conversaciones_soporte() from public, anon;
revoke all on function public.reporte_operaciones_por_dia(timestamptz, timestamptz)
  from public, anon;
-- OJO: es_admin() NO se le revoca a `anon`. No es una fuga (para una
-- sesión sin usuario siempre devuelve false), y sobre todo aparece dentro
-- de las políticas RLS de mensajes_soporte, ganancias_concursos, usuarios,
-- senales, noticias, etc. Esas políticas se evalúan con el rol de la
-- sesión, así que sin EXECUTE un visitante anónimo recibiría
-- "permission denied for function es_admin" en vez de simplemente no ver
-- filas — y eso rompería la portada pública.
revoke all on function public.es_admin() from public;

-- Se reafirma explícitamente lo que SÍ debe poder llamar cada rol, para
-- que la migración sea idempotente y el estado final quede declarado.
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text) to authenticated;
grant execute on function public.cerrar_operacion(uuid, numeric) to authenticated;
grant execute on function public.admin_cerrar_operacion(uuid, numeric) to authenticated;
grant execute on function public.admin_agregar_saldo(uuid, numeric) to authenticated;
grant execute on function public.contar_invitados() to authenticated;
grant execute on function public.listar_conversaciones_soporte() to authenticated;
grant execute on function public.reporte_operaciones_por_dia(timestamptz, timestamptz) to authenticated;
grant execute on function public.es_admin() to anon, authenticated;
-- estadisticas_publicas solo devuelve totales agregados: sigue siendo
-- pública a propósito (la portada la usa sin sesión).
grant execute on function public.estadisticas_publicas() to anon, authenticated;
-- cerrar_senal_automatica sigue disponible para anon a propósito (corre
-- en un Server Component que puede servir a un visitante sin sesión);
-- lo que autoriza de verdad es el secreto, no el rol.
grant execute on function public.cerrar_senal_automatica(uuid, text, text) to anon, authenticated;

-- ------------------------------------------------------------
-- 2) search_path fijo en todas las funciones SECURITY DEFINER
-- ------------------------------------------------------------
-- pg_temp va al final a propósito: por defecto Postgres busca el esquema
-- temporal ANTES que public al resolver nombres de tabla, así que una
-- sesión que pudiera crear tablas temporales podría hacerle sombra a una
-- tabla real dentro de una función que corre como `postgres`.

alter function public.es_admin() set search_path = pg_catalog, public, pg_temp;
alter function public.contar_invitados() set search_path = pg_catalog, public, pg_temp;
alter function public.handle_new_user() set search_path = pg_catalog, public, pg_temp;
alter function public.handle_new_user_saldo() set search_path = pg_catalog, public, pg_temp;
alter function public.proteger_columnas_sensibles_usuarios()
  set search_path = pg_catalog, public, pg_temp;
alter function public.secreto_servidor_ok(text) set search_path = pg_catalog, public, pg_temp;
alter function public.abrir_operacion(text, text, numeric, numeric, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.cerrar_operacion(uuid, numeric) set search_path = pg_catalog, public, pg_temp;
alter function public.admin_cerrar_operacion(uuid, numeric)
  set search_path = pg_catalog, public, pg_temp;
alter function public.admin_agregar_saldo(uuid, numeric)
  set search_path = pg_catalog, public, pg_temp;
alter function public.cerrar_senal_automatica(uuid, text, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.listar_conversaciones_soporte()
  set search_path = pg_catalog, public, pg_temp;
alter function public.reporte_operaciones_por_dia(timestamptz, timestamptz)
  set search_path = pg_catalog, public, pg_temp;
alter function public.estadisticas_publicas() set search_path = pg_catalog, public, pg_temp;

-- ------------------------------------------------------------
-- 3) mensajes_soporte: un mensaje enviado es inmutable
-- ------------------------------------------------------------
-- Lo único que la app actualiza de un mensaje son los dos flags de
-- "leído" (ver src/lib/actions/chat.ts). Todo lo demás —contenido, quién
-- lo escribió, de quién es la conversación, cuándo— queda congelado para
-- todos, admin incluido: un historial de soporte que se puede editar a
-- posteriori no sirve como respaldo de nada.

create or replace function public.proteger_mensajes_soporte()
returns trigger as $$
begin
  if new.id is distinct from old.id
     or new.usuario_id is distinct from old.usuario_id
     or new.remitente_id is distinct from old.remitente_id
     or new.contenido is distinct from old.contenido
     or new.created_at is distinct from old.created_at then
    raise exception 'Un mensaje de soporte enviado no se puede modificar; solo marcarse como leído.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_editar_mensaje_soporte on public.mensajes_soporte;
create trigger antes_de_editar_mensaje_soporte
  before update on public.mensajes_soporte
  for each row execute procedure public.proteger_mensajes_soporte();

revoke all on function public.proteger_mensajes_soporte() from public, anon, authenticated;

-- La política de UPDATE pasa a declarar su "with check" explícitamente.
-- Sin él, Postgres reutiliza el "using" como check (que es lo que hoy
-- impide mover un mensaje a otra conversación), pero dejarlo implícito
-- hace que el día que alguien afloje el "using" se afloje también,
-- silenciosamente, lo que se puede escribir.
drop policy if exists "marcar como leido en conversacion propia o si es admin"
  on public.mensajes_soporte;

create policy "marcar como leido en conversacion propia o si es admin"
  on public.mensajes_soporte for update
  using (usuario_id = auth.uid() or public.es_admin())
  with check (usuario_id = auth.uid() or public.es_admin());

-- ------------------------------------------------------------
-- 4) usuarios: columnas de identidad congeladas para el no-admin
-- ------------------------------------------------------------
-- Reemplaza la versión de la migración 012 agregando las columnas de
-- identidad. Un usuario normal solo puede editar wallet_usdt_erc20.

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
declare
  v_es_admin boolean := public.es_admin();
begin
  if (new.role is distinct from old.role
      or new.activo is distinct from old.activo
      or new.trading_habilitado is distinct from old.trading_habilitado)
     and not v_es_admin then
    raise exception 'Solo un admin puede cambiar el rol, el estado o el permiso de trading de una cuenta.';
  end if;

  -- Identidad: lo que el admin ve en /usuarios, en la bandeja de soporte
  -- y en el CSV de reportes. Si el dueño de la fila lo puede reescribir,
  -- puede hacerse pasar por otra persona (o por el propio soporte)
  -- delante del admin, y falsear el conteo de referidos.
  if (new.id is distinct from old.id
      or new.email is distinct from old.email
      or new.codigo_invitacion is distinct from old.codigo_invitacion
      or new.invitado_por is distinct from old.invitado_por
      or new.id_corto is distinct from old.id_corto
      or new.created_at is distinct from old.created_at)
     and not v_es_admin then
    raise exception 'No puedes modificar los datos de identidad de tu cuenta. Contacta a soporte.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.proteger_columnas_sensibles_usuarios()
  from public, anon, authenticated;

-- Igual que con mensajes_soporte: el "with check" explícito evita que una
-- fila de `usuarios` se pueda mover fuera del alcance de la política.
drop policy if exists "cada usuario edita el suyo, admin edita cualquiera" on public.usuarios;

create policy "cada usuario edita el suyo, admin edita cualquiera"
  on public.usuarios for update
  using (auth.uid() = id or public.es_admin())
  with check (auth.uid() = id or public.es_admin());

-- ------------------------------------------------------------
-- 5) noticias.url_fuente: solo http/https
-- ------------------------------------------------------------
-- Se renderiza como href en la portada pública. "javascript:...",
-- "data:text/html,..." o "vbscript:..." ahí son XSS almacenado.

update public.noticias
set url_fuente = null
where url_fuente is not null
  and url_fuente !~* '^https?://[^[:space:]]+$';

alter table public.noticias
  drop constraint if exists noticias_url_fuente_http;

alter table public.noticias
  add constraint noticias_url_fuente_http check (
    url_fuente is null
    or url_fuente ~* '^https?://[^[:space:]]+$'
  );

-- ------------------------------------------------------------
-- 6) Límite de frecuencia en mensajes de soporte
-- ------------------------------------------------------------
-- mensajes_soporte es la única tabla donde un usuario normal puede
-- insertar filas sin pasar por un RPC, y no había ningún límite: un solo
-- usuario podía escribir mensajes de 2000 caracteres en bucle y llenar la
-- bandeja del admin (y la base) hasta hacerla inservible. El límite va en
-- la base, no en el server action, porque el insert se puede hacer también
-- directo con la anon key, y porque un contador en memoria de Next.js no
-- sirve cuando hay más de una instancia.

create or replace function public.limitar_frecuencia_mensajes_soporte()
returns trigger as $$
declare
  v_recientes int;
begin
  -- El admin responde muchas conversaciones seguidas: no se le limita.
  if public.es_admin() then
    return new;
  end if;

  select count(*) into v_recientes
  from public.mensajes_soporte
  where remitente_id = new.remitente_id
    and created_at > now() - interval '1 minute';

  if v_recientes >= 10 then
    raise exception 'Estás enviando mensajes demasiado rápido. Espera un momento antes de volver a escribir.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_insertar_mensaje_soporte on public.mensajes_soporte;
create trigger antes_de_insertar_mensaje_soporte
  before insert on public.mensajes_soporte
  for each row execute procedure public.limitar_frecuencia_mensajes_soporte();

revoke all on function public.limitar_frecuencia_mensajes_soporte()
  from public, anon, authenticated;

-- Índice para que ese count(*) no escanee la tabla entera a medida que el
-- historial de soporte crece.
create index if not exists mensajes_soporte_remitente_fecha
  on public.mensajes_soporte (remitente_id, created_at desc);

-- ------------------------------------------------------------
-- 7) favoritos: formato de símbolo y tope por usuario
-- ------------------------------------------------------------
-- El server action guardaba el símbolo tal cual llegaba del formulario,
-- sin formato ni cantidad máxima. Con la anon key se podía llenar la
-- tabla con texto arbitrario, y cada favorito se traduce en una petición
-- a Binance al renderizar /perfil: una lista inflada convierte una sola
-- visita en cientos de llamadas salientes y quema el límite de peticiones
-- de Binance, que es compartido por toda la plataforma.

delete from public.favoritos
where activo !~ '^[A-Z0-9]{5,20}$';

alter table public.favoritos
  drop constraint if exists favoritos_simbolo_formato;

alter table public.favoritos
  add constraint favoritos_simbolo_formato
  check (activo ~ '^[A-Z0-9]{5,20}$');

create or replace function public.limitar_favoritos_por_usuario()
returns trigger as $$
declare
  v_total int;
begin
  select count(*) into v_total
  from public.favoritos
  where usuario_id = new.usuario_id;

  if v_total >= 50 then
    raise exception 'Llegaste al máximo de 50 activos favoritos. Quita alguno antes de agregar otro.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_insertar_favorito on public.favoritos;
create trigger antes_de_insertar_favorito
  before insert on public.favoritos
  for each row execute procedure public.limitar_favoritos_por_usuario();

revoke all on function public.limitar_favoritos_por_usuario()
  from public, anon, authenticated;

-- ------------------------------------------------------------
-- 8) "Cuenta desactivada" tiene que significar algo en la base
-- ------------------------------------------------------------
-- Hasta ahora, desactivar una cuenta solo la frenaba en el código de
-- Next.js: las páginas redirigen a /cuenta-desactivada y los server
-- actions llaman a exigirActivo(). Pero la sesión de Supabase sigue
-- siendo válida, y con la anon key se puede escribir directo saltándose
-- por completo los server actions. En la práctica un usuario baneado
-- podía seguir insertando mensajes en la bandeja de soporte.
-- es_admin() ya exige activo = true desde la migración 005; esto hace lo
-- propio para el usuario normal.

create or replace function public.cuenta_activa()
returns boolean as $$
  select exists (
    select 1 from public.usuarios
    where id = auth.uid() and activo = true
  );
$$ language sql security definer stable set search_path = pg_catalog, public, pg_temp;

revoke all on function public.cuenta_activa() from public;
grant execute on function public.cuenta_activa() to anon, authenticated;

drop policy if exists "enviar mensaje propio, en conversacion propia o si es admin"
  on public.mensajes_soporte;

create policy "enviar mensaje propio, en conversacion propia o si es admin"
  on public.mensajes_soporte for insert
  with check (
    remitente_id = auth.uid()
    and public.cuenta_activa()
    and (usuario_id = auth.uid() or public.es_admin())
  );

-- Mismo criterio para los favoritos.
drop policy if exists "usuario agrega sus propios favoritos" on public.favoritos;

create policy "usuario agrega sus propios favoritos"
  on public.favoritos for insert
  with check (auth.uid() = usuario_id and public.cuenta_activa());

-- Y para abrir operaciones: abrir_operacion validaba trading_habilitado
-- pero no activo, así que una cuenta desactivada seguía siendo operable a
-- nivel de base. Se recrea la función de la migración 019 agregando ese
-- chequeo; todo lo demás queda idéntico.
create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric,
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a cero.';
  end if;
  if p_precio is null or p_precio = 'NaN'::numeric or p_precio <= 0 then
    raise exception 'No se pudo determinar un precio de entrada válido.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;
  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select activo into v_pick
  from public.pick_del_dia
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo < p_monto then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := p_monto / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, p_precio, v_cantidad, p_monto, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = saldo_usd - p_monto, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.abrir_operacion(text, text, numeric, numeric, text)
  from public, anon;
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text)
  to authenticated;

-- ------------------------------------------------------------
-- 9) Quitar privilegios que PostgREST nunca usa
-- ------------------------------------------------------------
-- TRUNCATE no respeta RLS: con él, cualquier acceso SQL futuro con estos
-- roles podría vaciar las tablas de dinero saltándose todas las
-- políticas. TRIGGER y REFERENCES tampoco hacen falta para la API.

revoke truncate, trigger, references
  on public.usuarios, public.senales, public.noticias, public.config_portada,
     public.favoritos, public.saldo_virtual, public.operaciones_simuladas,
     public.pick_del_dia, public.mensajes_soporte, public.ganancias_concursos
  from anon, authenticated;

-- ============================================================
-- ROTACIÓN DEL SECRETO DE SERVIDOR
--
-- La migración 019 traía el valor real de `trading_server_secret` escrito
-- en texto plano, y este repositorio se entrega a terceros: hay que
-- considerarlo comprometido. Ese literal ya se quitó del archivo 019.
--
-- La rotación NO se escribe aquí a propósito (volvería a dejar el secreto
-- nuevo dentro de un archivo versionado). Se hace una sola vez, fuera de
-- git, con estos dos pasos:
--
--   1) Generar el valor:
--        node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
--   2) Guardarlo en LOS DOS lados:
--        · en .env.local (y en las variables de entorno del hosting)
--          como TRADING_SERVER_SECRET
--        · en la base, con:
--            update public.config_servidor
--            set valor = 'EL_VALOR_NUEVO', actualizado_en = now()
--            where clave = 'trading_server_secret';
--
-- Si los dos valores no coinciden, "Trade del día" y el cierre automático
-- de señales fallan a propósito (no se degradan en silencio).
-- ============================================================

-- Red de seguridad: si la fila no existe (instalación nueva), se crea con
-- un valor evidentemente inválido para que falle ruidosamente hasta que
-- alguien haga la rotación de arriba.
insert into public.config_servidor (clave, valor)
values ('trading_server_secret', 'FALTA-ROTAR-ESTE-SECRETO')
on conflict (clave) do nothing;

-- ============================================================
-- === MIGRACION 022 (022_indices_de_rendimiento.sql) ===
-- ============================================================

-- ============================================================================
-- 022 — Índices para las consultas que van a crecer con el uso real
-- ============================================================================
-- Auditoría de rendimiento previa al despliegue. Hasta aquí las únicas tablas
-- con índices propios eran mensajes_soporte y ganancias_concursos; todo lo
-- demás dependía de la clave primaria, así que cada listado hacía un recorrido
-- secuencial de la tabla entera. Con 2 usuarios de prueba eso no se nota; con
-- miles de operaciones y señales sí, y el plan gratuito de Supabase es
-- justamente donde peor sienta.
--
-- Solo se AGREGAN índices: no se toca ninguna política, función ni columna.
-- Cada uno responde a una consulta concreta que ya existe en el código.
--
-- Nota sobre CONCURRENTLY: no se usa a propósito. Estas tablas son pequeñas
-- hoy, y CREATE INDEX CONCURRENTLY no puede correr dentro de una transacción,
-- lo que complicaría aplicar la migración de un tirón en una instalación nueva
-- (que es como la va a correr quien reciba el proyecto).
-- ============================================================================

-- ── operaciones_simuladas ───────────────────────────────────────────────────

-- /trade-del-dia: historial del usuario
--   .eq(usuario_id).eq(estado,'cerrada').order(cerrado_en desc).limit(5)
-- y /usuarios/[id]: .eq(usuario_id).order(created_at desc).limit(20)
create index if not exists operaciones_usuario_created_at_idx
  on public.operaciones_simuladas (usuario_id, created_at desc);

create index if not exists operaciones_usuario_cerrado_en_idx
  on public.operaciones_simuladas (usuario_id, cerrado_en desc)
  where estado = 'cerrada';

-- reporte_operaciones_por_dia(p_inicio, p_fin): rango de fechas sobre TODA la
-- tabla, agrupando por usuario. Es la consulta que decide a quién se le paga
-- el premio, y la que más va a crecer (una fila por operación de cada día).
create index if not exists operaciones_created_at_idx
  on public.operaciones_simuladas (created_at);

-- Cierre masivo del admin y la tarjeta de "símbolos abiertos":
--   .select(...).eq('estado','abierta')
-- Índice parcial: solo indexa las abiertas, que siempre serán un puñado
-- frente al histórico completo de cerradas.
create index if not exists operaciones_abiertas_idx
  on public.operaciones_simuladas (activo)
  where estado = 'abierta';

-- ── senales ─────────────────────────────────────────────────────────────────

-- /senales: .order(created_at desc) sobre la tabla completa (página pública).
create index if not exists senales_created_at_idx
  on public.senales (created_at desc);

-- revisarYCerrarSenalesActivas(): .eq('estado','activa').is('resultado',null)
-- Corre en CADA carga de /senales, así que conviene que sea instantánea.
create index if not exists senales_activas_idx
  on public.senales (created_at)
  where estado = 'activa' and resultado is null;

-- ── noticias ────────────────────────────────────────────────────────────────

-- Portada: .order(destacada desc).order(created_at desc).limit(6)
-- y /noticias: .order(created_at desc)
create index if not exists noticias_destacada_created_at_idx
  on public.noticias (destacada desc, created_at desc);

-- ── ganancias_concursos ─────────────────────────────────────────────────────

-- Ya existe (usuario_id, created_at), pero /perfil y /usuarios/[id] ordenan
-- DESC; con el índice ascendente Postgres igual lo puede recorrer al revés,
-- así que no se duplica. Lo que sí falta es el filtro de pendientes de pago.
create index if not exists ganancias_pendientes_idx
  on public.ganancias_concursos (usuario_id)
  where not pagado;

-- ── usuarios ────────────────────────────────────────────────────────────────

-- /usuarios: .order(created_at desc) con la lista completa de cuentas.
create index if not exists usuarios_created_at_idx
  on public.usuarios (created_at desc);

-- contar_invitados() y el contador de "personas invitadas" de /usuarios/[id]:
--   where invitado_por = <id>
create index if not exists usuarios_invitado_por_idx
  on public.usuarios (invitado_por)
  where invitado_por is not null;

-- /usuarios/reportes: .select(id, email, id_corto).order('email')
create index if not exists usuarios_email_idx
  on public.usuarios (email);

-- ── favoritos ───────────────────────────────────────────────────────────────
-- No necesita nada: la clave primaria es (usuario_id, activo), así que las
-- consultas por usuario_id ya usan el prefijo de ese índice.

-- ── mensajes_soporte ────────────────────────────────────────────────────────
-- Ya tiene (usuario_id, created_at) y (remitente_id, created_at desc), que
-- cubren la conversación, el límite de frecuencia y listar_conversaciones_soporte.
-- Falta el contador de no leídos del badge de /perfil para el admin:
--   .select(id, head, count).eq('leido_admin', false)
create index if not exists mensajes_no_leidos_admin_idx
  on public.mensajes_soporte (created_at)
  where not leido_admin;

analyze public.operaciones_simuladas;
analyze public.senales;
analyze public.noticias;
analyze public.usuarios;
analyze public.ganancias_concursos;
analyze public.mensajes_soporte;

-- ============================================================
-- === MIGRACION 023 (023_contenido_bilingue_senales_noticias.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 024 (024_wallets_multiples_admin.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 024: hasta 3 wallets para el admin, 1 para el resto
-- Pegar en Supabase → SQL Editor → Run (después de la migración 023)
--
-- El admin puede guardar hasta 3 direcciones USDT-ERC20 en su perfil
-- (wallet_usdt_erc20 ya existía; se agregan _2 y _3). Un usuario normal
-- se queda exactamente igual que antes: una sola wallet. La restricción
-- se aplica también a nivel de base (no solo ocultando los campos en la
-- interfaz) para que no se pueda saltar llamando la API directo.
-- ============================================================

alter table public.usuarios
  add column wallet_usdt_erc20_2 text,
  add column wallet_usdt_erc20_3 text;

alter table public.usuarios
  add constraint wallet_usdt_erc20_2_formato
  check (
    wallet_usdt_erc20_2 is null
    or wallet_usdt_erc20_2 ~ '^0x[a-fA-F0-9]{40}$'
  );

alter table public.usuarios
  add constraint wallet_usdt_erc20_3_formato
  check (
    wallet_usdt_erc20_3 is null
    or wallet_usdt_erc20_3 ~ '^0x[a-fA-F0-9]{40}$'
  );

-- Reemplaza la versión de la migración 021 agregando el bloqueo de las
-- wallets 2 y 3 para quien no sea admin.
create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
declare
  v_es_admin boolean := public.es_admin();
begin
  if (new.role is distinct from old.role
      or new.activo is distinct from old.activo
      or new.trading_habilitado is distinct from old.trading_habilitado)
     and not v_es_admin then
    raise exception 'Solo un admin puede cambiar el rol, el estado o el permiso de trading de una cuenta.';
  end if;

  if (new.id is distinct from old.id
      or new.email is distinct from old.email
      or new.codigo_invitacion is distinct from old.codigo_invitacion
      or new.invitado_por is distinct from old.invitado_por
      or new.id_corto is distinct from old.id_corto
      or new.created_at is distinct from old.created_at)
     and not v_es_admin then
    raise exception 'No puedes modificar los datos de identidad de tu cuenta. Contacta a soporte.';
  end if;

  -- Solo el admin puede tener más de una wallet guardada.
  if (new.wallet_usdt_erc20_2 is not null or new.wallet_usdt_erc20_3 is not null)
     and not v_es_admin then
    raise exception 'Solo un admin puede guardar más de una wallet.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.proteger_columnas_sensibles_usuarios()
  from public, anon, authenticated;

-- ============================================================
-- === MIGRACION 025 (025_wallets_admin_publicas_y_simulacion.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 025: wallets del admin visibles para el flujo de depósito
-- simulado (RPC de solo lectura, sin exponer el resto de la fila)
-- Pegar en Supabase → SQL Editor → Run (después de la migración 024)
-- ============================================================

-- Un usuario normal no tiene (ni debe tener) permiso para leer filas
-- ajenas de `usuarios`. Esta función expone SOLO las wallets del/los
-- admin(es), nunca su email ni ninguna otra columna — para que el botón
-- "Depositar (simulación)" del perfil normal pueda mostrar una al azar.
create or replace function public.obtener_wallets_admin()
returns text[] as $$
  select coalesce(array_remove(array_agg(w), null), array[]::text[])
  from (
    select wallet_usdt_erc20 as w from public.usuarios
      where role = 'admin' and wallet_usdt_erc20 is not null
    union all
    select wallet_usdt_erc20_2 from public.usuarios
      where role = 'admin' and wallet_usdt_erc20_2 is not null
    union all
    select wallet_usdt_erc20_3 from public.usuarios
      where role = 'admin' and wallet_usdt_erc20_3 is not null
  ) t;
$$ language sql security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.obtener_wallets_admin() from public, anon;
grant execute on function public.obtener_wallets_admin() to authenticated;

-- El mensaje del cuadro de "esto es una simulación" reutiliza
-- config_portada (clave/valor genérico, ya usado para hero y nosotros)
-- bajo clave = 'simulacion_deposito' — no hace falta una tabla nueva.

-- ============================================================
-- === MIGRACION 026 (026_depositos_simulados.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 027 (027_depositos_simulados_monto_finito.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 027: el monto del depósito simulado tiene que ser un número
-- de verdad (ni NaN ni Infinity ni 400 dígitos)
-- Pegar en Supabase → SQL Editor → Run (después de 001-026)
--
-- El `check (monto > 0)` de la migración 026 NO alcanzaba: en Postgres el
-- tipo numeric admite los valores especiales 'NaN' e 'Infinity', y ambos
-- pasan la comparación (NaN se ordena por encima de cualquier número, así
-- que 'NaN' > 0 es TRUE). Cualquier usuario autenticado podía insertar
-- {"monto": "NaN"} llamando a la API directamente (sin pasar por el
-- formulario) y PostgREST devolvía ese monto como string. En el cliente,
-- monto.toFixed(2) sobre un string lanza un TypeError: eso tumbaba con un
-- 500 la página /usuarios del admin — y el admin quedaba sin manera de
-- borrar la fila, porque la propia pantalla que tiene el botón Eliminar ya
-- no cargaba. También hacía caer el /perfil del propio usuario.
--
-- Arreglo: numeric(14,2) (montos de dinero, con la escala fija) y un check
-- con tope superior. El tope es lo que descarta NaN e Infinity, porque
-- `NaN <= 100000000` es FALSE. El código además ya no usa .toFixed sobre
-- este valor, así que quedan las dos capas.
-- ============================================================

-- Por si quedara alguna fila envenenada de antes: el cast a numeric(14,2)
-- fallaría con Infinity, y el check nuevo no se podría crear con NaN.
delete from public.depositos_simulados
where monto is null
   or not (monto > 0 and monto <= 100000000);

alter table public.depositos_simulados
  drop constraint depositos_simulados_monto_check;

alter table public.depositos_simulados
  alter column monto type numeric(14, 2);

alter table public.depositos_simulados
  add constraint depositos_simulados_monto_check
  check (monto > 0 and monto <= 100000000);

-- wallet_mostrada la manda el propio cliente, así que por API directa
-- acepta cualquier texto de cualquier tamaño (se probó guardando 200 KB en
-- una sola fila). Hoy no se muestra en ninguna pantalla, así que no hay
-- XSS posible, pero es una columna de texto libre sin tope: se limita al
-- largo de una dirección ERC-20 con margen.
alter table public.depositos_simulados
  add constraint depositos_simulados_wallet_mostrada_check
  check (wallet_mostrada is null or length(wallet_mostrada) <= 120);

-- ============================================================
-- === MIGRACION 028 (028_datos_contacto_usuario.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 029 (029_admin_principal_protegido.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 029: admin "principal" protegido contra otros admins
-- Pegar en Supabase → SQL Editor → Run (después de 001-028)
--
-- La protección que ya existía (migración 012) solo evita quedarse SIN
-- NINGÚN admin activo — pero con 2+ admins, cualquiera podía desactivar,
-- quitarle el rol o bloquearle el trading a cualquier OTRO admin,
-- incluido el admin "dueño" de la cuenta. Se necesita para dar de alta un
-- admin de prueba (tester) que tenga todos los permisos de admin excepto
-- el de tocar la cuenta del admin principal.
--
-- `es_principal` se marca a mano (nunca desde la app) en como mucho una
-- cuenta. Mientras esté marcada, nadie más que esa misma cuenta puede
-- cambiarle role/activo/trading_habilitado — ni siquiera otro admin.
-- ============================================================

alter table public.usuarios
  add column es_principal boolean not null default false;

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
declare
  v_es_admin boolean := public.es_admin();
begin
  -- es_principal nunca se toca desde la aplicación, ni siquiera un admin
  -- — solo con acceso directo a la base de datos.
  if new.es_principal is distinct from old.es_principal then
    raise exception 'Ese campo no se puede modificar desde la aplicación.';
  end if;

  -- Un admin marcado como principal solo se puede modificar a sí mismo:
  -- ningún otro admin puede quitarle el rol, desactivarlo o bloquearle
  -- el trading.
  if old.es_principal
     and auth.uid() is distinct from old.id
     and (new.role is distinct from old.role
          or new.activo is distinct from old.activo
          or new.trading_habilitado is distinct from old.trading_habilitado)
  then
    raise exception 'No puedes modificar la cuenta del administrador principal.';
  end if;

  if (new.role is distinct from old.role
      or new.activo is distinct from old.activo
      or new.trading_habilitado is distinct from old.trading_habilitado)
     and not v_es_admin then
    raise exception 'Solo un admin puede cambiar el rol, el estado o el permiso de trading de una cuenta.';
  end if;

  if (new.id is distinct from old.id
      or new.email is distinct from old.email
      or new.codigo_invitacion is distinct from old.codigo_invitacion
      or new.invitado_por is distinct from old.invitado_por
      or new.id_corto is distinct from old.id_corto
      or new.created_at is distinct from old.created_at)
     and not v_es_admin then
    raise exception 'No puedes modificar los datos de identidad de tu cuenta. Contacta a soporte.';
  end if;

  -- Solo el admin puede tener más de una wallet guardada.
  if (new.wallet_usdt_erc20_2 is not null or new.wallet_usdt_erc20_3 is not null)
     and not v_es_admin then
    raise exception 'Solo un admin puede guardar más de una wallet.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = pg_catalog, public, pg_temp;

revoke all on function public.proteger_columnas_sensibles_usuarios()
  from public, anon, authenticated;

-- ============================================================
-- === MIGRACION 030 (030_ganancias_automaticas_y_referidos.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 030: ganancias de Trade del día pasan a "pendiente de pago",
-- el saldo de práctica deja de moverse con el resultado, y base para el
-- módulo de referidos
-- Pegar en Supabase → SQL Editor → Run (después de 001-029)
--
-- ANTES: al cerrar una operación, saldo_virtual.saldo_usd sumaba
-- monto_usado + ganancia_perdida (podía subir o bajar según el resultado).
-- AHORA: el saldo de práctica SIEMPRE recupera solo el monto_usado, gane o
-- pierda — deja de fluctuar con el trading. Si hubo ganancia (> 0), se
-- crea automáticamente una fila en ganancias_concursos con pagado=false
-- (la misma pantalla de "Ganancias pendientes de pago" en Reportes que ya
-- existe para premios de concursos). Si hubo pérdida, no se crea nada
-- nuevo — el historial ya queda en operaciones_simuladas (con el pick,
-- precio de entrada/salida y el monto perdido), que ya se muestra en
-- /usuarios/[id] y en el propio Trade del día del usuario.
--
-- `ganancias_concursos` gana columnas para poder distinguir el origen de
-- cada fila sin romper las que ya existen (todas quedan origen='concurso'
-- por default) y para el módulo de referidos.
-- ============================================================

alter table public.ganancias_concursos
  add column origen text not null default 'concurso'
    check (origen in ('concurso', 'trade', 'referido')),
  add column operacion_id uuid references public.operaciones_simuladas(id) on delete set null,
  add column invitado_id uuid references public.usuarios(id) on delete set null;

-- Cada persona invitada genera como mucho una fila de premio por
-- referido, para que el admin no pueda otorgarlo dos veces sin querer.
create unique index if not exists ganancias_concursos_invitado_unico
  on public.ganancias_concursos (invitado_id)
  where invitado_id is not null;

create index if not exists ganancias_concursos_operacion_idx
  on public.ganancias_concursos (operacion_id)
  where operacion_id is not null;

-- ------------------------------------------------------------
-- cerrar_operacion (usuario/admin cerrando su propia operación)
-- ------------------------------------------------------------
create or replace function public.cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar operaciones. Espera a que se liquide la sesión.';
  end if;
  if p_precio_salida is null
     or p_precio_salida = 'NaN'::numeric
     or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id
    and usuario_id = v_usuario_id
    and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - v_operacion.precio_entrada) * v_operacion.cantidad
    else (v_operacion.precio_entrada - p_precio_salida) * v_operacion.cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = now()
  where id = p_operacion_id
  returning * into v_operacion;

  -- El saldo de práctica siempre recupera lo invertido, gane o pierda — el
  -- resultado ya no lo toca. La ganancia real (si la hubo) se paga aparte.
  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- admin_cerrar_operacion (admin cerrando la operación de OTRO usuario)
-- ------------------------------------------------------------
create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;
  if p_precio_salida is null
     or p_precio_salida = 'NaN'::numeric
     or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - v_operacion.precio_entrada) * v_operacion.cantidad
    else (v_operacion.precio_entrada - p_precio_salida) * v_operacion.cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = now()
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_operacion.usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer;

revoke execute on function public.cerrar_operacion(uuid, numeric) from public;
grant execute on function public.cerrar_operacion(uuid, numeric) to authenticated;
revoke execute on function public.admin_cerrar_operacion(uuid, numeric) from public;
grant execute on function public.admin_cerrar_operacion(uuid, numeric) to authenticated;

-- ============================================================
-- === MIGRACION 031 (031_search_path_cierre_operaciones.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 031: restaura el search_path fijo en las funciones de cierre
-- de operaciones
-- Pegar en Supabase → SQL Editor → Run (después de 001-030)
--
-- La migración 021 le puso a TODAS las funciones `security definer` un
-- search_path fijo:
--
--   alter function ... set search_path = pg_catalog, public, pg_temp;
--
-- Eso es la protección estándar contra el secuestro de search_path en
-- funciones que corren con los permisos de su dueño (CVE-2018-1058): sin
-- él, la función resuelve los nombres sin esquema usando el search_path
-- de QUIEN la llama, no el del dueño.
--
-- La migración 030 volvió a escribir `cerrar_operacion` y
-- `admin_cerrar_operacion` con `create or replace function` SIN repetir
-- la cláusula `set search_path`. En PostgreSQL, `create or replace` no
-- conserva la configuración de la función anterior: la reemplaza con los
-- valores por defecto. Resultado: las dos funciones que mueven dinero al
-- liquidar una operación quedaron como las ÚNICAS `security definer` del
-- esquema con search_path mutable (se comprueba con
-- `select proname, proconfig from pg_proc where prosecdef`), y también
-- las marca el linter de Supabase como `function_search_path_mutable`.
--
-- Hoy no es explotable de forma directa (el rol `authenticated` no tiene
-- CREATE sobre ningún esquema del search_path y PostgreSQL no busca
-- funciones ni operadores en pg_temp de forma implícita), pero es una
-- regresión de un control de seguridad que una auditoría anterior había
-- puesto a propósito. Se restaura.
--
-- Ojo al tocar estas funciones en el futuro: si se vuelven a escribir con
-- `create or replace`, hay que repetir la cláusula `set search_path`
-- dentro de la propia definición o volver a correr este `alter function`.
-- ============================================================

alter function public.cerrar_operacion(uuid, numeric)
  set search_path = pg_catalog, public, pg_temp;

alter function public.admin_cerrar_operacion(uuid, numeric)
  set search_path = pg_catalog, public, pg_temp;

-- Comprobación: esta consulta no debe devolver ninguna fila.
--
--   select p.proname
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.prosecdef and p.proconfig is null;

-- ============================================================
-- === MIGRACION 032 (032_forzar_monto_completo_servidor.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 032: abrir_operacion ignora el monto recibido y siempre usa
-- el saldo completo — cierra la superficie de ataque, no solo la UI
-- Pegar en Supabase → SQL Editor → Run (después de 001-031)
--
-- El campo de monto en el formulario ya era de solo lectura (sesión
-- anterior), pero eso es cosmético: cualquiera podía llamar el RPC o la
-- Server Action directo con un p_monto distinto al saldo completo. La
-- auditoría de hoy confirmó que era explotable (aunque de severidad baja,
-- sin forma de perjudicar al usuario ni a la plataforma) y recomendó
-- cerrarlo de raíz: se deja el parámetro p_monto en la firma para no
-- tener que tocar la Server Action que la llama, pero su valor ya NO se
-- usa para nada — la cantidad y el monto_usado siempre salen del saldo
-- real en saldo_virtual, leído aquí mismo con bloqueo de fila.
--
-- Se repite el `set search_path` fijo a propósito: la migración 030 lo
-- había perdido sin querer al reescribir esta función con
-- "create or replace" (create or replace NO conserva la config anterior),
-- y la auditoría de hoy lo encontró y ya lo corrigió en la 031. Esta
-- migración también reescribe la función, así que hay que repetirlo aquí
-- para no volver a perderlo.
-- ============================================================

drop function if exists public.abrir_operacion(text, text, numeric, numeric, text);

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric, -- ya no se usa: se opera siempre con el saldo completo
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_precio is null or p_precio = 'NaN'::numeric or p_precio <= 0 then
    raise exception 'No se pudo determinar un precio de entrada válido.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo into v_pick
  from public.pick_del_dia
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  select trading_habilitado into v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := v_saldo / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, p_precio, v_cantidad, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke execute on function public.abrir_operacion(text, text, numeric, numeric, text) from public;
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text) to authenticated;

-- ============================================================
-- === MIGRACION 033 (033_recompensa_referido_automatica.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 033: la recompensa por referido se genera SOLA al registrarse
-- Pegar en Supabase → SQL Editor → Run (después de 001-032)
--
-- Antes, el admin tenía que entrar a /referidos y darle clic a "Otorgar
-- premio" por cada persona invitada. Ahora: en el momento mismo en que
-- alguien se registra con un código de invitación válido, se le crea
-- automáticamente al invitador una fila en ganancias_concursos con
-- pagado=false, usando el monto configurado en ese momento (config_portada,
-- clave='premio_referido' — el mismo que edita AdminPremioReferidoForm en
-- /referidos). El admin ya no "otorga" nada, solo marca pagado cuando
-- corresponda (BotonPagoGanancia, sin cambios).
--
-- El botón "Otorgar premio" de /referidos se deja tal cual como respaldo
-- manual: solo aparece cuando NO existe todavía una fila de recompensa
-- para ese invitado (por ejemplo, relaciones de invitado_por de ANTES de
-- esta migración), así que sigue siendo útil sin tocar ni una línea de
-- ese componente.
--
-- Se repite el `set search_path` fijo a propósito (ver migraciones 030 y
-- 031): "create or replace function" resetea esa configuración si no se
-- repite explícitamente, y esta es una función que corre en cada alta de
-- usuario.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  v_nuevo_id_corto int;
  v_premio numeric;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20, id_corto)
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial, v_nuevo_id_corto
  );

  if id_invitador is not null then
    select coalesce((valor ->> 'monto')::numeric, 5)
    into v_premio
    from public.config_portada
    where clave = 'premio_referido';

    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      id_invitador, coalesce(v_premio, 5), 'Referido: ' || new.email, 'referido', new.id
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 034 (034_recompensa_referido_por_deposito.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 034: la recompensa por referido pasa a ser un % del depósito
-- simulado del invitado, más un bono repetible por cantidad de referidos
-- Pegar en Supabase → SQL Editor → Run (después de 001-033)
--
-- Reemplaza el diseño de la migración 033 (premio fijo automático al
-- REGISTRARSE) por este, definitivo:
--
-- 1) Cuando un usuario invitado hace SU depósito simulado (una sola vez
--    por usuario, ver migración 026), se le genera automáticamente a
--    quien lo invitó una recompensa PENDIENTE = porcentaje configurado ×
--    el monto de ese depósito. Si nunca deposita, no hay recompensa por
--    esa persona — es la señal de que fue un referido "calificado".
-- 2) Cada vez que el invitador acumula un múltiplo del umbral configurado
--    de referidos calificados (10, 20, 30...), se le genera además un
--    bono fijo configurado, también pendiente de pago.
--
-- config_portada.clave='premio_referido' cambia de forma:
--   ANTES:  { "monto": 5 }
--   AHORA:  { "porcentaje": 10, "bono_cada": 10, "bono_monto": 1000 }
-- (el helper de la app y el form de admin se actualizan aparte en el
-- mismo commit).
--
-- Por eso se revierte el paso de la 033 que insertaba la recompensa
-- dentro de handle_new_user() — ya no aplica, la recompensa se calcula
-- en el depósito, no en el registro.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Revertir handle_new_user() al comportamiento de antes de la 033
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  v_nuevo_id_corto int;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20, id_corto)
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial, v_nuevo_id_corto
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ------------------------------------------------------------
-- 2) Recompensa automática al depositar (comisión + bono por meta)
-- ------------------------------------------------------------
create or replace function public.otorgar_recompensa_referido()
returns trigger as $$
declare
  v_invitador uuid;
  v_email_invitado text;
  v_config jsonb;
  v_porcentaje numeric;
  v_bono_cada int;
  v_bono_monto numeric;
  v_comision numeric;
  v_calificados_count int;
begin
  select invitado_por, email into v_invitador, v_email_invitado
  from public.usuarios
  where id = new.usuario_id;

  -- Este usuario no llegó por invitación de nadie: no hay a quién premiar.
  if v_invitador is null then
    return new;
  end if;

  select valor into v_config
  from public.config_portada
  where clave = 'premio_referido';

  v_porcentaje := coalesce((v_config ->> 'porcentaje')::numeric, 10);
  v_bono_cada := coalesce((v_config ->> 'bono_cada')::int, 10);
  v_bono_monto := coalesce((v_config ->> 'bono_monto')::numeric, 1000);

  v_comision := round(new.monto * greatest(v_porcentaje, 0) / 100, 2);

  if v_comision > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      v_invitador, v_comision,
      'Referido (' || v_porcentaje || '%): ' || v_email_invitado,
      'referido', new.usuario_id
    );
  end if;

  -- Cuenta cuántos referidos de este invitador ya hicieron su depósito
  -- (son los "calificados" para el bono por meta).
  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id
  where u.invitado_por = v_invitador;

  if v_bono_cada > 0 and v_calificados_count > 0
     and v_calificados_count % v_bono_cada = 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen
    ) values (
      v_invitador, v_bono_monto,
      'Bono por ' || v_calificados_count || ' referidos calificados',
      'referido'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists on_deposito_simulado_recompensa on public.depositos_simulados;
create trigger on_deposito_simulado_recompensa
  after insert on public.depositos_simulados
  for each row execute procedure public.otorgar_recompensa_referido();

revoke all on function public.otorgar_recompensa_referido() from public, anon, authenticated;

-- ============================================================
-- === MIGRACION 035 (035_fix_recompensa_referido_al_repetir.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 035: fix — repetir el depósito simulado (tras borrarlo el
-- admin) ya no revienta ni duplica premios
-- Pegar en Supabase → SQL Editor → Run (después de 001-034)
--
-- Encontrado en QA propio de la 034, con un ciclo real: usuario deposita
-- → genera comisión pendiente → admin borra el depósito para que lo
-- repita (flujo ya existente de la migración 026) → usuario deposita de
-- nuevo. Dos bugs reales:
--
-- 1) El INSERT de la comisión reventaba con
--    "duplicate key value violates unique constraint
--    ganancias_concursos_invitado_unico" — y como el trigger corre DENTRO
--    de la misma transacción del insert en depositos_simulados, el
--    depósito nuevo se revertía completo (el usuario no podía repetirlo,
--    aunque la UI solo mostraba el mensaje genérico de "no se pudo
--    registrar"). Fix: `on conflict (invitado_id) do update`, y solo si
--    la comisión anterior seguía SIN pagar (si ya se pagó, no se toca —
--    el admin ya la resolvió con el monto que le tocó en su momento).
--
-- 2) El bono por meta se recalculaba iafresh cada vez: si el conteo de
--    referidos calificados quedaba en el mismo múltiplo de antes (típico
--    al repetir un depósito, el conteo de personas no cambia), se
--    insertaba OTRO bono duplicado por la misma meta. Fix: comprobar que
--    no exista ya un bono con ese mismo conteo antes de insertar.
-- ============================================================

create or replace function public.otorgar_recompensa_referido()
returns trigger as $$
declare
  v_invitador uuid;
  v_email_invitado text;
  v_config jsonb;
  v_porcentaje numeric;
  v_bono_cada int;
  v_bono_monto numeric;
  v_comision numeric;
  v_calificados_count int;
  v_concepto_bono text;
begin
  select invitado_por, email into v_invitador, v_email_invitado
  from public.usuarios
  where id = new.usuario_id;

  if v_invitador is null then
    return new;
  end if;

  select valor into v_config
  from public.config_portada
  where clave = 'premio_referido';

  v_porcentaje := coalesce((v_config ->> 'porcentaje')::numeric, 10);
  v_bono_cada := coalesce((v_config ->> 'bono_cada')::int, 10);
  v_bono_monto := coalesce((v_config ->> 'bono_monto')::numeric, 1000);

  v_comision := round(new.monto * greatest(v_porcentaje, 0) / 100, 2);

  if v_comision > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      v_invitador, v_comision,
      'Referido (' || v_porcentaje || '%): ' || v_email_invitado,
      'referido', new.usuario_id
    )
    -- Si el usuario repite su depósito (el admin le borró el anterior
    -- para permitírselo), ya existe una fila con este invitado_id: se
    -- actualiza al nuevo monto en vez de fallar, pero solo si esa
    -- comisión seguía pendiente — una ya pagada no se toca.
    -- El índice único es PARCIAL (where invitado_id is not null): ON
    -- CONFLICT tiene que repetir esa misma condición para poder usarlo,
    -- si no Postgres no lo reconoce como destino válido de conflicto.
    on conflict (invitado_id) where invitado_id is not null do update
    set monto = excluded.monto,
        concepto = excluded.concepto
    where public.ganancias_concursos.pagado = false;
  end if;

  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id
  where u.invitado_por = v_invitador;

  if v_bono_cada > 0 and v_calificados_count > 0
     and v_calificados_count % v_bono_cada = 0 then
    v_concepto_bono := 'Bono por ' || v_calificados_count || ' referidos calificados';

    if not exists (
      select 1 from public.ganancias_concursos
      where usuario_id = v_invitador
        and origen = 'referido'
        and invitado_id is null
        and concepto = v_concepto_bono
    ) then
      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, origen
      ) values (
        v_invitador, v_bono_monto, v_concepto_bono, 'referido'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 036 (036_invitado_por_inmutable.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 036: invitado_por pasa a ser inmutable, ni siquiera el admin
-- lo puede reescribir
-- Pegar en Supabase → SQL Editor → Run (después de 001-035)
--
-- La auditoría de hoy encontró que un admin autenticado (con la sola
-- anon key pública) SÍ podía reescribir usuarios.invitado_por de
-- cualquiera vía PostgREST directo, porque esa columna estaba en el
-- bloque de "identidad" que solo bloqueaba a los no-admins
-- (`and not v_es_admin`). Con eso se podía armar un ciclo (A invitado
-- por B y B por A, o alguien invitado por sí mismo), que tumbaba
-- /referidos con un "Maximum call stack size exceeded" — ya mitigado del
-- lado de la UI (ArbolReferidos.tsx / BotonExportarArbolReferidos.tsx
-- cortan la recursión y avisan), pero la causa de fondo seguía abierta:
-- nada impedía escribir el dato corrupto en primer lugar.
--
-- Ahora invitado_por es inmutable para TODOS sin excepción — solo
-- handle_new_user() lo asigna, una sola vez, al crearse la cuenta (esa
-- función hace un INSERT, no un UPDATE, así que este trigger de UPDATE
-- no la afecta). Si alguna vez hace falta corregir a mano una relación
-- de referido mal asignada, hay que hacerlo con acceso directo a la
-- base (el mismo nivel de acceso que ya hace falta para cosas como
-- rotar el TRADING_SERVER_SECRET), no desde la aplicación.
-- ============================================================

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
declare
  v_es_admin boolean := public.es_admin();
begin
  -- es_principal nunca se toca desde la aplicación, ni siquiera un admin
  -- — solo con acceso directo a la base de datos.
  if new.es_principal is distinct from old.es_principal then
    raise exception 'Ese campo no se puede modificar desde la aplicación.';
  end if;

  -- invitado_por es inmutable para todos, incluido el admin: solo el
  -- registro lo asigna, una sola vez.
  if new.invitado_por is distinct from old.invitado_por then
    raise exception 'La relación de quién invitó a quién no se puede modificar.';
  end if;

  -- Un admin marcado como principal solo se puede modificar a sí mismo:
  -- ningún otro admin puede quitarle el rol, desactivarlo o bloquearle
  -- el trading.
  if old.es_principal
     and auth.uid() is distinct from old.id
     and (new.role is distinct from old.role
          or new.activo is distinct from old.activo
          or new.trading_habilitado is distinct from old.trading_habilitado)
  then
    raise exception 'No puedes modificar la cuenta del administrador principal.';
  end if;

  if (new.role is distinct from old.role
      or new.activo is distinct from old.activo
      or new.trading_habilitado is distinct from old.trading_habilitado)
     and not v_es_admin then
    raise exception 'Solo un admin puede cambiar el rol, el estado o el permiso de trading de una cuenta.';
  end if;

  if (new.id is distinct from old.id
      or new.email is distinct from old.email
      or new.codigo_invitacion is distinct from old.codigo_invitacion
      or new.id_corto is distinct from old.id_corto
      or new.created_at is distinct from old.created_at)
     and not v_es_admin then
    raise exception 'No puedes modificar los datos de identidad de tu cuenta. Contacta a soporte.';
  end if;

  -- Solo el admin puede tener más de una wallet guardada.
  if (new.wallet_usdt_erc20_2 is not null or new.wallet_usdt_erc20_3 is not null)
     and not v_es_admin then
    raise exception 'Solo un admin puede guardar más de una wallet.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 037 (037_reponer_chequeo_cuenta_activa_abrir_operacion.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 037: repone el chequeo de cuenta activa en abrir_operacion,
-- perdido sin querer en la migración 032
-- Pegar en Supabase → SQL Editor → Run (después de 001-036)
--
-- Encontrado en QA de Fase 2 (perfil y datos personales), al revisar de
-- dónde sale el saldo que se muestra en /perfil: la migración 021 agregó
-- a abrir_operacion() la validación "if v_activo is not true then raise
-- exception 'Tu cuenta está desactivada.'" — motivada por el mismo
-- razonamiento que ya protege a mensajes_soporte y favoritos (una cuenta
-- desactivada solo lo está de verdad si también lo está a nivel de base,
-- no solo en las páginas de Next.js).
--
-- La migración 030 reescribió cerrar_operacion/admin_cerrar_operacion pero
-- no tocó abrir_operacion. La migración 032 sí volvió a escribir
-- abrir_operacion completa (para forzar el monto al saldo íntegro) —y al
-- hacerlo con un "create or replace" partiendo de una copia vieja del
-- cuerpo de la función, se le perdió por completo la variable v_activo y
-- su chequeo. Quedó re-verificado contra la base real: con la anon key y
-- una sesión de un usuario con activo=false, el RPC abrir_operacion
-- completaba sin error y abría la operación igual, saltándose por
-- completo el estado de la cuenta — el mismo tipo de bypass que la
-- migración 021 ya había cerrado para el resto de la escritura de datos.
--
-- Fix: se repone el chequeo, sin tocar nada más del comportamiento de la
-- migración 032 (sigue operando siempre con el saldo completo).
-- ============================================================

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_precio is null or p_precio = 'NaN'::numeric or p_precio <= 0 then
    raise exception 'No se pudo determinar un precio de entrada válido.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  select activo into v_pick
  from public.pick_del_dia
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := v_saldo / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, p_precio, v_cantidad, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke execute on function public.abrir_operacion(text, text, numeric, numeric, text) from public, anon;
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text) to authenticated;

-- ============================================================
-- === MIGRACION 038 (038_admin_agregar_saldo_rechaza_infinity.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 038: admin_agregar_saldo rechaza también Infinity/-Infinity
-- Pegar en Supabase → SQL Editor → Run (después de 001-037)
--
-- La QA de Fase 6 (gestión de usuarios / reportes) encontró que
-- admin_agregar_saldo (013, endurecida en 019 contra 'NaN') seguía
-- aceptando p_monto = 'Infinity' llamando al RPC directo (con la sola
-- anon key, sesión de admin). El chequeo existente solo comparaba contra
-- 0 y 'NaN'::numeric, y 'Infinity' pasa ambas: no es igual a 0 ni a NaN.
-- saldo_virtual.saldo_usd es un numeric sin CHECK ni tope (a diferencia
-- de depositos_simulados.monto, ya blindado en la migración 027 con el
-- mismo problema), así que el saldo del usuario quedaba en 'Infinity' de
-- forma irrecuperable por este mismo RPC: greatest(0, Infinity + X) es
-- Infinity para cualquier X finito, así que ni siquiera restar arregla
-- el número — hay que corregirlo a mano en la base.
--
-- Arreglo, mismo patrón que la migración 027: en vez de comparar contra
-- valores especiales uno por uno, se exige que el monto cumpla un rango
-- finito. 'NaN' y 'Infinity'/'-Infinity' fallan cualquier comparación de
-- rango (evaluar a FALSE), así que quedan cubiertos sin necesidad de
-- casos especiales adicionales.
-- ============================================================

create or replace function public.admin_agregar_saldo(
  p_usuario_id uuid,
  p_monto numeric
) returns public.saldo_virtual as $$
declare
  v_saldo public.saldo_virtual;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede ajustar el saldo de otro usuario.';
  end if;

  -- p_monto <> 0 además del rango: 'NaN' no es estrictamente mayor ni
  -- menor que ningún límite (la comparación da FALSE), así que el BETWEEN
  -- ya lo descarta, pero se deja el chequeo explícito por claridad con la
  -- versión anterior. Infinity/-Infinity quedan fuera del rango.
  if p_monto is null
     or p_monto = 0
     or p_monto = 'NaN'::numeric
     or p_monto < -100000000
     or p_monto > 100000000
  then
    raise exception 'El monto debe ser un número finito y distinto de cero.';
  end if;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + p_monto),
      actualizado_en = now()
  where usuario_id = p_usuario_id
  returning * into v_saldo;

  if v_saldo.usuario_id is null then
    raise exception 'Este usuario no tiene saldo virtual inicializado.';
  end if;

  return v_saldo;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_agregar_saldo(uuid, numeric) from public, anon;
grant execute on function public.admin_agregar_saldo(uuid, numeric) to authenticated;

-- ============================================================
-- === MIGRACION 039 (039_nombre_telefono_en_registro.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 039: handle_new_user() ahora guarda nombre y teléfono
-- si vienen en el registro (RegistroForm.tsx los manda opcionalmente
-- via raw_user_meta_data, igual que ya hacía con "ref" y "wallet").
-- Pegar en Supabase → SQL Editor → Run (después de 001-038)
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  nombre_inicial text;
  telefono_inicial text;
  v_nuevo_id_corto int;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  nombre_inicial := nullif(trim(new.raw_user_meta_data ->> 'nombre'), '');
  telefono_inicial := nullif(trim(new.raw_user_meta_data ->> 'telefono'), '');
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (
    id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20,
    id_corto, nombre, telefono
  )
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    v_nuevo_id_corto, nombre_inicial, telefono_inicial
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 040 (040_validar_codigo_invitacion.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 040: valida el código de invitación antes de registrar,
-- y una cuenta desactivada deja de poder recibir referidos nuevos.
-- Pegar en Supabase → SQL Editor → Run (después de 001-039)
--
-- Hallazgos del QA del 2026-09-24 sobre el registro con código manual:
-- 1) Un código mal tipeado se perdía en silencio y era irrecuperable
--    (invitado_por es inmutable desde la migración 036) — ahora el
--    formulario puede preguntar si el código existe ANTES de enviar.
-- 2) El código de una cuenta desactivada seguía sirviendo para sumar
--    referidos nuevos a su árbol — se decide bloquearlo.
-- ============================================================

-- ------------------------------------------------------------
-- 1) RPC pública de solo lectura: ¿este código existe y su dueño
--    está activo? No expone nada más de la cuenta (ni el email, ni
--    el id) — mismo patrón que estadisticas_publicas().
-- ------------------------------------------------------------
create or replace function public.codigo_invitacion_valido(p_codigo text)
returns boolean as $$
  select exists (
    select 1
    from public.usuarios
    where codigo_invitacion = upper(trim(coalesce(p_codigo, '')))
      and activo = true
  );
$$ language sql stable security definer
   set search_path = pg_catalog, public, pg_temp;

grant execute on function public.codigo_invitacion_valido(text) to anon, authenticated;

-- ------------------------------------------------------------
-- 2) handle_new_user(): una cuenta desactivada ya no puede ser
--    invitadora de gente nueva (defensa en profundidad — el chequeo
--    de arriba es solo un aviso previo en el formulario, esto es lo
--    que de verdad decide invitado_por al crear la cuenta).
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  nombre_inicial text;
  telefono_inicial text;
  v_nuevo_id_corto int;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref
      and activo = true;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  nombre_inicial := nullif(trim(new.raw_user_meta_data ->> 'nombre'), '');
  telefono_inicial := nullif(trim(new.raw_user_meta_data ->> 'telefono'), '');
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (
    id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20,
    id_corto, nombre, telefono
  )
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    v_nuevo_id_corto, nombre_inicial, telefono_inicial
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 041 (041_solicitudes_retiro.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 041: Solicitudes de retiro (contra ganancias, no contra el
-- saldo de inversión/práctica)
-- Pegar en Supabase → SQL Editor → Run (después de 001-040)
--
-- El usuario ya podía ver sus ganancias (ganancias_concursos) marcadas
-- pendiente/pagado, pero quien decidía CUÁNDO pagarlas era siempre el
-- admin (empujando el pago). Esto agrega el camino inverso: el usuario
-- pide un monto puntual de lo que tiene disponible, y el admin lo ve en
-- una cola para procesar.
--
-- "Disponible para retirar" = suma de ganancias_concursos.monto con
-- pagado=false, MENOS lo que ya esté solicitado (pendiente o pagado) en
-- esta tabla nueva — así no se puede pedir dos veces el mismo dinero.
-- No se tocan las filas de ganancias_concursos al pagar un retiro (no se
-- marcan pagado=true una por una): la tabla de solicitudes es su propio
-- libro de "cuánto de ese fondo ya se reclamó". Simplificación aceptada
-- a propósito para no tener que partir montos entre filas que no calzan
-- exacto; el efecto secundario es que el listado de "Ganancias" del
-- perfil puede seguir mostrando como "Pendiente" dinero que ya se pagó
-- vía un retiro — aceptable por ahora, revisar si en el futuro hace
-- falta reconciliar ambas vistas con precisión de centavos.
-- ============================================================

create table public.solicitudes_retiro (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  monto numeric(14,2) not null,
  wallet_destino text not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'pagado', 'rechazado')),
  nota_admin text,
  created_at timestamptz not null default now(),
  procesado_en timestamptz,
  procesado_por uuid references public.usuarios(id),
  -- Mismo patrón de rango finito que las migraciones 027/038 (rechaza
  -- NaN/Infinity sin necesitar casos especiales: en Postgres NaN se
  -- ordena como mayor que cualquier valor finito, así que cae en el
  -- límite superior igual que Infinity).
  constraint monto_valido check (monto > 0 and monto < 100000000)
);

create index on public.solicitudes_retiro (usuario_id, created_at);
create index on public.solicitudes_retiro (estado);

alter table public.solicitudes_retiro enable row level security;

create policy "usuario ve sus solicitudes, admin ve todas"
  on public.solicitudes_retiro for select
  using (usuario_id = auth.uid() or public.es_admin());

create policy "solo admin actualiza solicitudes"
  on public.solicitudes_retiro for update
  using (public.es_admin());

create policy "solo admin elimina solicitudes"
  on public.solicitudes_retiro for delete
  using (public.es_admin());

-- No hay policy de insert: la única forma de crear una fila es la RPC de
-- abajo, que calcula el disponible server-side (nunca confiar en un
-- monto que mande el cliente sin verificarlo contra la base).
revoke all on public.solicitudes_retiro from anon, authenticated;
grant select on public.solicitudes_retiro to anon, authenticated;
grant update, delete on public.solicitudes_retiro to authenticated;

create function public.solicitar_retiro(p_monto numeric)
returns public.solicitudes_retiro as $$
declare
  v_usuario_id uuid := auth.uid();
  v_wallet text;
  v_pendiente numeric;
  v_ya_solicitado numeric;
  v_disponible numeric;
  v_nueva public.solicitudes_retiro;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado.';
  end if;

  if p_monto is null or p_monto <= 0 or p_monto >= 100000000 then
    raise exception 'Monto invalido.';
  end if;

  select wallet_usdt_erc20 into v_wallet
  from public.usuarios
  where id = v_usuario_id;

  if v_wallet is null or trim(v_wallet) = '' then
    raise exception 'Registra tu wallet USDT (ERC20) en tu perfil antes de solicitar un retiro.';
  end if;

  if exists (
    select 1 from public.solicitudes_retiro
    where usuario_id = v_usuario_id and estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end if;

  select coalesce(sum(monto), 0) into v_pendiente
  from public.ganancias_concursos
  where usuario_id = v_usuario_id and pagado = false;

  select coalesce(sum(monto), 0) into v_ya_solicitado
  from public.solicitudes_retiro
  where usuario_id = v_usuario_id and estado in ('pendiente', 'pagado');

  v_disponible := v_pendiente - v_ya_solicitado;

  if round(p_monto, 2) > v_disponible then
    raise exception 'No puedes retirar mas de lo que tienes disponible.';
  end if;

  insert into public.solicitudes_retiro (usuario_id, monto, wallet_destino)
  values (v_usuario_id, round(p_monto, 2), v_wallet)
  returning * into v_nueva;

  return v_nueva;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.solicitar_retiro(numeric) from public, anon;
grant execute on function public.solicitar_retiro(numeric) to authenticated;

-- ============================================================
-- === MIGRACION 042 (042_retiro_serializar_por_usuario.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 042: Retiros — serializar solicitar_retiro() por usuario
-- Pegar en Supabase → SQL Editor → Run (después de 001-041)
--
-- En la 041, solicitar_retiro() hace "¿ya tiene una pendiente?" y
-- "¿cuánto le queda disponible?" con SELECTs normales y luego INSERT.
-- En READ COMMITTED dos llamadas simultáneas del mismo usuario (dos
-- pestañas, doble clic, un script) pueden pasar las dos los chequeos
-- antes de que cualquiera haga commit, e insertar DOS solicitudes
-- pendientes por el mismo dinero (el disponible se descontaría dos
-- veces del mismo fondo). En la QA no se logró reproducir por HTTP
-- (la ventana es de microsegundos), pero la lógica lo permite.
--
-- Arreglo:
--  1) Un advisory lock transaccional por usuario al entrar a la RPC:
--     las llamadas del mismo usuario se procesan de a una, y la segunda
--     ya ve la fila que insertó la primera.
--  2) Índice único parcial como respaldo a nivel de base: nunca puede
--     haber más de una solicitud 'pendiente' por usuario, venga de donde
--     venga.
-- ============================================================

create unique index if not exists solicitudes_retiro_una_pendiente_por_usuario
  on public.solicitudes_retiro (usuario_id)
  where estado = 'pendiente';

create or replace function public.solicitar_retiro(p_monto numeric)
returns public.solicitudes_retiro as $$
declare
  v_usuario_id uuid := auth.uid();
  v_wallet text;
  v_pendiente numeric;
  v_ya_solicitado numeric;
  v_disponible numeric;
  v_nueva public.solicitudes_retiro;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado.';
  end if;

  if p_monto is null or p_monto <= 0 or p_monto >= 100000000 then
    raise exception 'Monto invalido.';
  end if;

  -- Serializa las solicitudes del mismo usuario (se libera solo al
  -- terminar la transacción). No bloquea a otros usuarios.
  perform pg_advisory_xact_lock(
    hashtextextended('solicitar_retiro:' || v_usuario_id::text, 0)
  );

  select wallet_usdt_erc20 into v_wallet
  from public.usuarios
  where id = v_usuario_id;

  if v_wallet is null or trim(v_wallet) = '' then
    raise exception 'Registra tu wallet USDT (ERC20) en tu perfil antes de solicitar un retiro.';
  end if;

  if exists (
    select 1 from public.solicitudes_retiro
    where usuario_id = v_usuario_id and estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end if;

  select coalesce(sum(monto), 0) into v_pendiente
  from public.ganancias_concursos
  where usuario_id = v_usuario_id and pagado = false;

  select coalesce(sum(monto), 0) into v_ya_solicitado
  from public.solicitudes_retiro
  where usuario_id = v_usuario_id and estado in ('pendiente', 'pagado');

  v_disponible := v_pendiente - v_ya_solicitado;

  if round(p_monto, 2) > v_disponible then
    raise exception 'No puedes retirar mas de lo que tienes disponible.';
  end if;

  begin
    insert into public.solicitudes_retiro (usuario_id, monto, wallet_destino)
    values (v_usuario_id, round(p_monto, 2), v_wallet)
    returning * into v_nueva;
  exception when unique_violation then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end;

  return v_nueva;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.solicitar_retiro(numeric) from public, anon;
grant execute on function public.solicitar_retiro(numeric) to authenticated;

-- ============================================================
-- === MIGRACION 043 (043_reconciliar_retiro_con_ganancias.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 043: al pagar un retiro, reconciliar con ganancias_concursos
-- (evita pago doble)
-- Pegar en Supabase → SQL Editor → Run (después de 001-042)
--
-- Hallazgo del QA del 2026-09-25 sobre el módulo de Retiro: pagar un
-- retiro no marcaba pagado=true en ganancias_concursos, así que esas
-- mismas ganancias seguían apareciendo pendientes en Usuarios →
-- Reportes con su propio botón de pago — riesgo real de pagar el mismo
-- dinero dos veces. El usuario confirmó: reconciliar automático.
--
-- Cambios:
-- 1) Backfill retroactivo: para cada retiro YA pagado antes de esta
--    migración, marca pagado=true en las ganancias más antiguas del
--    usuario hasta cubrir ese monto (mismo criterio "oldest first" que
--    ya se usa en otras partes del proyecto, ej. bono por meta de
--    referidos). Sin esto, la fórmula nueva del punto 2 le devolvería a
--    esos usuarios como "disponible" dinero que ya recibieron.
-- 2) solicitar_retiro(): el disponible ahora resta solo los retiros en
--    estado 'pendiente' (ya no 'pendiente' Y 'pagado') — los pagados ya
--    se reflejan directo en ganancias_concursos.pagado gracias a la
--    reconciliación, restarlos aparte sería contarlos dos veces.
-- 3) admin_marcar_retiro_pagado(): reemplaza el UPDATE directo que
--    hacía BotonProcesarRetiro.tsx para "pagado" — marca la solicitud Y
--    reconcilia las ganancias en la misma transacción (todo o nada).
--    Rechazar sigue siendo un UPDATE directo, sin reconciliar (no hay
--    nada que reconciliar si no se pagó).
--
-- Simplificación que se mantiene: si el monto no divide exacto entre
-- las filas de ganancias, la ÚLTIMA fila tocada se marca pagada
-- completa aunque "sobre" un poco — no se parte una fila en dos. El
-- total reconcilia bien igual porque solicitudes_retiro sigue siendo su
-- propio libro contra el fondo pendiente.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Backfill retroactivo
-- ------------------------------------------------------------
do $$
declare
  r_retiro record;
  r_ganancia record;
  v_restante numeric;
begin
  for r_retiro in
    select id, usuario_id, monto, procesado_en, procesado_por
    from public.solicitudes_retiro
    where estado = 'pagado'
    order by created_at
  loop
    v_restante := r_retiro.monto;
    for r_ganancia in
      select id, monto
      from public.ganancias_concursos
      where usuario_id = r_retiro.usuario_id and pagado = false
      order by created_at
    loop
      exit when v_restante <= 0;
      update public.ganancias_concursos
      set pagado = true,
          pagado_en = coalesce(r_retiro.procesado_en, now()),
          pagado_por = r_retiro.procesado_por
      where id = r_ganancia.id;
      v_restante := v_restante - r_ganancia.monto;
    end loop;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 2) solicitar_retiro(): disponible solo resta 'pendiente'
-- ------------------------------------------------------------
create or replace function public.solicitar_retiro(p_monto numeric)
returns public.solicitudes_retiro as $$
declare
  v_usuario_id uuid := auth.uid();
  v_wallet text;
  v_pendiente numeric;
  v_ya_solicitado numeric;
  v_disponible numeric;
  v_nueva public.solicitudes_retiro;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado.';
  end if;

  if p_monto is null or p_monto <= 0 or p_monto >= 100000000 then
    raise exception 'Monto invalido.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('solicitar_retiro:' || v_usuario_id::text, 0)
  );

  select wallet_usdt_erc20 into v_wallet
  from public.usuarios
  where id = v_usuario_id;

  if v_wallet is null or trim(v_wallet) = '' then
    raise exception 'Registra tu wallet USDT (ERC20) en tu perfil antes de solicitar un retiro.';
  end if;

  if exists (
    select 1 from public.solicitudes_retiro
    where usuario_id = v_usuario_id and estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end if;

  select coalesce(sum(monto), 0) into v_pendiente
  from public.ganancias_concursos
  where usuario_id = v_usuario_id and pagado = false;

  -- Antes: 'pendiente','pagado'. Un retiro pagado ya redujo el fondo
  -- pendiente de verdad (reconciliacion), asi que contarlo aqui tambien
  -- lo restaria dos veces.
  select coalesce(sum(monto), 0) into v_ya_solicitado
  from public.solicitudes_retiro
  where usuario_id = v_usuario_id and estado = 'pendiente';

  v_disponible := v_pendiente - v_ya_solicitado;

  if round(p_monto, 2) > v_disponible then
    raise exception 'No puedes retirar mas de lo que tienes disponible.';
  end if;

  begin
    insert into public.solicitudes_retiro (usuario_id, monto, wallet_destino)
    values (v_usuario_id, round(p_monto, 2), v_wallet)
    returning * into v_nueva;
  exception when unique_violation then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end;

  return v_nueva;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ------------------------------------------------------------
-- 3) admin_marcar_retiro_pagado(): paga Y reconcilia, todo o nada
-- ------------------------------------------------------------
create function public.admin_marcar_retiro_pagado(p_solicitud_id uuid)
returns public.solicitudes_retiro as $$
declare
  v_admin_id uuid := auth.uid();
  v_solicitud public.solicitudes_retiro;
  v_restante numeric;
  r_ganancia record;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un retiro como pagado.';
  end if;

  -- El mismo patron que ya usaba BotonPagoGanancia.tsx: el .eq(estado,
  -- 'pendiente') implicito aqui evita que dos admins paguen la misma
  -- solicitud dos veces.
  update public.solicitudes_retiro
  set estado = 'pagado', procesado_en = now(), procesado_por = v_admin_id
  where id = p_solicitud_id and estado = 'pendiente'
  returning * into v_solicitud;

  if v_solicitud.id is null then
    raise exception 'Esta solicitud ya fue procesada.';
  end if;

  v_restante := v_solicitud.monto;
  for r_ganancia in
    select id, monto
    from public.ganancias_concursos
    where usuario_id = v_solicitud.usuario_id and pagado = false
    order by created_at
  loop
    exit when v_restante <= 0;
    update public.ganancias_concursos
    set pagado = true, pagado_en = now(), pagado_por = v_admin_id
    where id = r_ganancia.id;
    v_restante := v_restante - r_ganancia.monto;
  end loop;

  return v_solicitud;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_marcar_retiro_pagado(uuid) from public, anon;
grant execute on function public.admin_marcar_retiro_pagado(uuid) to authenticated;

-- ============================================================
-- === MIGRACION 044 (044_saldo_inicial_cero.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 044: el saldo de inversión inicial pasa de $10,000 a $0
-- Pegar en Supabase → SQL Editor → Run (después de 001-043)
--
-- Decisión del usuario (2026-09-25): un usuario nuevo ya no arranca con
-- saldo automático. El admin se lo asigna a mano cuando corresponda,
-- usando admin_agregar_saldo() (ya existe, migraciones 013/019/038) desde
-- Gestión de usuarios. "Depositar (simulación)" se queda exactamente
-- igual que hoy — sigue siendo solo un registro informativo para la
-- comisión de referidos, no acredita saldo.
--
-- Solo afecta a cuentas NUEVAS. No se toca el saldo de nadie que ya
-- exista.
-- ============================================================

alter table public.saldo_virtual
  alter column saldo_usd set default 0;

create or replace function public.handle_new_user_saldo()
returns trigger as $$
begin
  insert into public.saldo_virtual (usuario_id, saldo_usd)
  values (new.id, 0);
  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 045 (045_imagenes_soporte.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 045: imágenes de comprobante en el chat de soporte
-- Pegar en Supabase → SQL Editor → Run (después de 001-044)
--
-- Bucket privado (no público): un comprobante de pago no debe quedar
-- accesible por link directo a cualquiera que lo adivine. Se sirve
-- siempre por URL firmada de corta duración, generada bajo las mismas
-- políticas de RLS de abajo.
--
-- Convención de ruta: {usuario_id_de_la_conversación}/{uuid}.{ext} — NO
-- el id de quien sube el archivo. Así el admin puede subir dentro de la
-- conversación de un usuario, y las políticas de lectura/escritura se
-- basan en esa carpeta, no en quién es el remitente.
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'comprobantes-soporte',
  'comprobantes-soporte',
  false,
  5242880, -- 5 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy "sube comprobante a su conversacion, admin a cualquiera"
  on storage.objects for insert
  with check (
    bucket_id = 'comprobantes-soporte'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.es_admin())
  );

create policy "ve comprobante de su conversacion, admin ve todos"
  on storage.objects for select
  using (
    bucket_id = 'comprobantes-soporte'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.es_admin())
  );

alter table public.mensajes_soporte
  add column if not exists imagen_path text;

-- ============================================================
-- === MIGRACION 046 (046_limpieza_comprobantes.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 046: job diario que borra comprobantes de más de 5 días
-- Pegar en Supabase → SQL Editor → Run (después de 001-045)
--
-- Supabase bloquea el borrado directo de storage.objects por SQL ("Direct
-- deletion from storage tables is not allowed. Use the Storage API
-- instead." — confirmado empíricamente el 2026-09-25) — así que el borrado
-- de verdad tiene que pasar por la API REST de Storage, que exige la
-- service_role key (una clave distinta a la anon key, con permisos
-- completos, que nunca debe llegar al navegador). Se guarda igual que
-- TRADING_SERVER_SECRET (migración 019): en config_servidor, con RLS sin
-- políticas, solo legible por funciones SECURITY DEFINER.
--
-- IMPORTANTE — paso manual pendiente después de correr esto: reemplazar
-- el valor de placeholder por la clave real:
--   update public.config_servidor
--   set valor = 'LA_SERVICE_ROLE_KEY_REAL', actualizado_en = now()
--   where clave = 'supabase_service_role_key';
-- (Project Settings → API Keys → "service_role", en el dashboard de
-- Supabase). Sin esto, la función se ejecuta todos los días pero no hace
-- nada — no falla, solo se queda esperando la clave.
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

insert into public.config_servidor (clave, valor)
values ('supabase_service_role_key', 'FALTA-CONFIGURAR-ESTA-CLAVE')
on conflict (clave) do nothing;

create or replace function public.limpiar_comprobantes_vencidos()
returns void as $$
declare
  r record;
  v_service_key text;
begin
  select valor into v_service_key
  from public.config_servidor
  where clave = 'supabase_service_role_key';

  if v_service_key is null or v_service_key = 'FALTA-CONFIGURAR-ESTA-CLAVE' then
    raise notice 'supabase_service_role_key sin configurar todavia, se omite la limpieza de comprobantes';
    return;
  end if;

  for r in
    select id, imagen_path
    from public.mensajes_soporte
    where imagen_path is not null
      and created_at < now() - interval '5 days'
  loop
    -- net.http_delete encola la petición (asíncrono, no bloquea el loop) —
    -- suficiente para un job de limpieza que no necesita confirmar cada
    -- borrado uno por uno.
    perform net.http_delete(
      url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || r.imagen_path,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_service_key,
        'apikey', v_service_key
      )
    );
    -- Se limpia la referencia ya mismo (no espera la respuesta HTTP): el
    -- mensaje de texto (si tenía) se conserva, solo se quita el link a una
    -- imagen que ya está en proceso de borrarse.
    update public.mensajes_soporte
    set imagen_path = null
    where id = r.id;
  end loop;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

revoke all on function public.limpiar_comprobantes_vencidos() from public, anon, authenticated;

select cron.schedule(
  'limpiar-comprobantes-soporte',
  '0 6 * * *', -- todos los días a las 6:00am UTC
  $$select public.limpiar_comprobantes_vencidos()$$
);

-- ============================================================
-- === MIGRACION 047 (047_notificacion_depositos.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 047: notificación de depósitos nuevos para el admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-046)
--
-- Hoy los depósitos simulados solo se veían sueltos, uno por fila, dentro
-- de Gestión de usuarios — no había ni una cola centralizada ni forma de
-- saber cuáles son "nuevos" sin haber entrado a revisar cada usuario.
-- Mismo patrón que ya existe para mensajes de soporte (leido_admin): un
-- booleano que se marca true al visitar la pantalla nueva /depositos, y
-- un badge que cuenta los que siguen en false.
-- ============================================================

alter table public.depositos_simulados
  add column if not exists revisado_por_admin boolean not null default false;

create index if not exists depositos_simulados_sin_revisar
  on public.depositos_simulados (revisado_por_admin)
  where revisado_por_admin = false;

-- La tabla nunca tuvo policy de UPDATE (no hacía falta hasta ahora) —
-- sin esto, RLS deniega por defecto y el admin no podría marcar nada
-- como revisado.
create policy "solo admin marca depositos como revisados"
  on public.depositos_simulados for update
  using (public.es_admin())
  with check (public.es_admin());

-- ============================================================
-- === MIGRACION 048 (048_depositos_estado_pagado.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 048: estado "pagado" en depósitos (separado de "revisado")
-- Pegar en Supabase → SQL Editor → Run (después de 001-047)
--
-- "revisado_por_admin" (migración 047) solo dice que el admin YA VIO el
-- depósito — no que ya le acreditó el saldo correspondiente a mano en
-- Gestión de usuarios. Se agrega un estado separado para eso, mismo
-- patrón que ya usan ganancias_concursos y solicitudes_retiro
-- (pagado/pagado_en/pagado_por).
-- ============================================================

alter table public.depositos_simulados
  add column if not exists pagado boolean not null default false,
  add column if not exists pagado_en timestamptz,
  add column if not exists pagado_por uuid references public.usuarios(id);

-- La policy de UPDATE de la migración 047 ya es "solo admin, cualquier
-- columna" (using/with check es_admin()), así que estas columnas nuevas
-- quedan cubiertas sin necesitar una policy aparte.

-- ============================================================
-- === MIGRACION 049 (049_deposito_pagado_acredita_saldo.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 049: marcar un depósito como pagado ahora SÍ acredita el
-- saldo de inversión (por el monto exacto del depósito)
-- Pegar en Supabase → SQL Editor → Run (después de 001-048)
--
-- Aclaración del usuario: como las cuentas nuevas arrancan en $0
-- (migración 044), el flujo real es: el usuario deposita (por fuera de
-- la plataforma, a la wallet mostrada) → registra el depósito en la
-- app → el admin ve la notificación en /depositos → confirma que el
-- dinero llegó de verdad → lo marca "pagado" → RECIÉN AHÍ se le acredita
-- ese monto exacto a su saldo_virtual. Antes "pagado" solo cambiaba el
-- badge, no tocaba el saldo.
--
-- La validación de "un depósito por usuario en toda su existencia" ya
-- existe desde la migración 026 (constraint UNIQUE en usuario_id) — no
-- hace falta agregar nada ahí, ya está.
--
-- Nueva RPC (reemplaza el UPDATE directo que hacía
-- BotonPagoDeposito.tsx): marca el depósito Y ajusta el saldo en la
-- misma transacción (todo o nada), con "for update" para que dos admins
-- tocando el mismo depósito a la vez no puedan acreditar el saldo dos
-- veces.
--
-- Nota: si un admin marca "pagado" y luego se arrepiente y lo vuelve a
-- "pendiente", se le RESTA ese monto al saldo (con greatest(0, ...) para
-- no dejarlo negativo) — si el usuario ya operó con ese dinero, esto
-- simplemente le baja el saldo actual hasta el límite de lo que le
-- queda, no revierte las operaciones ya hechas. Usar el des-marcado con
-- cuidado, igual que ya aplica para admin_agregar_saldo.
-- ============================================================

create or replace function public.admin_alternar_pago_deposito(p_deposito_id uuid)
returns public.depositos_simulados as $$
declare
  v_admin_id uuid := auth.uid();
  v_deposito public.depositos_simulados;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un deposito como pagado.';
  end if;

  select * into v_deposito
  from public.depositos_simulados
  where id = p_deposito_id
  for update;

  if v_deposito.id is null then
    raise exception 'Deposito no encontrado.';
  end if;

  if v_deposito.pagado then
    update public.depositos_simulados
    set pagado = false, pagado_en = null, pagado_por = null
    where id = p_deposito_id
    returning * into v_deposito;

    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - v_deposito.monto),
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  else
    update public.depositos_simulados
    set pagado = true, pagado_en = now(), pagado_por = v_admin_id
    where id = p_deposito_id
    returning * into v_deposito;

    update public.saldo_virtual
    set saldo_usd = saldo_usd + v_deposito.monto,
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  end if;

  return v_deposito;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_alternar_pago_deposito(uuid) from public, anon;
grant execute on function public.admin_alternar_pago_deposito(uuid) to authenticated;

-- ============================================================
-- === MIGRACION 050 (050_deposito_pago_idempotente.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 050: pago de depósitos idempotente + el usuario ya no puede
-- registrar su depósito "pre-pagado"
-- Pegar en Supabase → SQL Editor → Run (después de 001-049)
--
-- Encontrado en QA (2026-09-25), dos bugs reales:
--
-- 1) admin_alternar_pago_deposito (049) era un TOGGLE puro. El "for
--    update" sí evitaba acreditar dos veces, pero si dos admins (o un
--    admin con la página vieja abierta en otra pestaña) hacían clic en
--    "Marcar como pagado" sobre el mismo depósito, el segundo clic lo
--    REVERTÍA a pendiente y le restaba el saldo al usuario — justo lo
--    contrario de lo que el admin pidió. Probado con dos conexiones
--    reales a Postgres: la segunda quedaba esperando el lock y al
--    soltarse dejaba el depósito en pendiente con saldo $0.
--    Fix: la RPC recibe el estado DESEADO (p_pagado). Si el depósito ya
--    está en ese estado, falla con un mensaje claro y no toca el saldo.
--    p_pagado es opcional (null = toggle viejo) solo para que la versión
--    ya desplegada del front siga funcionando hasta el próximo deploy.
--
-- 2) La policy de INSERT (026) solo validaba usuario_id: un usuario
--    podía registrar su propio depósito ya con pagado=true,
--    revisado_por_admin=true y pagado_por = id de un admin. No le
--    acreditaba saldo, pero lo sacaba de la cola de Pendientes, le
--    quitaba el aviso de "Nuevo" al admin y falsificaba quién lo pagó.
--    Fix: el INSERT del usuario tiene que llegar con esas columnas en su
--    valor inicial.
--
-- Además: si por lo que sea el usuario no tuviera fila en saldo_virtual,
-- antes el depósito quedaba "pagado" sin acreditar nada. Ahora falla y
-- no se marca.
-- ============================================================

drop policy if exists "usuario registra su propia simulacion" on public.depositos_simulados;
create policy "usuario registra su propia simulacion"
  on public.depositos_simulados for insert
  with check (
    usuario_id = auth.uid()
    and not public.es_admin()
    and pagado = false
    and pagado_en is null
    and pagado_por is null
    and revisado_por_admin = false
  );

drop function if exists public.admin_alternar_pago_deposito(uuid);

create or replace function public.admin_alternar_pago_deposito(
  p_deposito_id uuid,
  p_pagado boolean default null
)
returns public.depositos_simulados as $$
declare
  v_admin_id uuid := auth.uid();
  v_deposito public.depositos_simulados;
  v_nuevo_estado boolean;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un deposito como pagado.';
  end if;

  select * into v_deposito
  from public.depositos_simulados
  where id = p_deposito_id
  for update;

  if v_deposito.id is null then
    raise exception 'Deposito no encontrado.';
  end if;

  v_nuevo_estado := coalesce(p_pagado, not v_deposito.pagado);

  if v_nuevo_estado = v_deposito.pagado then
    if v_deposito.pagado then
      raise exception 'Este depósito ya estaba marcado como pagado (otro admin u otra pestaña se adelantó). No se acreditó nada de nuevo.';
    else
      raise exception 'Este depósito ya estaba pendiente (otro admin u otra pestaña se adelantó). No se restó nada.';
    end if;
  end if;

  if v_nuevo_estado then
    update public.depositos_simulados
    set pagado = true, pagado_en = now(), pagado_por = v_admin_id
    where id = p_deposito_id
    returning * into v_deposito;

    update public.saldo_virtual
    set saldo_usd = saldo_usd + v_deposito.monto,
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  else
    update public.depositos_simulados
    set pagado = false, pagado_en = null, pagado_por = null
    where id = p_deposito_id
    returning * into v_deposito;

    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - v_deposito.monto),
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  end if;

  if not found then
    raise exception 'El usuario no tiene cuenta de inversión (saldo_virtual); no se marcó el depósito.';
  end if;

  return v_deposito;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_alternar_pago_deposito(uuid, boolean) from public, anon;
grant execute on function public.admin_alternar_pago_deposito(uuid, boolean) to authenticated;

-- ============================================================
-- === MIGRACION 051 (051_totales_dashboard_admin.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 051: totales del dashboard del admin sumados en la base
-- Pegar en Supabase → SQL Editor → Run (después de 001-050)
--
-- Encontrado en QA (2026-09-25): /perfil del admin traía TODAS las filas
-- de saldo_virtual (y de ganancias de hoy) y las sumaba en JS. PostgREST
-- corta cualquier select en 1000 filas (max_rows de Supabase) sin avisar,
-- así que con más de 1000 usuarios el "Total en cuentas de inversión"
-- habría salido más bajo de lo real, en silencio. Se suma aquí.
--
-- security invoker: respeta la RLS de siempre (el admin ve todas las
-- filas; si un usuario normal la llamara, solo sumaría las suyas).
-- ============================================================

create or replace function public.admin_totales_dashboard(
  p_inicio timestamptz,
  p_fin timestamptz
)
returns table (total_cuentas numeric, total_a_pagar_hoy numeric)
language sql
stable
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
  select
    (select coalesce(sum(saldo_usd), 0) from public.saldo_virtual),
    (select coalesce(sum(monto), 0)
       from public.ganancias_concursos
      where origen = 'trade'
        and pagado = false
        and created_at >= p_inicio
        and created_at < p_fin);
$$;

revoke all on function public.admin_totales_dashboard(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_totales_dashboard(timestamptz, timestamptz) to authenticated;

-- ============================================================
-- === MIGRACION 052 (052_recompensa_referido_solo_al_confirmar.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 052: la comisión de referido se genera al CONFIRMAR el
-- depósito (admin lo marca pagado), no al registrarlo
-- Pegar en Supabase → SQL Editor → Run (después de 001-051)
--
-- Hallazgo del QA (2026-09-25): el trigger otorgar_recompensa_referido()
-- corría en AFTER INSERT sobre depositos_simulados — es decir, apenas el
-- usuario REGISTRABA su depósito (un número que él mismo escribe, sin que
-- nadie lo verifique todavía), su invitador ya recibía una comisión
-- pendiente calculada sobre ese monto. Como el registro es autoservicio y
-- sin límite superior real, alguien podía registrar un "depósito" de
-- $100,000,000 nunca confirmado y su invitador quedaba con $10,000,000 en
-- comisión pendiente, pedible desde /retiros. Se encontró un caso real en
-- la base (lsprueba@gmail.com generó comisión para abelspam1234@gmail.com
-- con un depósito nunca confirmado) — no se tocó ese caso, queda para que
-- el usuario lo revise a mano.
--
-- Fix: el trigger pasa de AFTER INSERT a AFTER UPDATE OF pagado, y solo
-- dispara cuando pagado pasa de false a true (el admin lo confirmó de
-- verdad en admin_alternar_pago_deposito, migración 050). Si el admin
-- revierte un pago (pagado true -> false), la comisión correspondiente se
-- borra SOLO si todavía estaba pendiente — una ya pagada al invitador no
-- se toca, mismo criterio que ya usaba la migración 035 para no pisar
-- comisiones ya resueltas.
--
-- También se corrige el conteo de "referidos calificados" para el bono
-- por meta: antes contaba a cualquiera con una FILA en
-- depositos_simulados (sin importar si estaba pagada), el mismo hueco.
-- Ahora exige pagado = true.
-- ============================================================

drop trigger if exists on_deposito_simulado_recompensa on public.depositos_simulados;

create or replace function public.otorgar_recompensa_referido()
returns trigger as $$
declare
  v_invitador uuid;
  v_email_invitado text;
  v_config jsonb;
  v_porcentaje numeric;
  v_bono_cada int;
  v_bono_monto numeric;
  v_comision numeric;
  v_calificados_count int;
  v_concepto_bono text;
begin
  -- Reversión: el admin marcó el depósito de vuelta a pendiente. Si la
  -- comisión de ESTE invitado seguía sin pagar, se borra — nunca se
  -- confirmó de verdad el depósito que la generaba. Una ya pagada no se
  -- toca (el invitador ya recibió su USDT, revertir el registro interno
  -- no se lo puede quitar).
  if new.pagado = false and old.pagado = true then
    delete from public.ganancias_concursos
    where invitado_id = new.usuario_id
      and origen = 'referido'
      and pagado = false;
    return new;
  end if;

  select invitado_por, email into v_invitador, v_email_invitado
  from public.usuarios
  where id = new.usuario_id;

  if v_invitador is null then
    return new;
  end if;

  select valor into v_config
  from public.config_portada
  where clave = 'premio_referido';

  v_porcentaje := coalesce((v_config ->> 'porcentaje')::numeric, 10);
  v_bono_cada := coalesce((v_config ->> 'bono_cada')::int, 10);
  v_bono_monto := coalesce((v_config ->> 'bono_monto')::numeric, 1000);

  v_comision := round(new.monto * greatest(v_porcentaje, 0) / 100, 2);

  if v_comision > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      v_invitador, v_comision,
      'Referido (' || v_porcentaje || '%): ' || v_email_invitado,
      'referido', new.usuario_id
    )
    on conflict (invitado_id) where invitado_id is not null do update
    set monto = excluded.monto,
        concepto = excluded.concepto
    where public.ganancias_concursos.pagado = false;
  end if;

  -- Solo cuentan como "calificados" los referidos con el depósito
  -- CONFIRMADO — antes contaba cualquier fila, sin importar pagado.
  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id and d.pagado = true
  where u.invitado_por = v_invitador;

  if v_bono_cada > 0 and v_calificados_count > 0
     and v_calificados_count % v_bono_cada = 0 then
    v_concepto_bono := 'Bono por ' || v_calificados_count || ' referidos calificados';

    if not exists (
      select 1 from public.ganancias_concursos
      where usuario_id = v_invitador
        and origen = 'referido'
        and invitado_id is null
        and concepto = v_concepto_bono
    ) then
      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, origen
      ) values (
        v_invitador, v_bono_monto, v_concepto_bono, 'referido'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

create trigger on_deposito_simulado_recompensa
  after update of pagado on public.depositos_simulados
  for each row
  when (new.pagado is distinct from old.pagado)
  execute procedure public.otorgar_recompensa_referido();

-- ------------------------------------------------------------
-- Backfill: limpia comisiones de referido que ya existían para
-- depósitos que NUNCA se confirmaron (el caso encontrado en QA:
-- lsprueba@gmail.com -> abelspam1234@gmail.com). Solo borra las que
-- siguen SIN PAGAR — si alguna ya se le pagó de verdad al invitador,
-- se deja igual, no se le quita nada que ya haya recibido.
-- ------------------------------------------------------------
delete from public.ganancias_concursos gc
using public.depositos_simulados d
where gc.origen = 'referido'
  and gc.invitado_id = d.usuario_id
  and gc.pagado = false
  and d.pagado = false;

-- ============================================================
-- === MIGRACION 053 (053_borrar_deposito_pagado_revierte_saldo.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 053: borrar un depósito ya pagado también revierte el saldo
-- Pegar en Supabase → SQL Editor → Run (después de 001-052)
--
-- Hallazgo del QA (2026-09-25): borrar un depósito ya pagado desde
-- Gestión de usuarios (BotonEliminarAdmin.tsx, ya existía) no le
-- restaba el saldo que se le había acreditado, Y además liberaba el
-- constraint UNIQUE(usuario_id) — el usuario podía volver a registrar
-- un depósito y que se lo pagaran otra vez.
--
-- Fix: un trigger AFTER DELETE que, si el depósito borrado estaba
-- pagado, hace exactamente lo mismo que ya hace "revertir a pendiente"
-- en admin_alternar_pago_deposito (migración 050): resta el monto del
-- saldo (con greatest(0, ...)) y borra la comisión de referido
-- correspondiente si seguía sin pagar. Uno pagado al invitador no se
-- toca, mismo criterio de siempre.
-- ============================================================

create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
begin
  if old.pagado then
    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;

    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists on_deposito_borrado_revertir_saldo on public.depositos_simulados;
create trigger on_deposito_borrado_revertir_saldo
  after delete on public.depositos_simulados
  for each row
  execute procedure public.revertir_saldo_al_borrar_deposito();

-- ============================================================
-- === MIGRACION 054 (054_comprobante_obligatorio_deposito.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 054: comprobante de imagen obligatorio al depositar
-- Pegar en Supabase → SQL Editor → Run (después de 001-053)
--
-- Nueva columna con el path del comprobante en el mismo bucket privado que
-- ya usa el chat de soporte (comprobantes-soporte, migración 045). Se deja
-- NULLABLE a nivel de tabla a propósito: los depósitos ya existentes (antes
-- de este cambio) no tienen comprobante y no hay forma de pedírselo
-- retroactivamente. La obligatoriedad se impone solo en el INSERT (deposito
-- nuevo) vía la policy de abajo, nunca en el UPDATE — así
-- admin_alternar_pago_deposito puede seguir marcando como pagado un
-- depósito viejo sin comprobante sin que un CHECK de tabla lo bloquee.
-- ============================================================

alter table public.depositos_simulados
  add column if not exists comprobante_path text;

drop policy if exists "usuario registra su propia simulacion" on public.depositos_simulados;
create policy "usuario registra su propia simulacion"
  on public.depositos_simulados for insert
  with check (
    usuario_id = auth.uid()
    and not public.es_admin()
    and pagado = false
    and pagado_en is null
    and pagado_por is null
    and revisado_por_admin = false
    and comprobante_path is not null
  );

-- ============================================================
-- === MIGRACION 055 (055_no_limpiar_comprobante_de_deposito.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 055: no borrar del storage la imagen que además es el
-- comprobante oficial de un depósito
-- Pegar en Supabase → SQL Editor → Run (después de 001-054)
--
-- Al registrar un depósito (migración 054) se copia el mismo path del
-- comprobante en un mensaje del chat de soporte, para que el usuario y el
-- admin lo vean ahí (así lo pidió el usuario). Pero limpiar_comprobantes_
-- vencidos() (migración 046) borra CUALQUIER imagen de mensajes_soporte
-- con más de 5 días vía la API real de Storage -- si ese mensaje comparte
-- el path con depositos_simulados.comprobante_path, el archivo físico
-- desaparecería y el registro permanente del depósito quedaría con una
-- imagen rota, aunque su propia columna nunca se tocó.
--
-- El comprobante de un depósito es un registro financiero permanente (uno
-- por usuario en toda su existencia) y no debe expirar como un adjunto
-- cualquiera de chat -- se excluye de la limpieza.
-- ============================================================

create or replace function public.limpiar_comprobantes_vencidos()
returns void as $$
declare
  r record;
  v_service_key text;
begin
  select valor into v_service_key
  from public.config_servidor
  where clave = 'supabase_service_role_key';

  if v_service_key is null or v_service_key = 'FALTA-CONFIGURAR-ESTA-CLAVE' then
    raise notice 'supabase_service_role_key sin configurar todavia, se omite la limpieza de comprobantes';
    return;
  end if;

  for r in
    select ms.id, ms.imagen_path
    from public.mensajes_soporte ms
    where ms.imagen_path is not null
      and ms.created_at < now() - interval '5 days'
      and not exists (
        select 1 from public.depositos_simulados d
        where d.comprobante_path = ms.imagen_path
      )
  loop
    -- net.http_delete encola la petición (asíncrono, no bloquea el loop) —
    -- suficiente para un job de limpieza que no necesita confirmar cada
    -- borrado uno por uno.
    perform net.http_delete(
      url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || r.imagen_path,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_service_key,
        'apikey', v_service_key
      )
    );
    -- Se limpia la referencia ya mismo (no espera la respuesta HTTP): el
    -- mensaje de texto (si tenía) se conserva, solo se quita el link a una
    -- imagen que ya está en proceso de borrarse.
    update public.mensajes_soporte
    set imagen_path = null
    where id = r.id;
  end loop;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

revoke all on function public.limpiar_comprobantes_vencidos() from public, anon, authenticated;

-- ============================================================
-- === MIGRACION 056 (056_admin_fija_precio_entrada_al_cerrar.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 056: el admin fija precio de entrada, precio de salida y horas
-- al cerrar operaciones — deja de depender de que Binance haya dado el
-- precio de entrada correcto en el momento en que cada usuario abrió
-- Pegar en Supabase → SQL Editor → Run (después de 001-055)
--
-- Motivo (pedido del usuario, 2026-09-27): el módulo de operaciones dio
-- varios problemas reales con los pares (símbolo mal escrito BTCUSD,
-- bloqueo geográfico de Binance en Railway US/EU que tumbó la app
-- entera). Hasta ahora el precio de ENTRADA se auto-capturaba de Binance
-- en el momento en que cada usuario abría su operación (abrir_operacion,
-- migración 037) y era imposible de corregir después. El precio de SALIDA
-- ya lo fijaba el admin a mano por símbolo al cerrar en bloque
-- (BotonCerrarTodasOperaciones.tsx). Ahora el admin fija AMBOS precios (y
-- opcionalmente las horas de entrada/cierre) al momento de cerrar, en
-- bloque por símbolo — igual que ya funciona hoy con el precio de salida.
--
-- Para el usuario, abrir una operación no cambia en nada: sigue viendo el
-- precio "en vivo" al momento de abrir, como siempre. Lo que cambia es que
-- ESE precio deja de ser la fuente de verdad para el cálculo de ganancia:
-- el admin lo puede corregir al cerrar, y esa corrección recalcula todo
-- desde cero (cantidad de unidades y ganancia/pérdida), no es solo un dato
-- informativo. Confirmado explícitamente con el usuario.
--
-- Fórmula (sin cambios, solo cambia de dónde sale precio_entrada): cada
-- operación mantiene su propio monto_usado (lo que ESE usuario invirtió,
-- no cambia), así que el mismo precio en bloque por símbolo produce una
-- ganancia/pérdida distinta en dólares por usuario (mismo % de cambio,
-- distinto monto) — es la misma fórmula de siempre, ver migración 030.
--
-- Las horas de entrada/cierre son opcionales: si el admin no las
-- especifica, created_at (hora de entrada) queda como estaba y cerrado_en
-- (hora de cierre) usa now() — mismo comportamiento de siempre.
-- ============================================================

drop function if exists public.admin_cerrar_operacion(uuid, numeric);

create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_entrada numeric,
  p_precio_salida numeric,
  p_hora_entrada timestamptz default null,
  p_hora_cierre timestamptz default null
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_cantidad numeric;
  v_ganancia numeric;
  v_cerrado_en timestamptz := coalesce(p_hora_cierre, now());
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;
  if p_precio_entrada is null or p_precio_entrada = 'NaN'::numeric or p_precio_entrada <= 0 then
    raise exception 'El precio de entrada debe ser mayor a cero.';
  end if;
  if p_precio_salida is null or p_precio_salida = 'NaN'::numeric or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;
  if p_hora_entrada is not null and p_hora_cierre is not null
     and p_hora_entrada >= p_hora_cierre then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  -- El precio de entrada del admin REEMPLAZA al auto-capturado al abrir:
  -- se recalcula la cantidad de unidades con el monto que ese usuario ya
  -- tenía invertido (monto_usado no cambia) y la ganancia sale de esa
  -- cantidad nueva — no es un dato solo informativo.
  v_cantidad := v_operacion.monto_usado / p_precio_entrada;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - p_precio_entrada) * v_cantidad
    else (p_precio_entrada - p_precio_salida) * v_cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_entrada = p_precio_entrada,
      cantidad = v_cantidad,
      precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = v_cerrado_en,
      created_at = coalesce(p_hora_entrada, created_at)
  where id = p_operacion_id
  returning * into v_operacion;

  -- El saldo de práctica siempre recupera lo invertido, gane o pierda — el
  -- resultado ya no lo toca (migración 030). La ganancia real (si la hubo)
  -- se paga aparte vía ganancias_concursos.
  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_operacion.usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_cerrar_operacion(uuid, numeric, numeric, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_cerrar_operacion(uuid, numeric, numeric, timestamptz, timestamptz)
  to authenticated;

-- Comprobación: esta consulta no debe devolver ninguna fila (checklist de
-- search_path en toda función security definer).
--
--   select p.proname
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.prosecdef and p.proconfig is null;

-- ============================================================
-- === MIGRACION 057 (057_comprobante_pertenece_al_usuario_y_limpieza_al_borrar.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 057: el comprobante de depósito debe pertenecer al usuario que
-- deposita, y borrar un depósito limpia la foto vieja (storage + chat)
-- Pegar en Supabase → SQL Editor → Run (después de 001-056)
--
-- Hallazgo del QA de hoy (Fase 2, comprobante obligatorio): la policy de
-- INSERT (migración 054) exigía que `comprobante_path` no fuera null, pero
-- no validaba que esa ruta perteneciera de verdad al usuario que deposita.
-- Alguien saltándose el formulario (llamando la API directo) podía mandar
-- una ruta inventada o la de OTRO usuario. Impacto bajo en la práctica
-- (un depósito por usuario en toda su existencia, y nada se acredita sin
-- que el admin confirme viendo la foto primero), pero el usuario pidió
-- cerrarlo de todos modos.
--
-- Fix 1: la policy ahora exige que el path empiece con el propio
-- auth.uid() (misma convención de carpeta que ya usa subirComprobante() en
-- lib/actions/comprobantes.ts: "{usuario_id}/{uuid}.ext").
--
-- Fix 2 (pedido explícito del usuario): cuando el admin borra un depósito
-- (típicamente para dejar que el usuario intente de nuevo, ya que solo
-- puede depositar una vez), la foto vieja del comprobante NO debe quedar
-- dando vueltas ni en el bucket ni en el mensaje de chat que la espejaba.
-- Se extiende el trigger AFTER DELETE de la migración 053
-- (revertir_saldo_al_borrar_deposito) para que, además de revertir el
-- saldo si estaba pagado, borre el archivo físico vía la API de Storage
-- (mismo mecanismo que el cron de limpieza de 5 días, migración 046 —
-- Supabase no permite borrar storage.objects por SQL directo) y limpie la
-- referencia en mensajes_soporte, sin importar si el depósito estaba
-- pagado o no.
-- ============================================================

drop policy if exists "usuario registra su propia simulacion" on public.depositos_simulados;
create policy "usuario registra su propia simulacion"
  on public.depositos_simulados for insert
  with check (
    usuario_id = auth.uid()
    and not public.es_admin()
    and pagado = false
    and pagado_en is null
    and pagado_por is null
    and revisado_por_admin = false
    and comprobante_path is not null
    and comprobante_path like (auth.uid()::text || '/%')
  );

create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
declare
  v_service_key text;
begin
  if old.pagado then
    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;

    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;
  end if;

  -- El comprobante de ESTE depósito ya no tiene ningún registro que lo
  -- respalde: se borra el archivo físico (igual que limpiar_comprobantes_
  -- vencidos, migración 046) y se limpia su espejo en el chat, sin
  -- importar si el depósito estaba pagado o no.
  if old.comprobante_path is not null then
    select valor into v_service_key
    from public.config_servidor
    where clave = 'supabase_service_role_key';

    if v_service_key is not null and v_service_key <> 'FALTA-CONFIGURAR-ESTA-CLAVE' then
      perform net.http_delete(
        url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || old.comprobante_path,
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_service_key,
          'apikey', v_service_key
        )
      );
    end if;

    update public.mensajes_soporte
    set imagen_path = null
    where imagen_path = old.comprobante_path;
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

-- ============================================================
-- === MIGRACION 058 (058_limpiar_comprobante_huerfano.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 058: limpiar el comprobante huérfano cuando se sube la imagen
-- pero el registro del depósito falla justo después
-- Pegar en Supabase → SQL Editor → Run (después de 001-057)
--
-- Hallazgo del QA de hoy (Fase 4): registrarDepositoSimulado() sube la
-- imagen al bucket ANTES de insertar la fila en depositos_simulados. Si el
-- insert falla (ej. una carrera entre dos pestañas, o cualquier otro
-- error), la imagen ya subida se queda sin ningún depósito ni mensaje que
-- la referencie -- huérfana para siempre, porque el cron de limpieza de
-- 5 días (migración 046/055) solo mira mensajes_soporte, nunca el bucket
-- directamente.
--
-- No se le da a los usuarios un permiso general de DELETE sobre storage.
-- objects (eso permitiría borrar el comprobante de un depósito YA
-- registrado antes de que el admin lo revise). En su lugar, esta RPC solo
-- deja borrar un path que (a) es de la propia carpeta del usuario que
-- llama, Y (b) no está referenciado por NINGÚN depósito real -- así nunca
-- se puede usar para borrar un comprobante legítimo.
-- ============================================================

create or replace function public.limpiar_comprobante_huerfano(p_path text)
returns void as $$
declare
  v_usuario_id uuid := auth.uid();
  v_service_key text;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_path is null or p_path not like (v_usuario_id::text || '/%') then
    raise exception 'Solo puedes limpiar comprobantes de tu propia carpeta.';
  end if;

  if exists (
    select 1 from public.depositos_simulados where comprobante_path = p_path
  ) then
    raise exception 'Ese comprobante pertenece a un depósito registrado, no se puede borrar.';
  end if;

  select valor into v_service_key
  from public.config_servidor
  where clave = 'supabase_service_role_key';

  if v_service_key is null or v_service_key = 'FALTA-CONFIGURAR-ESTA-CLAVE' then
    return; -- sin la clave configurada, no se puede llamar a la API de Storage
  end if;

  perform net.http_delete(
    url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || p_path,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'apikey', v_service_key
    )
  );
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

revoke all on function public.limpiar_comprobante_huerfano(text) from public, anon;
grant execute on function public.limpiar_comprobante_huerfano(text) to authenticated;

-- ============================================================
-- === MIGRACION 059 (059_bloquea_traversal_limpieza_comprobante.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 059: bloquea path traversal en limpiar_comprobante_huerfano
-- Pegar en Supabase → SQL Editor → Run (después de 001-058)
--
-- Hallazgo de QA (2026-09-27) sobre la migración 058: la función nueva
-- solo validaba que p_path EMPEZARA con "<mi_uuid>/" (like) y que no
-- existiera tal cual en depositos_simulados.comprobante_path (=). Ninguna
-- de las dos validaciones detiene un p_path como:
--
--   "<mi_uuid>/../<otro_uuid>/<archivo_real>.png"
--
-- Ese path SÍ empieza con "<mi_uuid>/" (pasa el check "a"), y como cadena
-- literal NO es igual a ningún comprobante_path guardado -- aunque el
-- archivo señalado por "../<otro_uuid>/<archivo>.png" sí sea el de un
-- depósito ajeno, incluso uno ya con pagado = true (pasa el check "b").
-- La función igual llama a net.http_delete con esa URL, y se confirmó en
-- pruebas reales que el backend de Storage SÍ resuelve el "..", así que
-- termina borrando el archivo de OTRO usuario -- exactamente lo que la
-- migración 058 decía que era imposible por diseño.
--
-- Fix: además de exigir el prefijo "<mi_uuid>/", el resto del path después
-- de la carpeta debe ser un único segmento (sin más "/"), sin "..", y con
-- un charset seguro (coincide con cómo se generan hoy los paths reales:
-- "<uuid>/<uuid>.jpg|png|webp", ver subirComprobante() en
-- lib/actions/comprobantes.ts). Cualquier "/" o ".." adicional se rechaza
-- antes de siquiera llegar al check de depositos_simulados.
-- ============================================================

create or replace function public.limpiar_comprobante_huerfano(p_path text)
returns void as $$
declare
  v_usuario_id uuid := auth.uid();
  v_service_key text;
  v_resto text;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_path is null or p_path not like (v_usuario_id::text || '/%') then
    raise exception 'Solo puedes limpiar comprobantes de tu propia carpeta.';
  end if;

  v_resto := substring(p_path from length(v_usuario_id::text) + 2);

  -- El resto debe ser EXACTAMENTE un nombre de archivo: sin más "/", sin
  -- "..", charset seguro. Esto es lo que de verdad impide el traversal --
  -- el "not like" de arriba por sí solo NO bastaba.
  if v_resto is null
     or v_resto = ''
     or v_resto like '%/%'
     or v_resto like '%..%'
     or v_resto !~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'
  then
    raise exception 'Ruta de comprobante inválida.';
  end if;

  if exists (
    select 1 from public.depositos_simulados where comprobante_path = p_path
  ) then
    raise exception 'Ese comprobante pertenece a un depósito registrado, no se puede borrar.';
  end if;

  select valor into v_service_key
  from public.config_servidor
  where clave = 'supabase_service_role_key';

  if v_service_key is null or v_service_key = 'FALTA-CONFIGURAR-ESTA-CLAVE' then
    return; -- sin la clave configurada, no se puede llamar a la API de Storage
  end if;

  perform net.http_delete(
    url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || p_path,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'apikey', v_service_key
    )
  );
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

revoke all on function public.limpiar_comprobante_huerfano(text) from public, anon;
grant execute on function public.limpiar_comprobante_huerfano(text) to authenticated;

-- ============================================================
-- === MIGRACION 060 (060_abrir_operacion_sin_precio_externo.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 060: abrir una operación ya no depende de ningún precio
-- externo (ni Binance ni ningún otro) — el precio de entrada lo fija el
-- admin al cerrar
-- Pegar en Supabase → SQL Editor → Run (después de 001-059)
--
-- Pedido explícito del usuario (2026-09-27/28): el pick del día ahora puede
-- ser CUALQUIER activo (acciones, forex, materias primas — no solo cripto,
-- ver AdminPickForm.tsx sin validación de Binance). Pero abrir_operacion()
-- seguía yendo a buscar el precio en vivo a Binance (paperTrading.ts,
-- obtenerPrecioCripto) para fijar precio_entrada -- eso fallaba con
-- "No se pudo obtener el precio de GOLDUSD" para cualquier pick que no
-- fuera un par real de Binance.
--
-- Desde la migración 056, el precio de entrada YA NO es autoritativo al
-- abrir: el admin lo reemplaza por completo al cerrar (recalcula cantidad
-- y ganancia desde cero con SU precio de entrada, no con el capturado al
-- abrir). O sea que ir a buscar un precio en vivo al abrir era trabajo que
-- ya no servía para nada al final -- se elimina esa dependencia entera.
--
-- precio_entrada y cantidad pasan a ser NULLABLE: en el momento de abrir
-- se guardan como null (todavía no hay un precio de verdad), y
-- admin_cerrar_operacion (migración 056) los llena con los valores reales
-- al cerrar. Nunca se leen los valores viejos de open-time en el cierre
-- (solo usa monto_usado y tipo), así que esto no afecta el cálculo de
-- ganancias en absoluto.
-- ============================================================

alter table public.operaciones_simuladas
  alter column precio_entrada drop not null,
  alter column cantidad drop not null;

drop function if exists public.abrir_operacion(text, text, numeric, numeric, text);

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  select activo into v_pick
  from public.pick_del_dia
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  -- precio_entrada y cantidad quedan en null: el admin los fija al cerrar
  -- (admin_cerrar_operacion, migración 056), que recalcula todo desde cero
  -- sin leer estos valores. monto_usado sí queda fijo desde ya, es lo que
  -- ese usuario invirtió y lo que usa el cierre para calcular su ganancia.
  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke execute on function public.abrir_operacion(text, text, numeric, text) from public, anon;
grant execute on function public.abrir_operacion(text, text, numeric, text) to authenticated;

-- ============================================================
-- === MIGRACION 061 (061_quita_cierre_viejo_y_limita_pick.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 061: dos huecos que dejó la migración 060 (abrir sin precio)
-- Pegar en Supabase → SQL Editor → Run (después de 001-060)
--
-- 1) cerrar_operacion(uuid, numeric) — la función de cierre VIEJA (antes de
--    la 056) seguía existiendo y ejecutable por cualquier admin vía RPC.
--    Ya no la usa la app (el cierre es admin_cerrar_operacion), pero calcula
--    la ganancia con el precio_entrada/cantidad capturados al abrir. Desde
--    la 060 esos valores son NULL, y como GREATEST() de Postgres ignora los
--    NULL, greatest(NULL, -monto_usado) = -monto_usado: la operación se
--    cerraba "bien" pero registrando una PÉRDIDA TOTAL del monto invertido,
--    sin ningún error. Probado en QA: operación de $500 cerrada con esa
--    función quedó con ganancia_perdida = -500 y precio_entrada NULL.
--    Se elimina: el único cierre válido es admin_cerrar_operacion (056).
--
-- 2) pick_del_dia.activo no tenía ningún límite, pero abrirOperacion()
--    (paperTrading.ts) rechaza cualquier activo de más de 30 caracteres con
--    "Símbolo de activo inválido". Un admin podía guardar un pick de 50
--    caracteres y NADIE podía operarlo ese día. Se alinea con un CHECK de
--    1 a 30 caracteres, sin espacios al inicio/fin (el formulario ya hace
--    trim, esto cubre inserts directos vía API con la sesión de admin).
-- ============================================================

drop function if exists public.cerrar_operacion(uuid, numeric);

alter table public.pick_del_dia
  drop constraint if exists pick_del_dia_activo_formato;

alter table public.pick_del_dia
  add constraint pick_del_dia_activo_formato
  check (char_length(activo) between 1 and 30 and activo = btrim(activo));

-- ============================================================
-- === MIGRACION 062 (062_pick_del_dia_vence_y_se_puede_borrar.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 062: el pick del día vence al terminar el día (NY) y el admin
-- puede eliminarlo
-- Pegar en Supabase → SQL Editor → Run (después de 001-061)
--
-- Hallazgo del usuario (2026-09-28): "el pick no vence, siempre está el
-- pick y cuando se agrega otro entonces hay 2 pick". La tabla pick_del_dia
-- ya guarda una columna `fecha`, pero NINGUNA consulta la usaba para
-- decidir cuál es el pick "vigente" -- tanto abrir_operacion() como las
-- pantallas de Next.js simplemente tomaban la fila más reciente por
-- created_at, sin importar qué tan vieja fuera. Si un día se le olvidaba
-- al admin definir un pick nuevo, el de AYER (o de hace una semana) seguía
-- "vigente" indefinidamente. Y no había ninguna forma de borrar uno desde
-- la UI (nunca existió policy de DELETE para esta tabla).
--
-- Fix: abrir_operacion ahora exige que el pick coincida con el día de HOY
-- (hora de Nueva York), no solo que sea "el más reciente que exista". El
-- filtro por fecha en las pantallas de Next.js se hace en el código
-- (trade-del-dia/page.tsx, paperTrading.ts), esto solo cubre el lado de
-- la base de datos, que es lo que de verdad importa para la seguridad.
-- ============================================================

create policy "solo admin borra el pick del dia"
  on public.pick_del_dia for delete
  using (public.es_admin());

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  -- El pick tiene que ser el de HOY (hora de Nueva York) -- antes se
  -- tomaba el más reciente que existiera, sin importar la fecha, así que
  -- un pick de ayer (o de hace una semana) seguía "vigente" para siempre
  -- si nadie definía uno nuevo.
  select activo into v_pick
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 063 (063_pick_del_dia_fecha_default_ny.sql) ===
-- ============================================================

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

-- ============================================================
-- === MIGRACION 064 (064_horario_mercado_parametrizable.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 064: el horario de mercado deja de estar fijo en el código —
-- se vuelve editable por el admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-063)
--
-- Pedido del usuario (2026-09-28): poder parametrizar el horario en que
-- los usuarios pueden abrir operaciones, incluida la opción de dejarlo
-- abierto sin restricción para que simulen a cualquier hora.
--
-- No se crea una tabla nueva: se reutiliza config_portada (clave/valor
-- jsonb), el mismo patrón que ya usa esta app para configuración editable
-- por admin sin tocar código (ver "simulacion_deposito"). Clave nueva:
-- "horario_mercado", valor = {"apertura":"09:30","cierre":"16:00",
-- "dias":[1,2,3,4,5],"abierto_siempre":false} (días en formato ISO:
-- 1=lunes...7=domingo). Sin fila guardada, se usan estos mismos valores
-- por defecto -- exactamente el comportamiento de hoy, cero riesgo si el
-- admin nunca toca el formulario nuevo.
--
-- El mensaje de error se deja genérico ("El mercado está cerrado en este
-- momento") en vez de intentar describir días/horas en SQL -- el mensaje
-- detallado y dinámico (con los días/horas configurados de verdad) se
-- arma del lado de Next.js (paperTrading.ts), donde formatear texto legible
-- es mucho más simple que en PL/pgSQL. Esta excepción es solo el respaldo
-- de seguridad si alguien se salta esa capa.
-- ============================================================

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
  v_horario jsonb;
  v_apertura time;
  v_cierre time;
  v_dias_habiles int[];
  v_abierto_siempre boolean;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  select activo into v_pick
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    v_abierto_siempre := coalesce((v_horario->>'abierto_siempre')::boolean, false);

    if not v_abierto_siempre then
      v_apertura := coalesce((v_horario->>'apertura')::time, time '09:30');
      v_cierre := coalesce((v_horario->>'cierre')::time, time '16:00');
      v_dias_habiles := coalesce(
        (
          select array_agg(d::int)
          from jsonb_array_elements_text(coalesce(v_horario->'dias', '[]'::jsonb)) d
        ),
        array[1, 2, 3, 4, 5]
      );

      v_hora_ny := (now() at time zone 'America/New_York')::time;
      v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));

      if not (v_dia_semana_ny = any(v_dias_habiles))
         or v_hora_ny < v_apertura
         or v_hora_ny >= v_cierre then
        raise exception 'El mercado está cerrado en este momento.';
      end if;
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 065 (065_horario_mercado_valores_invalidos.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 065: abrir_operacion tolera un horario_mercado mal guardado
-- Pegar en Supabase → SQL Editor → Run (después de 001-064)
--
-- Bug encontrado en QA de la 064: si el admin BORRA la hora de apertura en
-- el formulario de /trade-del-dia (el <input type="time"> queda en ""), la
-- validación del formulario la dejaba pasar ("" >= "16:00" es false) y se
-- guardaba {"apertura": ""}. Resultado: la UI (que trata "" como "usar el
-- default") mostraba el mercado abierto, pero abrir_operacion reventaba en
-- ""::time y TODOS los usuarios veían el error crudo de Postgres
-- 'invalid input syntax for type time: ""' -- nadie podía operar.
--
-- Arreglo: cada campo inválido cae a su valor por defecto (misma regla que
-- normalizarHorario() del lado de Next.js). El formulario también se
-- corrigió para no dejar guardar horas vacías/inválidas.
-- Días vacíos ([]) siguen significando "usar el default lunes-viernes"
-- (igual que en la 064 y en la UI); el formulario no permite guardarlos.
-- apertura >= cierre (guardado saltándose el formulario) deja el mercado
-- cerrado todo el día para usuarios normales: seguro, no se toca.
-- ============================================================

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
  v_horario jsonb;
  v_apertura time;
  v_cierre time;
  v_dias_habiles int[];
  v_abierto_siempre boolean;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  select activo into v_pick
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    -- Valores inválidos (vacío, "abc", "25:00", días fuera de 1-7, tipos
    -- raros) caen al valor por defecto de ESE campo en vez de reventar el
    -- cast -- la misma regla que normalizarHorario() en
    -- lib/config-horario-mercado.ts, para que la UI y la base nunca
    -- discrepen sobre si el mercado está abierto.
    v_abierto_siempre := coalesce(v_horario->>'abierto_siempre' = 'true', false);

    if not v_abierto_siempre then
      v_apertura := case
        when v_horario->>'apertura' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'apertura')::time
        else time '09:30'
      end;
      v_cierre := case
        when v_horario->>'cierre' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'cierre')::time
        else time '16:00'
      end;
      v_dias_habiles := coalesce(
        (
          select array_agg(distinct d::int)
          from jsonb_array_elements_text(
            case when jsonb_typeof(v_horario->'dias') = 'array'
              then v_horario->'dias' else '[]'::jsonb end
          ) d
          where d ~ '^[1-7]$'
        ),
        array[1, 2, 3, 4, 5]
      );

      v_hora_ny := (now() at time zone 'America/New_York')::time;
      v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));

      if not (v_dia_semana_ny = any(v_dias_habiles))
         or v_hora_ny < v_apertura
         or v_hora_ny >= v_cierre then
        raise exception 'El mercado está cerrado en este momento.';
      end if;
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 066 (066_no_borrar_comprobante_del_chat.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 066: borrar un depósito ya NO borra la foto del chat de soporte
-- Pegar en Supabase → SQL Editor → Run (después de 001-065)
--
-- Decisión explícita del usuario (2026-09-28): cuando el admin borra un
-- depósito (típicamente para dejar que el usuario reintente), la foto que
-- quedó espejada en el chat de soporte debe conservarse como registro de
-- la conversación -- no debe desaparecer.
--
-- Se quita del trigger AFTER DELETE (revertir_saldo_al_borrar_deposito,
-- migración 053, extendido en 057) la parte que borraba el archivo físico
-- del bucket (net.http_delete) y la que ponía en null
-- mensajes_soporte.imagen_path. Se conserva intacta la reversión de saldo
-- y de comisión de referido -- eso sigue siendo correcto y necesario.
--
-- Efecto en la limpieza automática de 5 días (limpiar_comprobantes_
-- vencidos, migración 046/055): una vez borrado el depósito, su
-- comprobante_path ya no existe en depositos_simulados, así que esa foto
-- vuelve a ser un adjunto de chat normal -- si pasan 5 días, el cron la
-- limpia como cualquier otra imagen de soporte (esto es correcto: mientras
-- el depósito existía, la foto era un comprobante permanente; una vez
-- borrado el depósito, ya no hay nada financiero que proteger para
-- siempre, pero se mantiene visible en el chat como conversación normal).
-- ============================================================

create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
begin
  if old.pagado then
    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;

    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 067 (067_senales_cerradas_inmutables_y_fecha_de_toque.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 067: Historial de señales consistente
-- Pegar en Supabase → SQL Editor → Run (después de 001-066)
--
-- QA funcional de /senales (2026-09-29). Tres correcciones:
--
-- 1) UNA SEÑAL CERRADA SE PODÍA EDITAR Y EL HISTORIAL QUEDABA INCOHERENTE.
--    El botón "Editar" seguía visible en las tarjetas ya cerradas. Al
--    cambiarle entrada o take profit a una señal con "TP tocado", la
--    tarjeta pública mostraba p. ej. "Entrada 90000 · TP 30000" junto a
--    "Cerró en 20000 (+76.31%)" — el precio de cierre y el porcentaje se
--    calcularon con los niveles viejos y nadie los recalcula. En la base
--    ya había un caso real así (TP 130000 con "cerró en 120000").
--    Ahora, una vez que la señal tiene resultado, sus niveles (par, tipo,
--    entrada, SL, TP) quedan congelados; la razón se puede seguir
--    corrigiendo. La UI además deja de mostrar "Editar" en las cerradas.
--
-- 2) LA FECHA DE CIERRE AUTOMÁTICO ERA LA DE LA VISITA, NO LA DEL TOQUE.
--    El chequeo de TP/SL corre al cargar /senales (no hay cron), así que
--    cerrado_en quedaba con la hora en que alguien abrió la página, que
--    puede ser horas o días después de que el precio tocara el nivel (se
--    vio una señal que tocó TP a la 01:31 UTC y quedó cerrada a las 13:17).
--    El filtro "desde/hasta" del historial usa esa fecha. Nueva versión de
--    cerrar_senal_automatica con un cuarto parámetro: la hora de la vela
--    que tocó el nivel, acotada entre la publicación de la señal y now().
--    La versión de 3 parámetros se conserva tal cual para que el servidor
--    ya desplegado siga funcionando hasta el próximo deploy.
--
-- 3) creado_por NUNCA SE LLENABA en senales (todas las filas en NULL): el
--    formulario del admin no lo manda. Se pone auth.uid() por defecto.
-- ============================================================

-- 1) Niveles congelados una vez cerrada ---------------------------------

create or replace function public.senales_congelar_cerradas()
returns trigger as $$
begin
  if old.resultado is not null and (
       new.par is distinct from old.par
    or new.tipo is distinct from old.tipo
    or new.entrada is distinct from old.entrada
    or new.stop_loss is distinct from old.stop_loss
    or new.take_profit is distinct from old.take_profit
  ) then
    raise exception 'Esta señal ya está cerrada: sus niveles no se pueden cambiar (solo la razón). Si hubo un error, elimínala y publícala de nuevo.';
  end if;
  return new;
end;
$$ language plpgsql
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists senales_congelar_cerradas on public.senales;
create trigger senales_congelar_cerradas
  before update on public.senales
  for each row execute function public.senales_congelar_cerradas();

-- 2) Cierre automático con la hora real del toque ------------------------

create or replace function public.cerrar_senal_automatica(
  p_senal_id uuid,
  p_resultado text,
  p_secreto text,
  p_tocado_en timestamptz
) returns void as $$
declare
  v_senal public.senales;
  v_precio numeric;
  v_porcentaje numeric;
  v_cerrado_en timestamptz;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Solo la aplicación puede cerrar señales automáticamente.';
  end if;
  if p_resultado not in ('tp', 'sl') then
    raise exception 'Resultado inválido.';
  end if;

  select * into v_senal
  from public.senales
  where id = p_senal_id and estado = 'activa' and resultado is null
  for update;

  if v_senal.id is null then
    return; -- ya estaba cerrada: no hay nada que hacer
  end if;

  v_precio := case when p_resultado = 'tp'
                   then v_senal.take_profit
                   else v_senal.stop_loss end;

  if v_precio is null then
    raise exception 'La señal no tiene definido ese nivel.';
  end if;

  v_porcentaje := case
    when v_senal.tipo = 'compra'
      then ((v_precio - v_senal.entrada) / v_senal.entrada) * 100
    else ((v_senal.entrada - v_precio) / v_senal.entrada) * 100
  end;

  -- La vela que tocó el nivel no puede ser anterior a la publicación ni
  -- posterior a ahora; sin dato, se usa now() como antes.
  v_cerrado_en := least(greatest(coalesce(p_tocado_en, now()), v_senal.created_at), now());

  update public.senales
  set estado = 'cerrada',
      resultado = p_resultado,
      precio_cierre = v_precio,
      porcentaje_resultado = v_porcentaje,
      cerrado_en = v_cerrado_en
  where id = p_senal_id;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke execute on function public.cerrar_senal_automatica(uuid, text, text, timestamptz) from public;
grant execute on function public.cerrar_senal_automatica(uuid, text, text, timestamptz) to anon, authenticated;

-- 3) Quién publicó la señal ---------------------------------------------

alter table public.senales alter column creado_por set default auth.uid();

-- ============================================================
-- === MIGRACION 068 (068_abrir_operacion_mensaje_operacion_abierta.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 068: abrir_operacion avisa "ya tienes una operación abierta"
-- en vez de "saldo insuficiente" cuando el usuario ya tiene una abierta
-- Pegar en Supabase → SQL Editor → Run (después de 001-067)
--
-- Bug encontrado en QA de Trade del día (2026-09-29): abrir una operación
-- usa SIEMPRE el saldo completo (migración 032), así que después de abrir
-- una el saldo queda en $0. El chequeo de saldo iba ANTES del de
-- "operación abierta", por lo que un segundo intento (otra pestaña, doble
-- clic tardío, página vieja) siempre respondía "Saldo virtual
-- insuficiente." -- el usuario pensaba que había perdido su dinero en vez
-- de entender que ya tiene una operación en curso. El chequeo de
-- "operación abierta" nunca llegaba a ejecutarse en la práctica.
--
-- Arreglo: mismo cuerpo que la 065, solo se invierte el orden -- primero
-- se bloquea la fila de saldo (igual que antes, para serializar
-- peticiones simultáneas del mismo usuario), después se revisa si ya hay
-- una operación abierta, y recién después el saldo. El mensaje ya no dice
-- "Ciérrala primero": el usuario no puede cerrar operaciones, las liquida
-- el admin en bloque.
-- ============================================================

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
  v_horario jsonb;
  v_apertura time;
  v_cierre time;
  v_dias_habiles int[];
  v_abierto_siempre boolean;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  select activo into v_pick
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    -- Valores inválidos (vacío, "abc", "25:00", días fuera de 1-7, tipos
    -- raros) caen al valor por defecto de ESE campo en vez de reventar el
    -- cast -- la misma regla que normalizarHorario() en
    -- lib/config-horario-mercado.ts, para que la UI y la base nunca
    -- discrepen sobre si el mercado está abierto.
    v_abierto_siempre := coalesce(v_horario->>'abierto_siempre' = 'true', false);

    if not v_abierto_siempre then
      v_apertura := case
        when v_horario->>'apertura' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'apertura')::time
        else time '09:30'
      end;
      v_cierre := case
        when v_horario->>'cierre' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'cierre')::time
        else time '16:00'
      end;
      v_dias_habiles := coalesce(
        (
          select array_agg(distinct d::int)
          from jsonb_array_elements_text(
            case when jsonb_typeof(v_horario->'dias') = 'array'
              then v_horario->'dias' else '[]'::jsonb end
          ) d
          where d ~ '^[1-7]$'
        ),
        array[1, 2, 3, 4, 5]
      );

      v_hora_ny := (now() at time zone 'America/New_York')::time;
      v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));

      if not (v_dia_semana_ny = any(v_dias_habiles))
         or v_hora_ny < v_apertura
         or v_hora_ny >= v_cierre then
        raise exception 'El mercado está cerrado en este momento.';
      end if;
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  -- Antes del chequeo de saldo: con una operación abierta el saldo SIEMPRE
  -- está en $0 (se usa completo), así que al revés este mensaje nunca salía.
  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Podrás abrir otra cuando el admin cierre la sesión.';
  end if;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 069 (069_cierre_valida_horas_efectivas.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 069: el cierre en bloque valida hora de entrada < hora de
-- cierre con los valores EFECTIVOS, no solo cuando el admin manda las dos
-- Pegar en Supabase → SQL Editor → Run (después de 001-068)
--
-- Bug (QA 2026-09-29): admin_cerrar_operacion (migración 056) solo
-- comparaba p_hora_entrada >= p_hora_cierre si el admin escribía AMBAS
-- horas. Como las dos son opcionales, bastaba con escribir una sola para
-- guardar una operación que "cierra antes de abrir":
--   · solo hora de entrada, en el futuro → created_at = 31-dic, cerrado_en
--     = now() (probado: la función lo aceptaba).
--   · solo hora de cierre, anterior a la apertura real de la operación →
--     cerrado_en = 1-sep, created_at = 29-sep (probado: lo aceptaba).
-- Ahora se compara coalesce(p_hora_entrada, created_at real) contra
-- coalesce(p_hora_cierre, now()), que es exactamente lo que se guarda.
--
-- Fórmula de ganancia, piso en -monto_usado, saldo y ganancias_concursos:
-- SIN CAMBIOS respecto de la 056.
-- ============================================================

create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_entrada numeric,
  p_precio_salida numeric,
  p_hora_entrada timestamptz default null,
  p_hora_cierre timestamptz default null
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_cantidad numeric;
  v_ganancia numeric;
  v_cerrado_en timestamptz := coalesce(p_hora_cierre, now());
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;
  if p_precio_entrada is null or p_precio_entrada = 'NaN'::numeric or p_precio_entrada <= 0 then
    raise exception 'El precio de entrada debe ser mayor a cero.';
  end if;
  if p_precio_salida is null or p_precio_salida = 'NaN'::numeric or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;
  if p_hora_entrada is not null and p_hora_cierre is not null
     and p_hora_entrada >= p_hora_cierre then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  -- Con una sola hora escrita, la otra es la real (apertura) o now()
  -- (cierre): se valida contra lo que efectivamente se va a guardar.
  if coalesce(p_hora_entrada, v_operacion.created_at) >= v_cerrado_en then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  v_cantidad := v_operacion.monto_usado / p_precio_entrada;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - p_precio_entrada) * v_cantidad
    else (p_precio_entrada - p_precio_salida) * v_cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_entrada = p_precio_entrada,
      cantidad = v_cantidad,
      precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = v_cerrado_en,
      created_at = coalesce(p_hora_entrada, created_at)
  where id = p_operacion_id
  returning * into v_operacion;

  -- El saldo de práctica siempre recupera lo invertido, gane o pierda (030).
  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_operacion.usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_cerrar_operacion(uuid, numeric, numeric, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_cerrar_operacion(uuid, numeric, numeric, timestamptz, timestamptz)
  to authenticated;

-- ============================================================
-- === MIGRACION 071 (071_cierre_en_bloque_atomico.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 071: cierre en bloque atómico (todo o nada)
-- Pegar en Supabase → SQL Editor → Run (después de 001-070)
--
-- QA de "Cierre de operaciones" (2026-09-29): el cierre en bloque cerraba
-- una operación a la vez, cada una en su propia llamada RPC desde el
-- servidor. Si la conexión se cortaba a mitad del bucle, algunas quedaban
-- cerradas y otras no. El dueño del proyecto pidió hacerlo atómico: o se
-- cierran TODAS las operaciones recibidas, o no se cierra NINGUNA.
--
-- admin_cerrar_operaciones_bloque recibe un array JSON con todos los cierres
-- (operacion_id, precio_entrada, precio_salida, hora_entrada, hora_cierre) y
-- los procesa en un solo bucle DENTRO de la función, reutilizando
-- admin_cerrar_operacion para cada uno (misma validación y fórmula, sin
-- duplicar lógica). Como esta función se invoca en una sola llamada RPC, en
-- Postgres toda ella corre como una única transacción implícita: si
-- CUALQUIER cierre del array levanta una excepción (precio inválido, hora
-- inválida, ya estaba cerrada, etc.), la excepción no se atrapa aquí adentro
-- y Postgres deshace automáticamente TODOS los cierres ya aplicados en esa
-- misma llamada, sin necesidad de BEGIN/COMMIT explícito.
-- ============================================================

create or replace function public.admin_cerrar_operaciones_bloque(
  p_cierres jsonb
) returns setof public.operaciones_simuladas as $$
declare
  v_item jsonb;
  v_operacion public.operaciones_simuladas;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar operaciones.';
  end if;

  if jsonb_typeof(p_cierres) is distinct from 'array' then
    raise exception 'Formato inválido: se esperaba una lista de cierres.';
  end if;

  -- Sin manejo de excepción a propósito: si un solo elemento falla, la
  -- excepción sube sin atraparse y Postgres revierte todo lo hecho en esta
  -- llamada (incluidos los cierres de elementos anteriores del mismo array).
  for v_item in select * from jsonb_array_elements(p_cierres)
  loop
    v_operacion := public.admin_cerrar_operacion(
      (v_item->>'operacion_id')::uuid,
      (v_item->>'precio_entrada')::numeric,
      (v_item->>'precio_salida')::numeric,
      nullif(v_item->>'hora_entrada', '')::timestamptz,
      nullif(v_item->>'hora_cierre', '')::timestamptz
    );
    return next v_operacion;
  end loop;

  return;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_cerrar_operaciones_bloque(jsonb) from public, anon;
grant execute on function public.admin_cerrar_operaciones_bloque(jsonb) to authenticated;

-- ============================================================
-- === MIGRACION 072 (072_retiro_pago_parcial_parte_la_ganancia.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 072: pagar un retiro reconcilia EXACTO lo pagado
-- (parte la última ganancia en vez de marcarla pagada completa)
-- Pegar en Supabase → SQL Editor → Run (después de 001-071)
--
-- Hallazgo del QA del módulo de Retiro (2026-09-29): con ganancias
-- pendientes de $10 + $200 + $0.90 (= $210.90), el usuario pide un
-- retiro de $50 y el admin lo marca pagado. La reconciliación de la
-- migración 043 marcaba pagada COMPLETA la última fila tocada ($200),
-- así que el disponible del usuario caía a $0.90 en vez de $160.90:
-- el usuario perdía $160 que nunca se le pagaron. La "simplificación"
-- que documentaba la 043 dejó de ser inofensiva cuando esa misma
-- migración pasó a calcular el disponible solo desde
-- ganancias_concursos.pagado (ya no resta los retiros pagados aparte).
--
-- Cambio: admin_marcar_retiro_pagado() ahora, si la fila que toca vale
-- más que lo que falta por reconciliar, la PARTE en dos:
--   - la fila original baja su monto a lo pagado y queda pagado=true
--     (conserva invitado_id / operacion_id / concepto originales, así
--     el ON CONFLICT (invitado_id) de otorgar_recompensa_referido sigue
--     viendo la comisión como ya pagada y no la vuelve a inflar, y el
--     chequeo de "bono ya otorgado" por concepto sigue funcionando);
--   - se inserta una fila nueva con el resto, pagado=false, mismo
--     usuario/origen/operación/created_at, sin invitado_id (el índice
--     único de invitado_id no permite dos filas con el mismo).
-- La suma total de ganancias del usuario no cambia; solo se reparte.
-- Las filas se bloquean (FOR UPDATE) para que un pago de retiro y un
-- pago desde Reportes no reconcilien la misma fila a la vez.
--
-- No se corrigen retroactivamente retiros pagados antes de esta
-- migración: los únicos casos con exceso encontrados son cuentas qa-.
-- ============================================================

create or replace function public.admin_marcar_retiro_pagado(p_solicitud_id uuid)
returns public.solicitudes_retiro as $$
declare
  v_admin_id uuid := auth.uid();
  v_solicitud public.solicitudes_retiro;
  v_restante numeric;
  r_ganancia record;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un retiro como pagado.';
  end if;

  update public.solicitudes_retiro
  set estado = 'pagado', procesado_en = now(), procesado_por = v_admin_id
  where id = p_solicitud_id and estado = 'pendiente'
  returning * into v_solicitud;

  if v_solicitud.id is null then
    raise exception 'Esta solicitud ya fue procesada.';
  end if;

  v_restante := v_solicitud.monto;
  for r_ganancia in
    select *
    from public.ganancias_concursos
    where usuario_id = v_solicitud.usuario_id and pagado = false
    order by created_at, id
    for update
  loop
    exit when v_restante <= 0;

    if r_ganancia.monto <= v_restante then
      update public.ganancias_concursos
      set pagado = true, pagado_en = now(), pagado_por = v_admin_id
      where id = r_ganancia.id;
      v_restante := v_restante - r_ganancia.monto;
    else
      -- Pago parcial de esta fila: lo pagado se queda en la original,
      -- el resto sigue pendiente en una fila nueva.
      update public.ganancias_concursos
      set monto = v_restante, pagado = true, pagado_en = now(), pagado_por = v_admin_id
      where id = r_ganancia.id;

      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, creado_por, created_at, pagado,
        origen, operacion_id
      ) values (
        r_ganancia.usuario_id, r_ganancia.monto - v_restante,
        coalesce(r_ganancia.concepto, 'Ganancia') || ' (resto tras retiro)', r_ganancia.creado_por,
        r_ganancia.created_at, false, r_ganancia.origen, r_ganancia.operacion_id
      );

      v_restante := 0;
    end if;
  end loop;

  return v_solicitud;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_marcar_retiro_pagado(uuid) from public, anon;
grant execute on function public.admin_marcar_retiro_pagado(uuid) to authenticated;

-- ============================================================
-- === MIGRACION 073 (073_ganancia_redondeada_hacia_abajo.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 073: la ganancia/pérdida se redondea a centavos, hacia abajo
-- Pegar en Supabase → SQL Editor → Run (después de 001-072)
--
-- QA de "Cálculos de ganancia y pérdida" (2026-09-29): admin_cerrar_operacion
-- guardaba la ganancia con muchos decimales (ej. 4.508349783919329816), lo
-- que dejaba restos de fracciones de centavo pendientes de pago y una
-- diferencia entre "pendiente por recibir" y "disponible para retirar" (que
-- ya se trunca hacia abajo — ver perfil/page.tsx). Decisión del dueño del
-- proyecto: redondear siempre hacia abajo, mismo patrón floor(x*100)/100 que
-- ya usa el resto de la app para montos de dinero (nunca pagar de más).
--
-- El redondeo se aplica ANTES del piso de -monto_usado, para que el piso
-- siga siendo exacto incluso si el redondeo empujara el valor más allá.
-- ============================================================

create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_entrada numeric,
  p_precio_salida numeric,
  p_hora_entrada timestamptz default null,
  p_hora_cierre timestamptz default null
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_cantidad numeric;
  v_ganancia numeric;
  v_cerrado_en timestamptz := coalesce(p_hora_cierre, now());
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;
  if p_precio_entrada is null or p_precio_entrada = 'NaN'::numeric or p_precio_entrada <= 0 then
    raise exception 'El precio de entrada debe ser mayor a cero.';
  end if;
  if p_precio_salida is null or p_precio_salida = 'NaN'::numeric or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;
  if p_hora_entrada is not null and p_hora_cierre is not null
     and p_hora_entrada >= p_hora_cierre then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  -- Con una sola hora escrita, la otra es la real (apertura) o now()
  -- (cierre): se valida contra lo que efectivamente se va a guardar.
  if coalesce(p_hora_entrada, v_operacion.created_at) >= v_cerrado_en then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  v_cantidad := v_operacion.monto_usado / p_precio_entrada;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - p_precio_entrada) * v_cantidad
    else (p_precio_entrada - p_precio_salida) * v_cantidad
  end;
  -- Redondeo hacia abajo a centavos (floor, no round): una ganancia nunca
  -- se infla por el redondeo, y una pérdida nunca se reduce por él.
  v_ganancia := floor(v_ganancia * 100) / 100;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_entrada = p_precio_entrada,
      cantidad = v_cantidad,
      precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = v_cerrado_en,
      created_at = coalesce(p_hora_entrada, created_at)
  where id = p_operacion_id
  returning * into v_operacion;

  -- El saldo de práctica siempre recupera lo invertido, gane o pierda (030).
  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_operacion.usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 074 (074_reporte_por_dia_de_cierre.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 074: el reporte diario cuenta por el día en que la operación
-- se CIERRA (cerrado_en), no por el día en que se abrió (created_at)
-- Pegar en Supabase → SQL Editor → Run (después de 001-073)
--
-- QA de "Reportes" (2026-09-28) encontró que reporte_operaciones_por_dia
-- (migración 015) agrupaba por created_at: una operación abierta un día y
-- cerrada al siguiente contaba (y pagaba) en el reporte del día de
-- apertura, no del día en que el admin la liquidó de verdad. Decisión del
-- dueño del proyecto: el reporte debe reflejar el día de cierre, que es
-- cuando el resultado queda definitivo. Solo se cuentan operaciones
-- CERRADAS (una abierta sin resolver no tiene ganancia que reportar).
-- ============================================================

create or replace function public.reporte_operaciones_por_dia(
  p_inicio timestamptz,
  p_fin timestamptz
) returns table (
  usuario_id uuid,
  num_operaciones bigint,
  ganancia_neta numeric
) as $$
  select
    usuario_id,
    count(*) as num_operaciones,
    coalesce(sum(ganancia_perdida), 0) as ganancia_neta
  from public.operaciones_simuladas
  where public.es_admin()
    and estado = 'cerrada'
    and cerrado_en >= p_inicio
    and cerrado_en <= p_fin
  group by usuario_id;
$$ language sql security definer stable
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 075 (075_retiro_bloquea_si_falta_cobertura.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 075: pagar un retiro se BLOQUEA si las ganancias pendientes
-- ya no alcanzan a cubrirlo completo
-- Pegar en Supabase → SQL Editor → Run (después de 001-074)
--
-- Duda de negocio de la fase de Retiro (2026-09-29), resuelta: si un admin
-- paga o borra ganancias pendientes desde Reportes MIENTRAS hay una
-- solicitud de retiro pendiente, admin_marcar_retiro_pagado (migración 072)
-- reconciliaba con lo que quedara disponible y marcaba el retiro como
-- "pagado" igual, aunque cubriera menos de lo pedido — en silencio, sin
-- avisar que faltó dinero por reconciliar.
--
-- Ahora, si al terminar de recorrer las ganancias pendientes todavía queda
-- v_restante > 0 (no había suficiente para cubrir el monto del retiro), la
-- función entera revierte (ninguna ganancia se marca pagada, el retiro
-- vuelve a quedar 'pendiente') y se explica el motivo.
-- ============================================================

create or replace function public.admin_marcar_retiro_pagado(p_solicitud_id uuid)
returns public.solicitudes_retiro as $$
declare
  v_admin_id uuid := auth.uid();
  v_solicitud public.solicitudes_retiro;
  v_restante numeric;
  r_ganancia record;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un retiro como pagado.';
  end if;

  update public.solicitudes_retiro
  set estado = 'pagado', procesado_en = now(), procesado_por = v_admin_id
  where id = p_solicitud_id and estado = 'pendiente'
  returning * into v_solicitud;

  if v_solicitud.id is null then
    raise exception 'Esta solicitud ya fue procesada.';
  end if;

  v_restante := v_solicitud.monto;
  for r_ganancia in
    select *
    from public.ganancias_concursos
    where usuario_id = v_solicitud.usuario_id and pagado = false
    order by created_at, id
    for update
  loop
    exit when v_restante <= 0;

    if r_ganancia.monto <= v_restante then
      update public.ganancias_concursos
      set pagado = true, pagado_en = now(), pagado_por = v_admin_id
      where id = r_ganancia.id;
      v_restante := v_restante - r_ganancia.monto;
    else
      -- Pago parcial de esta fila: lo pagado se queda en la original,
      -- el resto sigue pendiente en una fila nueva.
      update public.ganancias_concursos
      set monto = v_restante, pagado = true, pagado_en = now(), pagado_por = v_admin_id
      where id = r_ganancia.id;

      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, creado_por, created_at, pagado,
        origen, operacion_id
      ) values (
        r_ganancia.usuario_id, r_ganancia.monto - v_restante,
        coalesce(r_ganancia.concepto, 'Ganancia') || ' (resto tras retiro)', r_ganancia.creado_por,
        r_ganancia.created_at, false, r_ganancia.origen, r_ganancia.operacion_id
      );

      v_restante := 0;
    end if;
  end loop;

  -- Si algo pagó o borró ganancias pendientes de este usuario mientras la
  -- solicitud esperaba (ej. desde Reportes), no queda suficiente para
  -- cubrirla: se revierte TODO (ninguna ganancia se toca, el retiro sigue
  -- 'pendiente') en vez de marcarlo pagado con un faltante silencioso.
  if v_restante > 0 then
    raise exception 'No hay suficientes ganancias pendientes para cubrir este retiro (faltan %). Puede que otro pago ya haya usado ese dinero — revisa las ganancias pendientes del usuario antes de reintentar.', v_restante;
  end if;

  return v_solicitud;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 076 (076_cuenta_desactivada_no_retira_ni_edita_perfil.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 076: una cuenta desactivada ya no puede solicitar retiros
-- ni editar su perfil (wallet / datos de contacto)
-- Pegar en Supabase → SQL Editor → Run (después de 001-075)
--
-- Hallazgo del QA de Gestión de usuarios (2026-09-29): si el usuario ya
-- tenía /perfil abierto cuando el admin lo desactivaba, el botón
-- "Solicitar retiro" seguía funcionando — solicitar_retiro (migraciones
-- 041-043) nunca miraba usuarios.activo, así que la solicitud quedaba
-- creada y le aparecía al admin en /retiros como si nada. Lo mismo con
-- la wallet y los datos de contacto: son un update directo sobre
-- `usuarios` y ni la política ni el trigger miraban `activo`. Todo lo
-- demás (abrir operación, depósito, soporte, favoritos) ya lo bloqueaba.
--
-- Fix:
--   1) solicitar_retiro: mismo chequeo y mismo texto que abrir_operacion
--      ("Tu cuenta está desactivada.") — el resto de la función queda
--      idéntica a la versión vigente en producción.
--   2) proteger_columnas_sensibles_usuarios: un usuario NO admin cuya
--      cuenta está desactivada no puede modificar su propia fila. Solo
--      aplica cuando es él mismo (auth.uid() = old.id): el admin sigue
--      pudiendo reactivarlo/editarlo, y las actualizaciones internas sin
--      sesión (auth.uid() null, p. ej. SQL directo) no se ven afectadas.
-- ============================================================

create or replace function public.solicitar_retiro(p_monto numeric)
returns public.solicitudes_retiro
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_usuario_id uuid := auth.uid();
  v_wallet text;
  v_activo boolean;
  v_pendiente numeric;
  v_ya_solicitado numeric;
  v_disponible numeric;
  v_nueva public.solicitudes_retiro;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado.';
  end if;

  if p_monto is null or p_monto <= 0 or p_monto >= 100000000 then
    raise exception 'Monto invalido.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('solicitar_retiro:' || v_usuario_id::text, 0)
  );

  select wallet_usdt_erc20, activo into v_wallet, v_activo
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  if v_wallet is null or trim(v_wallet) = '' then
    raise exception 'Registra tu wallet USDT (ERC20) en tu perfil antes de solicitar un retiro.';
  end if;

  if exists (
    select 1 from public.solicitudes_retiro
    where usuario_id = v_usuario_id and estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end if;

  select coalesce(sum(monto), 0) into v_pendiente
  from public.ganancias_concursos
  where usuario_id = v_usuario_id and pagado = false;

  -- Antes: 'pendiente','pagado'. Un retiro pagado ya redujo el fondo
  -- pendiente de verdad (reconciliacion), asi que contarlo aqui tambien
  -- lo restaria dos veces.
  select coalesce(sum(monto), 0) into v_ya_solicitado
  from public.solicitudes_retiro
  where usuario_id = v_usuario_id and estado = 'pendiente';

  v_disponible := v_pendiente - v_ya_solicitado;

  if round(p_monto, 2) > v_disponible then
    raise exception 'No puedes retirar mas de lo que tienes disponible.';
  end if;

  begin
    insert into public.solicitudes_retiro (usuario_id, monto, wallet_destino)
    values (v_usuario_id, round(p_monto, 2), v_wallet)
    returning * into v_nueva;
  exception when unique_violation then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end;

  return v_nueva;
end;
$function$;

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_es_admin boolean := public.es_admin();
begin
  -- es_principal nunca se toca desde la aplicación, ni siquiera un admin
  -- — solo con acceso directo a la base de datos.
  if new.es_principal is distinct from old.es_principal then
    raise exception 'Ese campo no se puede modificar desde la aplicación.';
  end if;

  -- invitado_por es inmutable para todos, incluido el admin: solo el
  -- registro lo asigna, una sola vez.
  if new.invitado_por is distinct from old.invitado_por then
    raise exception 'La relación de quién invitó a quién no se puede modificar.';
  end if;

  -- Migración 076: una cuenta desactivada no edita nada de su propio
  -- perfil (wallet, nombre, teléfono) — aunque tenga /perfil abierto de
  -- antes de que el admin la desactivara.
  if old.activo = false
     and auth.uid() = old.id
     and not v_es_admin
  then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  -- Un admin marcado como principal solo se puede modificar a sí mismo:
  -- ningún otro admin puede quitarle el rol, desactivarlo o bloquearle
  -- el trading.
  if old.es_principal
     and auth.uid() is distinct from old.id
     and (new.role is distinct from old.role
          or new.activo is distinct from old.activo
          or new.trading_habilitado is distinct from old.trading_habilitado)
  then
    raise exception 'No puedes modificar la cuenta del administrador principal.';
  end if;

  if (new.role is distinct from old.role
      or new.activo is distinct from old.activo
      or new.trading_habilitado is distinct from old.trading_habilitado)
     and not v_es_admin then
    raise exception 'Solo un admin puede cambiar el rol, el estado o el permiso de trading de una cuenta.';
  end if;

  if (new.id is distinct from old.id
      or new.email is distinct from old.email
      or new.codigo_invitacion is distinct from old.codigo_invitacion
      or new.id_corto is distinct from old.id_corto
      or new.created_at is distinct from old.created_at)
     and not v_es_admin then
    raise exception 'No puedes modificar los datos de identidad de tu cuenta. Contacta a soporte.';
  end if;

  -- Solo el admin puede tener más de una wallet guardada.
  if (new.wallet_usdt_erc20_2 is not null or new.wallet_usdt_erc20_3 is not null)
     and not v_es_admin then
    raise exception 'Solo un admin puede guardar más de una wallet.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$function$;

-- ============================================================
-- === MIGRACION 077 (077_cancela_operacion_al_desactivar_o_borrar_deposito.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 077: cancela la operación abierta al desactivar una cuenta o
-- al borrar el depósito que la financiaba
-- Pegar en Supabase → SQL Editor → Run (después de 001-076)
--
-- Duda de negocio de la fase de Gestión de usuarios (2026-09-29), resuelta:
-- desactivar una cuenta (o borrar un depósito ya gastado en una operación)
-- dejaba esa operación "abierta" para siempre, sin que nadie pudiera
-- cerrarla nunca (el usuario no puede, y el cierre en bloque del admin
-- exige que el símbolo siga siendo el pick vigente). Decisión: cancelarla
-- automáticamente.
--
-- Dos casos, con reglas de saldo distintas:
--   1) Desactivar la cuenta: el dinero sigue siendo legítimamente del
--      usuario (nada se revirtió), así que se le REPONE su monto_usado al
--      saldo — queda listo para cuando lo reactiven.
--   2) Borrar un depósito ya pagado: el fondeo mismo desaparece, así que
--      la operación se cancela SIN reponer nada (si se repusiera, sería
--      dinero que ya no existe).
-- En ambos casos: estado = 'cancelada' (se agrega como valor válido),
-- precio_salida y ganancia_perdida quedan en null/0 -- no es un resultado
-- de trading, es una anulación administrativa.
-- ============================================================

alter table public.operaciones_simuladas
  drop constraint if exists operaciones_simuladas_estado_check;

alter table public.operaciones_simuladas
  add constraint operaciones_simuladas_estado_check
  check (estado in ('abierta', 'cerrada', 'cancelada'));

-- 1) Desactivar la cuenta cancela su operación abierta y repone el saldo --

create or replace function public.cancelar_operacion_al_desactivar_cuenta()
returns trigger as $$
declare
  v_monto numeric;
begin
  if new.activo = false and old.activo = true then
    update public.operaciones_simuladas
    set estado = 'cancelada', cerrado_en = now(),
        precio_salida = null, ganancia_perdida = 0
    where usuario_id = new.id and estado = 'abierta'
    returning monto_usado into v_monto;

    if v_monto is not null then
      update public.saldo_virtual
      set saldo_usd = saldo_usd + v_monto, actualizado_en = now()
      where usuario_id = new.id;
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists cancelar_operacion_al_desactivar on public.usuarios;
create trigger cancelar_operacion_al_desactivar
  after update on public.usuarios
  for each row execute function public.cancelar_operacion_al_desactivar_cuenta();

-- 2) Borrar un depósito pagado cancela la operación SIN reponer el monto --
-- (mismo cuerpo que la 066, con este paso agregado al final).

create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
begin
  if old.pagado then
    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;

    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;

    -- Con una sola operación abierta por usuario y esa operación usando
    -- siempre el saldo COMPLETO (migración 032), si hay una abierta es
    -- porque el dinero de este depósito (u otro) está atrapado ahí. El
    -- depósito que se está borrando ya no existe, así que ese dinero
    -- tampoco -- se anula la operación sin devolver nada.
    update public.operaciones_simuladas
    set estado = 'cancelada', cerrado_en = now(),
        precio_salida = null, ganancia_perdida = 0
    where usuario_id = old.usuario_id and estado = 'abierta';
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 078 (078_totales_dashboard_admin_ajustado.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 078: ajusta admin_totales_dashboard (migración 051)
-- Pegar en Supabase → SQL Editor → Run (después de 001-077)
--
-- Tres decisiones del dueño del proyecto tras el QA de Perfil de admin
-- (2026-09-29):
--
-- 1) "Total a pagar hoy" solo sumaba ganancias con origen='trade' — deja
--    fuera bonos de concurso y comisiones de referido. Ahora suma
--    cualquier origen, siempre que siga sin pagar.
--
-- 2) La fecha usada para "hoy" no coincidía con la de Reportes (migración
--    074): el dashboard usaba ganancias_concursos.created_at (el momento
--    real en que se registró la fila) y Reportes usa
--    operaciones_simuladas.cerrado_en (la hora de cierre que el admin
--    escribe a mano, que puede quedar en el pasado). Ahora las dos
--    pantallas usan el mismo criterio: para ganancias de trade (tienen
--    operacion_id), se usa el cerrado_en de esa operación; para las que no
--    vienen de una operación (concurso, referido — no tienen operacion_id),
--    se sigue usando su propio created_at, que es lo único que tiene
--    sentido para ellas.
--
-- 3) "Total en cuentas" sumaba TODAS las filas de saldo_virtual, incluida
--    la del propio admin (que no opera, ese número no significa nada) y
--    las de cuentas desactivadas (que sí se mantienen, no se excluyen).
--    Ahora excluye únicamente las cuentas con role='admin'.
-- ============================================================

create or replace function public.admin_totales_dashboard(
  p_inicio timestamptz,
  p_fin timestamptz
)
returns table (total_cuentas numeric, total_a_pagar_hoy numeric)
language sql
stable
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
  select
    (select coalesce(sum(sv.saldo_usd), 0)
       from public.saldo_virtual sv
       join public.usuarios u on u.id = sv.usuario_id
      where u.role <> 'admin'),
    (select coalesce(sum(g.monto), 0)
       from public.ganancias_concursos g
       left join public.operaciones_simuladas o on o.id = g.operacion_id
      where g.pagado = false
        and coalesce(o.cerrado_en, g.created_at) >= p_inicio
        and coalesce(o.cerrado_en, g.created_at) < p_fin);
$$;

-- ============================================================
-- === MIGRACION 079 (079_revertir_deposito_borra_bono_si_ya_no_alcanza.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 079: revertir un depósito borra el bono de referido si el
-- conteo de calificados ya no alcanza para ese hito (y sigue sin pagar)
-- Pegar en Supabase → SQL Editor → Run (después de 001-078)
--
-- Duda de negocio del QA de Comunidad + Referidos (2026-09-29), resuelta:
-- si el admin revierte el depósito de un referido y eso hace bajar el
-- conteo de calificados del invitador por debajo de un hito ya alcanzado
-- (ej. de 10 a 9), el bono de ese hito se quedaba intacto, sin pagar,
-- aunque el hito ya no se cumpliera de verdad. Solo se borraba la
-- comisión del referido revertido, nunca el bono.
--
-- Fix: en la misma rama de reversión de otorgar_recompensa_referido(), tras
-- borrar la comisión, se recalcula el conteo de calificados del invitador
-- (con el depósito ya revertido) y se borran los bonos de referido SIN
-- PAGAR cuyo hito (el número embebido en el concepto "Bono por N referidos
-- calificados") ya no alcanza ese conteo. Un bono YA PAGADO nunca se toca
-- (el invitador ya recibió ese dinero fuera de la plataforma).
-- ============================================================

create or replace function public.otorgar_recompensa_referido()
returns trigger as $$
declare
  v_invitador uuid;
  v_email_invitado text;
  v_config jsonb;
  v_porcentaje numeric;
  v_bono_cada int;
  v_bono_monto numeric;
  v_comision numeric;
  v_calificados_count int;
  v_concepto_bono text;
begin
  -- Reversión: el admin marcó el depósito de vuelta a pendiente. Si la
  -- comisión de ESTE invitado seguía sin pagar, se borra — nunca se
  -- confirmó de verdad el depósito que la generaba. Una ya pagada no se
  -- toca (el invitador ya recibió su USDT, revertir el registro interno
  -- no se lo puede quitar).
  if new.pagado = false and old.pagado = true then
    delete from public.ganancias_concursos
    where invitado_id = new.usuario_id
      and origen = 'referido'
      and pagado = false;

    -- El conteo de calificados del invitador de este referido puede haber
    -- bajado por debajo de un hito ya alcanzado. Se recalcula CON el
    -- depósito ya revertido (new.pagado = false en esta misma fila) y se
    -- borran los bonos sin pagar que ya no alcanzan ese conteo.
    select invitado_por into v_invitador
    from public.usuarios
    where id = new.usuario_id;

    if v_invitador is not null then
      select count(*) into v_calificados_count
      from public.usuarios u
      join public.depositos_simulados d on d.usuario_id = u.id and d.pagado = true
      where u.invitado_por = v_invitador;

      delete from public.ganancias_concursos
      where usuario_id = v_invitador
        and origen = 'referido'
        and invitado_id is null
        and pagado = false
        and coalesce(nullif(regexp_replace(concepto, '\D', '', 'g'), '')::int, 0)
            > v_calificados_count;
    end if;

    return new;
  end if;

  select invitado_por, email into v_invitador, v_email_invitado
  from public.usuarios
  where id = new.usuario_id;

  if v_invitador is null then
    return new;
  end if;

  select valor into v_config
  from public.config_portada
  where clave = 'premio_referido';

  v_porcentaje := coalesce((v_config ->> 'porcentaje')::numeric, 10);
  v_bono_cada := coalesce((v_config ->> 'bono_cada')::int, 10);
  v_bono_monto := coalesce((v_config ->> 'bono_monto')::numeric, 1000);

  v_comision := round(new.monto * greatest(v_porcentaje, 0) / 100, 2);

  if v_comision > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      v_invitador, v_comision,
      'Referido (' || v_porcentaje || '%): ' || v_email_invitado,
      'referido', new.usuario_id
    )
    on conflict (invitado_id) where invitado_id is not null do update
    set monto = excluded.monto,
        concepto = excluded.concepto
    where public.ganancias_concursos.pagado = false;
  end if;

  -- Solo cuentan como "calificados" los referidos con el depósito
  -- CONFIRMADO — antes contaba cualquier fila, sin importar pagado.
  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id and d.pagado = true
  where u.invitado_por = v_invitador;

  if v_bono_cada > 0 and v_calificados_count > 0
     and v_calificados_count % v_bono_cada = 0 then
    v_concepto_bono := 'Bono por ' || v_calificados_count || ' referidos calificados';

    if not exists (
      select 1 from public.ganancias_concursos
      where usuario_id = v_invitador
        and origen = 'referido'
        and invitado_id is null
        and concepto = v_concepto_bono
    ) then
      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, origen
      ) values (
        v_invitador, v_bono_monto, v_concepto_bono, 'referido'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 080 (080_cron_cierre_automatico_senales.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 080: cron real para el cierre automático de señales por TP/SL
-- Pegar en Supabase → SQL Editor → Run (después de 001-079)
--
-- Hasta ahora, revisarYCerrarSenalesActivas() (src/lib/senales/verificarTpSl.ts)
-- solo corría cuando alguien cargaba /senales (o su auto-refresh). El
-- resultado final siempre fue correcto (se revisan las velas históricas de
-- Binance desde que se publicó la señal, no el precio del momento), pero si
-- nadie visitaba la página, una señal que ya tocó su nivel se quedaba
-- "activa" en la UI hasta la próxima visita — podían pasar horas o días.
--
-- Mismo patrón que limpiar_comprobantes_vencidos() (migración 046):
-- pg_cron dispara una función SECURITY DEFINER que usa pg_net para llamar
-- por HTTP a la app real en Railway. Se llama a una ruta API nueva
-- (/api/cron/senales) que reutiliza la MISMA función de TypeScript que ya
-- usa /senales — no hay lógica de TP/SL duplicada en SQL.
--
-- El secreto para autenticar la llamada es el MISMO trading_server_secret
-- que ya vive en config_servidor (migración 019) — no hace falta agregar
-- ninguna variable de entorno nueva en Railway.
--
-- IMPORTANTE si el dominio cambia (ej. al conectar un dominio propio): hay
-- que actualizar la URL de esta función con
--   select cron.unschedule('cerrar-senales-automatico');
-- y volver a correr el bloque de abajo con la URL nueva.
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public.disparar_cron_senales()
returns void as $$
declare
  v_secreto text;
begin
  select valor into v_secreto
  from public.config_servidor
  where clave = 'trading_server_secret';

  if v_secreto is null or v_secreto = 'FALTA-ROTAR-ESTE-SECRETO' then
    raise notice 'trading_server_secret sin configurar todavia, se omite el cron de senales';
    return;
  end if;

  -- Encola la petición (asíncrono, no bloquea) — el cron no necesita
  -- esperar la respuesta, solo dispararla; la propia ruta hace el trabajo.
  perform net.http_post(
    url := 'https://criarcaballo-production.up.railway.app/api/cron/senales',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secreto,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  );
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

revoke all on function public.disparar_cron_senales() from public, anon, authenticated;

select cron.schedule(
  'cerrar-senales-automatico',
  '* * * * *', -- cada minuto; la propia app se auto-limita a revisar como mucho cada 30s
  $$select public.disparar_cron_senales()$$
);

-- ============================================================
-- === MIGRACION 081 (081_seguridad_rutas_comprobantes_y_retiros.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 081: auditoría AppSec (2026-09-30)
-- Pegar en Supabase → SQL Editor → Run (después de 001-080)
--
-- 1) ALTA: mensajes_soporte.imagen_path no tenía ninguna validación. Un
--    usuario normal, con su propio JWT y la anon key (PostgREST directo,
--    sin pasar por la Server Action), podía insertar o editar un mensaje
--    con imagen_path = 'su-uid/../../otro-bucket/archivo' (o la carpeta de
--    OTRO usuario) y además poner created_at en el pasado. El cron diario
--    limpiar_comprobantes_vencidos() arma la URL de Storage con ese valor y
--    hace el DELETE con la service_role key → borrado arbitrario de
--    archivos de Storage (el mismo tipo de traversal que la 059 cerró en
--    limpiar_comprobante_huerfano, pero por la otra puerta).
--    Además, created_at editable permitía saltarse el límite de 10
--    mensajes/minuto, y leido_admin editable permitía ocultarle al admin
--    los mensajes no leídos.
--
--    Arreglo: CHECK de formato exacto (<usuario_id>/<uuid>.<jpg|png|webp>,
--    lo único que genera subirComprobante()), created_at forzado a now() al
--    insertar, leido_admin solo lo toca un admin, imagen_path solo se puede
--    cambiar a NULL después de insertado, y el cron vuelve a validar la
--    ruta antes de llamar a Storage (defensa en profundidad).
--
-- 2) BAJA: mismo CHECK de formato para depositos_simulados.comprobante_path
--    (la policy solo exigía el prefijo 'uid/%', aceptaba 'uid/../x').
--
-- 3) MEDIA: políticas "qa test insert"/"qa test select" sobrantes de una
--    ronda de QA sobre el bucket qa-test-bucket: cualquiera, INCLUSO SIN
--    SESIÓN (anon), podía subir archivos sin límite de tamaño ni de tipo.
--
-- 4) BAJA: una solicitud de retiro ya procesada (pagado/rechazado) se podía
--    volver a 'pendiente' con un UPDATE directo (policy de admin) y pagarla
--    de nuevo, marcando como pagadas más ganancias de las retiradas. Ahora
--    el estado final es inmutable y monto/usuario/wallet no se editan.
--
-- 5) Higiene: se quita EXECUTE a anon/authenticated de funciones que solo
--    son de trigger.
-- ============================================================

-- 1) mensajes_soporte ------------------------------------------------------

alter table public.mensajes_soporte
  add constraint mensajes_soporte_imagen_path_formato check (
    imagen_path is null
    or imagen_path ~ (
      '^' || usuario_id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
    )
  );

create or replace function public.limitar_frecuencia_mensajes_soporte()
returns trigger as $$
declare
  v_recientes int;
begin
  -- Nadie elige la fecha de su mensaje: backdatear servía para saltarse
  -- este mismo límite y para que el cron de 5 días lo procesara ya.
  new.created_at := now();

  -- El admin responde muchas conversaciones seguidas: no se le limita.
  if public.es_admin() then
    return new;
  end if;

  -- Un usuario no puede marcar su propio mensaje como ya leído por el admin.
  new.leido_admin := false;

  select count(*) into v_recientes
  from public.mensajes_soporte
  where remitente_id = new.remitente_id
    and created_at > now() - interval '1 minute';

  if v_recientes >= 10 then
    raise exception 'Estás enviando mensajes demasiado rápido. Espera un momento antes de volver a escribir.';
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

create or replace function public.proteger_mensajes_soporte()
returns trigger as $$
begin
  if new.id is distinct from old.id
     or new.usuario_id is distinct from old.usuario_id
     or new.remitente_id is distinct from old.remitente_id
     or new.contenido is distinct from old.contenido
     or new.created_at is distinct from old.created_at then
    raise exception 'Un mensaje de soporte enviado no se puede modificar; solo marcarse como leído.';
  end if;

  -- La imagen solo puede quitarse (cron de limpieza), nunca reemplazarse.
  if new.imagen_path is distinct from old.imagen_path
     and new.imagen_path is not null then
    raise exception 'La imagen de un mensaje enviado no se puede cambiar.';
  end if;

  -- leido_admin es el contador del admin; el usuario no lo toca.
  -- auth.uid() null = cron / SQL directo, se permite.
  if new.leido_admin is distinct from old.leido_admin
     and auth.uid() is not null
     and not public.es_admin() then
    raise exception 'Solo un admin puede marcar mensajes como leídos por soporte.';
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

create or replace function public.limpiar_comprobantes_vencidos()
returns void as $$
declare
  r record;
  v_service_key text;
begin
  select valor into v_service_key
  from public.config_servidor
  where clave = 'supabase_service_role_key';

  if v_service_key is null or v_service_key = 'FALTA-CONFIGURAR-ESTA-CLAVE' then
    raise notice 'supabase_service_role_key sin configurar todavia, se omite la limpieza de comprobantes';
    return;
  end if;

  for r in
    select ms.id, ms.imagen_path
    from public.mensajes_soporte ms
    where ms.imagen_path is not null
      and ms.created_at < now() - interval '5 days'
      and not exists (
        select 1 from public.depositos_simulados d
        where d.comprobante_path = ms.imagen_path
      )
  loop
    -- Defensa en profundidad: aunque el CHECK ya lo garantiza, nunca se
    -- manda a Storage (con la service_role key) una ruta que no sea
    -- exactamente <uuid>/<uuid>.<ext>.
    if r.imagen_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$' then
      perform net.http_delete(
        url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || r.imagen_path,
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_service_key,
          'apikey', v_service_key
        )
      );
    end if;

    update public.mensajes_soporte
    set imagen_path = null
    where id = r.id;
  end loop;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

-- 2) depositos_simulados ---------------------------------------------------

alter table public.depositos_simulados
  add constraint depositos_simulados_comprobante_path_formato check (
    comprobante_path is null
    or comprobante_path ~ (
      '^' || usuario_id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
    )
  );

-- 3) bucket de QA abierto a anon -------------------------------------------

drop policy if exists "qa test insert" on storage.objects;
drop policy if exists "qa test select" on storage.objects;

-- 4) solicitudes_retiro: estado final inmutable ----------------------------

create or replace function public.proteger_solicitudes_retiro()
returns trigger as $$
begin
  if new.id is distinct from old.id
     or new.usuario_id is distinct from old.usuario_id
     or new.monto is distinct from old.monto
     or new.wallet_destino is distinct from old.wallet_destino
     or new.created_at is distinct from old.created_at then
    raise exception 'Los datos de una solicitud de retiro no se pueden modificar.';
  end if;

  if old.estado <> 'pendiente' and new.estado is distinct from old.estado then
    raise exception 'Esta solicitud ya fue procesada; su estado no se puede cambiar.';
  end if;

  return new;
end;
$$ language plpgsql
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_editar_solicitud_retiro on public.solicitudes_retiro;
create trigger antes_de_editar_solicitud_retiro
  before update on public.solicitudes_retiro
  for each row execute function public.proteger_solicitudes_retiro();

-- 5) funciones de trigger: no invocables por RPC ---------------------------

revoke execute on function public.cancelar_operacion_al_desactivar_cuenta() from public, anon, authenticated;
revoke execute on function public.revertir_saldo_al_borrar_deposito() from public, anon, authenticated;
revoke execute on function public.senales_congelar_cerradas() from public, anon, authenticated;
revoke execute on function public.proteger_solicitudes_retiro() from public, anon, authenticated;

-- ============================================================
-- === MIGRACION 082 (082_un_pick_por_usuario_una_sola_vez.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 082: un usuario solo puede operar cada pick UNA vez
-- Pegar en Supabase → SQL Editor → Run (después de 001-081)
--
-- Hallazgo del dueño del proyecto (2026-09-30): abrir_operacion solo
-- comparaba el SÍMBOLO del pick vigente (p.ej. "SPACE X"), nunca un id de
-- pick concreto. admin_cerrar_operacion siempre devuelve el capital
-- invertido a saldo_virtual (gane o pierda la operación, migración 030).
-- Resultado: si el admin cierra la sesión y no borra/cambia el pick de
-- inmediato, el usuario recupera su saldo completo y puede volver a abrir
-- otra operación sobre EL MISMO pick, cobrando la misma señal una y otra
-- vez mientras el pick siga vigente.
--
-- Arreglo: cada operación ahora guarda el id exacto del pick con el que se
-- abrió (pick_id). abrir_operacion bloquea una nueva apertura si el
-- usuario YA tiene cualquier operación (abierta o cerrada) con ese mismo
-- pick_id -- no depende de que el admin se acuerde de borrar el pick.
-- ============================================================

alter table public.operaciones_simuladas
  add column if not exists pick_id uuid references public.pick_del_dia(id) on delete set null;

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick_id uuid;
  v_pick_activo text;
  v_horario jsonb;
  v_apertura time;
  v_cierre time;
  v_dias_habiles int[];
  v_abierto_siempre boolean;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  select id, activo into v_pick_id, v_pick_activo
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1;

  if v_pick_id is null or upper(v_pick_activo) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    v_abierto_siempre := coalesce(v_horario->>'abierto_siempre' = 'true', false);

    if not v_abierto_siempre then
      v_apertura := case
        when v_horario->>'apertura' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'apertura')::time
        else time '09:30'
      end;
      v_cierre := case
        when v_horario->>'cierre' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'cierre')::time
        else time '16:00'
      end;
      v_dias_habiles := coalesce(
        (
          select array_agg(distinct d::int)
          from jsonb_array_elements_text(
            case when jsonb_typeof(v_horario->'dias') = 'array'
              then v_horario->'dias' else '[]'::jsonb end
          ) d
          where d ~ '^[1-7]$'
        ),
        array[1, 2, 3, 4, 5]
      );

      v_hora_ny := (now() at time zone 'America/New_York')::time;
      v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));

      if not (v_dia_semana_ny = any(v_dias_habiles))
         or v_hora_ny < v_apertura
         or v_hora_ny >= v_cierre then
        raise exception 'El mercado está cerrado en este momento.';
      end if;
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Podrás abrir otra cuando el admin cierre la sesión.';
  end if;

  -- El núcleo del arreglo: ya se operó este pick (abierta o cerrada), sin
  -- importar que el admin haya devuelto el saldo al cerrarla.
  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and pick_id = v_pick_id
  ) then
    raise exception 'Ya operaste el pick de hoy. Espera a que el admin publique uno nuevo.';
  end if;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado, pick_id
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta', v_pick_id
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 083 (083_pick_se_borra_solo_al_cerrar_la_ultima_operacion.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 083: el pick se borra solo cuando se cierra su última
-- operación abierta, y nunca se puede borrar con operaciones pendientes
-- Pegar en Supabase → SQL Editor → Run (después de 001-082)
--
-- Hallazgo real del dueño del proyecto (2026-10-01): con la migración 082
-- sola, un usuario que YA había operado un pick quedaba bloqueado de
-- repetirlo, pero alguien que nunca había operado ESE pick sí podía
-- abrir una posición nueva sobre él después de que el admin liquidó la
-- sesión de los demás -- el pick seguía "vigente" en pantalla hasta que
-- el admin lo borrara a mano.
--
-- Decisión del dueño del proyecto: en vez de agregar un estado "cerrado"
-- al pick (lo que se había planteado primero), que el pick se BORRE solo,
-- automáticamente, en el mismo momento en que se cierra su última
-- operación abierta -- así no hay ventana de tiempo ni paso manual que el
-- admin se pueda saltar. abrir_operacion YA rechaza cualquier apertura si
-- no hay un pick vigente ("Ese activo no es el pick del día vigente."),
-- así que borrar el pick alcanza por sí solo, sin tocar esa función.
--
-- La trazabilidad que pidió el dueño del proyecto (saber por cuál pick se
-- pagó una ganancia, aunque el pick ya no exista) no se pierde: el símbolo
-- (activo) queda guardado directo en operaciones_simuladas.activo y en
-- ganancias_concursos.concepto ("Trade del día — BITCOIN"), columnas de
-- texto independientes de la fila de pick_del_dia.
--
-- Seguro adicional: un trigger BEFORE DELETE en pick_del_dia bloquea CUALQUIER
-- borrado (manual, desde el botón "Eliminar" del admin, o por SQL directo)
-- mientras ese pick todavía tenga una operación en estado 'abierta' -- el
-- problema real que se reportó fue causado por borrar el pick ANTES de
-- cerrar la operación de praxedes@gmail.com; con este seguro eso ya no se
-- puede repetir ni por accidente. El borrado automático de más abajo nunca
-- choca con este seguro porque solo se dispara cuando ya no queda NINGUNA
-- operación abierta de ese pick.
-- ============================================================

create or replace function public.proteger_borrado_pick_del_dia()
returns trigger as $$
begin
  if exists (
    select 1 from public.operaciones_simuladas
    where pick_id = old.id and estado = 'abierta'
  ) then
    raise exception 'Este pick todavía tiene operaciones abiertas. Ciérralas primero desde "Cerrar todas las operaciones abiertas".';
  end if;
  return old;
end;
$$ language plpgsql
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_borrar_pick_del_dia on public.pick_del_dia;
create trigger antes_de_borrar_pick_del_dia
  before delete on public.pick_del_dia
  for each row execute function public.proteger_borrado_pick_del_dia();

revoke execute on function public.proteger_borrado_pick_del_dia() from public, anon, authenticated;

create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_entrada numeric,
  p_precio_salida numeric,
  p_hora_entrada timestamptz default null,
  p_hora_cierre timestamptz default null
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_cantidad numeric;
  v_ganancia numeric;
  v_cerrado_en timestamptz := coalesce(p_hora_cierre, now());
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;
  if p_precio_entrada is null or p_precio_entrada = 'NaN'::numeric or p_precio_entrada <= 0 then
    raise exception 'El precio de entrada debe ser mayor a cero.';
  end if;
  if p_precio_salida is null or p_precio_salida = 'NaN'::numeric or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;
  if p_hora_entrada is not null and p_hora_cierre is not null
     and p_hora_entrada >= p_hora_cierre then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  if coalesce(p_hora_entrada, v_operacion.created_at) >= v_cerrado_en then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  v_cantidad := v_operacion.monto_usado / p_precio_entrada;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - p_precio_entrada) * v_cantidad
    else (p_precio_entrada - p_precio_salida) * v_cantidad
  end;
  v_ganancia := floor(v_ganancia * 100) / 100;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_entrada = p_precio_entrada,
      cantidad = v_cantidad,
      precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = v_cerrado_en,
      created_at = coalesce(p_hora_entrada, created_at)
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_operacion.usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  -- El núcleo del arreglo: si esta era la última operación abierta de su
  -- pick, el pick se borra solo -- nadie (haya operado o no) puede abrir
  -- nada sobre él porque abrir_operacion ya rechaza cuando no hay pick
  -- vigente. El trigger de arriba nunca bloquea este DELETE porque la
  -- condición "not exists" ya garantiza cero operaciones abiertas.
  if v_operacion.pick_id is not null
     and not exists (
       select 1 from public.operaciones_simuladas
       where pick_id = v_operacion.pick_id and estado = 'abierta'
     ) then
    delete from public.pick_del_dia where id = v_operacion.pick_id;
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 084 (084_apellido_y_cedula_en_registro.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 084: apellido y cédula (national ID) en el registro
-- Pegar en Supabase → SQL Editor → Run (después de 001-083)
--
-- IMPORTANTE: esta migración debe correrse ANTES de desplegar el código
-- nuevo (handle_new_user() inserta en columnas apellido/cedula -- si no
-- existen todavía, CUALQUIER registro nuevo, no solo los que usan estos
-- campos, fallaría con "column does not exist" en el trigger).
--
-- Pedido del dueño del proyecto (2026-10-01): el registro ahora pide
-- apellido y cédula (formato dominicano NNN-NNNNNNN-N), ambos obligatorios
-- junto con nombre y correo (nombre y correo ya eran obligatorios).
--
-- Las columnas aceptan NULL a nivel de base de datos (las cuentas ya
-- existentes no tienen estos datos y no se les puede exigir
-- retroactivamente) -- la obligatoriedad real la aplica el formulario de
-- registro. El CHECK de formato de cédula sí es duro: si se manda un
-- valor, tiene que tener el formato correcto.
-- ============================================================

alter table public.usuarios
  add column if not exists apellido text,
  add column if not exists cedula text;

alter table public.usuarios
  drop constraint if exists usuarios_cedula_formato;

alter table public.usuarios
  add constraint usuarios_cedula_formato check (
    cedula is null or cedula ~ '^[0-9]{3}-[0-9]{7}-[0-9]$'
  );

create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  nombre_inicial text;
  apellido_inicial text;
  telefono_inicial text;
  cedula_inicial text;
  v_nuevo_id_corto int;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref
      and activo = true;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  nombre_inicial := nullif(trim(new.raw_user_meta_data ->> 'nombre'), '');
  apellido_inicial := nullif(trim(new.raw_user_meta_data ->> 'apellido'), '');
  telefono_inicial := nullif(trim(new.raw_user_meta_data ->> 'telefono'), '');
  cedula_inicial := nullif(trim(new.raw_user_meta_data ->> 'cedula'), '');
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (
    id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20,
    id_corto, nombre, apellido, telefono, cedula
  )
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    v_nuevo_id_corto, nombre_inicial, apellido_inicial, telefono_inicial, cedula_inicial
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 085 (085_fee_de_retiro_parametrizable.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 085: fee de retiro parametrizable (% sobre el monto pedido)
-- Pegar en Supabase → SQL Editor → Run (después de 001-084)
--
-- Pedido del dueño del proyecto (2026-10-01): un fee sobre los retiros,
-- parametrizable (no fijo en código) para poder ajustarlo sin desplegar,
-- igual que el % de comisión de referidos. Decisión de negocio: el fee se
-- le resta al usuario del monto que pidió (pide $50 con 10% de fee, se le
-- transfieren $45) -- no lo absorbe la plataforma aparte.
--
-- El monto que consume del fondo de ganancias pendientes sigue siendo el
-- BRUTO pedido (sin cambios en esa lógica): lo único nuevo es cuánto USDT
-- hay que transferirle de verdad, que ahora se puede calcular (monto -
-- monto * fee_porcentaje/100) tanto en el formulario del usuario como en
-- la cola del admin.
--
-- El % se guarda en cada solicitud (fee_porcentaje) en el momento en que
-- se crea -- si el admin cambia el % global después, las solicitudes ya
-- hechas (pendientes o pagadas) conservan el % con el que se pidieron,
-- mismo patrón que el % de comisión de referidos (config-referidos.ts).
-- ============================================================

alter table public.solicitudes_retiro
  add column if not exists fee_porcentaje numeric not null default 0;

alter table public.solicitudes_retiro
  drop constraint if exists fee_porcentaje_valido;
alter table public.solicitudes_retiro
  add constraint fee_porcentaje_valido check (fee_porcentaje >= 0 and fee_porcentaje <= 100);

create or replace function public.solicitar_retiro(p_monto numeric)
returns public.solicitudes_retiro
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_usuario_id uuid := auth.uid();
  v_wallet text;
  v_activo boolean;
  v_pendiente numeric;
  v_ya_solicitado numeric;
  v_disponible numeric;
  v_fee numeric;
  v_nueva public.solicitudes_retiro;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado.';
  end if;

  if p_monto is null or p_monto <= 0 or p_monto >= 100000000 then
    raise exception 'Monto invalido.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('solicitar_retiro:' || v_usuario_id::text, 0)
  );

  select wallet_usdt_erc20, activo into v_wallet, v_activo
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  if v_wallet is null or trim(v_wallet) = '' then
    raise exception 'Registra tu wallet USDT (ERC20) en tu perfil antes de solicitar un retiro.';
  end if;

  if exists (
    select 1 from public.solicitudes_retiro
    where usuario_id = v_usuario_id and estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end if;

  select coalesce(sum(monto), 0) into v_pendiente
  from public.ganancias_concursos
  where usuario_id = v_usuario_id and pagado = false;

  select coalesce(sum(monto), 0) into v_ya_solicitado
  from public.solicitudes_retiro
  where usuario_id = v_usuario_id and estado = 'pendiente';

  v_disponible := v_pendiente - v_ya_solicitado;

  if round(p_monto, 2) > v_disponible then
    raise exception 'No puedes retirar mas de lo que tienes disponible.';
  end if;

  select coalesce((valor->>'porcentaje')::numeric, 0) into v_fee
  from public.config_portada
  where clave = 'fee_retiro';

  begin
    insert into public.solicitudes_retiro (usuario_id, monto, wallet_destino, fee_porcentaje)
    values (v_usuario_id, round(p_monto, 2), v_wallet, coalesce(v_fee, 0))
    returning * into v_nueva;
  exception when unique_violation then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end;

  return v_nueva;
end;
$function$;

-- ============================================================
-- === MIGRACION 086 (086_fee_retiro_lectura_robusta.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 086: solicitar_retiro lee el fee igual que la app
-- Pegar en Supabase → SQL Editor → Run (después de 001-085)
--
-- QA 2026-10-01: la RPC de la migración 085 leía config_portada.fee_retiro
-- con un cast directo ((valor->>'porcentaje')::numeric), mientras que la
-- app (obtenerFeeRetiro) solo acepta un número JSON entre 0 y 100 y si no
-- muestra "sin fee". El formulario de admin siempre guarda un número
-- válido, así que solo pasa si alguien escribe la config a mano (SQL/API),
-- pero entonces:
--   - {"porcentaje": 150} o {"porcentaje": "abc"} -> TODOS los retiros
--     fallaban (violación de fee_porcentaje_valido / error de cast).
--   - {"porcentaje": "7.5"} (string) -> la app mostraba 0% al usuario y al
--     admin, pero la solicitud quedaba con 7.5% y el admin veía un neto
--     menor al transferir.
-- Comprobado en una transacción revertida contra la base real.
-- Solo cambia cómo se lee el %; el resto de la función es idéntico a 085.
-- ============================================================

create or replace function public.solicitar_retiro(p_monto numeric)
returns public.solicitudes_retiro
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_usuario_id uuid := auth.uid();
  v_wallet text;
  v_activo boolean;
  v_pendiente numeric;
  v_ya_solicitado numeric;
  v_disponible numeric;
  v_fee numeric;
  v_nueva public.solicitudes_retiro;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado.';
  end if;

  if p_monto is null or p_monto <= 0 or p_monto >= 100000000 then
    raise exception 'Monto invalido.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('solicitar_retiro:' || v_usuario_id::text, 0)
  );

  select wallet_usdt_erc20, activo into v_wallet, v_activo
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  if v_wallet is null or trim(v_wallet) = '' then
    raise exception 'Registra tu wallet USDT (ERC20) en tu perfil antes de solicitar un retiro.';
  end if;

  if exists (
    select 1 from public.solicitudes_retiro
    where usuario_id = v_usuario_id and estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end if;

  select coalesce(sum(monto), 0) into v_pendiente
  from public.ganancias_concursos
  where usuario_id = v_usuario_id and pagado = false;

  select coalesce(sum(monto), 0) into v_ya_solicitado
  from public.solicitudes_retiro
  where usuario_id = v_usuario_id and estado = 'pendiente';

  v_disponible := v_pendiente - v_ya_solicitado;

  if round(p_monto, 2) > v_disponible then
    raise exception 'No puedes retirar mas de lo que tienes disponible.';
  end if;

  -- Misma regla que obtenerFeeRetiro() (src/lib/config-retiros.ts), que es
  -- lo que ve el usuario en el formulario: solo cuenta un NUMERO JSON entre
  -- 0 y 100; cualquier otra cosa = sin fee. Antes se casteaba a ciegas: un
  -- valor fuera de rango o no numerico bloqueaba TODOS los retiros (error de
  -- constraint/cast), y uno guardado como string ("7.5") se cobraba aunque
  -- la app le mostraba al usuario que no habia fee.
  select case
           when jsonb_typeof(valor->'porcentaje') = 'number'
                and (valor->>'porcentaje')::numeric between 0 and 100
           then (valor->>'porcentaje')::numeric
           else 0
         end
  into v_fee
  from public.config_portada
  where clave = 'fee_retiro';

  begin
    insert into public.solicitudes_retiro (usuario_id, monto, wallet_destino, fee_porcentaje)
    values (v_usuario_id, round(p_monto, 2), v_wallet, coalesce(v_fee, 0))
    returning * into v_nueva;
  exception when unique_violation then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end;

  return v_nueva;
end;
$function$;

-- ============================================================
-- === MIGRACION 088 (088_editar_nombre_del_pick_del_dia.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 088: el admin puede editar el nombre del pick del día
-- Pegar en Supabase → SQL Editor → Run (después de 001-087)
--
-- Pedido del dueño del proyecto (2026-10-05): antes, para cambiarle el
-- nombre a un pick ya creado había que eliminarlo y crear uno nuevo —
-- pero migración 083 ya hace eso automáticamente cuando se cierra su
-- última operación, así que "eliminar para renombrar" en realidad
-- bloqueaba a cualquiera que ya hubiera operado (abrir_operacion exige
-- que el pick siga existiendo). Ahora se puede renombrar sin borrar nada.
--
-- Las operaciones ya CERRADAS conservan su nombre histórico tal cual
-- (nunca se reescribe el pasado). Las que siguen ABIERTAS sí se renombran
-- junto con el pick: el formulario de "cerrar todas las operaciones"
-- agrupa por el texto `activo` de cada operación, no por pick_id — sin
-- este renombrado en cascada, cambiar el nombre a mitad del día dejaría
-- dos grupos distintos para cerrar (el nombre viejo y el nuevo) aunque
-- sea la misma señal, obligando al admin a escribir el mismo precio dos
-- veces.
-- ============================================================

create or replace function public.admin_editar_pick_del_dia(
  p_pick_id uuid,
  p_nuevo_activo text
) returns public.pick_del_dia as $$
declare
  v_activo text;
  v_pick public.pick_del_dia;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede editar el pick del día.';
  end if;

  v_activo := upper(trim(coalesce(p_nuevo_activo, '')));
  if v_activo = '' then
    raise exception 'Ingresa el nombre del activo.';
  end if;
  if length(v_activo) > 30 then
    raise exception 'El nombre del activo no puede tener más de 30 caracteres.';
  end if;

  update public.pick_del_dia
  set activo = v_activo
  where id = p_pick_id
  returning * into v_pick;

  if v_pick.id is null then
    raise exception 'Pick no encontrado.';
  end if;

  update public.operaciones_simuladas
  set activo = v_activo
  where pick_id = p_pick_id and estado = 'abierta';

  return v_pick;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_editar_pick_del_dia(uuid, text) from public, anon;
grant execute on function public.admin_editar_pick_del_dia(uuid, text) to authenticated;

-- ============================================================
-- === MIGRACION 089 (089_abrir_operacion_bloquea_pick_contra_renombrado.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 089: abrir_operacion bloquea la fila del pick mientras abre
-- Pegar en Supabase → SQL Editor → Run (después de 001-088)
--
-- Hallazgo de QA (2026-10-05, sobre la migración 088): abrir_operacion
-- leía el nombre del pick SIN bloquear la fila. Si el admin renombraba el
-- pick (admin_editar_pick_del_dia) y confirmaba justo entre esa lectura y
-- el INSERT de la operación, el renombrado en cascada ya había corrido y
-- no veía la operación nueva, que quedaba guardada con el nombre VIEJO.
-- Resultado: el formulario de "cerrar todas las operaciones" (agrupa por
-- texto `activo`) mostraba dos grupos para la misma señal. Reproducido de
-- forma determinista en QA (sesión A estacionada en el lock de saldo,
-- sesión B renombra y confirma → operación con nombre viejo).
--
-- Arreglo: la lectura del pick es ahora `for share`. Un renombrado en
-- curso espera a que termine la apertura (y entonces su cascada SÍ ve la
-- operación nueva), o la apertura espera al renombrado y lee el nombre
-- nuevo (y rechaza el símbolo viejo con "Ese activo no es el pick del día
-- vigente.", igual que antes). Además el lock del saldo se toma ANTES que
-- el del pick, en el mismo orden que admin_cerrar_operacion (saldo → pick),
-- para que las dos funciones no puedan bloquearse mutuamente (deadlock).
--
-- Fuera de esos dos cambios, la función es idéntica a la de la 082.
-- ============================================================

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick_id uuid;
  v_pick_activo text;
  v_horario jsonb;
  v_apertura time;
  v_cierre time;
  v_dias_habiles int[];
  v_abierto_siempre boolean;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  -- Orden de locks: saldo primero, pick después (ver cabecera).
  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  select id, activo into v_pick_id, v_pick_activo
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1
  for share;

  if v_pick_id is null or upper(v_pick_activo) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    v_abierto_siempre := coalesce(v_horario->>'abierto_siempre' = 'true', false);

    if not v_abierto_siempre then
      v_apertura := case
        when v_horario->>'apertura' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'apertura')::time
        else time '09:30'
      end;
      v_cierre := case
        when v_horario->>'cierre' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'cierre')::time
        else time '16:00'
      end;
      v_dias_habiles := coalesce(
        (
          select array_agg(distinct d::int)
          from jsonb_array_elements_text(
            case when jsonb_typeof(v_horario->'dias') = 'array'
              then v_horario->'dias' else '[]'::jsonb end
          ) d
          where d ~ '^[1-7]$'
        ),
        array[1, 2, 3, 4, 5]
      );

      v_hora_ny := (now() at time zone 'America/New_York')::time;
      v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));

      if not (v_dia_semana_ny = any(v_dias_habiles))
         or v_hora_ny < v_apertura
         or v_hora_ny >= v_cierre then
        raise exception 'El mercado está cerrado en este momento.';
      end if;
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Podrás abrir otra cuando el admin cierre la sesión.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and pick_id = v_pick_id
  ) then
    raise exception 'Ya operaste el pick de hoy. Espera a que el admin publique uno nuevo.';
  end if;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado, pick_id
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta', v_pick_id
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 090 (090_acepta_terminos_en_registro.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 090: registra cuándo se aceptaron los Términos y Condiciones
-- Pegar en Supabase → SQL Editor → Run (después de 001-089)
--
-- Pedido del dueño del proyecto (2026-10-07): agregar un checkbox
-- obligatorio de Términos y Condiciones en Registro y Login. El checkbox
-- en sí es un gate de UI (el botón de enviar queda deshabilitado sin
-- marcarlo), pero el momento legal real que hay que dejar constancia es
-- la ACEPTACIÓN AL REGISTRARSE — por eso se guarda un timestamp en
-- usuarios.terminos_aceptados_en, puesto por el propio trigger con
-- now() (no se confía en un timestamp que mande el cliente, que podría
-- tener el reloj mal puesto o ser manipulado).
--
-- El checkbox en Login no crea un nuevo registro de aceptación cada vez
-- (no tiene sentido legal "volver a aceptar" lo mismo en cada sesión) —
-- solo exige tenerlo marcado para poder enviar el formulario, igual que
-- ya se exige con Turnstile.
-- ============================================================

alter table public.usuarios
  add column if not exists terminos_aceptados_en timestamptz;

create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  nombre_inicial text;
  apellido_inicial text;
  telefono_inicial text;
  cedula_inicial text;
  v_nuevo_id_corto int;
  v_acepto_terminos boolean;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref
      and activo = true;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  nombre_inicial := nullif(trim(new.raw_user_meta_data ->> 'nombre'), '');
  apellido_inicial := nullif(trim(new.raw_user_meta_data ->> 'apellido'), '');
  telefono_inicial := nullif(trim(new.raw_user_meta_data ->> 'telefono'), '');
  cedula_inicial := nullif(trim(new.raw_user_meta_data ->> 'cedula'), '');
  v_acepto_terminos := (new.raw_user_meta_data ->> 'acepto_terminos') = 'true';
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (
    id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20,
    id_corto, nombre, apellido, telefono, cedula, terminos_aceptados_en
  )
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    v_nuevo_id_corto, nombre_inicial, apellido_inicial, telefono_inicial, cedula_inicial,
    case when v_acepto_terminos then now() else null end
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 091 (091_total_retiros_solicitados_dashboard.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 091: agrega "Retiros solicitados" al dashboard del admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-090)
--
-- Pedido del dueño del proyecto (2026-10-08): en /perfil (vista de admin),
-- debajo de "Ganancias de hoy sin pagar", agregar cuánto dinero suman las
-- solicitudes de retiro PENDIENTES — para que el admin vea de un vistazo
-- cuánto le han pedido retirar sin tener que entrar a /retiros.
--
-- Se extiende admin_totales_dashboard (migración 078) con una tercera
-- columna, mismo patrón de "security invoker" (el admin ya tiene SELECT
-- sobre solicitudes_retiro vía RLS, migración 041 — no hace falta
-- definer).
-- ============================================================

-- create or replace no permite cambiar las columnas de salida de una
-- función existente ("cannot change return type") — hay que borrarla y
-- volver a crearla.
drop function if exists public.admin_totales_dashboard(timestamptz, timestamptz);

create function public.admin_totales_dashboard(
  p_inicio timestamptz,
  p_fin timestamptz
)
returns table (
  total_cuentas numeric,
  total_a_pagar_hoy numeric,
  total_retiros_solicitados numeric
)
language sql
stable
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
  select
    (select coalesce(sum(sv.saldo_usd), 0)
       from public.saldo_virtual sv
       join public.usuarios u on u.id = sv.usuario_id
      where u.role <> 'admin'),
    (select coalesce(sum(g.monto), 0)
       from public.ganancias_concursos g
       left join public.operaciones_simuladas o on o.id = g.operacion_id
      where g.pagado = false
        and coalesce(o.cerrado_en, g.created_at) >= p_inicio
        and coalesce(o.cerrado_en, g.created_at) < p_fin),
    (select coalesce(sum(sr.monto), 0)
       from public.solicitudes_retiro sr
      where sr.estado = 'pendiente');
$$;

-- ============================================================
-- === MIGRACION 092 (092_restaurar_permisos_admin_totales_dashboard.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 092: restaura los permisos de admin_totales_dashboard
-- Pegar en Supabase → SQL Editor → Run (después de 001-091)
--
-- QA 2026-10-08: la migración 091 hizo DROP FUNCTION + CREATE FUNCTION
-- (necesario para cambiar las columnas de salida). Un DROP borra también
-- los GRANT/REVOKE de la función, y el CREATE nuevo vuelve a los
-- privilegios por defecto de Supabase: EXECUTE para PUBLIC y anon. Eso
-- deshizo en silencio el "revoke ... from public, anon" de la migración
-- 051. Verificado en producción tras la 091:
--   proacl = {=X/postgres, anon=X/postgres, authenticated=X/postgres, ...}
--
-- Impacto real: bajo (la función es security invoker, así que un anónimo
-- o un usuario normal solo obtiene lo que su propia RLS le deja ver — en
-- la práctica ceros o sus propios datos), pero es una regresión del
-- endurecimiento de la 051 y se restaura igual.
-- ============================================================

revoke all on function public.admin_totales_dashboard(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_totales_dashboard(timestamptz, timestamptz)
  to authenticated;

-- ============================================================
-- === MIGRACION 093 (093_auto_respuesta_fuera_de_horario_soporte.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 093: auto-respuesta de "fuera de horario" en el chat de soporte
-- Pegar en Supabase → SQL Editor → Run (después de 001-092)
--
-- Pedido del dueño del proyecto (2026-10-11): cuando un usuario escribe en
-- el chat de soporte FUERA del horario de atención (8:00am-3:00pm hora de
-- Japón, JST/UTC+9), se le responde automáticamente con un aviso fijo —
-- en inglés o español según el idioma activo de la página.
--
-- remitente_id pasa a ser nullable: la auto-respuesta no "la escribe"
-- ningún admin en particular (si se usara el id de un admin real, ESE
-- admin la vería como un mensaje propio ya enviado — ChatBox.tsx decide
-- el lado de la burbuja comparando remitente_id con quien mira la
-- pantalla). NULL se renderiza como "no es mío" para TODOS los que
-- miran la conversación, sin importar quién sea.
--
-- La lógica de horario/idioma vive en la app (src/lib/actions/chat.ts),
-- no en un trigger: el idioma activo es una cookie HTTP, algo que la base
-- de datos no puede leer. La función de abajo solo hace la inserción
-- privilegiada (bypassa el INSERT policy, que exige remitente_id =
-- auth.uid()) después de que la app ya decidió que corresponde mandarla.
-- ============================================================

alter table public.mensajes_soporte
  alter column remitente_id drop not null;

alter table public.mensajes_soporte
  add column if not exists es_auto_respuesta boolean not null default false;

create or replace function public.insertar_auto_respuesta_soporte(
  p_usuario_id uuid,
  p_contenido text
) returns public.mensajes_soporte as $$
declare
  v_mensaje public.mensajes_soporte;
begin
  -- Mismo criterio de permiso que el resto de las RPC de este chat: el
  -- propio usuario (en su conversación) o un admin.
  if auth.uid() is distinct from p_usuario_id and not public.es_admin() then
    raise exception 'No tienes permiso para escribir en esta conversación.';
  end if;

  insert into public.mensajes_soporte (
    usuario_id, remitente_id, contenido, leido_admin, leido_usuario, es_auto_respuesta
  ) values (
    p_usuario_id, null, p_contenido, true, false, true
  )
  returning * into v_mensaje;

  return v_mensaje;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.insertar_auto_respuesta_soporte(uuid, text) from public, anon;
grant execute on function public.insertar_auto_respuesta_soporte(uuid, text) to authenticated;

-- ============================================================
-- === MIGRACION 094 (094_auto_respuesta_no_cuenta_como_sin_leer.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 094: la auto-respuesta de fuera de horario no infla el
-- contador de "sin responder" del admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-093)
--
-- Hallazgo de QA (2026-10-11) sobre la migración 093: el trigger
-- limitar_frecuencia_mensajes_soporte (migración 021) fuerza
-- leido_admin=false en CUALQUIER inserción hecha por una sesión no-admin
-- — incluida la auto-respuesta insertada por insertar_auto_respuesta_
-- soporte() (que corre con la sesión del propio usuario, aunque sea
-- SECURITY DEFINER). Eso pisaba el leido_admin=true que esa función
-- pedía, y listar_conversaciones_soporte() cuenta "sin responder" por
-- leido_admin=false — el aviso automático terminaba inflando el badge
-- del admin como si fuera un mensaje real esperando respuesta.
--
-- Fix: el trigger exime la auto-respuesta de ese forzado, pero SOLO si
-- remitente_id es NULL — no alcanza con mirar es_auto_respuesta sola,
-- porque esa columna no tiene ninguna restricción propia y un usuario
-- podría insertar un mensaje DIRECTO (sin pasar por la RPC) con
-- es_auto_respuesta=true para saltarse el límite de frecuencia. La
-- policy de insert exige remitente_id = auth.uid() (nunca null para una
-- sesión autenticada), así que remitente_id NULL solo lo puede producir
-- la función SECURITY DEFINER — nunca un insert directo del cliente.
-- ============================================================

create or replace function public.limitar_frecuencia_mensajes_soporte()
returns trigger as $$
declare
  v_recientes int;
begin
  new.created_at := now();

  if new.es_auto_respuesta and new.remitente_id is null then
    return new;
  end if;

  -- El admin responde muchas conversaciones seguidas: no se le limita.
  if public.es_admin() then
    return new;
  end if;

  -- Un usuario no puede marcar su propio mensaje como ya leído por el admin.
  new.leido_admin := false;

  select count(*) into v_recientes
  from public.mensajes_soporte
  where remitente_id = new.remitente_id
    and created_at > now() - interval '1 minute';

  if v_recientes >= 10 then
    raise exception 'Estás enviando mensajes demasiado rápido. Espera un momento antes de volver a escribir.';
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 095 (095_auto_respuesta_soporte_texto_fijo_y_dedupe.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 095: auto-respuesta de soporte con texto fijo en la base,
-- deduplicada y serializada
-- Pegar en Supabase → SQL Editor → Run (después de 001-094)
-- IMPORTANTE: aplicar JUNTO con el deploy del cambio en
-- src/lib/actions/chat.ts (la firma de la RPC cambia; con código viejo
-- + esta migración, o código nuevo sin ella, simplemente no se manda el
-- aviso — no rompe el envío del mensaje del usuario).
--
-- Hallazgos de QA (2026-10-11) sobre la 093/094:
--
-- 1) La RPC insertar_auto_respuesta_soporte(p_usuario_id, p_contenido)
--    aceptaba CUALQUIER texto y estaba concedida a `authenticated`. Un
--    usuario podía llamarla directo (supabase.rpc) y meter en su propio
--    chat mensajes con remitente_id NULL — que el chat pinta igual que una
--    respuesta del equipo de soporte — con el texto que quisiera ("tu
--    retiro de $50,000 fue aprobado"), sin límite de frecuencia (el
--    trigger exime remitente_id NULL) y con leido_admin=true (el admin no
--    se entera). Reproducido: 24 inserciones en segundos.
--    Fix: la función ya no recibe el texto — solo el idioma — y el texto
--    vive acá. El usuario sale de auth.uid(), no de un parámetro.
--
-- 2) La deduplicación (en la app) miraba solo el mensaje INMEDIATAMENTE
--    anterior: U1, AUTO, U2 (anterior=AUTO, no repite), U3 (anterior=U2,
--    SÍ repite)... Una ráfaga de 10 mensajes generaba 5 avisos. Además,
--    envíos concurrentes (varias pestañas) se saltaban el chequeo por
--    carrera: 5 envíos simultáneos → 3 avisos.
--    Fix: la decisión se toma acá, bajo un advisory lock por usuario, y
--    mira el último mensaje de la conversación que NO escribió el propio
--    usuario: si es un aviso automático (nadie del equipo contestó
--    después), no se repite.
--
-- 3) proteger_mensajes_soporte() no protegía es_auto_respuesta: un
--    usuario podía cambiarla en sus filas (p. ej. apagarla en el aviso
--    para forzar avisos repetidos). Ahora es inmutable como el resto.
-- ============================================================

drop function if exists public.insertar_auto_respuesta_soporte(uuid, text);

create or replace function public.insertar_auto_respuesta_soporte(
  p_idioma text
) returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_ultimo_es_auto boolean;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if not public.cuenta_activa() then
    return false;
  end if;

  -- Serializa los avisos de ESTE usuario: dos envíos simultáneos no
  -- pueden ver ambos "no hay aviso pendiente" e insertar dos.
  perform pg_advisory_xact_lock(
    hashtextextended('auto_respuesta_soporte:' || v_uid::text, 0)
  );

  select m.es_auto_respuesta into v_ultimo_es_auto
  from public.mensajes_soporte m
  where m.usuario_id = v_uid
    and m.remitente_id is distinct from v_uid
  order by m.created_at desc, m.id desc
  limit 1;

  if coalesce(v_ultimo_es_auto, false) then
    return false;
  end if;

  insert into public.mensajes_soporte (
    usuario_id, remitente_id, contenido, leido_admin, leido_usuario, es_auto_respuesta
  ) values (
    v_uid,
    null,
    case when p_idioma = 'es' then
      E'Horario de atención al cliente\n\n'
      || E'Nuestro equipo de soporte está disponible de 8:00 a.m. a 3:00 p.m. (hora estándar de Japón, JST — UTC+9).\n\n'
      || 'Gracias por tu comprensión. Esperamos poder ayudarte dentro de nuestro horario de atención.'
    else
      E'Customer Support Hours\n\n'
      || E'Our customer support team is available from 8:00 a.m. to 3:00 p.m. (Japan Standard Time, JST — UTC+9).\n\n'
      || 'Thank you for your understanding. We look forward to assisting you during our business hours.'
    end,
    true,
    false,
    true
  );

  return true;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.insertar_auto_respuesta_soporte(text) from public, anon;
grant execute on function public.insertar_auto_respuesta_soporte(text) to authenticated;

create or replace function public.proteger_mensajes_soporte()
returns trigger as $$
begin
  if new.id is distinct from old.id
     or new.usuario_id is distinct from old.usuario_id
     or new.remitente_id is distinct from old.remitente_id
     or new.contenido is distinct from old.contenido
     or new.created_at is distinct from old.created_at
     or new.es_auto_respuesta is distinct from old.es_auto_respuesta then
    raise exception 'Un mensaje de soporte enviado no se puede modificar; solo marcarse como leído.';
  end if;

  -- La imagen solo puede quitarse (cron de limpieza), nunca reemplazarse.
  if new.imagen_path is distinct from old.imagen_path
     and new.imagen_path is not null then
    raise exception 'La imagen de un mensaje enviado no se puede cambiar.';
  end if;

  -- leido_admin es el contador del admin; el usuario no lo toca.
  -- auth.uid() null = cron / SQL directo, se permite.
  if new.leido_admin is distinct from old.leido_admin
     and auth.uid() is not null
     and not public.es_admin() then
    raise exception 'Solo un admin puede marcar mensajes como leídos por soporte.';
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 096 (096_bono_referido_solo_borra_bonos_reales.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 096: la limpieza de bonos de referido que ya no alcanzan su
-- hito solo toca BONOS de verdad (no restos de comisiones), y también
-- corre al BORRAR un depósito pagado, no solo al revertirlo
-- Pegar en Supabase → SQL Editor → Run (después de 001-095)
--
-- Hallazgos del QA pre-producción de Referidos (2026-10-12), ambos
-- reproducidos en vivo contra la base real:
--
-- 1) (Dinero) La migración 079 borraba "bonos sin pagar cuyo hito ya no
--    alcanza" identificándolos como cualquier fila de origen 'referido'
--    con invitado_id NULL, y sacaba el hito con
--    regexp_replace(concepto, '\D', '', 'g') — es decir, TODOS los dígitos
--    del concepto. Pero el resto que deja un retiro parcial sobre una
--    COMISIÓN (migración 072/075) también queda con invitado_id NULL y su
--    concepto es "Referido (10%): correo123@x.com (resto tras retiro)" →
--    dígitos "10123", siempre mayor que el conteo de calificados. Resultado:
--    revertir el depósito de CUALQUIER otro referido del mismo invitador
--    borraba en silencio ese resto de comisión pendiente (dinero que el
--    invitador sí se ganó). Repro: invitador con 21 calificados, retiro de
--    $5 que parte la comisión de $10 de inv-a (resto $5 pendiente),
--    revertir el depósito de inv-u → el pendiente bajó $15 en vez de $10.
--    Además, con un correo con muchos dígitos el número no cabe en int y
--    el cast ::int lanzaba "integer out of range", haciendo fallar la
--    reversión del depósito por completo.
--    Fix: solo se consideran filas cuyo concepto tiene la forma exacta
--    del bono ("Bono por N referidos calificados", opcionalmente con el
--    sufijo " (resto tras retiro)"), y N se extrae de ESA posición.
--
-- 2) (Consistencia con la decisión de la 079) Borrar un depósito YA
--    PAGADO desde Gestión de usuarios (revertir_saldo_al_borrar_deposito,
--    migración 077) borraba la comisión del referido pero dejaba intacto
--    el bono sin pagar aunque el conteo de calificados ya no alcanzara el
--    hito (repro: 20 calificados con bono de 20 → borrar uno → 19
--    calificados y el bono de 20 seguía pendiente). Ahora usa la misma
--    limpieza que la reversión.
--
-- Un bono YA PAGADO nunca se toca (igual que antes).
-- ============================================================

-- ------------------------------------------------------------
-- Helper compartido: borra los bonos de referido SIN PAGAR de un
-- invitador cuyo hito ya no alcanza su conteo actual de calificados.
-- Solo lo llaman los triggers de abajo (security definer); no se expone.
-- ------------------------------------------------------------
create or replace function public.limpiar_bonos_referido_no_alcanzados(p_invitador uuid)
returns void as $$
declare
  v_calificados_count int;
begin
  if p_invitador is null then
    return;
  end if;

  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id and d.pagado = true
  where u.invitado_por = p_invitador;

  delete from public.ganancias_concursos
  where usuario_id = p_invitador
    and origen = 'referido'
    and invitado_id is null
    and pagado = false
    and concepto ~ '^Bono por [0-9]+ referidos calificados( \(resto tras retiro\))*$'
    and substring(concepto from '^Bono por ([0-9]+) ')::numeric > v_calificados_count;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.limpiar_bonos_referido_no_alcanzados(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 1) otorgar_recompensa_referido(): mismo cuerpo que la 079, la rama de
--    reversión ahora usa el helper.
-- ------------------------------------------------------------
create or replace function public.otorgar_recompensa_referido()
returns trigger as $$
declare
  v_invitador uuid;
  v_email_invitado text;
  v_config jsonb;
  v_porcentaje numeric;
  v_bono_cada int;
  v_bono_monto numeric;
  v_comision numeric;
  v_calificados_count int;
  v_concepto_bono text;
begin
  -- Reversión: el admin marcó el depósito de vuelta a pendiente. Si la
  -- comisión de ESTE invitado seguía sin pagar, se borra. Una ya pagada no
  -- se toca.
  if new.pagado = false and old.pagado = true then
    delete from public.ganancias_concursos
    where invitado_id = new.usuario_id
      and origen = 'referido'
      and pagado = false;

    select invitado_por into v_invitador
    from public.usuarios
    where id = new.usuario_id;

    -- Recalcula CON el depósito ya revertido y borra solo bonos (no restos
    -- de comisiones) sin pagar cuyo hito ya no se alcanza — ver 096.
    perform public.limpiar_bonos_referido_no_alcanzados(v_invitador);

    return new;
  end if;

  select invitado_por, email into v_invitador, v_email_invitado
  from public.usuarios
  where id = new.usuario_id;

  if v_invitador is null then
    return new;
  end if;

  select valor into v_config
  from public.config_portada
  where clave = 'premio_referido';

  v_porcentaje := coalesce((v_config ->> 'porcentaje')::numeric, 10);
  v_bono_cada := coalesce((v_config ->> 'bono_cada')::int, 10);
  v_bono_monto := coalesce((v_config ->> 'bono_monto')::numeric, 1000);

  v_comision := round(new.monto * greatest(v_porcentaje, 0) / 100, 2);

  if v_comision > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      v_invitador, v_comision,
      'Referido (' || v_porcentaje || '%): ' || v_email_invitado,
      'referido', new.usuario_id
    )
    on conflict (invitado_id) where invitado_id is not null do update
    set monto = excluded.monto,
        concepto = excluded.concepto
    where public.ganancias_concursos.pagado = false;
  end if;

  -- Solo cuentan como "calificados" los referidos con el depósito
  -- CONFIRMADO.
  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id and d.pagado = true
  where u.invitado_por = v_invitador;

  if v_bono_cada > 0 and v_calificados_count > 0
     and v_calificados_count % v_bono_cada = 0 then
    v_concepto_bono := 'Bono por ' || v_calificados_count || ' referidos calificados';

    if not exists (
      select 1 from public.ganancias_concursos
      where usuario_id = v_invitador
        and origen = 'referido'
        and invitado_id is null
        and concepto = v_concepto_bono
    ) then
      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, origen
      ) values (
        v_invitador, v_bono_monto, v_concepto_bono, 'referido'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ------------------------------------------------------------
-- 2) revertir_saldo_al_borrar_deposito(): mismo cuerpo que la 077, más la
--    limpieza de bonos del invitador (AFTER DELETE: el depósito ya no
--    existe, así que el conteo ya lo excluye).
-- ------------------------------------------------------------
create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
declare
  v_invitador uuid;
begin
  if old.pagado then
    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;

    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;

    select invitado_por into v_invitador
    from public.usuarios
    where id = old.usuario_id;

    perform public.limpiar_bonos_referido_no_alcanzados(v_invitador);

    -- Con una sola operación abierta por usuario y esa operación usando
    -- siempre el saldo COMPLETO (migración 032), si hay una abierta es
    -- porque el dinero de este depósito (u otro) está atrapado ahí. El
    -- depósito que se está borrando ya no existe, así que ese dinero
    -- tampoco -- se anula la operación sin devolver nada.
    update public.operaciones_simuladas
    set estado = 'cancelada', cerrado_en = now(),
        precio_salida = null, ganancia_perdida = 0
    where usuario_id = old.usuario_id and estado = 'abierta';
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 097 (097_revertir_deposito_cancela_operacion_abierta.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 097: revertir un depósito pagado a pendiente cancela la
-- operación abierta que ese depósito financiaba
-- Pegar en Supabase → SQL Editor → Run (después de 001-096 — usa el
-- helper limpiar_bonos_referido_no_alcanzados() que crea la 096)
-- IMPORTANTE: desplegar junto con el cambio de BotonPagoDeposito.tsx y
-- /depositos/page.tsx (el aviso al admin ahora dice que la operación se
-- cancela; sin esta migración eso no pasaría).
--
-- Hallazgo de QA pre-producción del módulo de Depósitos (2026-10-12),
-- reproducido contra la base real con cuentas descartables:
--   1) Admin marca pagado un depósito de $300 → saldo = 300.
--   2) El usuario abre la operación del día → abrir_operacion pone
--      monto_usado = 300 y saldo = 0 (usa el saldo COMPLETO).
--   3) Admin revierte el depósito a pendiente → saldo = greatest(0, 0 -
--      300) = 0, pero la operación seguía ABIERTA con los 300 adentro.
--   4) Admin cierra la operación → admin_cerrar_operacion devuelve
--      monto_usado al saldo → saldo = 300 con el depósito PENDIENTE.
--   5) Admin lo vuelve a marcar pagado → saldo = 600: el mismo depósito
--      acreditado dos veces.
-- Borrar el depósito ya pagado (trigger de la 077/096) sí cancelaba la
-- operación; revertirlo a pendiente no — misma situación, distinta regla.
--
-- Fix (las dos rutas quedan con la MISMA regla):
--   - Fondos reales del usuario = saldo + monto_usado de su operación
--     abierta (solo puede haber una, y usa el saldo completo).
--   - Se cancela la operación abierta (estado 'cancelada', igual que la
--     077: anulación administrativa, no resultado de trading).
--   - Saldo nuevo = greatest(0, fondos - monto del depósito). En el caso
--     normal (todo el saldo venía de este depósito) queda en 0 igual que
--     antes; si había fondos extra (ej. saldo agregado a mano por el admin
--     antes de operar) ya no se pierden junto con la operación cancelada
--     — antes, borrar el depósito en ese caso dejaba el saldo en 0.
--   - En la RPC se bloquea la fila de saldo ANTES de buscar la operación
--     abierta (mismo orden que abrir_operacion: saldo primero). Sin eso,
--     una reversión simultánea a una apertura podía leer "sin operación
--     abierta" y dejar el mismo hueco de arriba.
-- ============================================================

create or replace function public.admin_alternar_pago_deposito(
  p_deposito_id uuid,
  p_pagado boolean default null
)
returns public.depositos_simulados
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_admin_id uuid := auth.uid();
  v_deposito public.depositos_simulados;
  v_nuevo_estado boolean;
  v_monto_operacion numeric;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un deposito como pagado.';
  end if;

  select * into v_deposito
  from public.depositos_simulados
  where id = p_deposito_id
  for update;

  if v_deposito.id is null then
    raise exception 'Deposito no encontrado.';
  end if;

  v_nuevo_estado := coalesce(p_pagado, not v_deposito.pagado);

  if v_nuevo_estado = v_deposito.pagado then
    if v_deposito.pagado then
      raise exception 'Este depósito ya estaba marcado como pagado (otro admin u otra pestaña se adelantó). No se acreditó nada de nuevo.';
    else
      raise exception 'Este depósito ya estaba pendiente (otro admin u otra pestaña se adelantó). No se restó nada.';
    end if;
  end if;

  -- Saldo primero (mismo orden de locks que abrir_operacion).
  perform 1
  from public.saldo_virtual
  where usuario_id = v_deposito.usuario_id
  for update;

  if not found then
    raise exception 'El usuario no tiene cuenta de inversión (saldo_virtual); no se marcó el depósito.';
  end if;

  if v_nuevo_estado then
    update public.depositos_simulados
    set pagado = true, pagado_en = now(), pagado_por = v_admin_id
    where id = p_deposito_id
    returning * into v_deposito;

    update public.saldo_virtual
    set saldo_usd = saldo_usd + v_deposito.monto,
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  else
    update public.depositos_simulados
    set pagado = false, pagado_en = null, pagado_por = null
    where id = p_deposito_id
    returning * into v_deposito;

    -- sum() en vez de "returning ... into": si por cualquier motivo
    -- hubiera más de una abierta, se cancelan todas y no revienta.
    with canceladas as (
      update public.operaciones_simuladas
      set estado = 'cancelada', cerrado_en = now(),
          precio_salida = null, ganancia_perdida = 0
      where usuario_id = v_deposito.usuario_id and estado = 'abierta'
      returning monto_usado
    )
    select coalesce(sum(monto_usado), 0) into v_monto_operacion
    from canceladas;

    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd + v_monto_operacion - v_deposito.monto),
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  end if;

  return v_deposito;
end;
$$;

revoke all on function public.admin_alternar_pago_deposito(uuid, boolean) from public, anon;
grant execute on function public.admin_alternar_pago_deposito(uuid, boolean) to authenticated;

-- Borrar un depósito ya pagado: mismo cuerpo que la 096 (incluida la
-- limpieza de bonos), pero con la misma regla de saldo/operación que la
-- reversión de arriba.
create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_invitador uuid;
  v_monto_operacion numeric;
begin
  if old.pagado then
    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;

    select invitado_por into v_invitador
    from public.usuarios
    where id = old.usuario_id;

    perform public.limpiar_bonos_referido_no_alcanzados(v_invitador);

    -- Con una sola operación abierta por usuario y esa operación usando
    -- siempre el saldo COMPLETO (migración 032), si hay una abierta es
    -- porque el dinero de este depósito (u otro) está atrapado ahí. Se
    -- anula la operación y solo se devuelve lo que exceda el depósito
    -- borrado (normalmente nada).
    with canceladas as (
      update public.operaciones_simuladas
      set estado = 'cancelada', cerrado_en = now(),
          precio_salida = null, ganancia_perdida = 0
      where usuario_id = old.usuario_id and estado = 'abierta'
      returning monto_usado
    )
    select coalesce(sum(monto_usado), 0) into v_monto_operacion
    from canceladas;

    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd + v_monto_operacion - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;
  end if;

  return old;
end;
$$;

-- ============================================================
-- === MIGRACION 098 (098_cancelada_no_bloquea_reoperar_pick.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 098: una operación CANCELADA administrativamente no bloquea
-- volver a operar el mismo pick
-- Pegar en Supabase → SQL Editor → Run (después de 001-097)
--
-- Pedido del dueño del proyecto (2026-10-12), tras QA pre-producción de
-- Trade del día: el bloqueo "ya operaste el pick de hoy" (migración 082)
-- cuenta CUALQUIER fila con ese pick_id, sin importar el estado. Pero una
-- operación 'cancelada' (migración 077/097: cuenta desactivada, o
-- depósito pagado revertido/borrado) es una anulación administrativa, no
-- algo que el usuario eligió — nunca llegó a operar esa señal de verdad
-- con su dinero. Bloquearlo de reintentar el mismo pick tras reactivarse
-- (o volver a confirmar su depósito) era injusto.
--
-- Fix: el chequeo ahora excluye 'cancelada' — solo 'abierta'/'cerrada'
-- cuentan como "ya operaste este pick". Fuera de esa línea, la función es
-- idéntica a la de la 089.
-- ============================================================

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick_id uuid;
  v_pick_activo text;
  v_horario jsonb;
  v_apertura time;
  v_cierre time;
  v_dias_habiles int[];
  v_abierto_siempre boolean;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  -- Orden de locks: saldo primero, pick después (ver migración 089).
  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  select id, activo into v_pick_id, v_pick_activo
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1
  for share;

  if v_pick_id is null or upper(v_pick_activo) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    v_abierto_siempre := coalesce(v_horario->>'abierto_siempre' = 'true', false);

    if not v_abierto_siempre then
      v_apertura := case
        when v_horario->>'apertura' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'apertura')::time
        else time '09:30'
      end;
      v_cierre := case
        when v_horario->>'cierre' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          then (v_horario->>'cierre')::time
        else time '16:00'
      end;
      v_dias_habiles := coalesce(
        (
          select array_agg(distinct d::int)
          from jsonb_array_elements_text(
            case when jsonb_typeof(v_horario->'dias') = 'array'
              then v_horario->'dias' else '[]'::jsonb end
          ) d
          where d ~ '^[1-7]$'
        ),
        array[1, 2, 3, 4, 5]
      );

      v_hora_ny := (now() at time zone 'America/New_York')::time;
      v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));

      if not (v_dia_semana_ny = any(v_dias_habiles))
         or v_hora_ny < v_apertura
         or v_hora_ny >= v_cierre then
        raise exception 'El mercado está cerrado en este momento.';
      end if;
    end if;
  end if;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Podrás abrir otra cuando el admin cierre la sesión.';
  end if;

  -- El núcleo del cambio: 'cancelada' ya no cuenta como "ya operaste este
  -- pick" — fue una anulación administrativa, no una operación real.
  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and pick_id = v_pick_id and estado <> 'cancelada'
  ) then
    raise exception 'Ya operaste el pick de hoy. Espera a que el admin publique uno nuevo.';
  end if;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado, pick_id
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta', v_pick_id
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 099 (099_deposito_valida_wallet_y_comprobante_en_la_base.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 099: la wallet "mostrada" y el comprobante de un depósito se
-- validan en la BASE, no solo en la Server Action
-- Pegar en Supabase → SQL Editor → Run (después de 001-098)
--
-- Hallazgo de QA (2026-10-12) sobre el commit d6dfa0c: el fix de
-- registrarDepositoSimulado() (solo guardar wallet_mostrada si coincide con
-- obtener_wallets_admin()) se podía saltar por completo insertando DIRECTO
-- en depositos_simulados vía PostgREST con la anon key + el JWT del propio
-- usuario: la policy "usuario registra su propia simulacion" (057) no mira
-- wallet_mostrada para nada. Reproducido contra la base real con una cuenta
-- descartable:
--   insert into depositos_simulados (usuario_id, monto, wallet_mostrada,
--     comprobante_path) values (auth.uid(), 5, '0xINVENTADA...',
--     '<uid>/<uuid cualquiera>.png')
--   → aceptado, con la wallet inventada guardada tal cual.
-- El mismo insert también demostró que el comprobante "obligatorio" (054)
-- se puede saltar: el check de formato (057) solo valida el TEXTO del path,
-- no que la imagen exista en el bucket — un path con un UUID inventado
-- pasa, y el admin recibe un depósito sin ninguna imagen detrás.
--
-- Fix (trigger BEFORE INSERT, aplica a cualquier camino de inserción):
--   - wallet_mostrada que no esté entre las wallets de depósito
--     configuradas AHORA (obtener_wallets_admin) → se guarda null. Misma
--     regla que la Server Action: es un campo informativo, no se rechaza
--     el depósito por esto.
--   - comprobante_path que no exista como objeto en el bucket
--     comprobantes-soporte → se rechaza el insert. La Server Action sube la
--     imagen ANTES de insertar, así que el flujo normal nunca choca con
--     esto (y si chocara, su rama de error ya limpia la imagen huérfana).
-- ============================================================

create or replace function public.validar_deposito_simulado_al_insertar()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.wallet_mostrada is not null
     and not (new.wallet_mostrada = any(public.obtener_wallets_admin())) then
    new.wallet_mostrada := null;
  end if;

  if new.comprobante_path is not null
     and not exists (
       select 1 from storage.objects
       where bucket_id = 'comprobantes-soporte'
         and name = new.comprobante_path
     ) then
    raise exception 'El comprobante del depósito no existe. Vuelve a adjuntar la imagen.';
  end if;

  return new;
end;
$$;

revoke all on function public.validar_deposito_simulado_al_insertar() from public, anon, authenticated;

drop trigger if exists antes_de_insertar_deposito_simulado on public.depositos_simulados;
create trigger antes_de_insertar_deposito_simulado
  before insert on public.depositos_simulados
  for each row execute function public.validar_deposito_simulado_al_insertar();

-- ============================================================
-- === MIGRACION 100 (100_horario_soporte_630_a_1100.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 100: nuevo horario de atención del chat de soporte,
-- 6:30am-11:00am JST (antes 8:00am-3:00pm)
-- Pegar en Supabase → SQL Editor → Run (después de 001-099)
-- IMPORTANTE: desplegar junto con el cambio de
-- src/lib/actions/chat.ts (fueraDeHorarioSoporte ahora compara en
-- minutos, no solo en horas enteras, porque 6:30 no es una hora
-- redonda).
--
-- Pedido del dueño del proyecto (2026-10-12): mismo texto fijo de la
-- migración 095, solo cambia el horario mencionado.
-- ============================================================

create or replace function public.insertar_auto_respuesta_soporte(
  p_idioma text
) returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_ultimo_es_auto boolean;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if not public.cuenta_activa() then
    return false;
  end if;

  -- Serializa los avisos de ESTE usuario: dos envíos simultáneos no
  -- pueden ver ambos "no hay aviso pendiente" e insertar dos.
  perform pg_advisory_xact_lock(
    hashtextextended('auto_respuesta_soporte:' || v_uid::text, 0)
  );

  select m.es_auto_respuesta into v_ultimo_es_auto
  from public.mensajes_soporte m
  where m.usuario_id = v_uid
    and m.remitente_id is distinct from v_uid
  order by m.created_at desc, m.id desc
  limit 1;

  if coalesce(v_ultimo_es_auto, false) then
    return false;
  end if;

  insert into public.mensajes_soporte (
    usuario_id, remitente_id, contenido, leido_admin, leido_usuario, es_auto_respuesta
  ) values (
    v_uid,
    null,
    case when p_idioma = 'es' then
      E'Horario de atención al cliente\n\n'
      || E'Nuestro equipo de soporte está disponible de 6:30 a.m. a 11:00 a.m. (hora estándar de Japón, JST — UTC+9).\n\n'
      || 'Gracias por tu comprensión. Esperamos poder ayudarte dentro de nuestro horario de atención.'
    else
      E'Customer Support Hours\n\n'
      || E'Our customer support team is available from 6:30 a.m. to 11:00 a.m. (Japan Standard Time, JST — UTC+9).\n\n'
      || 'Thank you for your understanding. We look forward to assisting you during our business hours.'
    end,
    true,
    false,
    true
  );

  return true;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 101 (101_minimos_deposito_y_retiro.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 101: mínimo de depósito (500 USDT) y de retiro (35 USDT)
-- Pegar en Supabase → SQL Editor → Run (después de 001-100)
--
-- Pedido del dueño del proyecto (2026-10-12). Doble capa, igual que el
-- resto de reglas de dinero del proyecto: el cliente (BotonDepositarSimulado
-- / BotonSolicitarRetiro) ya valida esto para dar un mensaje inmediato, pero
-- la única fuente de verdad real es la base -- un insert directo vía
-- PostgREST con la anon key no pasa por el cliente.
--
-- El check de depósito se agrega NOT VALID a propósito: hay depósitos
-- históricos (de prueba y reales) por debajo de 500 USDT, de antes de que
-- existiera esta regla de negocio. NOT VALID aplica el check a partir de
-- ahora (cualquier INSERT/UPDATE nuevo) sin validar ni tocar las filas
-- viejas -- no se borra ni se modifica ningún depósito existente.
-- ============================================================

alter table public.depositos_simulados
  add constraint depositos_simulados_monto_minimo_check
  check (monto >= 500) not valid;

-- solicitar_retiro: idéntica a la migración 086, solo se agrega el piso de
-- 35 USDT. El mensaje usa la palabra "mínimo" (con tilde) a propósito: es
-- el texto que el cliente matchea (BotonSolicitarRetiro.tsx) para mostrar
-- la traducción correcta -- ninguna otra excepción de esta función la usa.
create or replace function public.solicitar_retiro(p_monto numeric)
returns public.solicitudes_retiro
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_usuario_id uuid := auth.uid();
  v_wallet text;
  v_activo boolean;
  v_pendiente numeric;
  v_ya_solicitado numeric;
  v_disponible numeric;
  v_fee numeric;
  v_nueva public.solicitudes_retiro;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado.';
  end if;

  if p_monto is null or p_monto <= 0 or p_monto >= 100000000 then
    raise exception 'Monto invalido.';
  end if;

  if p_monto < 35 then
    raise exception 'El monto mínimo de retiro es 35 USDT.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('solicitar_retiro:' || v_usuario_id::text, 0)
  );

  select wallet_usdt_erc20, activo into v_wallet, v_activo
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  if v_wallet is null or trim(v_wallet) = '' then
    raise exception 'Registra tu wallet USDT (ERC20) en tu perfil antes de solicitar un retiro.';
  end if;

  if exists (
    select 1 from public.solicitudes_retiro
    where usuario_id = v_usuario_id and estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end if;

  select coalesce(sum(monto), 0) into v_pendiente
  from public.ganancias_concursos
  where usuario_id = v_usuario_id and pagado = false;

  select coalesce(sum(monto), 0) into v_ya_solicitado
  from public.solicitudes_retiro
  where usuario_id = v_usuario_id and estado = 'pendiente';

  v_disponible := v_pendiente - v_ya_solicitado;

  if round(p_monto, 2) > v_disponible then
    raise exception 'No puedes retirar mas de lo que tienes disponible.';
  end if;

  select case
           when jsonb_typeof(valor->'porcentaje') = 'number'
                and (valor->>'porcentaje')::numeric between 0 and 100
           then (valor->>'porcentaje')::numeric
           else 0
         end
  into v_fee
  from public.config_portada
  where clave = 'fee_retiro';

  begin
    insert into public.solicitudes_retiro (usuario_id, monto, wallet_destino, fee_porcentaje)
    values (v_usuario_id, round(p_monto, 2), v_wallet, coalesce(v_fee, 0))
    returning * into v_nueva;
  exception when unique_violation then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end;

  return v_nueva;
end;
$function$;

-- ============================================================
-- === MIGRACION 102 (102_minimo_deposito_como_trigger.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 102: el mínimo de depósito pasa de CHECK a trigger BEFORE INSERT
-- Pegar en Supabase → SQL Editor → Run (después de 001-101)
--
-- QA con Opus (2026-10-12) sobre la migración 101: un `check (...) not
-- valid` no deja de aplicarse a las filas viejas -- NOT VALID solo evita el
-- escaneo de validación inicial al crear el constraint, pero CUALQUIER
-- UPDATE posterior sobre una fila vieja (aunque no toque la columna monto)
-- se revalida igual. Reproducido en una transacción revertida: un
-- `update ... set pagado = true` sobre una fila con monto < 500 fallaba con
-- "violates check constraint". Hoy no hay ninguna fila así en
-- depositos_simulados, así que no rompió nada en producción, pero
-- admin_alternar_pago_deposito y el UPDATE masivo de marcarDepositosRevisados
-- habrían quedado rotos (el segundo en silencio, sin tirar error) apenas
-- existiera una.
--
-- La intención real siempre fue "los depósitos NUEVOS tienen que ser de al
-- menos 500", no "toda fila de esta tabla, para siempre, incluso al
-- actualizar otra columna". Un trigger BEFORE INSERT (mismo patrón que la
-- migración 099 para wallet/comprobante) sí refleja eso: solo se evalúa al
-- crear la fila, nunca en un UPDATE.
-- ============================================================

alter table public.depositos_simulados
  drop constraint depositos_simulados_monto_minimo_check;

create or replace function public.validar_monto_minimo_deposito()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.monto < 500 then
    raise exception 'El depósito mínimo es 500 USDT.';
  end if;
  return new;
end;
$$;

drop trigger if exists antes_de_insertar_deposito_monto_minimo on public.depositos_simulados;
create trigger antes_de_insertar_deposito_monto_minimo
  before insert on public.depositos_simulados
  for each row execute function public.validar_monto_minimo_deposito();

-- ============================================================
-- === MIGRACION 103 (103_qa_totales_y_retiro_parcial_referido.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 103: 2 bugs reales de la QA con Opus (2026-10-12)
-- Pegar en Supabase → SQL Editor → Run (después de 001-102)
-- ============================================================

-- ----------------------------------------------------------------
-- BUG 1: "Total en cuentas de inversión (todos los usuarios)" del
-- dashboard del admin solo sumaba saldo_virtual -- el dinero que un
-- usuario tiene metido en una operación abierta (monto_usado) no se
-- contaba, así que el total bajaba cada vez que alguien operaba y
-- volvía a subir al cerrar. Medido en vivo: $23,000 mostrados vs
-- $25,800 reales (faltaban $2,800 en 3 operaciones abiertas).
--
-- create or replace, mismas columnas de salida que la 091 -> no hace
-- falta DROP, los GRANT/REVOKE de la 092 quedan intactos.
-- ----------------------------------------------------------------
create or replace function public.admin_totales_dashboard(
  p_inicio timestamptz,
  p_fin timestamptz
)
returns table (
  total_cuentas numeric,
  total_a_pagar_hoy numeric,
  total_retiros_solicitados numeric
)
language sql
stable
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
  select
    (select coalesce(sum(sv.saldo_usd), 0)
       from public.saldo_virtual sv
       join public.usuarios u on u.id = sv.usuario_id
      where u.role <> 'admin')
    +
    (select coalesce(sum(o.monto_usado), 0)
       from public.operaciones_simuladas o
       join public.usuarios u on u.id = o.usuario_id
      where u.role <> 'admin' and o.estado = 'abierta'),
    (select coalesce(sum(g.monto), 0)
       from public.ganancias_concursos g
       left join public.operaciones_simuladas o on o.id = g.operacion_id
      where g.pagado = false
        and coalesce(o.cerrado_en, g.created_at) >= p_inicio
        and coalesce(o.cerrado_en, g.created_at) < p_fin),
    (select coalesce(sum(sr.monto), 0)
       from public.solicitudes_retiro sr
      where sr.estado = 'pendiente');
$$;

-- ----------------------------------------------------------------
-- BUG 3: cuando un retiro paga solo PARTE de una comisión de referido
-- (admin_marcar_retiro_pagado, migración 072), la fila ORIGINAL (que
-- conserva invitado_id) se reducía al monto YA PAGADO, y el RESTO
-- pendiente se insertaba en una fila nueva SIN invitado_id -- a
-- propósito, según el comentario de la 072, porque el índice único
-- parcial ganancias_concursos_invitado_unico no permite dos filas con
-- el mismo invitado_id.
--
-- Eso dejaba el resto pendiente "huérfano": en /referidos aparecía
-- como un bono suelto en vez de la comisión del invitado, y
-- revertir_saldo_al_borrar_deposito / otorgar_recompensa_referido (que
-- filtran por invitado_id) ya no lo encontraban -- si después se
-- revertía el depósito de ese invitado, el resto pendiente NO se
-- borraba, y el invitador se quedaba con comisión de un depósito ya
-- revertido.
--
-- Arreglo: se invierte qué fila se queda con invitado_id. La fila
-- ORIGINAL (con su invitado_id intacto) pasa a quedarse con el RESTO
-- pendiente (solo se le baja el monto). Se inserta una fila NUEVA, ya
-- pagada, por la parte que sí se cubrió -- sin invitado_id, porque una
-- vez pagada no necesita seguir enganchada al invitado: ni
-- revertir_saldo_al_borrar_deposito ni otorgar_recompensa_referido
-- tocan nunca una fila con pagado = true. Así el índice único sigue
-- respetado, y lo que de verdad importa rastrear (lo pendiente) queda
-- donde la lógica de referidos lo busca.
-- ----------------------------------------------------------------
create or replace function public.admin_marcar_retiro_pagado(p_solicitud_id uuid)
returns public.solicitudes_retiro as $$
declare
  v_admin_id uuid := auth.uid();
  v_solicitud public.solicitudes_retiro;
  v_restante numeric;
  r_ganancia record;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un retiro como pagado.';
  end if;

  update public.solicitudes_retiro
  set estado = 'pagado', procesado_en = now(), procesado_por = v_admin_id
  where id = p_solicitud_id and estado = 'pendiente'
  returning * into v_solicitud;

  if v_solicitud.id is null then
    raise exception 'Esta solicitud ya fue procesada.';
  end if;

  v_restante := v_solicitud.monto;
  for r_ganancia in
    select *
    from public.ganancias_concursos
    where usuario_id = v_solicitud.usuario_id and pagado = false
    order by created_at, id
    for update
  loop
    exit when v_restante <= 0;

    if r_ganancia.monto <= v_restante then
      update public.ganancias_concursos
      set pagado = true, pagado_en = now(), pagado_por = v_admin_id
      where id = r_ganancia.id;
      v_restante := v_restante - r_ganancia.monto;
    else
      -- Pago parcial: la parte pagada va a una fila NUEVA (sin
      -- invitado_id), la fila original se queda con el resto pendiente
      -- (y conserva su invitado_id, si tenía).
      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, creado_por, created_at, pagado,
        pagado_en, pagado_por, origen, operacion_id
      ) values (
        r_ganancia.usuario_id, v_restante, r_ganancia.concepto, r_ganancia.creado_por,
        r_ganancia.created_at, true, now(), v_admin_id, r_ganancia.origen, r_ganancia.operacion_id
      );

      update public.ganancias_concursos
      set monto = r_ganancia.monto - v_restante
      where id = r_ganancia.id;

      v_restante := 0;
    end if;
  end loop;

  if v_restante > 0 then
    raise exception 'No hay suficientes ganancias pendientes para cubrir este retiro (faltan %). Puede que otro pago ya haya usado ese dinero — revisa las ganancias pendientes del usuario antes de reintentar.', v_restante;
  end if;

  return v_solicitud;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ============================================================
-- === MIGRACION 104 (104_datos_contacto_obligatorios_en_la_base.sql) ===
-- ============================================================

-- ============================================================
-- MIGRACIÓN 104: nombre/apellido/cédula/teléfono obligatorios TAMBIÉN
-- en la base, no solo en el formulario
-- Pegar en Supabase → SQL Editor → Run (después de 001-103)
--
-- QA con Opus (2026-10-13) sobre la migración de ayer (DatosContactoForm
-- ahora exige los 4 campos): confirmó que es un hueco real -- un usuario
-- autenticado puede llamar
-- `supabase.from("usuarios").update({ nombre: null, ... })` directo con
-- su propio JWT (sin pasar por el formulario) y la base lo acepta sin
-- problema. También se podía guardar "   " (solo espacios), o un
-- teléfono tipo "abc" que no respeta el formato.
--
-- Trigger BEFORE UPDATE (mismo patrón que la migración 099 para
-- wallet/comprobante de depósito): solo se dispara cuando alguno de
-- estos 4 campos CAMBIA en el UPDATE (comparación IS DISTINCT FROM) --
-- así no afecta ningún otro update de la fila (rol, saldo, activo,
-- wallet...) ni rompe cuentas viejas/de prueba que ya tenían estos
-- campos en null y nadie los está tocando. En cuanto alguien intenta
-- cambiar cualquiera de los 4, exige que los 4 queden completos y bien
-- formados en la fila resultante -- igual que ya hace el formulario,
-- que siempre manda los 4 juntos.
--
-- A propósito NO se toca el INSERT de handle_new_user(): esa función
-- también la usan las cuentas creadas por fuera del formulario público
-- (Admin API con el service_role, el mecanismo que se usó para crear
-- todas las cuentas de prueba de este proyecto, incluida admin-tester) y
-- exigir estos campos ahí rompería ese flujo. El registro público
-- (RegistroForm.tsx) ya los exige del lado del cliente; este trigger
-- cierra el hueco de EDITAR, que es lo que encontró la QA.
-- ============================================================

create or replace function public.validar_datos_contacto_usuario()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.nombre is not distinct from old.nombre
     and new.apellido is not distinct from old.apellido
     and new.cedula is not distinct from old.cedula
     and new.telefono is not distinct from old.telefono then
    return new;
  end if;

  if new.nombre is null or trim(new.nombre) = '' then
    raise exception 'Ingresa tu nombre.';
  end if;
  if new.apellido is null or trim(new.apellido) = '' then
    raise exception 'Ingresa tu apellido.';
  end if;
  if new.cedula is null or new.cedula !~ '^[0-9]{3}-[0-9]{7}-[0-9]$' then
    raise exception 'La cédula debe tener el formato 001-1234567-8.';
  end if;
  if new.telefono is null or trim(new.telefono) = ''
     or new.telefono !~ '^[0-9+\-\s()]{6,30}$' then
    raise exception 'Ese teléfono no parece válido.';
  end if;

  return new;
end;
$$;

drop trigger if exists antes_de_actualizar_datos_contacto on public.usuarios;
create trigger antes_de_actualizar_datos_contacto
  before update on public.usuarios
  for each row execute function public.validar_datos_contacto_usuario();
