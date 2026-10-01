-- ============================================================
-- MIGRACIÓN 084: apellido y cédula (national ID) en el registro
-- Pegar en Supabase → SQL Editor → Run (después de 001-083)
--
-- IMPORTANTE: esta migración debe correrse ANTES de desplegar el código
-- nuevo (handle_new_user() inserta en columnas apellido/cedula -- si no
-- existen todavía, CUALQUIER registro nuevo, no solo los que usan estos
-- campos, fallaría con "column does not exist" en el trigger).
--
-- Pedido del dueño del proyecto (2026-10-01): el registro ahora pide
-- apellido y cédula (formato dominicano NNN-NNNNNNN-N), ambos obligatorios
-- junto con nombre y correo (nombre y correo ya eran obligatorios).
--
-- Las columnas aceptan NULL a nivel de base de datos (las cuentas ya
-- existentes no tienen estos datos y no se les puede exigir
-- retroactivamente) -- la obligatoriedad real la aplica el formulario de
-- registro. El CHECK de formato de cédula sí es duro: si se manda un
-- valor, tiene que tener el formato correcto.
-- ============================================================

alter table public.usuarios
  add column if not exists apellido text,
  add column if not exists cedula text;

alter table public.usuarios
  drop constraint if exists usuarios_cedula_formato;

alter table public.usuarios
  add constraint usuarios_cedula_formato check (
    cedula is null or cedula ~ '^[0-9]{3}-[0-9]{7}-[0-9]$'
  );

create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  nombre_inicial text;
  apellido_inicial text;
  telefono_inicial text;
  cedula_inicial text;
  v_nuevo_id_corto int;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref
      and activo = true;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  nombre_inicial := nullif(trim(new.raw_user_meta_data ->> 'nombre'), '');
  apellido_inicial := nullif(trim(new.raw_user_meta_data ->> 'apellido'), '');
  telefono_inicial := nullif(trim(new.raw_user_meta_data ->> 'telefono'), '');
  cedula_inicial := nullif(trim(new.raw_user_meta_data ->> 'cedula'), '');
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (
    id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20,
    id_corto, nombre, apellido, telefono, cedula
  )
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    v_nuevo_id_corto, nombre_inicial, apellido_inicial, telefono_inicial, cedula_inicial
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
