-- ============================================================
-- MIGRACIÓN 061: dos huecos que dejó la migración 060 (abrir sin precio)
-- Pegar en Supabase → SQL Editor → Run (después de 001-060)
--
-- 1) cerrar_operacion(uuid, numeric) — la función de cierre VIEJA (antes de
--    la 056) seguía existiendo y ejecutable por cualquier admin vía RPC.
--    Ya no la usa la app (el cierre es admin_cerrar_operacion), pero calcula
--    la ganancia con el precio_entrada/cantidad capturados al abrir. Desde
--    la 060 esos valores son NULL, y como GREATEST() de Postgres ignora los
--    NULL, greatest(NULL, -monto_usado) = -monto_usado: la operación se
--    cerraba "bien" pero registrando una PÉRDIDA TOTAL del monto invertido,
--    sin ningún error. Probado en QA: operación de $500 cerrada con esa
--    función quedó con ganancia_perdida = -500 y precio_entrada NULL.
--    Se elimina: el único cierre válido es admin_cerrar_operacion (056).
--
-- 2) pick_del_dia.activo no tenía ningún límite, pero abrirOperacion()
--    (paperTrading.ts) rechaza cualquier activo de más de 30 caracteres con
--    "Símbolo de activo inválido". Un admin podía guardar un pick de 50
--    caracteres y NADIE podía operarlo ese día. Se alinea con un CHECK de
--    1 a 30 caracteres, sin espacios al inicio/fin (el formulario ya hace
--    trim, esto cubre inserts directos vía API con la sesión de admin).
-- ============================================================

drop function if exists public.cerrar_operacion(uuid, numeric);

alter table public.pick_del_dia
  drop constraint if exists pick_del_dia_activo_formato;

alter table public.pick_del_dia
  add constraint pick_del_dia_activo_formato
  check (char_length(activo) between 1 and 30 and activo = btrim(activo));
