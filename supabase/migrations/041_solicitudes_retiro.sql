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
