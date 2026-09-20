-- ============================================================
-- MIGRACIÓN 019: Integridad de dinero, permisos del admin y
-- cierre automático de señales a prueba de manipulación
-- Pegar en Supabase → SQL Editor → Run (después de 001-018)
--
-- Auditoría independiente sobre el trabajo de las migraciones 010-018.
-- Corrige cinco cosas, de más grave a menos:
--
-- 1) EL ADMIN NO PODÍA VER NI CERRAR LAS OPERACIONES DE NADIE MÁS.
--    operaciones_simuladas y saldo_virtual solo tenían la política de
--    SELECT "auth.uid() = usuario_id" — nunca se agregó la variante
--    "o es_admin()" que sí tienen usuarios, ganancias_concursos y
--    mensajes_soporte. Consecuencias reales en producción:
--      · "Cerrar todas las operaciones abiertas" (/reto-del-dia) leía la
--        lista de operaciones abiertas con la sesión del admin, así que
--        RLS se la filtraba a las SUYAS: cerraba su propia operación y
--        ninguna de los demás usuarios, reportando "0 cerradas".
--      · /usuarios/[id] mostraba siempre "$0.00" de saldo virtual y
--        "todavía no ha abierto ninguna operación" para cualquier
--        usuario que no fuera el propio admin.
--    No se detectó antes porque la base de prueba tenía un solo usuario
--    (el admin), y consigo mismo el filtro de RLS es invisible.
--
-- 2) EL PRECIO DE ENTRADA DE UNA OPERACIÓN VENÍA DEL CLIENTE.
--    abrir_operacion() recibía p_precio y lo guardaba tal cual, y estaba
--    otorgada a "authenticated": cualquier usuario logueado podía abrir
--    la consola del navegador y llamar
--      supabase.rpc('abrir_operacion', {p_activo:'BTCUSDT', p_tipo:'compra',
--                                       p_precio: 0.01, p_monto: 10000})
--    con lo que cantidad = monto/precio = 1.000.000 BTC y, al liquidar el
--    admin la sesión, su "ganancia" era de miles de millones — arruinando
--    el ranking que decide los premios reales en USDT. El server action
--    de Next.js sí consultaba el precio en Binance, pero eso no servía de
--    nada porque el RPC se podía llamar directo saltándose el action.
--    Se corrige exigiendo un secreto que solo conoce el servidor de
--    Next.js (nunca llega al navegador), guardado en una tabla que ni
--    anon ni authenticated pueden leer.
--
-- 3) CUALQUIERA PODÍA FALSIFICAR EL RESULTADO DE UNA SEÑAL.
--    cerrar_senal_automatica() estaba otorgada a anon y aceptaba
--    resultado, precio de cierre y porcentaje como parámetros libres: con
--    la anon key (que viaja en el bundle del navegador) se podía marcar
--    cualquier señal como "TP tocado +900%". El historial de señales es
--    justo el activo de credibilidad del producto. Ahora la función
--    calcula ella misma el precio de cierre y el porcentaje desde la fila
--    de la señal (entrada/TP/SL ya guardados) y exige el mismo secreto de
--    servidor, así que solo el código de Next.js puede dispararla.
--
-- 4) VALIDACIONES NUMÉRICAS QUE FALTABAN.
--    · abrir_operacion: p_precio podía ser 0 (división por cero) o NULL.
--    · p_monto podía llegar como 'NaN' (en numeric de Postgres, NaN NO es
--      <= 0, así que pasaba el filtro) y dejaba el saldo del usuario en
--      NaN de forma permanente.
--    · cerrar_operacion / admin_cerrar_operacion no validaban el precio
--      de salida.
--    · admin_agregar_saldo aceptaba NaN.
--    · abrir_operacion no verificaba que el activo fuera el pick del día
--      vigente (solo lo hacía el server action, saltable igual que el
--      precio).
--
-- 5) SEÑALES CON TP/SL DEL LADO EQUIVOCADO.
--    Nada impedía publicar una señal de compra con el take profit POR
--    DEBAJO de la entrada. El cierre automático por velas la daba por
--    "TP tocado" en la primera vela revisada, con porcentaje negativo.
--    Se agrega un check en la base de datos.
-- ============================================================

-- ------------------------------------------------------------
-- 1) El admin puede leer operaciones y saldos de cualquier usuario
-- ------------------------------------------------------------
-- Las políticas permisivas se combinan con OR, así que esto no le abre
-- nada a un usuario normal: sigue viendo solo lo suyo.

