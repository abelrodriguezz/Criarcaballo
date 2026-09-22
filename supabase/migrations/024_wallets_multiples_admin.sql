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
