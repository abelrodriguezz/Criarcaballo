-- ============================================================
-- MIGRACIÓN 105: 3 bugs ALTA + 3 MEDIA/BAJA de la revisión de cobertura
-- con Opus (2026-10-17)
-- Pegar en Supabase → SQL Editor → Run (después de 001-104)
-- ============================================================

-- ----------------------------------------------------------------
-- ALTA 1: un admin NO principal podía cambiar la/s wallet(s), el email,
-- el nombre, etc. del admin PRINCIPAL -- proteger_columnas_sensibles_
-- usuarios solo protegía role/activo/trading_habilitado de esa cuenta.
-- Como la wallet del principal es (hoy) la única wallet de depósito real
-- en varios casos, esto dejaba abierto redirigir todos los depósitos a
-- una wallet ajena. Se extiende la protección del principal a TODA
-- columna sensible, no solo esas 3.
--
-- De paso (BAJA 7): se agrega terminos_aceptados_en a la lista de
-- columnas de identidad que ningún usuario (ni admin no-principal sobre
-- sí mismo tendría sentido) puede tocar desde la app -- es evidencia
-- legal, hoy el propio usuario la podía poner en null o cambiarle la
-- fecha.
--
-- De paso (BAJA 6): el chequeo "solo un admin puede tener 2+ wallets"
-- ahora solo se dispara si wallet_2/3 están CAMBIANDO a un valor nuevo
-- (no solo por existir ya en la fila) -- antes, un admin degradado a
-- user con esas columnas ya pobladas de antes quedaba trabado sin poder
-- guardar ningún otro cambio de su perfil (ej. el teléfono), porque la
-- condición vieja miraba el valor actual, no si se estaba modificando.
-- ----------------------------------------------------------------
create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_es_admin boolean := public.es_admin();
begin
  if new.es_principal is distinct from old.es_principal then
    raise exception 'Ese campo no se puede modificar desde la aplicación.';
  end if;

  if new.invitado_por is distinct from old.invitado_por then
    raise exception 'La relación de quién invitó a quién no se puede modificar.';
  end if;

  if old.activo = false
     and auth.uid() = old.id
     and not v_es_admin
  then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  -- Un admin marcado como principal solo se puede modificar a sí mismo:
  -- ningún otro admin puede tocar NADA sensible de esa cuenta -- antes
  -- esto solo cubría role/activo/trading_habilitado, dejando la(s)
  -- wallet(s), el email, el nombre, etc. sin protección.
  if old.es_principal
     and auth.uid() is distinct from old.id
     and (new.role is distinct from old.role
          or new.activo is distinct from old.activo
          or new.trading_habilitado is distinct from old.trading_habilitado
          or new.wallet_usdt_erc20 is distinct from old.wallet_usdt_erc20
          or new.wallet_usdt_erc20_2 is distinct from old.wallet_usdt_erc20_2
          or new.wallet_usdt_erc20_3 is distinct from old.wallet_usdt_erc20_3
          or new.email is distinct from old.email
          or new.nombre is distinct from old.nombre
          or new.apellido is distinct from old.apellido
          or new.cedula is distinct from old.cedula
          or new.telefono is distinct from old.telefono)
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
      or new.created_at is distinct from old.created_at
      or new.terminos_aceptados_en is distinct from old.terminos_aceptados_en)
     and not v_es_admin then
    raise exception 'No puedes modificar los datos de identidad de tu cuenta. Contacta a soporte.';
  end if;

  if ((new.wallet_usdt_erc20_2 is distinct from old.wallet_usdt_erc20_2
       and new.wallet_usdt_erc20_2 is not null)
      or (new.wallet_usdt_erc20_3 is distinct from old.wallet_usdt_erc20_3
          and new.wallet_usdt_erc20_3 is not null))
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

-- ----------------------------------------------------------------
-- ALTA 2: una cuenta desactivada podía seguir registrando un depósito
-- (la política de INSERT y la de storage no miraban cuenta_activa(), a
-- diferencia de favoritos/mensajes que sí la tenían).
-- ----------------------------------------------------------------
drop policy if exists "usuario registra su propia simulacion" on public.depositos_simulados;
create policy "usuario registra su propia simulacion"
  on public.depositos_simulados for insert
  with check (
    usuario_id = auth.uid()
    and public.cuenta_activa()
    and not public.es_admin()
    and pagado = false
    and pagado_en is null
    and pagado_por is null
    and revisado_por_admin = false
    and comprobante_path is not null
    and comprobante_path like (auth.uid()::text || '/%')
  );

