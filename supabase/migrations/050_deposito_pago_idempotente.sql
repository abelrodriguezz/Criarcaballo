-- ============================================================
-- MIGRACIÓN 050: pago de depósitos idempotente + el usuario ya no puede
-- registrar su depósito "pre-pagado"
-- Pegar en Supabase → SQL Editor → Run (después de 001-049)
--
-- Encontrado en QA (2026-09-25), dos bugs reales:
--
-- 1) admin_alternar_pago_deposito (049) era un TOGGLE puro. El "for
--    update" sí evitaba acreditar dos veces, pero si dos admins (o un
--    admin con la página vieja abierta en otra pestaña) hacían clic en
--    "Marcar como pagado" sobre el mismo depósito, el segundo clic lo
--    REVERTÍA a pendiente y le restaba el saldo al usuario — justo lo
--    contrario de lo que el admin pidió. Probado con dos conexiones
--    reales a Postgres: la segunda quedaba esperando el lock y al
--    soltarse dejaba el depósito en pendiente con saldo $0.
--    Fix: la RPC recibe el estado DESEADO (p_pagado). Si el depósito ya
--    está en ese estado, falla con un mensaje claro y no toca el saldo.
--    p_pagado es opcional (null = toggle viejo) solo para que la versión
--    ya desplegada del front siga funcionando hasta el próximo deploy.
--
-- 2) La policy de INSERT (026) solo validaba usuario_id: un usuario
--    podía registrar su propio depósito ya con pagado=true,
--    revisado_por_admin=true y pagado_por = id de un admin. No le
--    acreditaba saldo, pero lo sacaba de la cola de Pendientes, le
--    quitaba el aviso de "Nuevo" al admin y falsificaba quién lo pagó.
--    Fix: el INSERT del usuario tiene que llegar con esas columnas en su
--    valor inicial.
--
-- Además: si por lo que sea el usuario no tuviera fila en saldo_virtual,
-- antes el depósito quedaba "pagado" sin acreditar nada. Ahora falla y
-- no se marca.
-- ============================================================

drop policy if exists "usuario registra su propia simulacion" on public.depositos_simulados;
create policy "usuario registra su propia simulacion"
  on public.depositos_simulados for insert
  with check (
    usuario_id = auth.uid()
    and not public.es_admin()
    and pagado = false
    and pagado_en is null
    and pagado_por is null
    and revisado_por_admin = false
  );

drop function if exists public.admin_alternar_pago_deposito(uuid);

create or replace function public.admin_alternar_pago_deposito(
  p_deposito_id uuid,
  p_pagado boolean default null
)
returns public.depositos_simulados as $$
declare
  v_admin_id uuid := auth.uid();
  v_deposito public.depositos_simulados;
  v_nuevo_estado boolean;
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

    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - v_deposito.monto),
        actualizado_en = now()
    where usuario_id = v_deposito.usuario_id;
  end if;

  if not found then
    raise exception 'El usuario no tiene cuenta de inversión (saldo_virtual); no se marcó el depósito.';
  end if;

  return v_deposito;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_alternar_pago_deposito(uuid, boolean) from public, anon;
grant execute on function public.admin_alternar_pago_deposito(uuid, boolean) to authenticated;
