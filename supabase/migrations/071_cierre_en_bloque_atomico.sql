-- ============================================================
-- MIGRACIÓN 071: cierre en bloque atómico (todo o nada)
-- Pegar en Supabase → SQL Editor → Run (después de 001-070)
--
-- QA de "Cierre de operaciones" (2026-09-29): el cierre en bloque cerraba
-- una operación a la vez, cada una en su propia llamada RPC desde el
-- servidor. Si la conexión se cortaba a mitad del bucle, algunas quedaban
-- cerradas y otras no. El dueño del proyecto pidió hacerlo atómico: o se
-- cierran TODAS las operaciones recibidas, o no se cierra NINGUNA.
--
-- admin_cerrar_operaciones_bloque recibe un array JSON con todos los cierres
-- (operacion_id, precio_entrada, precio_salida, hora_entrada, hora_cierre) y
-- los procesa en un solo bucle DENTRO de la función, reutilizando
-- admin_cerrar_operacion para cada uno (misma validación y fórmula, sin
-- duplicar lógica). Como esta función se invoca en una sola llamada RPC, en
-- Postgres toda ella corre como una única transacción implícita: si
-- CUALQUIER cierre del array levanta una excepción (precio inválido, hora
-- inválida, ya estaba cerrada, etc.), la excepción no se atrapa aquí adentro
-- y Postgres deshace automáticamente TODOS los cierres ya aplicados en esa
-- misma llamada, sin necesidad de BEGIN/COMMIT explícito.
-- ============================================================

create or replace function public.admin_cerrar_operaciones_bloque(
  p_cierres jsonb
) returns setof public.operaciones_simuladas as $$
declare
  v_item jsonb;
  v_operacion public.operaciones_simuladas;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar operaciones.';
  end if;

  if jsonb_typeof(p_cierres) is distinct from 'array' then
    raise exception 'Formato inválido: se esperaba una lista de cierres.';
  end if;

  -- Sin manejo de excepción a propósito: si un solo elemento falla, la
  -- excepción sube sin atraparse y Postgres revierte todo lo hecho en esta
  -- llamada (incluidos los cierres de elementos anteriores del mismo array).
  for v_item in select * from jsonb_array_elements(p_cierres)
  loop
    v_operacion := public.admin_cerrar_operacion(
      (v_item->>'operacion_id')::uuid,
      (v_item->>'precio_entrada')::numeric,
      (v_item->>'precio_salida')::numeric,
      nullif(v_item->>'hora_entrada', '')::timestamptz,
      nullif(v_item->>'hora_cierre', '')::timestamptz
    );
    return next v_operacion;
  end loop;

  return;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_cerrar_operaciones_bloque(jsonb) from public, anon;
grant execute on function public.admin_cerrar_operaciones_bloque(jsonb) to authenticated;
