-- ============================================================
-- MIGRACIÓN 006: Wallet USDT (ERC20) para recompensas de concursos
-- Pegar en Supabase → SQL Editor → Run (después de 001-005)
--
-- Solo almacena la dirección para que el admin pague manualmente las
-- recompensas de concursos — no habilita depósitos ni retiros dentro
-- de la plataforma.
-- ============================================================

alter table public.usuarios
  add column wallet_usdt_erc20 text;

-- Valida el formato básico de una dirección ERC20 (0x + 40 caracteres hex)
-- para evitar que se guarde algo claramente inválido por error de tipeo.
alter table public.usuarios
  add constraint wallet_usdt_erc20_formato
  check (
    wallet_usdt_erc20 is null
    or wallet_usdt_erc20 ~ '^0x[a-fA-F0-9]{40}$'
  );

-- Se agrega también al alta automática de usuario, por si en el futuro se
-- quiere volver a ofrecer el campo directo en el registro (hoy el
-- formulario de registro lo deja para completar después en Perfil).
create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20)
  values (new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial);

  return new;
end;
$$ language plpgsql security definer;
