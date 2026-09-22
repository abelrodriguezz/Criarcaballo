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
