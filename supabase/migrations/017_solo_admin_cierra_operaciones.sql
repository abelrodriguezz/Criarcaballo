-- ============================================================
-- MIGRACIÓN 017: Solo el admin puede cerrar operaciones
-- Pegar en Supabase → SQL Editor → Run (después de 001-016)
--
-- El producto cambió: los usuarios abren su operación pero ya NO pueden
-- cerrarla ellos mismos — la sesión completa se liquida cuando el admin
-- usa "Cerrar todas las operaciones" con el precio que él defina. Se
-- quitó el botón individual del lado del código; esto lo refuerza en la
-- base de datos por si alguien llama cerrar_operacion() directo.
-- ============================================================

create or replace function public.cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar operaciones. Espera a que se liquide la sesión.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id
    and usuario_id = v_usuario_id
    and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - v_operacion.precio_entrada) * v_operacion.cantidad
    else (v_operacion.precio_entrada - p_precio_salida) * v_operacion.cantidad
  end;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = now()
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado + v_ganancia),
      actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;
