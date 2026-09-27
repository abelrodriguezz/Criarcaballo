-- ============================================================
-- MIGRACIÓN 055: no borrar del storage la imagen que además es el
-- comprobante oficial de un depósito
-- Pegar en Supabase → SQL Editor → Run (después de 001-054)
--
-- Al registrar un depósito (migración 054) se copia el mismo path del
-- comprobante en un mensaje del chat de soporte, para que el usuario y el
-- admin lo vean ahí (así lo pidió el usuario). Pero limpiar_comprobantes_
-- vencidos() (migración 046) borra CUALQUIER imagen de mensajes_soporte
-- con más de 5 días vía la API real de Storage -- si ese mensaje comparte
-- el path con depositos_simulados.comprobante_path, el archivo físico
-- desaparecería y el registro permanente del depósito quedaría con una
-- imagen rota, aunque su propia columna nunca se tocó.
--
-- El comprobante de un depósito es un registro financiero permanente (uno
-- por usuario en toda su existencia) y no debe expirar como un adjunto
-- cualquiera de chat -- se excluye de la limpieza.
-- ============================================================

create or replace function public.limpiar_comprobantes_vencidos()
returns void as $$
declare
  r record;
  v_service_key text;
begin
  select valor into v_service_key
  from public.config_servidor
  where clave = 'supabase_service_role_key';

  if v_service_key is null or v_service_key = 'FALTA-CONFIGURAR-ESTA-CLAVE' then
    raise notice 'supabase_service_role_key sin configurar todavia, se omite la limpieza de comprobantes';
    return;
  end if;

  for r in
    select ms.id, ms.imagen_path
    from public.mensajes_soporte ms
    where ms.imagen_path is not null
      and ms.created_at < now() - interval '5 days'
      and not exists (
        select 1 from public.depositos_simulados d
        where d.comprobante_path = ms.imagen_path
      )
  loop
    -- net.http_delete encola la petición (asíncrono, no bloquea el loop) —
    -- suficiente para un job de limpieza que no necesita confirmar cada
    -- borrado uno por uno.
    perform net.http_delete(
      url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || r.imagen_path,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_service_key,
        'apikey', v_service_key
      )
    );
    -- Se limpia la referencia ya mismo (no espera la respuesta HTTP): el
    -- mensaje de texto (si tenía) se conserva, solo se quita el link a una
    -- imagen que ya está en proceso de borrarse.
    update public.mensajes_soporte
    set imagen_path = null
    where id = r.id;
  end loop;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

revoke all on function public.limpiar_comprobantes_vencidos() from public, anon, authenticated;
