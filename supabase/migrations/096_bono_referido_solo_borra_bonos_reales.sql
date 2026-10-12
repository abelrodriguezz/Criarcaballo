-- ============================================================
-- MIGRACIÓN 096: la limpieza de bonos de referido que ya no alcanzan su
-- hito solo toca BONOS de verdad (no restos de comisiones), y también
-- corre al BORRAR un depósito pagado, no solo al revertirlo
-- Pegar en Supabase → SQL Editor → Run (después de 001-095)
--
-- Hallazgos del QA pre-producción de Referidos (2026-10-12), ambos
-- reproducidos en vivo contra la base real:
--
-- 1) (Dinero) La migración 079 borraba "bonos sin pagar cuyo hito ya no
--    alcanza" identificándolos como cualquier fila de origen 'referido'
--    con invitado_id NULL, y sacaba el hito con
--    regexp_replace(concepto, '\D', '', 'g') — es decir, TODOS los dígitos
--    del concepto. Pero el resto que deja un retiro parcial sobre una
--    COMISIÓN (migración 072/075) también queda con invitado_id NULL y su
--    concepto es "Referido (10%): correo123@x.com (resto tras retiro)" →
--    dígitos "10123", siempre mayor que el conteo de calificados. Resultado:
--    revertir el depósito de CUALQUIER otro referido del mismo invitador
--    borraba en silencio ese resto de comisión pendiente (dinero que el
--    invitador sí se ganó). Repro: invitador con 21 calificados, retiro de
--    $5 que parte la comisión de $10 de inv-a (resto $5 pendiente),
--    revertir el depósito de inv-u → el pendiente bajó $15 en vez de $10.
--    Además, con un correo con muchos dígitos el número no cabe en int y
--    el cast ::int lanzaba "integer out of range", haciendo fallar la
--    reversión del depósito por completo.
--    Fix: solo se consideran filas cuyo concepto tiene la forma exacta
--    del bono ("Bono por N referidos calificados", opcionalmente con el
--    sufijo " (resto tras retiro)"), y N se extrae de ESA posición.
--
-- 2) (Consistencia con la decisión de la 079) Borrar un depósito YA
--    PAGADO desde Gestión de usuarios (revertir_saldo_al_borrar_deposito,
--    migración 077) borraba la comisión del referido pero dejaba intacto
--    el bono sin pagar aunque el conteo de calificados ya no alcanzara el
--    hito (repro: 20 calificados con bono de 20 → borrar uno → 19
--    calificados y el bono de 20 seguía pendiente). Ahora usa la misma
--    limpieza que la reversión.
--
-- Un bono YA PAGADO nunca se toca (igual que antes).
-- ============================================================

-- ------------------------------------------------------------
-- Helper compartido: borra los bonos de referido SIN PAGAR de un
-- invitador cuyo hito ya no alcanza su conteo actual de calificados.
-- Solo lo llaman los triggers de abajo (security definer); no se expone.
-- ------------------------------------------------------------
create or replace function public.limpiar_bonos_referido_no_alcanzados(p_invitador uuid)
returns void as $$
declare
  v_calificados_count int;
begin
  if p_invitador is null then
    return;
  end if;

  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id and d.pagado = true
  where u.invitado_por = p_invitador;

  delete from public.ganancias_concursos
  where usuario_id = p_invitador
    and origen = 'referido'
    and invitado_id is null
    and pagado = false
    and concepto ~ '^Bono por [0-9]+ referidos calificados( \(resto tras retiro\))*$'
    and substring(concepto from '^Bono por ([0-9]+) ')::numeric > v_calificados_count;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.limpiar_bonos_referido_no_alcanzados(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 1) otorgar_recompensa_referido(): mismo cuerpo que la 079, la rama de
--    reversión ahora usa el helper.
-- ------------------------------------------------------------
create or replace function public.otorgar_recompensa_referido()
returns trigger as $$
declare
  v_invitador uuid;
  v_email_invitado text;
  v_config jsonb;
  v_porcentaje numeric;
  v_bono_cada int;
  v_bono_monto numeric;
  v_comision numeric;
  v_calificados_count int;
  v_concepto_bono text;
begin
  -- Reversión: el admin marcó el depósito de vuelta a pendiente. Si la
  -- comisión de ESTE invitado seguía sin pagar, se borra. Una ya pagada no
  -- se toca.
  if new.pagado = false and old.pagado = true then
    delete from public.ganancias_concursos
    where invitado_id = new.usuario_id
      and origen = 'referido'
      and pagado = false;

    select invitado_por into v_invitador
    from public.usuarios
    where id = new.usuario_id;

    -- Recalcula CON el depósito ya revertido y borra solo bonos (no restos
    -- de comisiones) sin pagar cuyo hito ya no se alcanza — ver 096.
    perform public.limpiar_bonos_referido_no_alcanzados(v_invitador);

    return new;
  end if;

  select invitado_por, email into v_invitador, v_email_invitado
  from public.usuarios
  where id = new.usuario_id;

  if v_invitador is null then
    return new;
  end if;

  select valor into v_config
  from public.config_portada
  where clave = 'premio_referido';

  v_porcentaje := coalesce((v_config ->> 'porcentaje')::numeric, 10);
  v_bono_cada := coalesce((v_config ->> 'bono_cada')::int, 10);
  v_bono_monto := coalesce((v_config ->> 'bono_monto')::numeric, 1000);

  v_comision := round(new.monto * greatest(v_porcentaje, 0) / 100, 2);

  if v_comision > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, origen, invitado_id
    ) values (
      v_invitador, v_comision,
      'Referido (' || v_porcentaje || '%): ' || v_email_invitado,
      'referido', new.usuario_id
    )
    on conflict (invitado_id) where invitado_id is not null do update
    set monto = excluded.monto,
        concepto = excluded.concepto
    where public.ganancias_concursos.pagado = false;
  end if;

  -- Solo cuentan como "calificados" los referidos con el depósito
  -- CONFIRMADO.
  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id and d.pagado = true
  where u.invitado_por = v_invitador;

  if v_bono_cada > 0 and v_calificados_count > 0
     and v_calificados_count % v_bono_cada = 0 then
    v_concepto_bono := 'Bono por ' || v_calificados_count || ' referidos calificados';

    if not exists (
      select 1 from public.ganancias_concursos
      where usuario_id = v_invitador
        and origen = 'referido'
        and invitado_id is null
        and concepto = v_concepto_bono
    ) then
      insert into public.ganancias_concursos (
        usuario_id, monto, concepto, origen
      ) values (
        v_invitador, v_bono_monto, v_concepto_bono, 'referido'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

-- ------------------------------------------------------------
-- 2) revertir_saldo_al_borrar_deposito(): mismo cuerpo que la 077, más la
--    limpieza de bonos del invitador (AFTER DELETE: el depósito ya no
--    existe, así que el conteo ya lo excluye).
-- ------------------------------------------------------------
create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
declare
  v_invitador uuid;
begin
  if old.pagado then
    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;

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
    -- porque el dinero de este depósito (u otro) está atrapado ahí. El
    -- depósito que se está borrando ya no existe, así que ese dinero
    -- tampoco -- se anula la operación sin devolver nada.
    update public.operaciones_simuladas
    set estado = 'cancelada', cerrado_en = now(),
        precio_salida = null, ganancia_perdida = 0
    where usuario_id = old.usuario_id and estado = 'abierta';
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
