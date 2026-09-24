-- ============================================================
-- MIGRACIÓN 040: valida el código de invitación antes de registrar,
-- y una cuenta desactivada deja de poder recibir referidos nuevos.
-- Pegar en Supabase → SQL Editor → Run (después de 001-039)
--
-- Hallazgos del QA del 2026-09-24 sobre el registro con código manual:
-- 1) Un código mal tipeado se perdía en silencio y era irrecuperable
--    (invitado_por es inmutable desde la migración 036) — ahora el
--    formulario puede preguntar si el código existe ANTES de enviar.
-- 2) El código de una cuenta desactivada seguía sirviendo para sumar
--    referidos nuevos a su árbol — se decide bloquearlo.
-- ============================================================

-- ------------------------------------------------------------
-- 1) RPC pública de solo lectura: ¿este código existe y su dueño
--    está activo? No expone nada más de la cuenta (ni el email, ni
--    el id) — mismo patrón que estadisticas_publicas().
-- ------------------------------------------------------------
create or replace function public.codigo_invitacion_valido(p_codigo text)
returns boolean as $$
  select exists (
    select 1
    from public.usuarios
    where codigo_invitacion = upper(trim(coalesce(p_codigo, '')))
      and activo = true
  );
$$ language sql stable security definer
   set search_path = pg_catalog, public, pg_temp;

grant execute on function public.codigo_invitacion_valido(text) to anon, authenticated;

-- ------------------------------------------------------------
-- 2) handle_new_user(): una cuenta desactivada ya no puede ser
--    invitadora de gente nueva (defensa en profundidad — el chequeo
--    de arriba es solo un aviso previo en el formulario, esto es lo
--    que de verdad decide invitado_por al crear la cuenta).
-- ------------------------------------------------------------
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
    where codigo_invitacion = codigo_ref
      and activo = true;
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
