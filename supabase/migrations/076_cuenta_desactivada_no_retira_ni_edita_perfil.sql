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
