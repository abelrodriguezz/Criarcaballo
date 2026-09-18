-- ============================================================
-- MIGRACIÓN 008: ID corto por usuario
-- Pegar en Supabase → SQL Editor → Run (después de 001-007)
--
-- Un número corto (empieza en 100000) que cada usuario puede dar por chat
-- o decir en voz alta, en vez del UUID interno (36 caracteres, impráctico).
-- ============================================================

create sequence public.usuarios_id_corto_seq start with 100000 increment by 1;

alter table public.usuarios
  add column id_corto integer unique;

-- Actualiza el alta automática de usuario para que también asigne el ID corto.
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

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20, id_corto)
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    nextval('public.usuarios_id_corto_seq')
  );

  return new;
end;
$$ language plpgsql security definer;

-- Le asigna un ID corto a los usuarios que ya existían antes de esta migración.
update public.usuarios
set id_corto = nextval('public.usuarios_id_corto_seq')
where id_corto is null;
