-- ============================================================
-- MIGRACIÓN 033: la recompensa por referido se genera SOLA al registrarse
-- Pegar en Supabase → SQL Editor → Run (después de 001-032)
--
-- Antes, el admin tenía que entrar a /referidos y darle clic a "Otorgar
-- premio" por cada persona invitada. Ahora: en el momento mismo en que
-- alguien se registra con un código de invitación válido, se le crea
-- automáticamente al invitador una fila en ganancias_concursos con
-- pagado=false, usando el monto configurado en ese momento (config_portada,
-- clave='premio_referido' — el mismo que edita AdminPremioReferidoForm en
-- /referidos). El admin ya no "otorga" nada, solo marca pagado cuando
-- corresponda (BotonPagoGanancia, sin cambios).
--
-- El botón "Otorgar premio" de /referidos se deja tal cual como respaldo
-- manual: solo aparece cuando NO existe todavía una fila de recompensa
-- para ese invitado (por ejemplo, relaciones de invitado_por de ANTES de
-- esta migración), así que sigue siendo útil sin tocar ni una línea de
-- ese componente.
--
-- Se repite el `set search_path` fijo a propósito (ver migraciones 030 y
-- 031): "create or replace function" resetea esa configuración si no se
-- repite explícitamente, y esta es una función que corre en cada alta de
-- usuario.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
  v_nuevo_id_corto int;
  v_premio numeric;
begin
  codigo_nuevo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  codigo_ref := new.raw_user_meta_data ->> 'ref';
  if codigo_ref is not null then
    select id into id_invitador
    from public.usuarios
    where codigo_invitacion = codigo_ref;
  end if;

  wallet_inicial := new.raw_user_meta_data ->> 'wallet';
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20, id_corto)
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial, v_nuevo_id_corto
  );

  if id_invitador is not null then
    select coalesce((valor ->> 'monto')::numeric, 5)
    into v_premio
    from public.config_portada
    where clave = 'premio_referido';

    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      id_invitador, coalesce(v_premio, 5), 'Referido: ' || new.email, 'referido', new.id
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
