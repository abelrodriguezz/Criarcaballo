-- ============================================================
-- VERIFICACIÓN DE SEGURIDAD (regresión)
--
-- Pegar en Supabase → SQL Editor → Run, o correrlo con psql contra la
-- base del proyecto. No modifica nada: solo comprueba que siguen en pie
-- las garantías que establecieron las migraciones 010, 017, 019 y 021.
-- Si algo se rompe (una migración futura que reintroduce un grant, un
-- "create or replace" que pierde el search_path, una política que pierde
-- su with check), esto falla con un mensaje concreto.
--
-- Emite el aviso "VERIFICACIÓN DE SEGURIDAD: OK" si todo está bien, y
-- lanza una excepción con la lista de problemas si algo falla.
-- ============================================================

do $$
declare
  v_fallos text[] := '{}';
  v_n int;
  v_txt text;
  v_nombre text;
begin
  -- ----------------------------------------------------------
  -- 1) El validador del secreto no debe ser invocable por la API
  -- ----------------------------------------------------------
  -- Esta era la vulnerabilidad crítica que corrigió la migración 021: con
  -- EXECUTE para anon/authenticated, cualquiera con la anon key podía
  -- usar la función como oráculo para validar candidatos a secreto.
  if has_function_privilege('anon', 'public.secreto_servidor_ok(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.secreto_servidor_ok(text)', 'EXECUTE')
  then
    v_fallos := array_append(
      v_fallos,
      'secreto_servidor_ok es ejecutable por anon/authenticated (oraculo del secreto)'
    );
  end if;

  -- ----------------------------------------------------------
  -- 2) El secreto de servidor tiene que estar rotado de verdad
  -- ----------------------------------------------------------
  -- El valor que traía escrito la migración 019 se considera público.
  if exists (
    select 1 from public.config_servidor
    where clave = 'trading_server_secret'
      and valor in (
        'f95daae7dede3568450cbc13094e08932414949c29c97a00f55400f2a29ad342',
        'FALTA-ROTAR-ESTE-SECRETO'
      )
  ) then
    v_fallos := array_append(
      v_fallos,
      'trading_server_secret sigue siendo el valor comprometido o el marcador sin rotar'
    );
  end if;

  -- ----------------------------------------------------------
  -- 3) Las funciones de trigger no deben exponerse como RPC
  -- ----------------------------------------------------------
  foreach v_nombre in array array[
    'public.handle_new_user()',
    'public.handle_new_user_saldo()',
    'public.proteger_columnas_sensibles_usuarios()',
    'public.proteger_mensajes_soporte()',
    'public.limitar_frecuencia_mensajes_soporte()',
    'public.limitar_favoritos_por_usuario()'
  ] loop
    if has_function_privilege('anon', v_nombre, 'EXECUTE')
       or has_function_privilege('authenticated', v_nombre, 'EXECUTE')
    then
      v_fallos := array_append(
        v_fallos,
        v_nombre || ' es invocable como RPC por anon/authenticated'
      );
    end if;
  end loop;

  -- ----------------------------------------------------------
  -- 4) Toda función SECURITY DEFINER con search_path fijo
  -- ----------------------------------------------------------
  select count(*), coalesce(string_agg(p.proname, ', '), '')
    into v_n, v_txt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and (p.proconfig is null
         or not exists (
           select 1 from unnest(p.proconfig) c where c like 'search_path=%'
         ));
  if v_n > 0 then
    v_fallos := array_append(
      v_fallos,
      'funciones SECURITY DEFINER sin search_path fijo: ' || v_txt
    );
  end if;

  -- ----------------------------------------------------------
  -- 5) RLS activa en todas las tablas de public
  -- ----------------------------------------------------------
  select count(*), coalesce(string_agg(c.relname, ', '), '')
    into v_n, v_txt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if v_n > 0 then
    v_fallos := array_append(v_fallos, 'tablas sin RLS: ' || v_txt);
  end if;

  -- ----------------------------------------------------------
  -- 6) config_servidor: RLS activa y SIN políticas (deniega todo)
  -- ----------------------------------------------------------
  select count(*) into v_n
  from pg_policies where schemaname = 'public' and tablename = 'config_servidor';
  if v_n > 0 then
    v_fallos := array_append(
      v_fallos,
      'config_servidor tiene politicas RLS: el secreto pasaria a ser legible por la API'
    );
  end if;
  if has_table_privilege('anon', 'public.config_servidor', 'SELECT')
     or has_table_privilege('authenticated', 'public.config_servidor', 'SELECT')
  then
    v_fallos := array_append(
      v_fallos,
      'anon/authenticated tienen SELECT sobre config_servidor'
    );
  end if;

  -- ----------------------------------------------------------
  -- 7) Nadie puede escribir directo en las tablas de dinero
  -- ----------------------------------------------------------
  -- saldo_virtual y operaciones_simuladas solo se tocan vía los RPC
  -- SECURITY DEFINER: no debe existir ninguna política de INSERT/UPDATE/
  -- DELETE sobre ellas (migración 010).
  select count(*), coalesce(string_agg(tablename || '/' || cmd || '/' || policyname, ', '), '')
    into v_n, v_txt
  from pg_policies
  where schemaname = 'public'
    and tablename in ('saldo_virtual', 'operaciones_simuladas')
    and cmd <> 'SELECT';
  if v_n > 0 then
    v_fallos := array_append(
      v_fallos,
      'hay politicas de escritura directa sobre tablas de dinero: ' || v_txt
    );
  end if;

  -- ----------------------------------------------------------
  -- 8) Los triggers de protección tienen que estar habilitados
  -- ----------------------------------------------------------
  foreach v_nombre in array array[
    'antes_de_editar_usuario',
    'antes_de_editar_mensaje_soporte',
    'antes_de_insertar_mensaje_soporte',
    'antes_de_insertar_favorito'
  ] loop
    -- tgenabled = 'D' significa deshabilitado
    if not exists (
      select 1 from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and t.tgname = v_nombre
        and not t.tgisinternal and t.tgenabled <> 'D'
    ) then
      v_fallos := array_append(
        v_fallos,
        'falta (o esta deshabilitado) el trigger ' || v_nombre
      );
    end if;
  end loop;

  -- ----------------------------------------------------------
  -- 9) Las políticas de UPDATE del usuario llevan with check
  -- ----------------------------------------------------------
  -- En usuarios y mensajes_soporte el "using" deja pasar a un usuario
  -- normal, así que el with check explícito no puede faltar.
  select count(*), coalesce(string_agg(tablename || '/' || policyname, ', '), '')
    into v_n, v_txt
  from pg_policies
  where schemaname = 'public' and cmd = 'UPDATE'
    and tablename in ('usuarios', 'mensajes_soporte')
    and with_check is null;
  if v_n > 0 then
    v_fallos := array_append(v_fallos, 'politicas UPDATE sin with check: ' || v_txt);
  end if;

  -- ----------------------------------------------------------
  -- 10) TRUNCATE (que ignora RLS) fuera del alcance de la API
  -- ----------------------------------------------------------
  select count(*), coalesce(string_agg(c.relname, ', '), '')
    into v_n, v_txt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and (has_table_privilege('anon', c.oid, 'TRUNCATE')
         or has_table_privilege('authenticated', c.oid, 'TRUNCATE'));
  if v_n > 0 then
    v_fallos := array_append(
      v_fallos,
      'anon/authenticated tienen TRUNCATE (ignora RLS) sobre: ' || v_txt
    );
  end if;

  -- ----------------------------------------------------------
  -- 11) noticias.url_fuente restringida a http/https
  -- ----------------------------------------------------------
  -- Ese campo se renderiza como href en la portada pública.
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.noticias'::regclass
      and conname = 'noticias_url_fuente_http'
  ) then
    v_fallos := array_append(
      v_fallos,
      'falta el constraint noticias_url_fuente_http (XSS via href)'
    );
  end if;
  if exists (
    select 1 from public.noticias
    where url_fuente is not null and url_fuente !~* '^https?://'
  ) then
    v_fallos := array_append(v_fallos, 'hay noticias con url_fuente que no es http/https');
  end if;

  -- ----------------------------------------------------------
  -- 12) Una sola operación abierta por usuario (anti doble gasto)
  -- ----------------------------------------------------------
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'operaciones_una_abierta_por_usuario'
  ) then
    v_fallos := array_append(
      v_fallos,
      'falta el indice unico operaciones_una_abierta_por_usuario (permite doble apertura)'
    );
  end if;

  select count(*) into v_n
  from (
    select usuario_id from public.operaciones_simuladas
    where estado = 'abierta' group by usuario_id having count(*) > 1
  ) s;
  if v_n > 0 then
    v_fallos := array_append(
      v_fallos,
      v_n || ' usuario(s) con mas de una operacion abierta'
    );
  end if;

  -- ----------------------------------------------------------
  -- 13) Integridad del dinero: nada de NaN ni negativos
  -- ----------------------------------------------------------
  select count(*) into v_n from public.saldo_virtual
  where saldo_usd is null or saldo_usd = 'NaN'::numeric or saldo_usd < 0;
  if v_n > 0 then
    v_fallos := array_append(
      v_fallos,
      v_n || ' fila(s) de saldo_virtual con valor invalido (NaN/negativo/null)'
    );
  end if;

  select count(*) into v_n from public.operaciones_simuladas
  where precio_entrada is null or precio_entrada = 'NaN'::numeric or precio_entrada <= 0
     or monto_usado = 'NaN'::numeric or cantidad = 'NaN'::numeric;
  if v_n > 0 then
    v_fallos := array_append(
      v_fallos,
      v_n || ' operacion(es) con precio/monto/cantidad invalido'
    );
  end if;

  -- ----------------------------------------------------------
  -- 14) Siempre tiene que quedar al menos un admin activo
  -- ----------------------------------------------------------
  select count(*) into v_n from public.usuarios where role = 'admin' and activo = true;
  if v_n = 0 then
    v_fallos := array_append(v_fallos, 'no queda ningun administrador activo');
  end if;

  -- ----------------------------------------------------------
  -- Resultado
  -- ----------------------------------------------------------
  if array_length(v_fallos, 1) is null then
    raise notice 'VERIFICACIÓN DE SEGURIDAD: OK (14 comprobaciones)';
  else
    raise exception E'VERIFICACIÓN DE SEGURIDAD: % FALLO(S)\n  - %',
      array_length(v_fallos, 1),
      array_to_string(v_fallos, E'\n  - ');
  end if;
end;
$$;
