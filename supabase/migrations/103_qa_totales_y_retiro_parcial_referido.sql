-- ============================================================
-- MIGRACIÓN 103: 2 bugs reales de la QA con Opus (2026-10-12)
-- Pegar en Supabase → SQL Editor → Run (después de 001-102)
-- ============================================================

-- ----------------------------------------------------------------
-- BUG 1: "Total en cuentas de inversión (todos los usuarios)" del
-- dashboard del admin solo sumaba saldo_virtual -- el dinero que un
-- usuario tiene metido en una operación abierta (monto_usado) no se
-- contaba, así que el total bajaba cada vez que alguien operaba y
-- volvía a subir al cerrar. Medido en vivo: $23,000 mostrados vs
-- $25,800 reales (faltaban $2,800 en 3 operaciones abiertas).
--
-- create or replace, mismas columnas de salida que la 091 -> no hace
-- falta DROP, los GRANT/REVOKE de la 092 quedan intactos.
-- ----------------------------------------------------------------
create or replace function public.admin_totales_dashboard(
  p_inicio timestamptz,
  p_fin timestamptz
)
returns table (
  total_cuentas numeric,
  total_a_pagar_hoy numeric,
  total_retiros_solicitados numeric
)
language sql
stable
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
  select
    (select coalesce(sum(sv.saldo_usd), 0)
       from public.saldo_virtual sv
       join public.usuarios u on u.id = sv.usuario_id
      where u.role <> 'admin')
    +
    (select coalesce(sum(o.monto_usado), 0)
       from public.operaciones_simuladas o
       join public.usuarios u on u.id = o.usuario_id
      where u.role <> 'admin' and o.estado = 'abierta'),
    (select coalesce(sum(g.monto), 0)
       from public.ganancias_concursos g
       left join public.operaciones_simuladas o on o.id = g.operacion_id
      where g.pagado = false
        and coalesce(o.cerrado_en, g.created_at) >= p_inicio
        and coalesce(o.cerrado_en, g.created_at) < p_fin),
    (select coalesce(sum(sr.monto), 0)
       from public.solicitudes_retiro sr
      where sr.estado = 'pendiente');
$$;

-- ----------------------------------------------------------------
-- BUG 3: cuando un retiro paga solo PARTE de una comisión de referido
-- (admin_marcar_retiro_pagado, migración 072), la fila ORIGINAL (que
-- conserva invitado_id) se reducía al monto YA PAGADO, y el RESTO
-- pendiente se insertaba en una fila nueva SIN invitado_id -- a
-- propósito, según el comentario de la 072, porque el índice único
-- parcial ganancias_concursos_invitado_unico no permite dos filas con
-- el mismo invitado_id.
--
-- Eso dejaba el resto pendiente "huérfano": en /referidos aparecía
-- como un bono suelto en vez de la comisión del invitado, y
-- revertir_saldo_al_borrar_deposito / otorgar_recompensa_referido (que
-- filtran por invitado_id) ya no lo encontraban -- si después se
-- revertía el depósito de ese invitado, el resto pendiente NO se
-- borraba, y el invitador se quedaba con comisión de un depósito ya
-- revertido.
--
-- Arreglo: se invierte qué fila se queda con invitado_id. La fila
-- ORIGINAL (con su invitado_id intacto) pasa a quedarse con el RESTO
-- pendiente (solo se le baja el monto). Se inserta una fila NUEVA, ya
-- pagada, por la parte que sí se cubrió -- sin invitado_id, porque una
-- vez pagada no necesita seguir enganchada al invitado: ni
-- revertir_saldo_al_borrar_deposito ni otorgar_recompensa_referido
-- tocan nunca una fila con pagado = true. Así el índice único sigue
-- respetado, y lo que de verdad importa rastrear (lo pendiente) queda
-- donde la lógica de referidos lo busca.
-- ----------------------------------------------------------------
create or replace function public.admin_marcar_retiro_pagado(p_solicitud_id uuid)
returns public.solicitudes_retiro as $$
declare
  v_admin_id uuid := auth.uid();
  v_solicitud public.solicitudes_retiro;
  v_restante numeric;
  r_ganancia record;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede marcar un retiro como pagado.';
  end if;

  update public.solicitudes_retiro
  set estado = 'pagado', procesado_en = now(), procesado_por = v_admin_id
  where id = p_solicitud_id and estado = 'pendiente'
  returning * into v_solicitud;

  if v_solicitud.id is null then
    raise exception 'Esta solicitud ya fue procesada.';
  end if;

  v_restante := v_solicitud.monto;
  for r_ganancia in
    select *
    from public.ganancias_concursos
    where usuario_id = v_solicitud.usuario_id and pagado = false
    order by created_at, id
    for update
  loop
    exit when v_restante <= 0;

    if r_ganancia.monto <= v_restante then
      update public.ganancias_concursos
      set pagado = true, pagado_en = now(), pagado_por = v_admin_id
      where id = r_ganancia.id;
      v_restante := v_restante - r_ganancia.monto;
    else
      -- Pago parcial: la parte pagada va a una fila NUEVA (sin
      -- invitado_id), la fila original se queda con el resto pendiente
      -- (y conserva su invitado_id, si tenía).
      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, creado_por, created_at, pagado,
        pagado_en, pagado_por, origen, operacion_id
      ) values (
        r_ganancia.usuario_id, v_restante, r_ganancia.concepto, r_ganancia.creado_por,
        r_ganancia.created_at, true, now(), v_admin_id, r_ganancia.origen, r_ganancia.operacion_id
      );

      update public.ganancias_concursos
      set monto = r_ganancia.monto - v_restante
      where id = r_ganancia.id;

      v_restante := 0;
    end if;
  end loop;

  if v_restante > 0 then
    raise exception 'No hay suficientes ganancias pendientes para cubrir este retiro (faltan %). Puede que otro pago ya haya usado ese dinero — revisa las ganancias pendientes del usuario antes de reintentar.', v_restante;
  end if;

  return v_solicitud;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
