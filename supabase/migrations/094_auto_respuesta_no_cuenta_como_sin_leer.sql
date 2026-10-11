-- ============================================================
-- MIGRACIÓN 094: la auto-respuesta de fuera de horario no infla el
-- contador de "sin responder" del admin
-- Pegar en Supabase → SQL Editor → Run (después de 001-093)
--
-- Hallazgo de QA (2026-10-11) sobre la migración 093: el trigger
-- limitar_frecuencia_mensajes_soporte (migración 021) fuerza
-- leido_admin=false en CUALQUIER inserción hecha por una sesión no-admin
-- — incluida la auto-respuesta insertada por insertar_auto_respuesta_
-- soporte() (que corre con la sesión del propio usuario, aunque sea
-- SECURITY DEFINER). Eso pisaba el leido_admin=true que esa función
-- pedía, y listar_conversaciones_soporte() cuenta "sin responder" por
-- leido_admin=false — el aviso automático terminaba inflando el badge
-- del admin como si fuera un mensaje real esperando respuesta.
--
-- Fix: el trigger exime la auto-respuesta de ese forzado, pero SOLO si
-- remitente_id es NULL — no alcanza con mirar es_auto_respuesta sola,
-- porque esa columna no tiene ninguna restricción propia y un usuario
-- podría insertar un mensaje DIRECTO (sin pasar por la RPC) con
-- es_auto_respuesta=true para saltarse el límite de frecuencia. La
-- policy de insert exige remitente_id = auth.uid() (nunca null para una
-- sesión autenticada), así que remitente_id NULL solo lo puede producir
-- la función SECURITY DEFINER — nunca un insert directo del cliente.
-- ============================================================

create or replace function public.limitar_frecuencia_mensajes_soporte()
returns trigger as $$
declare
  v_recientes int;
begin
  new.created_at := now();

  if new.es_auto_respuesta and new.remitente_id is null then
    return new;
  end if;

  -- El admin responde muchas conversaciones seguidas: no se le limita.
  if public.es_admin() then
    return new;
  end if;

  -- Un usuario no puede marcar su propio mensaje como ya leído por el admin.
  new.leido_admin := false;

  select count(*) into v_recientes
  from public.mensajes_soporte
  where remitente_id = new.remitente_id
    and created_at > now() - interval '1 minute';

  if v_recientes >= 10 then
    raise exception 'Estás enviando mensajes demasiado rápido. Espera un momento antes de volver a escribir.';
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
