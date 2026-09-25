-- ============================================================
-- MIGRACIÓN 043: al pagar un retiro, reconciliar con ganancias_concursos
-- (evita pago doble)
-- Pegar en Supabase → SQL Editor → Run (después de 001-042)
--
-- Hallazgo del QA del 2026-09-25 sobre el módulo de Retiro: pagar un
-- retiro no marcaba pagado=true en ganancias_concursos, así que esas
-- mismas ganancias seguían apareciendo pendientes en Usuarios →
-- Reportes con su propio botón de pago — riesgo real de pagar el mismo
-- dinero dos veces. El usuario confirmó: reconciliar automático.
--
-- Cambios:
-- 1) Backfill retroactivo: para cada retiro YA pagado antes de esta
--    migración, marca pagado=true en las ganancias más antiguas del
--    usuario hasta cubrir ese monto (mismo criterio "oldest first" que
--    ya se usa en otras partes del proyecto, ej. bono por meta de
--    referidos). Sin esto, la fórmula nueva del punto 2 le devolvería a
--    esos usuarios como "disponible" dinero que ya recibieron.
-- 2) solicitar_retiro(): el disponible ahora resta solo los retiros en
--    estado 'pendiente' (ya no 'pendiente' Y 'pagado') — los pagados ya
--    se reflejan directo en ganancias_concursos.pagado gracias a la
--    reconciliación, restarlos aparte sería contarlos dos veces.
-- 3) admin_marcar_retiro_pagado(): reemplaza el UPDATE directo que
--    hacía BotonProcesarRetiro.tsx para "pagado" — marca la solicitud Y
--    reconcilia las ganancias en la misma transacción (todo o nada).
--    Rechazar sigue siendo un UPDATE directo, sin reconciliar (no hay
--    nada que reconciliar si no se pagó).
--
-- Simplificación que se mantiene: si el monto no divide exacto entre
-- las filas de ganancias, la ÚLTIMA fila tocada se marca pagada
-- completa aunque "sobre" un poco — no se parte una fila en dos. El
-- total reconcilia bien igual porque solicitudes_retiro sigue siendo su
-- propio libro contra el fondo pendiente.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Backfill retroactivo
-- ------------------------------------------------------------
do $$
declare
  r_retiro record;
  r_ganancia record;
  v_restante numeric;
begin
  for r_retiro in
    select id, usuario_id, monto, procesado_en, procesado_por
    from public.solicitudes_retiro
    where estado = 'pagado'
    order by created_at
  loop
    v_restante := r_retiro.monto;
    for r_ganancia in
      select id, monto
      from public.ganancias_concursos
      where usuario_id = r_retiro.usuario_id and pagado = false
      order by created_at
    loop
      exit when v_restante <= 0;
      update public.ganancias_concursos
      set pagado = true,
          pagado_en = coalesce(r_retiro.procesado_en, now()),
          pagado_por = r_retiro.procesado_por
      where id = r_ganancia.id;
      v_restante := v_restante - r_ganancia.monto;
    end loop;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 2) solicitar_retiro(): disponible solo resta 'pendiente'
-- ------------------------------------------------------------
create or replace function public.solicitar_retiro(p_monto numeric)
returns public.solicitudes_retiro as $$
declare
  v_usuario_id uuid := auth.uid();
  v_wallet text;
  v_pendiente numeric;
  v_ya_solicitado numeric;
  v_disponible numeric;
  v_nueva public.solicitudes_retiro;
begin
  if v_usuario_id is null then
    raise exception 'No autenticado.';
  end if;

  if p_monto is null or p_monto <= 0 or p_monto >= 100000000 then
    raise exception 'Monto invalido.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('solicitar_retiro:' || v_usuario_id::text, 0)
  );

  select wallet_usdt_erc20 into v_wallet
  from public.usuarios
  where id = v_usuario_id;

  if v_wallet is null or trim(v_wallet) = '' then
    raise exception 'Registra tu wallet USDT (ERC20) en tu perfil antes de solicitar un retiro.';
  end if;

  if exists (
    select 1 from public.solicitudes_retiro
    where usuario_id = v_usuario_id and estado = 'pendiente'
  ) then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end if;

  select coalesce(sum(monto), 0) into v_pendiente
  from public.ganancias_concursos
  where usuario_id = v_usuario_id and pagado = false;

  -- Antes: 'pendiente','pagado'. Un retiro pagado ya redujo el fondo
  -- pendiente de verdad (reconciliacion), asi que contarlo aqui tambien
  -- lo restaria dos veces.
  select coalesce(sum(monto), 0) into v_ya_solicitado
  from public.solicitudes_retiro
  where usuario_id = v_usuario_id and estado = 'pendiente';

  v_disponible := v_pendiente - v_ya_solicitado;

  if round(p_monto, 2) > v_disponible then
    raise exception 'No puedes retirar mas de lo que tienes disponible.';
  end if;

  begin
    insert into public.solicitudes_retiro (usuario_id, monto, wallet_destino)
    values (v_usuario_id, round(p_monto, 2), v_wallet)
    returning * into v_nueva;
  exception when unique_violation then
    raise exception 'Ya tienes una solicitud de retiro pendiente.';
  end;

  return v_nueva;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ------------------------------------------------------------
-- 3) admin_marcar_retiro_pagado(): paga Y reconcilia, todo o nada
-- ------------------------------------------------------------
create function public.admin_marcar_retiro_pagado(p_solicitud_id uuid)
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

  -- El mismo patron que ya usaba BotonPagoGanancia.tsx: el .eq(estado,
  -- 'pendiente') implicito aqui evita que dos admins paguen la misma
  -- solicitud dos veces.
  update public.solicitudes_retiro
  set estado = 'pagado', procesado_en = now(), procesado_por = v_admin_id
  where id = p_solicitud_id and estado = 'pendiente'
  returning * into v_solicitud;

  if v_solicitud.id is null then
    raise exception 'Esta solicitud ya fue procesada.';
  end if;

  v_restante := v_solicitud.monto;
  for r_ganancia in
    select id, monto
    from public.ganancias_concursos
    where usuario_id = v_solicitud.usuario_id and pagado = false
    order by created_at
  loop
    exit when v_restante <= 0;
    update public.ganancias_concursos
    set pagado = true, pagado_en = now(), pagado_por = v_admin_id
    where id = r_ganancia.id;
    v_restante := v_restante - r_ganancia.monto;
  end loop;

  return v_solicitud;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_marcar_retiro_pagado(uuid) from public, anon;
grant execute on function public.admin_marcar_retiro_pagado(uuid) to authenticated;
