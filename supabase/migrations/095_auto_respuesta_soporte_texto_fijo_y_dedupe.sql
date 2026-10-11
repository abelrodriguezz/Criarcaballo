-- ============================================================
-- MIGRACIÓN 095: auto-respuesta de soporte con texto fijo en la base,
-- deduplicada y serializada
-- Pegar en Supabase → SQL Editor → Run (después de 001-094)
-- IMPORTANTE: aplicar JUNTO con el deploy del cambio en
-- src/lib/actions/chat.ts (la firma de la RPC cambia; con código viejo
-- + esta migración, o código nuevo sin ella, simplemente no se manda el
-- aviso — no rompe el envío del mensaje del usuario).
--
-- Hallazgos de QA (2026-10-11) sobre la 093/094:
--
-- 1) La RPC insertar_auto_respuesta_soporte(p_usuario_id, p_contenido)
--    aceptaba CUALQUIER texto y estaba concedida a `authenticated`. Un
--    usuario podía llamarla directo (supabase.rpc) y meter en su propio
--    chat mensajes con remitente_id NULL — que el chat pinta igual que una
--    respuesta del equipo de soporte — con el texto que quisiera ("tu
--    retiro de $50,000 fue aprobado"), sin límite de frecuencia (el
--    trigger exime remitente_id NULL) y con leido_admin=true (el admin no
--    se entera). Reproducido: 24 inserciones en segundos.
--    Fix: la función ya no recibe el texto — solo el idioma — y el texto
--    vive acá. El usuario sale de auth.uid(), no de un parámetro.
--
-- 2) La deduplicación (en la app) miraba solo el mensaje INMEDIATAMENTE
--    anterior: U1, AUTO, U2 (anterior=AUTO, no repite), U3 (anterior=U2,
--    SÍ repite)... Una ráfaga de 10 mensajes generaba 5 avisos. Además,
--    envíos concurrentes (varias pestañas) se saltaban el chequeo por
--    carrera: 5 envíos simultáneos → 3 avisos.
--    Fix: la decisión se toma acá, bajo un advisory lock por usuario, y
--    mira el último mensaje de la conversación que NO escribió el propio
--    usuario: si es un aviso automático (nadie del equipo contestó
--    después), no se repite.
--
-- 3) proteger_mensajes_soporte() no protegía es_auto_respuesta: un
--    usuario podía cambiarla en sus filas (p. ej. apagarla en el aviso
--    para forzar avisos repetidos). Ahora es inmutable como el resto.
-- ============================================================

drop function if exists public.insertar_auto_respuesta_soporte(uuid, text);

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
      || E'Nuestro equipo de soporte está disponible de 8:00 a.m. a 3:00 p.m. (hora estándar de Japón, JST — UTC+9).\n\n'
      || 'Gracias por tu comprensión. Esperamos poder ayudarte dentro de nuestro horario de atención.'
    else
      E'Customer Support Hours\n\n'
      || E'Our customer support team is available from 8:00 a.m. to 3:00 p.m. (Japan Standard Time, JST — UTC+9).\n\n'
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

revoke all on function public.insertar_auto_respuesta_soporte(text) from public, anon;
grant execute on function public.insertar_auto_respuesta_soporte(text) to authenticated;

create or replace function public.proteger_mensajes_soporte()
returns trigger as $$
begin
  if new.id is distinct from old.id
     or new.usuario_id is distinct from old.usuario_id
     or new.remitente_id is distinct from old.remitente_id
     or new.contenido is distinct from old.contenido
     or new.created_at is distinct from old.created_at
     or new.es_auto_respuesta is distinct from old.es_auto_respuesta then
    raise exception 'Un mensaje de soporte enviado no se puede modificar; solo marcarse como leído.';
  end if;

  -- La imagen solo puede quitarse (cron de limpieza), nunca reemplazarse.
  if new.imagen_path is distinct from old.imagen_path
     and new.imagen_path is not null then
    raise exception 'La imagen de un mensaje enviado no se puede cambiar.';
  end if;

  -- leido_admin es el contador del admin; el usuario no lo toca.
  -- auth.uid() null = cron / SQL directo, se permite.
  if new.leido_admin is distinct from old.leido_admin
     and auth.uid() is not null
     and not public.es_admin() then
    raise exception 'Solo un admin puede marcar mensajes como leídos por soporte.';
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
