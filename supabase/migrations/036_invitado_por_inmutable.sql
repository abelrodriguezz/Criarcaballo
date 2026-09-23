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
