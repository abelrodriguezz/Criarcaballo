-- ============================================================
-- MIGRACIÓN 097: revertir un depósito pagado a pendiente cancela la
-- operación abierta que ese depósito financiaba
-- Pegar en Supabase → SQL Editor → Run (después de 001-096 — usa el
-- helper limpiar_bonos_referido_no_alcanzados() que crea la 096)
-- IMPORTANTE: desplegar junto con el cambio de BotonPagoDeposito.tsx y
-- /depositos/page.tsx (el aviso al admin ahora dice que la operación se
-- cancela; sin esta migración eso no pasaría).
--
-- Hallazgo de QA pre-producción del módulo de Depósitos (2026-10-12),
-- reproducido contra la base real con cuentas descartables:
--   1) Admin marca pagado un depósito de $300 → saldo = 300.
--   2) El usuario abre la operación del día → abrir_operacion pone
--      monto_usado = 300 y saldo = 0 (usa el saldo COMPLETO).
--   3) Admin revierte el depósito a pendiente → saldo = greatest(0, 0 -
--      300) = 0, pero la operación seguía ABIERTA con los 300 adentro.
--   4) Admin cierra la operación → admin_cerrar_operacion devuelve
--      monto_usado al saldo → saldo = 300 con el depósito PENDIENTE.
--   5) Admin lo vuelve a marcar pagado → saldo = 600: el mismo depósito
--      acreditado dos veces.
-- Borrar el depósito ya pagado (trigger de la 077/096) sí cancelaba la
-- operación; revertirlo a pendiente no — misma situación, distinta regla.
--
-- Fix (las dos rutas quedan con la MISMA regla):
--   - Fondos reales del usuario = saldo + monto_usado de su operación
--     abierta (solo puede haber una, y usa el saldo completo).
--   - Se cancela la operación abierta (estado 'cancelada', igual que la
--     077: anulación administrativa, no resultado de trading).
--   - Saldo nuevo = greatest(0, fondos - monto del depósito). En el caso
--     normal (todo el saldo venía de este depósito) queda en 0 igual que
--     antes; si había fondos extra (ej. saldo agregado a mano por el admin
--     antes de operar) ya no se pierden junto con la operación cancelada
--     — antes, borrar el depósito en ese caso dejaba el saldo en 0.
--   - En la RPC se bloquea la fila de saldo ANTES de buscar la operación
--     abierta (mismo orden que abrir_operacion: saldo primero). Sin eso,
--     una reversión simultánea a una apertura podía leer "sin operación
--     abierta" y dejar el mismo hueco de arriba.
-- ============================================================

create or replace function public.admin_alternar_pago_deposito(
  p_deposito_id uuid,
  p_pagado boolean default null
)
returns public.depositos_simulados
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_admin_id uuid := auth.uid();
  v_deposito public.depositos_simulados;
  v_nuevo_estado boolean;
  v_monto_operacion numeric;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un deposito como pagado.';
  end if;

  select * into v_deposito
  from public.depositos_simulados
  where id = p_deposito_id
  for update;

  if v_deposito.id is null then
    raise exception 'Deposito no encontrado.';
  end if;

  v_nuevo_estado := coalesce(p_pagado, not v_deposito.pagado);

  if v_nuevo_estado = v_deposito.pagado then
    if v_deposito.pagado then
      raise exception 'Este depósito ya estaba marcado como pagado (otro admin u otra pestaña se adelantó). No se acreditó nada de nuevo.';
    else
      raise exception 'Este depósito ya estaba pendiente (otro admin u otra pestaña se adelantó). No se restó nada.';
    end if;
  end if;

  -- Saldo primero (mismo orden de locks que abrir_operacion).
  perform 1
  from public.saldo_virtual
  where usuario_id = v_deposito.usuario_id
  for update;

  if not found then
    raise exception 'El usuario no tiene cuenta de inversión (saldo_virtual); no se marcó el depósito.';
  end if;

  if v_nuevo_estado then
    update public.depositos_simulados
    set pagado = true, pagado_en = now(), pagado_por = v_admin_id
    where id = p_deposito_id
    returning * into v_deposito;

    update public.saldo_virtual
    set saldo_usd = saldo_usd + v_deposito.monto,
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  else
    update public.depositos_simulados
    set pagado = false, pagado_en = null, pagado_por = null
    where id = p_deposito_id
    returning * into v_deposito;

    -- sum() en vez de "returning ... into": si por cualquier motivo
    -- hubiera más de una abierta, se cancelan todas y no revienta.
    with canceladas as (
      update public.operaciones_simuladas
      set estado = 'cancelada', cerrado_en = now(),
          precio_salida = null, ganancia_perdida = 0
      where usuario_id = v_deposito.usuario_id and estado = 'abierta'
      returning monto_usado
    )
    select coalesce(sum(monto_usado), 0) into v_monto_operacion
    from canceladas;

    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd + v_monto_operacion - v_deposito.monto),
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  end if;

  return v_deposito;
end;
$$;

revoke all on function public.admin_alternar_pago_deposito(uuid, boolean) from public, anon;
grant execute on function public.admin_alternar_pago_deposito(uuid, boolean) to authenticated;

-- Borrar un depósito ya pagado: mismo cuerpo que la 096 (incluida la
-- limpieza de bonos), pero con la misma regla de saldo/operación que la
-- reversión de arriba.
create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_invitador uuid;
  v_monto_operacion numeric;
begin
  if old.pagado then
    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;

    select invitado_por into v_invitador
    from public.usuarios
    where id = old.usuario_id;

    perform public.limpiar_bonos_referido_no_alcanzados(v_invitador);

    -- Con una sola operación abierta por usuario y esa operación usando
    -- siempre el saldo COMPLETO (migración 032), si hay una abierta es
    -- porque el dinero de este depósito (u otro) está atrapado ahí. Se
    -- anula la operación y solo se devuelve lo que exceda el depósito
    -- borrado (normalmente nada).
    with canceladas as (
      update public.operaciones_simuladas
      set estado = 'cancelada', cerrado_en = now(),
          precio_salida = null, ganancia_perdida = 0
      where usuario_id = old.usuario_id and estado = 'abierta'
      returning monto_usado
    )
    select coalesce(sum(monto_usado), 0) into v_monto_operacion
    from canceladas;

    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd + v_monto_operacion - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;
  end if;

  return old;
end;
$$;
