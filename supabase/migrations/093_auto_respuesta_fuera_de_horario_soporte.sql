-- ============================================================
-- MIGRACIÓN 093: auto-respuesta de "fuera de horario" en el chat de soporte
-- Pegar en Supabase → SQL Editor → Run (después de 001-092)
--
-- Pedido del dueño del proyecto (2026-10-11): cuando un usuario escribe en
-- el chat de soporte FUERA del horario de atención (8:00am-3:00pm hora de
-- Japón, JST/UTC+9), se le responde automáticamente con un aviso fijo —
-- en inglés o español según el idioma activo de la página.
--
-- remitente_id pasa a ser nullable: la auto-respuesta no "la escribe"
-- ningún admin en particular (si se usara el id de un admin real, ESE
-- admin la vería como un mensaje propio ya enviado — ChatBox.tsx decide
-- el lado de la burbuja comparando remitente_id con quien mira la
-- pantalla). NULL se renderiza como "no es mío" para TODOS los que
-- miran la conversación, sin importar quién sea.
--
-- La lógica de horario/idioma vive en la app (src/lib/actions/chat.ts),
-- no en un trigger: el idioma activo es una cookie HTTP, algo que la base
-- de datos no puede leer. La función de abajo solo hace la inserción
-- privilegiada (bypassa el INSERT policy, que exige remitente_id =
-- auth.uid()) después de que la app ya decidió que corresponde mandarla.
-- ============================================================

alter table public.mensajes_soporte
  alter column remitente_id drop not null;

alter table public.mensajes_soporte
  add column if not exists es_auto_respuesta boolean not null default false;

create or replace function public.insertar_auto_respuesta_soporte(
  p_usuario_id uuid,
  p_contenido text
) returns public.mensajes_soporte as $$
declare
  v_mensaje public.mensajes_soporte;
begin
  -- Mismo criterio de permiso que el resto de las RPC de este chat: el
  -- propio usuario (en su conversación) o un admin.
  if auth.uid() is distinct from p_usuario_id and not public.es_admin() then
    raise exception 'No tienes permiso para escribir en esta conversación.';
  end if;

  insert into public.mensajes_soporte (
    usuario_id, remitente_id, contenido, leido_admin, leido_usuario, es_auto_respuesta
  ) values (
    p_usuario_id, null, p_contenido, true, false, true
  )
  returning * into v_mensaje;

  return v_mensaje;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.insertar_auto_respuesta_soporte(uuid, text) from public, anon;
grant execute on function public.insertar_auto_respuesta_soporte(uuid, text) to authenticated;
