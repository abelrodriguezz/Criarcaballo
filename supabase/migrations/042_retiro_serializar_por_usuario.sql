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
