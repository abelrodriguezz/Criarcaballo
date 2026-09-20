-- ============================================================
-- MIGRACIÓN 014: Horario de mercado (NYSE) + admin puede cerrar
-- operaciones de cualquier usuario
-- Pegar en Supabase → SQL Editor → Run (después de 001-013)
-- ============================================================

-- --- Reforzar abrir_operacion: horario de la bolsa de Nueva York ---
-- Lunes a viernes, 9:30am-4:00pm hora de Nueva York. Los admins pueden
-- operar a cualquier hora. Esto es defensa en profundidad — la UI ya
-- deshabilita el botón, pero esto evita que alguien la salte llamando el
-- RPC directo fuera de horario.
create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a cero.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  if not public.es_admin() then
    v_hora_ny := (now() at time zone 'America/New_York')::time;
    v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));
    if v_dia_semana_ny > 5 or v_hora_ny < time '09:30' or v_hora_ny >= time '16:00' then
      raise exception 'El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York.';
    end if;
  end if;

  select trading_habilitado into v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo < p_monto then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  v_cantidad := p_monto / p_precio;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, precio_entrada, cantidad, monto_usado, estado
  ) values (
    v_usuario_id, p_activo, p_tipo, p_precio, v_cantidad, p_monto, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = saldo_usd - p_monto, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

-- --- Nueva función: admin cierra la operación de CUALQUIER usuario ---
-- (cerrar_operacion de la migración 010 solo permite cerrar la propia,
-- vía auth.uid() — esta es la versión para el botón masivo del admin).
create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_salida numeric
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_ganancia numeric;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
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
  where usuario_id = v_operacion.usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

grant execute on function public.admin_cerrar_operacion(uuid, numeric) to authenticated;
