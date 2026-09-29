-- ============================================================
-- MIGRACIÓN 079: revertir un depósito borra el bono de referido si el
-- conteo de calificados ya no alcanza para ese hito (y sigue sin pagar)
-- Pegar en Supabase → SQL Editor → Run (después de 001-078)
--
-- Duda de negocio del QA de Comunidad + Referidos (2026-09-29), resuelta:
-- si el admin revierte el depósito de un referido y eso hace bajar el
-- conteo de calificados del invitador por debajo de un hito ya alcanzado
-- (ej. de 10 a 9), el bono de ese hito se quedaba intacto, sin pagar,
-- aunque el hito ya no se cumpliera de verdad. Solo se borraba la
-- comisión del referido revertido, nunca el bono.
--
-- Fix: en la misma rama de reversión de otorgar_recompensa_referido(), tras
-- borrar la comisión, se recalcula el conteo de calificados del invitador
-- (con el depósito ya revertido) y se borran los bonos de referido SIN
-- PAGAR cuyo hito (el número embebido en el concepto "Bono por N referidos
-- calificados") ya no alcanza ese conteo. Un bono YA PAGADO nunca se toca
-- (el invitador ya recibió ese dinero fuera de la plataforma).
-- ============================================================

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
  -- comisión de ESTE invitado seguía sin pagar, se borra — nunca se
  -- confirmó de verdad el depósito que la generaba. Una ya pagada no se
  -- toca (el invitador ya recibió su USDT, revertir el registro interno
  -- no se lo puede quitar).
  if new.pagado = false and old.pagado = true then
    delete from public.ganancias_concursos
    where invitado_id = new.usuario_id
      and origen = 'referido'
      and pagado = false;

    -- El conteo de calificados del invitador de este referido puede haber
    -- bajado por debajo de un hito ya alcanzado. Se recalcula CON el
    -- depósito ya revertido (new.pagado = false en esta misma fila) y se
    -- borran los bonos sin pagar que ya no alcanzan ese conteo.
    select invitado_por into v_invitador
    from public.usuarios
    where id = new.usuario_id;

    if v_invitador is not null then
      select count(*) into v_calificados_count
      from public.usuarios u
      join public.depositos_simulados d on d.usuario_id = u.id and d.pagado = true
      where u.invitado_por = v_invitador;

      delete from public.ganancias_concursos
      where usuario_id = v_invitador
        and origen = 'referido'
        and invitado_id is null
        and pagado = false
        and coalesce(nullif(regexp_replace(concepto, '\D', '', 'g'), '')::int, 0)
            > v_calificados_count;
    end if;

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
  -- CONFIRMADO — antes contaba cualquier fila, sin importar pagado.
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
