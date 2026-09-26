-- ============================================================
-- MIGRACIÓN 046: job diario que borra comprobantes de más de 5 días
-- Pegar en Supabase → SQL Editor → Run (después de 001-045)
--
-- Supabase bloquea el borrado directo de storage.objects por SQL ("Direct
-- deletion from storage tables is not allowed. Use the Storage API
-- instead." — confirmado empíricamente el 2026-09-25) — así que el borrado
-- de verdad tiene que pasar por la API REST de Storage, que exige la
-- service_role key (una clave distinta a la anon key, con permisos
-- completos, que nunca debe llegar al navegador). Se guarda igual que
-- TRADING_SERVER_SECRET (migración 019): en config_servidor, con RLS sin
-- políticas, solo legible por funciones SECURITY DEFINER.
--
-- IMPORTANTE — paso manual pendiente después de correr esto: reemplazar
-- el valor de placeholder por la clave real:
--   update public.config_servidor
--   set valor = 'LA_SERVICE_ROLE_KEY_REAL', actualizado_en = now()
--   where clave = 'supabase_service_role_key';
-- (Project Settings → API Keys → "service_role", en el dashboard de
-- Supabase). Sin esto, la función se ejecuta todos los días pero no hace
-- nada — no falla, solo se queda esperando la clave.
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

insert into public.config_servidor (clave, valor)
values ('supabase_service_role_key', 'FALTA-CONFIGURAR-ESTA-CLAVE')
on conflict (clave) do nothing;

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
    select id, imagen_path
    from public.mensajes_soporte
    where imagen_path is not null
      and created_at < now() - interval '5 days'
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

select cron.schedule(
  'limpiar-comprobantes-soporte',
  '0 6 * * *', -- todos los días a las 6:00am UTC
  $$select public.limpiar_comprobantes_vencidos()$$
);
