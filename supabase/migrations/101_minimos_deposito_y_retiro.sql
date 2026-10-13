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
