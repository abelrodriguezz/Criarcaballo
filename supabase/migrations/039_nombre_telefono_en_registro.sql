-- ============================================================
-- MIGRACIÓN 039: handle_new_user() ahora guarda nombre y teléfono
-- si vienen en el registro (RegistroForm.tsx los manda opcionalmente
-- via raw_user_meta_data, igual que ya hacía con "ref" y "wallet").
-- Pegar en Supabase → SQL Editor → Run (después de 001-038)
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  nombre_inicial text;
  telefono_inicial text;
  v_nuevo_id_corto int;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  nombre_inicial := nullif(trim(new.raw_user_meta_data ->> 'nombre'), '');
  telefono_inicial := nullif(trim(new.raw_user_meta_data ->> 'telefono'), '');
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (
    id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20,
    id_corto, nombre, telefono
  )
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    v_nuevo_id_corto, nombre_inicial, telefono_inicial
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
