-- ============================================================
-- MIGRACIÓN 059: bloquea path traversal en limpiar_comprobante_huerfano
-- Pegar en Supabase → SQL Editor → Run (después de 001-058)
--
-- Hallazgo de QA (2026-09-27) sobre la migración 058: la función nueva
-- solo validaba que p_path EMPEZARA con "<mi_uuid>/" (like) y que no
-- existiera tal cual en depositos_simulados.comprobante_path (=). Ninguna
-- de las dos validaciones detiene un p_path como:
--
--   "<mi_uuid>/../<otro_uuid>/<archivo_real>.png"
--
-- Ese path SÍ empieza con "<mi_uuid>/" (pasa el check "a"), y como cadena
-- literal NO es igual a ningún comprobante_path guardado -- aunque el
-- archivo señalado por "../<otro_uuid>/<archivo>.png" sí sea el de un
-- depósito ajeno, incluso uno ya con pagado = true (pasa el check "b").
-- La función igual llama a net.http_delete con esa URL, y se confirmó en
-- pruebas reales que el backend de Storage SÍ resuelve el "..", así que
-- termina borrando el archivo de OTRO usuario -- exactamente lo que la
-- migración 058 decía que era imposible por diseño.
--
-- Fix: además de exigir el prefijo "<mi_uuid>/", el resto del path después
-- de la carpeta debe ser un único segmento (sin más "/"), sin "..", y con
-- un charset seguro (coincide con cómo se generan hoy los paths reales:
-- "<uuid>/<uuid>.jpg|png|webp", ver subirComprobante() en
-- lib/actions/comprobantes.ts). Cualquier "/" o ".." adicional se rechaza
-- antes de siquiera llegar al check de depositos_simulados.
-- ============================================================

create or replace function public.limpiar_comprobante_huerfano(p_path text)
returns void as $$
declare
  v_usuario_id uuid := auth.uid();
  v_service_key text;
  v_resto text;
begin
  if v_usuario_id is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if p_path is null or p_path not like (v_usuario_id::text || '/%') then
    raise exception 'Solo puedes limpiar comprobantes de tu propia carpeta.';
  end if;

  v_resto := substring(p_path from length(v_usuario_id::text) + 2);

  -- El resto debe ser EXACTAMENTE un nombre de archivo: sin más "/", sin
  -- "..", charset seguro. Esto es lo que de verdad impide el traversal --
  -- el "not like" de arriba por sí solo NO bastaba.
  if v_resto is null
     or v_resto = ''
     or v_resto like '%/%'
     or v_resto like '%..%'
     or v_resto !~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'
  then
    raise exception 'Ruta de comprobante inválida.';
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
