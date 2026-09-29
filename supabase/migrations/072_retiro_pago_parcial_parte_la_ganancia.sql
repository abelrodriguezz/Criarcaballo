-- ============================================================
-- MIGRACIÓN 072: pagar un retiro reconcilia EXACTO lo pagado
-- (parte la última ganancia en vez de marcarla pagada completa)
-- Pegar en Supabase → SQL Editor → Run (después de 001-071)
--
-- Hallazgo del QA del módulo de Retiro (2026-09-29): con ganancias
-- pendientes de $10 + $200 + $0.90 (= $210.90), el usuario pide un
-- retiro de $50 y el admin lo marca pagado. La reconciliación de la
-- migración 043 marcaba pagada COMPLETA la última fila tocada ($200),
-- así que el disponible del usuario caía a $0.90 en vez de $160.90:
-- el usuario perdía $160 que nunca se le pagaron. La "simplificación"
-- que documentaba la 043 dejó de ser inofensiva cuando esa misma
-- migración pasó a calcular el disponible solo desde
-- ganancias_concursos.pagado (ya no resta los retiros pagados aparte).
--
-- Cambio: admin_marcar_retiro_pagado() ahora, si la fila que toca vale
-- más que lo que falta por reconciliar, la PARTE en dos:
--   - la fila original baja su monto a lo pagado y queda pagado=true
--     (conserva invitado_id / operacion_id / concepto originales, así
--     el ON CONFLICT (invitado_id) de otorgar_recompensa_referido sigue
--     viendo la comisión como ya pagada y no la vuelve a inflar, y el
--     chequeo de "bono ya otorgado" por concepto sigue funcionando);
--   - se inserta una fila nueva con el resto, pagado=false, mismo
--     usuario/origen/operación/created_at, sin invitado_id (el índice
--     único de invitado_id no permite dos filas con el mismo).
-- La suma total de ganancias del usuario no cambia; solo se reparte.
-- Las filas se bloquean (FOR UPDATE) para que un pago de retiro y un
-- pago desde Reportes no reconcilien la misma fila a la vez.
--
-- No se corrigen retroactivamente retiros pagados antes de esta
-- migración: los únicos casos con exceso encontrados son cuentas qa-.
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

  return v_solicitud;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_marcar_retiro_pagado(uuid) from public, anon;
grant execute on function public.admin_marcar_retiro_pagado(uuid) to authenticated;
