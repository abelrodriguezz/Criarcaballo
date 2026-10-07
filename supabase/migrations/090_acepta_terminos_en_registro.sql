-- ============================================================
-- MIGRACIÓN 090: registra cuándo se aceptaron los Términos y Condiciones
-- Pegar en Supabase → SQL Editor → Run (después de 001-089)
--
-- Pedido del dueño del proyecto (2026-10-07): agregar un checkbox
-- obligatorio de Términos y Condiciones en Registro y Login. El checkbox
-- en sí es un gate de UI (el botón de enviar queda deshabilitado sin
-- marcarlo), pero el momento legal real que hay que dejar constancia es
-- la ACEPTACIÓN AL REGISTRARSE — por eso se guarda un timestamp en
-- usuarios.terminos_aceptados_en, puesto por el propio trigger con
-- now() (no se confía en un timestamp que mande el cliente, que podría
-- tener el reloj mal puesto o ser manipulado).
--
-- El checkbox en Login no crea un nuevo registro de aceptación cada vez
-- (no tiene sentido legal "volver a aceptar" lo mismo en cada sesión) —
-- solo exige tenerlo marcado para poder enviar el formulario, igual que
-- ya se exige con Turnstile.
-- ============================================================

alter table public.usuarios
  add column if not exists terminos_aceptados_en timestamptz;

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
  v_acepto_terminos boolean;
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
  v_acepto_terminos := (new.raw_user_meta_data ->> 'acepto_terminos') = 'true';
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (
    id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20,
    id_corto, nombre, apellido, telefono, cedula, terminos_aceptados_en
  )
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial,
    v_nuevo_id_corto, nombre_inicial, apellido_inicial, telefono_inicial, cedula_inicial,
    case when v_acepto_terminos then now() else null end
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
