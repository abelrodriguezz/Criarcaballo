-- ============================================================
-- MIGRACIÓN 034: la recompensa por referido pasa a ser un % del depósito
-- simulado del invitado, más un bono repetible por cantidad de referidos
-- Pegar en Supabase → SQL Editor → Run (después de 001-033)
--
-- Reemplaza el diseño de la migración 033 (premio fijo automático al
-- REGISTRARSE) por este, definitivo:
--
-- 1) Cuando un usuario invitado hace SU depósito simulado (una sola vez
--    por usuario, ver migración 026), se le genera automáticamente a
--    quien lo invitó una recompensa PENDIENTE = porcentaje configurado ×
--    el monto de ese depósito. Si nunca deposita, no hay recompensa por
--    esa persona — es la señal de que fue un referido "calificado".
-- 2) Cada vez que el invitador acumula un múltiplo del umbral configurado
--    de referidos calificados (10, 20, 30...), se le genera además un
--    bono fijo configurado, también pendiente de pago.
--
-- config_portada.clave='premio_referido' cambia de forma:
--   ANTES:  { "monto": 5 }
--   AHORA:  { "porcentaje": 10, "bono_cada": 10, "bono_monto": 1000 }
-- (el helper de la app y el form de admin se actualizan aparte en el
-- mismo commit).
--
-- Por eso se revierte el paso de la 033 que insertaba la recompensa
-- dentro de handle_new_user() — ya no aplica, la recompensa se calcula
-- en el depósito, no en el registro.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Revertir handle_new_user() al comportamiento de antes de la 033
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
declare
  codigo_nuevo text;
  id_invitador uuid;
  codigo_ref text;
  wallet_inicial text;
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
  v_nuevo_id_corto := nextval('public.usuarios_id_corto_seq');

  insert into public.usuarios (id, email, role, codigo_invitacion, invitado_por, wallet_usdt_erc20, id_corto)
  values (
    new.id, new.email, 'user', codigo_nuevo, id_invitador, wallet_inicial, v_nuevo_id_corto
  );

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ------------------------------------------------------------
-- 2) Recompensa automática al depositar (comisión + bono por meta)
-- ------------------------------------------------------------
create or replace function public.otorgar_recompensa_referido()
returns trigger as $$
declare
  v_invitador uuid;
  v_email_invitado text;
  v_config jsonb;
  v_porcentaje numeric;
  v_bono_cada int;
  v_bono_monto numeric;
  v_comision numeric;
  v_calificados_count int;
begin
  select invitado_por, email into v_invitador, v_email_invitado
  from public.usuarios
  where id = new.usuario_id;

  -- Este usuario no llegó por invitación de nadie: no hay a quién premiar.
  if v_invitador is null then
    return new;
  end if;

  select valor into v_config
  from public.config_portada
  where clave = 'premio_referido';

  v_porcentaje := coalesce((v_config ->> 'porcentaje')::numeric, 10);
  v_bono_cada := coalesce((v_config ->> 'bono_cada')::int, 10);
  v_bono_monto := coalesce((v_config ->> 'bono_monto')::numeric, 1000);

  v_comision := round(new.monto * greatest(v_porcentaje, 0) / 100, 2);

  if v_comision > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      v_invitador, v_comision,
      'Referido (' || v_porcentaje || '%): ' || v_email_invitado,
      'referido', new.usuario_id
    );
  end if;

  -- Cuenta cuántos referidos de este invitador ya hicieron su depósito
  -- (son los "calificados" para el bono por meta).
  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id
  where u.invitado_por = v_invitador;

  if v_bono_cada > 0 and v_calificados_count > 0
     and v_calificados_count % v_bono_cada = 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen
    ) values (
      v_invitador, v_bono_monto,
      'Bono por ' || v_calificados_count || ' referidos calificados',
      'referido'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists on_deposito_simulado_recompensa on public.depositos_simulados;
create trigger on_deposito_simulado_recompensa
  after insert on public.depositos_simulados
  for each row execute procedure public.otorgar_recompensa_referido();

revoke all on function public.otorgar_recompensa_referido() from public, anon, authenticated;
