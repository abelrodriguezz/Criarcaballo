-- ============================================================
-- MIGRACIÓN 100: nuevo horario de atención del chat de soporte,
-- 6:30am-11:00am JST (antes 8:00am-3:00pm)
-- Pegar en Supabase → SQL Editor → Run (después de 001-099)
-- IMPORTANTE: desplegar junto con el cambio de
-- src/lib/actions/chat.ts (fueraDeHorarioSoporte ahora compara en
-- minutos, no solo en horas enteras, porque 6:30 no es una hora
-- redonda).
--
-- Pedido del dueño del proyecto (2026-10-12): mismo texto fijo de la
-- migración 095, solo cambia el horario mencionado.
-- ============================================================

create or replace function public.insertar_auto_respuesta_soporte(
  p_idioma text
) returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_ultimo_es_auto boolean;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if not public.cuenta_activa() then
    return false;
  end if;

  -- Serializa los avisos de ESTE usuario: dos envíos simultáneos no
  -- pueden ver ambos "no hay aviso pendiente" e insertar dos.
  perform pg_advisory_xact_lock(
    hashtextextended('auto_respuesta_soporte:' || v_uid::text, 0)
  );

  select m.es_auto_respuesta into v_ultimo_es_auto
  from public.mensajes_soporte m
  where m.usuario_id = v_uid
    and m.remitente_id is distinct from v_uid
  order by m.created_at desc, m.id desc
  limit 1;

  if coalesce(v_ultimo_es_auto, false) then
    return false;
  end if;

  insert into public.mensajes_soporte (
    usuario_id, remitente_id, contenido, leido_admin, leido_usuario, es_auto_respuesta
  ) values (
    v_uid,
    null,
    case when p_idioma = 'es' then
      E'Horario de atención al cliente\n\n'
      || E'Nuestro equipo de soporte está disponible de 6:30 a.m. a 11:00 a.m. (hora estándar de Japón, JST — UTC+9).\n\n'
      || 'Gracias por tu comprensión. Esperamos poder ayudarte dentro de nuestro horario de atención.'
    else
      E'Customer Support Hours\n\n'
      || E'Our customer support team is available from 6:30 a.m. to 11:00 a.m. (Japan Standard Time, JST — UTC+9).\n\n'
      || 'Thank you for your understanding. We look forward to assisting you during our business hours.'
    end,
    true,
    false,
    true
  );

  return true;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
