-- ============================================================
-- MIGRACIÓN 012: Permiso de trading por usuario + datos para el panel admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-011)
--
-- Agrega una columna para que el admin pueda impedirle a un usuario
-- puntual que opere (paper trading) sin tener que desactivarle toda la
-- cuenta. Protegida igual que "role"/"activo" (solo un admin puede
-- tocarla) y reforzada dentro de abrir_operacion() para que no se pueda
-- saltar llamando el RPC directo.
-- ============================================================

alter table public.usuarios
  add column trading_habilitado boolean not null default true;

-- --- Extiende el trigger de columnas sensibles (migración 010) ---

create or replace function public.proteger_columnas_sensibles_usuarios()
returns trigger as $$
begin
  if (new.role is distinct from old.role
      or new.activo is distinct from old.activo
      or new.trading_habilitado is distinct from old.trading_habilitado)
     and not public.es_admin() then
    raise exception 'Solo un admin puede cambiar el rol, el estado o el permiso de trading de una cuenta.';
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

-- --- Extiende abrir_operacion (migración 010) para respetar el permiso ---

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
