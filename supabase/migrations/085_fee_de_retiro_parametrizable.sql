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
