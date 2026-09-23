-- ============================================================
-- MIGRACIÓN 035: fix — repetir el depósito simulado (tras borrarlo el
-- admin) ya no revienta ni duplica premios
-- Pegar en Supabase → SQL Editor → Run (después de 001-034)
--
-- Encontrado en QA propio de la 034, con un ciclo real: usuario deposita
-- → genera comisión pendiente → admin borra el depósito para que lo
-- repita (flujo ya existente de la migración 026) → usuario deposita de
-- nuevo. Dos bugs reales:
--
-- 1) El INSERT de la comisión reventaba con
--    "duplicate key value violates unique constraint
--    ganancias_concursos_invitado_unico" — y como el trigger corre DENTRO
--    de la misma transacción del insert en depositos_simulados, el
--    depósito nuevo se revertía completo (el usuario no podía repetirlo,
--    aunque la UI solo mostraba el mensaje genérico de "no se pudo
--    registrar"). Fix: `on conflict (invitado_id) do update`, y solo si
--    la comisión anterior seguía SIN pagar (si ya se pagó, no se toca —
--    el admin ya la resolvió con el monto que le tocó en su momento).
--
-- 2) El bono por meta se recalculaba iafresh cada vez: si el conteo de
--    referidos calificados quedaba en el mismo múltiplo de antes (típico
--    al repetir un depósito, el conteo de personas no cambia), se
--    insertaba OTRO bono duplicado por la misma meta. Fix: comprobar que
--    no exista ya un bono con ese mismo conteo antes de insertar.
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
    -- Si el usuario repite su depósito (el admin le borró el anterior
    -- para permitírselo), ya existe una fila con este invitado_id: se
    -- actualiza al nuevo monto en vez de fallar, pero solo si esa
    -- comisión seguía pendiente — una ya pagada no se toca.
    -- El índice único es PARCIAL (where invitado_id is not null): ON
    -- CONFLICT tiene que repetir esa misma condición para poder usarlo,
    -- si no Postgres no lo reconoce como destino válido de conflicto.
    on conflict (invitado_id) where invitado_id is not null do update
    set monto = excluded.monto,
        concepto = excluded.concepto
    where public.ganancias_concursos.pagado = false;
  end if;

  select count(*) into v_calificados_count
  from public.usuarios u
  join public.depositos_simulados d on d.usuario_id = u.id
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
