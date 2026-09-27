-- ============================================================
-- MIGRACIÓN 056: el admin fija precio de entrada, precio de salida y horas
-- al cerrar operaciones — deja de depender de que Binance haya dado el
-- precio de entrada correcto en el momento en que cada usuario abrió
-- Pegar en Supabase → SQL Editor → Run (después de 001-055)
--
-- Motivo (pedido del usuario, 2026-09-27): el módulo de operaciones dio
-- varios problemas reales con los pares (símbolo mal escrito BTCUSD,
-- bloqueo geográfico de Binance en Railway US/EU que tumbó la app
-- entera). Hasta ahora el precio de ENTRADA se auto-capturaba de Binance
-- en el momento en que cada usuario abría su operación (abrir_operacion,
-- migración 037) y era imposible de corregir después. El precio de SALIDA
-- ya lo fijaba el admin a mano por símbolo al cerrar en bloque
-- (BotonCerrarTodasOperaciones.tsx). Ahora el admin fija AMBOS precios (y
-- opcionalmente las horas de entrada/cierre) al momento de cerrar, en
-- bloque por símbolo — igual que ya funciona hoy con el precio de salida.
--
-- Para el usuario, abrir una operación no cambia en nada: sigue viendo el
-- precio "en vivo" al momento de abrir, como siempre. Lo que cambia es que
-- ESE precio deja de ser la fuente de verdad para el cálculo de ganancia:
-- el admin lo puede corregir al cerrar, y esa corrección recalcula todo
-- desde cero (cantidad de unidades y ganancia/pérdida), no es solo un dato
-- informativo. Confirmado explícitamente con el usuario.
--
-- Fórmula (sin cambios, solo cambia de dónde sale precio_entrada): cada
-- operación mantiene su propio monto_usado (lo que ESE usuario invirtió,
-- no cambia), así que el mismo precio en bloque por símbolo produce una
-- ganancia/pérdida distinta en dólares por usuario (mismo % de cambio,
-- distinto monto) — es la misma fórmula de siempre, ver migración 030.
--
-- Las horas de entrada/cierre son opcionales: si el admin no las
-- especifica, created_at (hora de entrada) queda como estaba y cerrado_en
-- (hora de cierre) usa now() — mismo comportamiento de siempre.
-- ============================================================

drop function if exists public.admin_cerrar_operacion(uuid, numeric);

create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_entrada numeric,
  p_precio_salida numeric,
  p_hora_entrada timestamptz default null,
  p_hora_cierre timestamptz default null
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_cantidad numeric;
  v_ganancia numeric;
  v_cerrado_en timestamptz := coalesce(p_hora_cierre, now());
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;
  if p_precio_entrada is null or p_precio_entrada = 'NaN'::numeric or p_precio_entrada <= 0 then
    raise exception 'El precio de entrada debe ser mayor a cero.';
  end if;
  if p_precio_salida is null or p_precio_salida = 'NaN'::numeric or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;
  if p_hora_entrada is not null and p_hora_cierre is not null
     and p_hora_entrada >= p_hora_cierre then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  -- El precio de entrada del admin REEMPLAZA al auto-capturado al abrir:
  -- se recalcula la cantidad de unidades con el monto que ese usuario ya
  -- tenía invertido (monto_usado no cambia) y la ganancia sale de esa
  -- cantidad nueva — no es un dato solo informativo.
  v_cantidad := v_operacion.monto_usado / p_precio_entrada;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - p_precio_entrada) * v_cantidad
    else (p_precio_entrada - p_precio_salida) * v_cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_entrada = p_precio_entrada,
      cantidad = v_cantidad,
      precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = v_cerrado_en,
      created_at = coalesce(p_hora_entrada, created_at)
  where id = p_operacion_id
  returning * into v_operacion;

  -- El saldo de práctica siempre recupera lo invertido, gane o pierda — el
  -- resultado ya no lo toca (migración 030). La ganancia real (si la hubo)
  -- se paga aparte vía ganancias_concursos.
  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_operacion.usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_cerrar_operacion(uuid, numeric, numeric, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_cerrar_operacion(uuid, numeric, numeric, timestamptz, timestamptz)
  to authenticated;

-- Comprobación: esta consulta no debe devolver ninguna fila (checklist de
-- search_path en toda función security definer).
--
--   select p.proname
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.prosecdef and p.proconfig is null;
