-- ============================================================
-- MIGRACIÓN 052: la comisión de referido se genera al CONFIRMAR el
-- depósito (admin lo marca pagado), no al registrarlo
-- Pegar en Supabase → SQL Editor → Run (después de 001-051)
--
-- Hallazgo del QA (2026-09-25): el trigger otorgar_recompensa_referido()
-- corría en AFTER INSERT sobre depositos_simulados — es decir, apenas el
-- usuario REGISTRABA su depósito (un número que él mismo escribe, sin que
-- nadie lo verifique todavía), su invitador ya recibía una comisión
-- pendiente calculada sobre ese monto. Como el registro es autoservicio y
-- sin límite superior real, alguien podía registrar un "depósito" de
-- $100,000,000 nunca confirmado y su invitador quedaba con $10,000,000 en
-- comisión pendiente, pedible desde /retiros. Se encontró un caso real en
-- la base (lsprueba@gmail.com generó comisión para abelspam1234@gmail.com
-- con un depósito nunca confirmado) — no se tocó ese caso, queda para que
-- el usuario lo revise a mano.
--
-- Fix: el trigger pasa de AFTER INSERT a AFTER UPDATE OF pagado, y solo
-- dispara cuando pagado pasa de false a true (el admin lo confirmó de
-- verdad en admin_alternar_pago_deposito, migración 050). Si el admin
-- revierte un pago (pagado true -> false), la comisión correspondiente se
-- borra SOLO si todavía estaba pendiente — una ya pagada al invitador no
-- se toca, mismo criterio que ya usaba la migración 035 para no pisar
-- comisiones ya resueltas.
--
-- También se corrige el conteo de "referidos calificados" para el bono
-- por meta: antes contaba a cualquiera con una FILA en
-- depositos_simulados (sin importar si estaba pagada), el mismo hueco.
-- Ahora exige pagado = true.
-- ============================================================

drop trigger if exists on_deposito_simulado_recompensa on public.depositos_simulados;

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

create trigger on_deposito_simulado_recompensa
  after update of pagado on public.depositos_simulados
  for each row
  when (new.pagado is distinct from old.pagado)
  execute procedure public.otorgar_recompensa_referido();

-- ------------------------------------------------------------
-- Backfill: limpia comisiones de referido que ya existían para
-- depósitos que NUNCA se confirmaron (el caso encontrado en QA:
-- lsprueba@gmail.com -> abelspam1234@gmail.com). Solo borra las que
-- siguen SIN PAGAR — si alguna ya se le pagó de verdad al invitador,
-- se deja igual, no se le quita nada que ya haya recibido.
-- ------------------------------------------------------------
delete from public.ganancias_concursos gc
using public.depositos_simulados d
where gc.origen = 'referido'
  and gc.invitado_id = d.usuario_id
  and gc.pagado = false
  and d.pagado = false;

