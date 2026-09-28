-- ============================================================
-- MIGRACIÓN 062: el pick del día vence al terminar el día (NY) y el admin
-- puede eliminarlo
-- Pegar en Supabase → SQL Editor → Run (después de 001-061)
--
-- Hallazgo del usuario (2026-09-28): "el pick no vence, siempre está el
-- pick y cuando se agrega otro entonces hay 2 pick". La tabla pick_del_dia
-- ya guarda una columna `fecha`, pero NINGUNA consulta la usaba para
-- decidir cuál es el pick "vigente" -- tanto abrir_operacion() como las
-- pantallas de Next.js simplemente tomaban la fila más reciente por
-- created_at, sin importar qué tan vieja fuera. Si un día se le olvidaba
-- al admin definir un pick nuevo, el de AYER (o de hace una semana) seguía
-- "vigente" indefinidamente. Y no había ninguna forma de borrar uno desde
-- la UI (nunca existió policy de DELETE para esta tabla).
--
-- Fix: abrir_operacion ahora exige que el pick coincida con el día de HOY
-- (hora de Nueva York), no solo que sea "el más reciente que exista". El
-- filtro por fecha en las pantallas de Next.js se hace en el código
-- (trade-del-dia/page.tsx, paperTrading.ts), esto solo cubre el lado de
-- la base de datos, que es lo que de verdad importa para la seguridad.
-- ============================================================

create policy "solo admin borra el pick del dia"
  on public.pick_del_dia for delete
  using (public.es_admin());

create or replace function public.abrir_operacion(
  p_activo text,
  p_tipo text,
  p_monto numeric, -- no se usa: se opera siempre con el saldo completo (migración 032)
  p_secreto text
) returns public.operaciones_simuladas as $$
declare
  v_usuario_id uuid := auth.uid();
  v_saldo numeric;
  v_trading_habilitado boolean;
  v_activo boolean;
  v_operacion public.operaciones_simuladas;
  v_hora_ny time;
  v_dia_semana_ny int;
  v_pick text;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Esta operación solo se puede abrir desde la aplicación.';
  end if;

  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_tipo not in ('compra', 'venta') then
    raise exception 'Tipo de operación inválido.';
  end if;

  select activo, trading_habilitado into v_activo, v_trading_habilitado
  from public.usuarios
  where id = v_usuario_id;

  if v_activo is not true then
    raise exception 'Tu cuenta está desactivada.';
  end if;

  -- El pick tiene que ser el de HOY (hora de Nueva York) -- antes se
  -- tomaba el más reciente que existiera, sin importar la fecha, así que
  -- un pick de ayer (o de hace una semana) seguía "vigente" para siempre
  -- si nadie definía uno nuevo.
  select activo into v_pick
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
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

  if v_trading_habilitado is false then
    raise exception 'Un administrador deshabilitó el trading para tu cuenta.';
  end if;

  select saldo_usd into v_saldo
  from public.saldo_virtual
  where usuario_id = v_usuario_id
  for update;

  if v_saldo is null or v_saldo <= 0 then
    raise exception 'Saldo virtual insuficiente.';
  end if;

  if exists (
    select 1 from public.operaciones_simuladas
    where usuario_id = v_usuario_id and estado = 'abierta'
  ) then
    raise exception 'Ya tienes una operación abierta. Ciérrala primero.';
  end if;

  insert into public.operaciones_simuladas (
    usuario_id, activo, tipo, monto_usado, estado
  ) values (
    v_usuario_id, upper(p_activo), p_tipo, v_saldo, 'abierta'
  ) returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = 0, actualizado_en = now()
  where usuario_id = v_usuario_id;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
