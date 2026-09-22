-- ============================================================
-- MIGRACIÓN 031: restaura el search_path fijo en las funciones de cierre
-- de operaciones
-- Pegar en Supabase → SQL Editor → Run (después de 001-030)
--
-- La migración 021 le puso a TODAS las funciones `security definer` un
-- search_path fijo:
--
--   alter function ... set search_path = pg_catalog, public, pg_temp;
--
-- Eso es la protección estándar contra el secuestro de search_path en
-- funciones que corren con los permisos de su dueño (CVE-2018-1058): sin
-- él, la función resuelve los nombres sin esquema usando el search_path
-- de QUIEN la llama, no el del dueño.
--
-- La migración 030 volvió a escribir `cerrar_operacion` y
-- `admin_cerrar_operacion` con `create or replace function` SIN repetir
-- la cláusula `set search_path`. En PostgreSQL, `create or replace` no
-- conserva la configuración de la función anterior: la reemplaza con los
-- valores por defecto. Resultado: las dos funciones que mueven dinero al
-- liquidar una operación quedaron como las ÚNICAS `security definer` del
-- esquema con search_path mutable (se comprueba con
-- `select proname, proconfig from pg_proc where prosecdef`), y también
-- las marca el linter de Supabase como `function_search_path_mutable`.
--
-- Hoy no es explotable de forma directa (el rol `authenticated` no tiene
-- CREATE sobre ningún esquema del search_path y PostgreSQL no busca
-- funciones ni operadores en pg_temp de forma implícita), pero es una
-- regresión de un control de seguridad que una auditoría anterior había
-- puesto a propósito. Se restaura.
--
-- Ojo al tocar estas funciones en el futuro: si se vuelven a escribir con
-- `create or replace`, hay que repetir la cláusula `set search_path`
-- dentro de la propia definición o volver a correr este `alter function`.
-- ============================================================

alter function public.cerrar_operacion(uuid, numeric)
  set search_path = pg_catalog, public, pg_temp;

alter function public.admin_cerrar_operacion(uuid, numeric)
  set search_path = pg_catalog, public, pg_temp;

-- Comprobación: esta consulta no debe devolver ninguna fila.
--
--   select p.proname
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.prosecdef and p.proconfig is null;
