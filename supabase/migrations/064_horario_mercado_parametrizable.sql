-- ============================================================
-- MIGRACIÓN 064: el horario de mercado deja de estar fijo en el código —
-- se vuelve editable por el admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-063)
--
-- Pedido del usuario (2026-09-28): poder parametrizar el horario en que
-- los usuarios pueden abrir operaciones, incluida la opción de dejarlo
-- abierto sin restricción para que simulen a cualquier hora.
--
-- No se crea una tabla nueva: se reutiliza config_portada (clave/valor
-- jsonb), el mismo patrón que ya usa esta app para configuración editable
-- por admin sin tocar código (ver "simulacion_deposito"). Clave nueva:
-- "horario_mercado", valor = {"apertura":"09:30","cierre":"16:00",
-- "dias":[1,2,3,4,5],"abierto_siempre":false} (días en formato ISO:
-- 1=lunes...7=domingo). Sin fila guardada, se usan estos mismos valores
-- por defecto -- exactamente el comportamiento de hoy, cero riesgo si el
-- admin nunca toca el formulario nuevo.
--
-- El mensaje de error se deja genérico ("El mercado está cerrado en este
-- momento") en vez de intentar describir días/horas en SQL -- el mensaje
-- detallado y dinámico (con los días/horas configurados de verdad) se
-- arma del lado de Next.js (paperTrading.ts), donde formatear texto legible
-- es mucho más simple que en PL/pgSQL. Esta excepción es solo el respaldo
-- de seguridad si alguien se salta esa capa.
-- ============================================================

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
  v_horario jsonb;
  v_apertura time;
  v_cierre time;
  v_dias_habiles int[];
  v_abierto_siempre boolean;
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

  select activo into v_pick
  from public.pick_del_dia
  where fecha = (now() at time zone 'America/New_York')::date
  order by created_at desc
  limit 1;

  if v_pick is null or upper(v_pick) is distinct from upper(p_activo) then
    raise exception 'Ese activo no es el pick del día vigente.';
  end if;

  if not public.es_admin() then
    select valor into v_horario
    from public.config_portada
    where clave = 'horario_mercado';

    v_abierto_siempre := coalesce((v_horario->>'abierto_siempre')::boolean, false);

    if not v_abierto_siempre then
      v_apertura := coalesce((v_horario->>'apertura')::time, time '09:30');
      v_cierre := coalesce((v_horario->>'cierre')::time, time '16:00');
      v_dias_habiles := coalesce(
        (
          select array_agg(d::int)
          from jsonb_array_elements_text(coalesce(v_horario->'dias', '[]'::jsonb)) d
        ),
        array[1, 2, 3, 4, 5]
      );

      v_hora_ny := (now() at time zone 'America/New_York')::time;
      v_dia_semana_ny := extract(isodow from (now() at time zone 'America/New_York'));

      if not (v_dia_semana_ny = any(v_dias_habiles))
         or v_hora_ny < v_apertura
         or v_hora_ny >= v_cierre then
        raise exception 'El mercado está cerrado en este momento.';
      end if;
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
