-- ============================================================
-- MIGRACIÓN 002: Comunidad — código de invitación y referidos
-- Pegar en Supabase → SQL Editor → Run (después de la migración 001)
-- ============================================================

-- 1. Nuevas columnas en usuarios
alter table public.usuarios
  add column codigo_invitacion text unique,
  add column invitado_por uuid references public.usuarios(id);

-- 2. Reemplaza la función que crea el registro en "usuarios" al registrarse,
--    para que también genere el código de invitación y registre quién invitó
--    (si el registro llegó con ?ref=CODIGO).
create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
begin
  -- Genera un código corto y prácticamente único (8 caracteres)
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  -- Si el registro trae un código de referido en los metadatos, lo busca
  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por)
  values (new.id, new.email, 'user', codigo_nuevo, id_invitador);

  return new;
end;
$$ language plpgsql security definer;

-- 3. Función para contar cuántos usuarios ha invitado la persona actual,
--    SIN exponer los datos (email, etc.) de esos usuarios al front-end.
create function public.contar_invitados()
returns integer as $$
  select count(*)::int
  from public.usuarios
  where invitado_por = auth.uid();
$$ language sql security definer;

-- Por defecto Postgres ya da EXECUTE a todos los roles, pero se deja
-- explícito por si el proyecto tiene privilegios por defecto revocados.
grant execute on function public.contar_invitados() to authenticated;

-- ============================================================
-- Nota: los usuarios que ya existían antes de esta migración no tendrán
-- codigo_invitacion. Para generarles uno manualmente:
--
-- update public.usuarios
-- set codigo_invitacion = upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))
-- where codigo_invitacion is null;
-- ============================================================
