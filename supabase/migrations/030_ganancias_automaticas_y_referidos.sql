-- ============================================================
-- MIGRACIÓN 030: ganancias de Trade del día pasan a "pendiente de pago",
-- el saldo de práctica deja de moverse con el resultado, y base para el
-- módulo de referidos
-- Pegar en Supabase → SQL Editor → Run (después de 001-029)
--
-- ANTES: al cerrar una operación, saldo_virtual.saldo_usd sumaba
-- monto_usado + ganancia_perdida (podía subir o bajar según el resultado).
-- AHORA: el saldo de práctica SIEMPRE recupera solo el monto_usado, gane o
-- pierda — deja de fluctuar con el trading. Si hubo ganancia (> 0), se
-- crea automáticamente una fila en ganancias_concursos con pagado=false
-- (la misma pantalla de "Ganancias pendientes de pago" en Reportes que ya
-- existe para premios de concursos). Si hubo pérdida, no se crea nada
-- nuevo — el historial ya queda en operaciones_simuladas (con el pick,
-- precio de entrada/salida y el monto perdido), que ya se muestra en
-- /usuarios/[id] y en el propio Trade del día del usuario.
--
-- `ganancias_concursos` gana columnas para poder distinguir el origen de
-- cada fila sin romper las que ya existen (todas quedan origen='concurso'
-- por default) y para el módulo de referidos.
-- ============================================================

alter table public.ganancias_concursos
  add column origen text not null default 'concurso'
    check (origen in ('concurso', 'trade', 'referido')),
  add column operacion_id uuid references public.operaciones_simuladas(id) on delete set null,
  add column invitado_id uuid references public.usuarios(id) on delete set null;

-- Cada persona invitada genera como mucho una fila de premio por
-- referido, para que el admin no pueda otorgarlo dos veces sin querer.
create unique index if not exists ganancias_concursos_invitado_unico
  on public.ganancias_concursos (invitado_id)
  where invitado_id is not null;

create index if not exists ganancias_concursos_operacion_idx
  on public.ganancias_concursos (operacion_id)
  where operacion_id is not null;

-- ------------------------------------------------------------
-- cerrar_operacion (usuario/admin cerrando su propia operación)
-- ------------------------------------------------------------
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
  if p_precio_salida is null
     or p_precio_salida = 'NaN'::numeric
     or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
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

  -- El saldo de práctica siempre recupera lo invertido, gane o pierda — el
  -- resultado ya no lo toca. La ganancia real (si la hubo) se paga aparte.
  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- admin_cerrar_operacion (admin cerrando la operación de OTRO usuario)
-- ------------------------------------------------------------
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
  if p_precio_salida is null
     or p_precio_salida = 'NaN'::numeric
     or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
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
$$ language plpgsql security definer;

revoke execute on function public.cerrar_operacion(uuid, numeric) from public;
grant execute on function public.cerrar_operacion(uuid, numeric) to authenticated;
revoke execute on function public.admin_cerrar_operacion(uuid, numeric) from public;
grant execute on function public.admin_cerrar_operacion(uuid, numeric) to authenticated;