drop policy if exists "sube comprobante a su conversacion, admin a cualquiera" on storage.objects;
create policy "sube comprobante a su conversacion, admin a cualquiera"
  on storage.objects for insert
  with check (
    bucket_id = 'comprobantes-soporte'
    and (
      ((storage.foldername(name))[1] = auth.uid()::text and public.cuenta_activa())
      or public.es_admin()
    )
  );

-- ----------------------------------------------------------------
-- ALTA 3: registrarse directo por la API de Auth (sin pasar por
-- RegistroForm.tsx) se salta nombre/apellido/cédula/teléfono -- la
-- migración 104 solo valida en UPDATE, nunca en el INSERT inicial, y
-- esa cuenta igual podía depositar. Se extiende el trigger BEFORE
-- INSERT de depósito (migración 099) para exigir el perfil completo
-- antes de registrar un depósito -- no se toca handle_new_user()
-- porque también lo usa la Admin API para crear cuentas de gestión
-- (admin-tester, etc.) sin estos datos, a propósito.
-- ----------------------------------------------------------------
create or replace function public.validar_deposito_simulado_al_insertar()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$
declare
  v_nombre text;
  v_apellido text;
  v_cedula text;
  v_telefono text;
begin
  select nombre, apellido, cedula, telefono
    into v_nombre, v_apellido, v_cedula, v_telefono
  from public.usuarios
  where id = new.usuario_id;

  if coalesce(trim(v_nombre), '') = ''
     or coalesce(trim(v_apellido), '') = ''
     or v_cedula !~ '^[0-9]{3}-[0-9]{7}-[0-9]$'
     or coalesce(trim(v_telefono), '') = '' then
    raise exception 'Completa tus datos de contacto (nombre, apellido, cédula y teléfono) en tu perfil antes de depositar.';
  end if;

  if new.wallet_mostrada is not null
     and not (new.wallet_mostrada = any(public.obtener_wallets_admin())) then
    new.wallet_mostrada := null;
  end if;
  if new.comprobante_path is not null
     and not exists (select 1 from storage.objects
       where bucket_id = 'comprobantes-soporte' and name = new.comprobante_path) then
    raise exception 'El comprobante del depósito no existe. Vuelve a adjuntar la imagen.';
  end if;
  return new;
end;
$$;

-- ----------------------------------------------------------------
-- MEDIA 4: obtener_wallets_admin() mostraba (y el trigger de arriba
-- aceptaba) la wallet de un admin ya DESACTIVADO.
-- ----------------------------------------------------------------
create or replace function public.obtener_wallets_admin()
returns text[] as $$
  select coalesce(array_remove(array_agg(w), null), array[]::text[])
  from (
    select wallet_usdt_erc20 as w from public.usuarios
      where role = 'admin' and activo = true and wallet_usdt_erc20 is not null
    union all
    select wallet_usdt_erc20_2 from public.usuarios
      where role = 'admin' and activo = true and wallet_usdt_erc20_2 is not null
    union all
    select wallet_usdt_erc20_3 from public.usuarios
      where role = 'admin' and activo = true and wallet_usdt_erc20_3 is not null
  ) t;
$$ language sql security definer set search_path = pg_catalog, public, pg_temp;

-- ----------------------------------------------------------------
-- BAJA 8: admin_cerrar_operacion aceptaba 'Infinity' como precio
-- (> 0 y no es NaN, así que pasaba el check viejo) -- mismo tipo de
-- bug que la migración 038 ya había cerrado para el saldo. Se agrega
-- el mismo tope superior para descartar Infinity (y de paso cualquier
-- precio absurdo). admin_cerrar_operaciones_bloque reutiliza esta
-- misma función por cada elemento, así que queda cerrado también ahí.
-- ----------------------------------------------------------------
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
  if p_precio_entrada is null or p_precio_entrada = 'NaN'::numeric
     or p_precio_entrada <= 0 or p_precio_entrada > 100000000000 then
    raise exception 'El precio de entrada debe ser mayor a cero.';
  end if;
  if p_precio_salida is null or p_precio_salida = 'NaN'::numeric
     or p_precio_salida <= 0 or p_precio_salida > 100000000000 then
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
