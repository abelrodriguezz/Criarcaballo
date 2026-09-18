-- ============================================================
-- MIGRACIÓN 010: Arreglos de seguridad y validación (auditoría QA)
-- Pegar en Supabase → SQL Editor → Run (después de 001-009)
--
-- Resume varios huecos encontrados en una auditoría de código:
--
-- 1) La política de UPDATE de "usuarios" no tenía "with check", así que
--    cualquier usuario autenticado podía llamar
--    supabase.from('usuarios').update({role:'admin', activo:true}) sobre
--    su propia fila desde el navegador y auto-ascenderse a admin. Se
--    corrige con un trigger que exige ser admin para tocar role/activo,
--    y que impide dejar el sistema sin ningún admin activo.
--
-- 2) Por el mismo motivo, "saldo_virtual" y "operaciones_simuladas" se
--    podían editar directo desde el cliente (RLS solo validaba el dueño
--    de la fila, no el valor). Un usuario podía ponerse saldo_usd en
--    999,999,999 a mano. Se revocan esas políticas de UPDATE/INSERT y se
--    mueve la lógica de abrir/cerrar operaciones a funciones SECURITY
--    DEFINER (abrir_operacion / cerrar_operacion) que validan todo en
--    una sola transacción atómica — esto también elimina la condición de
--    carrera de abrir dos operaciones a la vez con doble clic.
--
-- 3) Constraints que solo existían en el formulario (cliente), no en la
--    base de datos: señales con entrada <= 0, noticias con título vacío.
--
-- 4) Trazabilidad de quién marcó una ganancia como pagada.
--
-- 5) Límite de longitud en mensajes de chat (no existía ninguno).
-- ============================================================

-- --- 1) Proteger role/activo en "usuarios" ---

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
begin
  if (new.role is distinct from old.role or new.activo is distinct from old.activo)
     and not public.es_admin() then
    raise exception 'Solo un admin puede cambiar el rol o el estado de una cuenta.';
  end if;

  if old.role = 'admin' and old.activo = true
     and (new.role <> 'admin' or new.activo = false)
     and not exists (
       select 1 from public.usuarios
       where role = 'admin' and activo = true and id <> old.id
     )
  then
    raise exception 'No puedes desactivar o quitarle el rol admin al único administrador activo.';
  end if;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists antes_de_editar_usuario on public.usuarios;
create trigger antes_de_editar_usuario
  before update on public.usuarios
  for each row execute procedure public.proteger_columnas_sensibles_usuarios();

-- --- 2) saldo_virtual / operaciones_simuladas: mover a RPC atómico ---

-- Ya nadie debe poder hacer update directo desde el cliente a estas
-- tablas — todo pasa por las funciones de abajo, que sí corren con
-- privilegios elevados y validan cada regla de negocio.
drop policy if exists "usuario actualiza su propio saldo" on public.saldo_virtual;
drop policy if exists "usuario crea sus propias operaciones" on public.operaciones_simuladas;
drop policy if exists "usuario cierra sus propias operaciones" on public.operaciones_simuladas;

-- Respaldo a nivel de base de datos: nunca más de una operación abierta
-- por usuario, ni siquiera si algo llama a estas tablas por fuera de la
-- función (defensa en profundidad).
create unique index if not exists operaciones_una_abierta_por_usuario
  on public.operaciones_simuladas (usuario_id)
  where estado = 'abierta';

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
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

  -- Bloquea la fila de saldo del usuario: si dos solicitudes llegan casi
  -- juntas, la segunda espera a que la primera termine, así que no puede
  -- haber doble apertura ni doble descuento del mismo saldo.
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
  -- Igual que antes: la pérdida máxima de una simulación se limita al
  -- monto arriesgado, no es una cuenta de margen real.
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

grant execute on function public.abrir_operacion(text, text, numeric, numeric) to authenticated;
grant execute on function public.cerrar_operacion(uuid, numeric) to authenticated;

-- --- 3) Constraints que solo vivían en el formulario ---

alter table public.senales
  add constraint senales_entrada_positiva check (entrada > 0),
  add constraint senales_par_no_vacio check (length(trim(par)) > 0);

alter table public.noticias
  add constraint noticias_titulo_no_vacio check (length(trim(titulo)) > 0);

-- --- 4) Trazabilidad de pagos de ganancias ---

alter table public.ganancias_concursos
  add column pagado_por uuid references public.usuarios(id);

-- --- 5) Límite de longitud en mensajes de chat ---

alter table public.mensajes_soporte
  add constraint mensajes_soporte_longitud check (length(contenido) <= 2000);
