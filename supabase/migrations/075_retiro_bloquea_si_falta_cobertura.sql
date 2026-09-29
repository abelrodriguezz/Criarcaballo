-- ============================================================
-- MIGRACIÓN 075: pagar un retiro se BLOQUEA si las ganancias pendientes
-- ya no alcanzan a cubrirlo completo
-- Pegar en Supabase → SQL Editor → Run (después de 001-074)
--
-- Duda de negocio de la fase de Retiro (2026-09-29), resuelta: si un admin
-- paga o borra ganancias pendientes desde Reportes MIENTRAS hay una
-- solicitud de retiro pendiente, admin_marcar_retiro_pagado (migración 072)
-- reconciliaba con lo que quedara disponible y marcaba el retiro como
-- "pagado" igual, aunque cubriera menos de lo pedido — en silencio, sin
-- avisar que faltó dinero por reconciliar.
--
-- Ahora, si al terminar de recorrer las ganancias pendientes todavía queda
-- v_restante > 0 (no había suficiente para cubrir el monto del retiro), la
-- función entera revierte (ninguna ganancia se marca pagada, el retiro
-- vuelve a quedar 'pendiente') y se explica el motivo.
-- ============================================================

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
      -- Pago parcial de esta fila: lo pagado se queda en la original,
      -- el resto sigue pendiente en una fila nueva.
      update public.ganancias_concursos
      set monto = v_restante, pagado = true, pagado_en = now(), pagado_por = v_admin_id
      where id = r_ganancia.id;

      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, creado_por, created_at, pagado,
        origen, operacion_id
      ) values (
        r_ganancia.usuario_id, r_ganancia.monto - v_restante,
        coalesce(r_ganancia.concepto, 'Ganancia') || ' (resto tras retiro)', r_ganancia.creado_por,
        r_ganancia.created_at, false, r_ganancia.origen, r_ganancia.operacion_id
      );

      v_restante := 0;
    end if;
  end loop;

  -- Si algo pagó o borró ganancias pendientes de este usuario mientras la
  -- solicitud esperaba (ej. desde Reportes), no queda suficiente para
  -- cubrirla: se revierte TODO (ninguna ganancia se toca, el retiro sigue
  -- 'pendiente') en vez de marcarlo pagado con un faltante silencioso.
  if v_restante > 0 then
    raise exception 'No hay suficientes ganancias pendientes para cubrir este retiro (faltan %). Puede que otro pago ya haya usado ese dinero — revisa las ganancias pendientes del usuario antes de reintentar.', v_restante;
  end if;

  return v_solicitud;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
