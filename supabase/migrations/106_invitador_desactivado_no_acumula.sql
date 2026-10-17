-- ============================================================
-- MIGRACIÓN 106: un invitador desactivado deja de acumular comisiones
-- y bonos NUEVOS de referido
-- Pegar en Supabase → SQL Editor → Run (después de 001-105)
--
-- Decisión de negocio del dueño del proyecto (2026-10-17), a partir de
-- un hallazgo de la revisión de cobertura con Opus: cuando se desactiva
-- un invitador, sus referidos podían seguir depositando/confirmando y
-- él seguía ganando comisión y bonos como si nada -- la desactivación
-- solo le bloqueaba a ÉL operar/depositar/retirar, no afectaba lo que
-- generaban sus invitados.
--
-- Fix: mismo cuerpo que la migración 096, con un solo chequeo nuevo
-- justo después de resolver quién es el invitador -- si no está
-- activo, no se genera ni comisión ni bono por este depósito. Lo que
-- ya se le había otorgado ANTES de desactivarlo no se toca (ni se
-- borra la comisión ya ganada, ni el bono ya pendiente de pago) --
-- esto solo congela lo NUEVO.
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
  if new.pagado = false and old.pagado = true then
    delete from public.ganancias_concursos
    where invitado_id = new.usuario_id
      and origen = 'referido'
      and pagado = false;

    select invitado_por into v_invitador
    from public.usuarios
    where id = new.usuario_id;

    perform public.limpiar_bonos_referido_no_alcanzados(v_invitador);

    return new;
  end if;

  select invitado_por, email into v_invitador, v_email_invitado
  from public.usuarios
  where id = new.usuario_id;

  if v_invitador is null then
    return new;
  end if;

  -- Invitador desactivado: no se le genera NADA nuevo (ni comisión ni
  -- bono) por este depósito. Lo ya otorgado antes de desactivarlo
  -- queda intacto -- esto solo frena lo nuevo.
  if not exists (
    select 1 from public.usuarios where id = v_invitador and activo = true
  ) then
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