drop policy if exists "admin ve todas las operaciones" on public.operaciones_simuladas;
create policy "admin ve todas las operaciones"
  on public.operaciones_simuladas for select
  using (public.es_admin());

drop policy if exists "admin ve todos los saldos" on public.saldo_virtual;
create policy "admin ve todos los saldos"
  on public.saldo_virtual for select
  using (public.es_admin());

-- ------------------------------------------------------------
-- 2) Secreto compartido servidor Next.js <-> Postgres
-- ------------------------------------------------------------
-- Tabla con RLS activada y SIN ninguna política: eso significa que anon y
-- authenticated no pueden leer ni escribir NADA aquí (RLS sin políticas
-- deniega todo). Solo las funciones SECURITY DEFINER de abajo, que corren
-- como el dueño de la tabla, pueden consultarla.

create table if not exists public.config_servidor (
  clave text primary key,
  valor text not null,
  actualizado_en timestamptz not null default now()
);

alter table public.config_servidor enable row level security;
revoke all on public.config_servidor from anon, authenticated;

-- El valor real NO va escrito aquí: este archivo se versiona y se entrega
-- con el proyecto, así que un secreto literal en esta línea es un secreto
-- público (así estaba hasta la migración 021, y por eso hubo que rotarlo).
-- Se inserta un marcador inválido para que la app falle de forma ruidosa
-- hasta que se genere el valor real y se guarde en los DOS lados:
--
--   1) node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
--   2) en .env.local (TRADING_SERVER_SECRET) y en la base:
--        update public.config_servidor
--        set valor = 'EL_VALOR_GENERADO', actualizado_en = now()
--        where clave = 'trading_server_secret';
insert into public.config_servidor (clave, valor)
values ('trading_server_secret', 'FALTA-ROTAR-ESTE-SECRETO')
on conflict (clave) do nothing;

create or replace function public.secreto_servidor_ok(p_secreto text)
returns boolean as $$
  select p_secreto is not null
     and exists (
       select 1 from public.config_servidor
       where clave = 'trading_server_secret'
         and valor = p_secreto
     );
$$ language sql security definer stable;

revoke execute on function public.secreto_servidor_ok(text) from public;

-- ------------------------------------------------------------
-- 3) abrir_operacion: exige secreto de servidor + valida todo
-- ------------------------------------------------------------
-- Se DROPEA la versión de 4 argumentos antes de crear la nueva: si solo
-- se hiciera "create or replace" con un argumento más, Postgres dejaría
-- las dos conviviendo como sobrecargas y la vieja (vulnerable) seguiría
-- siendo llamable desde el navegador.

drop function if exists public.abrir_operacion(text, text, numeric, numeric);

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_precio numeric,
  p_monto numeric,
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_cantidad numeric;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  -- El precio de entrada define la cantidad comprada y por lo tanto toda
  -- la ganancia; no puede venir de un cliente. Este secreto solo existe
  -- en el entorno del servidor de Next.js (TRADING_SERVER_SECRET), nunca
  -- en el bundle del navegador.
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  -- Ojo: en numeric de Postgres, 'NaN' NO cumple "<= 0" (NaN se ordena
  -- por encima de cualquier número), así que hay que descartarlo aparte o
  -- se cuela y deja el saldo del usuario en NaN para siempre.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a cero.';
  end if;
  if p_precio is null or p_precio = 'NaN'::numeric or p_precio <= 0 then
    raise exception 'No se pudo determinar un precio de entrada válido.';
  end if;
  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  -- El activo tiene que ser el pick del día vigente (mismo chequeo que
  -- hace el server action, repetido aquí para que no se pueda saltar).
  select activo into v_pick
  from public.pick_del_dia
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
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
    v_usuario_id, upper(p_activo), p_tipo, p_precio, v_cantidad, p_monto, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = saldo_usd - p_monto, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

revoke execute on function public.abrir_operacion(text, text, numeric, numeric, text) from public;
grant execute on function public.abrir_operacion(text, text, numeric, numeric, text) to authenticated;

-- ------------------------------------------------------------
-- 4) Precio de salida validado al cerrar (usuario y admin)
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

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado + v_ganancia),
      actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

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
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado + v_ganancia),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer;

revoke execute on function public.cerrar_operacion(uuid, numeric) from public;
grant execute on function public.cerrar_operacion(uuid, numeric) to authenticated;
revoke execute on function public.admin_cerrar_operacion(uuid, numeric) from public;
grant execute on function public.admin_cerrar_operacion(uuid, numeric) to authenticated;

