-- ============================================================
-- MIGRACIÓN 058: limpiar el comprobante huérfano cuando se sube la imagen
-- pero el registro del depósito falla justo después
-- Pegar en Supabase → SQL Editor → Run (después de 001-057)
--
-- Hallazgo del QA de hoy (Fase 4): registrarDepositoSimulado() sube la
-- imagen al bucket ANTES de insertar la fila en depositos_simulados. Si el
-- insert falla (ej. una carrera entre dos pestañas, o cualquier otro
-- error), la imagen ya subida se queda sin ningún depósito ni mensaje que
-- la referencie -- huérfana para siempre, porque el cron de limpieza de
-- 5 días (migración 046/055) solo mira mensajes_soporte, nunca el bucket
-- directamente.
--
-- No se le da a los usuarios un permiso general de DELETE sobre storage.
-- objects (eso permitiría borrar el comprobante de un depósito YA
-- registrado antes de que el admin lo revise). En su lugar, esta RPC solo
-- deja borrar un path que (a) es de la propia carpeta del usuario que
-- llama, Y (b) no está referenciado por NINGÚN depósito real -- así nunca
-- se puede usar para borrar un comprobante legítimo.
-- ============================================================

create or replace function public.limpiar_comprobante_huerfano(p_path text)
returns void as $$
declare
  v_usuario_id uuid := auth.uid();
  v_service_key text;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_path is null or p_path not like (v_usuario_id::text || '/%') then
    raise exception 'Solo puedes limpiar comprobantes de tu propia carpeta.';
  end if;

  if exists (
    select 1 from public.depositos_simulados where comprobante_path = p_path
  ) then
    raise exception 'Ese comprobante pertenece a un depósito registrado, no se puede borrar.';
  end if;

  select valor into v_service_key
  from public.config_servidor
  where clave = 'supabase_service_role_key';

  if v_service_key is null or v_service_key = 'FALTA-CONFIGURAR-ESTA-CLAVE' then
    return; -- sin la clave configurada, no se puede llamar a la API de Storage
  end if;

  perform net.http_delete(
    url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || p_path,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'apikey', v_service_key
    )
  );
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

revoke all on function public.limpiar_comprobante_huerfano(text) from public, anon;
grant execute on function public.limpiar_comprobante_huerfano(text) to authenticated;
