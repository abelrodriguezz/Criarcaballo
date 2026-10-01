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