-- ------------------------------------------------------------
-- 5) admin_agregar_saldo: descartar NaN
-- ------------------------------------------------------------

create or replace function public.admin_agregar_saldo(
  p_usuario_id uuid,
  p_monto numeric
) returns public.saldo_virtual as $$
declare
  v_saldo public.saldo_virtual;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede ajustar el saldo de otro usuario.';
  end if;
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto = 0 then
    raise exception 'El monto debe ser un número distinto de cero.';
  end if;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + p_monto),
      actualizado_en = now()
  where usuario_id = p_usuario_id
  returning * into v_saldo;

  if v_saldo.usuario_id is null then
    raise exception 'Este usuario no tiene saldo virtual inicializado.';
  end if;

  return v_saldo;
end;
$$ language plpgsql security definer;

revoke execute on function public.admin_agregar_saldo(uuid, numeric) from public;
grant execute on function public.admin_agregar_saldo(uuid, numeric) to authenticated;

-- ------------------------------------------------------------
-- 6) cerrar_senal_automatica: no acepta precios ni porcentajes del cliente
-- ------------------------------------------------------------
-- La decisión de "¿tocó TP o SL?" sigue viniendo del código de Next.js
-- (es el único que puede leer las velas de Binance), pero el precio de
-- cierre y el porcentaje los calcula ahora la propia base de datos desde
-- entrada/take_profit/stop_loss, así que no hay forma de inyectar un
-- "+900%" falso. Además exige el secreto de servidor.

drop function if exists public.cerrar_senal_automatica(uuid, text, numeric, numeric);

create or replace function public.cerrar_senal_automatica(
  p_senal_id uuid,
  p_resultado text,
  p_secreto text
) returns void as $$
declare
  v_senal public.senales;
  v_precio numeric;
  v_porcentaje numeric;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Solo la aplicación puede cerrar señales automáticamente.';
  end if;
  if p_resultado not in ('tp', 'sl') then
    raise exception 'Resultado inválido.';
  end if;

  select * into v_senal
  from public.senales
  where id = p_senal_id and estado = 'activa' and resultado is null
  for update;

  if v_senal.id is null then
    return; -- ya estaba cerrada: no es un error, solo no hay nada que hacer
  end if;

  v_precio := case when p_resultado = 'tp'
                   then v_senal.take_profit
                   else v_senal.stop_loss end;

  if v_precio is null then
    raise exception 'La señal no tiene definido ese nivel.';
  end if;

  v_porcentaje := case
    when v_senal.tipo = 'compra'
      then ((v_precio - v_senal.entrada) / v_senal.entrada) * 100
    else ((v_senal.entrada - v_precio) / v_senal.entrada) * 100
  end;

  update public.senales
  set estado = 'cerrada',
      resultado = p_resultado,
      precio_cierre = v_precio,
      porcentaje_resultado = v_porcentaje,
      cerrado_en = now()
  where id = p_senal_id;
end;
$$ language plpgsql security definer;

revoke execute on function public.cerrar_senal_automatica(uuid, text, text) from public;
-- Se mantiene el grant a anon: el chequeo corre en un Server Component de
-- Next.js que puede estar sirviendo a un visitante sin sesión, pero ahora
-- lo que autoriza de verdad es el secreto, no el rol.
grant execute on function public.cerrar_senal_automatica(uuid, text, text) to authenticated, anon;

-- ------------------------------------------------------------
-- 7) TP/SL tienen que estar del lado correcto de la entrada
-- ------------------------------------------------------------
-- En una compra se gana hacia arriba: TP > entrada > SL. En una venta al
-- revés. Sin esto, una señal mal tipeada se cerraba sola como "TP tocado"
-- en la primera vela revisada, con un porcentaje negativo.

alter table public.senales
  drop constraint if exists senales_niveles_coherentes;

alter table public.senales
  add constraint senales_niveles_coherentes check (
    (
      tipo = 'compra'
      and (take_profit is null or take_profit > entrada)
      and (stop_loss is null or stop_loss < entrada)
    )
    or (
      tipo = 'venta'
      and (take_profit is null or take_profit < entrada)
      and (stop_loss is null or stop_loss > entrada)
    )
  );

-- Nota: se verificó contra los datos reales antes de aplicarlo — todas
-- las señales existentes ya cumplen, así que el constraint entra
-- validado. Si en otra instalación hubiera históricos con los niveles
-- invertidos, agregarlo con "not valid" y luego "validate constraint".
