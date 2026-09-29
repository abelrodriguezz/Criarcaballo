-- ============================================================
-- MIGRACIÓN 070: el cierre en bloque no acepta una hora de cierre futura
-- Pegar en Supabase → SQL Editor → Run (después de 001-069)
--
-- QA de "Cierre de operaciones" (2026-09-29): admin_cerrar_operacion
-- aceptaba una hora de cierre posterior al momento real ("cerrado_en" en
-- el futuro). El dueño del proyecto confirmó que debe bloquearse.
-- Se agrega el mismo chequeo en la función (fuente de verdad), la server
-- action (para no dejar un cierre a medias si algún símbolo falla) y el
-- formulario (para avisar antes del confirm).
-- ============================================================

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
  v_ahora timestamptz := now();
  v_cerrado_en timestamptz := coalesce(p_hora_cierre, v_ahora);
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
  if p_hora_cierre is not null and p_hora_cierre > v_ahora then
    raise exception 'La hora de cierre no puede ser en el futuro.';
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

  -- Con una sola hora escrita, la otra es la real (apertura) o now()
  -- (cierre): se valida contra lo que efectivamente se va a guardar.
  if coalesce(p_hora_entrada, v_operacion.created_at) >= v_cerrado_en then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

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

  -- El saldo de práctica siempre recupera lo invertido, gane o pierda (030).
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
