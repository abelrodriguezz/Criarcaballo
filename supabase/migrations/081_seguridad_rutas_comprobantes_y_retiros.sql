-- ============================================================
-- MIGRACIÓN 081: auditoría AppSec (2026-09-30)
-- Pegar en Supabase → SQL Editor → Run (después de 001-080)
--
-- 1) ALTA: mensajes_soporte.imagen_path no tenía ninguna validación. Un
--    usuario normal, con su propio JWT y la anon key (PostgREST directo,
--    sin pasar por la Server Action), podía insertar o editar un mensaje
--    con imagen_path = 'su-uid/../../otro-bucket/archivo' (o la carpeta de
--    OTRO usuario) y además poner created_at en el pasado. El cron diario
--    limpiar_comprobantes_vencidos() arma la URL de Storage con ese valor y
--    hace el DELETE con la service_role key → borrado arbitrario de
--    archivos de Storage (el mismo tipo de traversal que la 059 cerró en
--    limpiar_comprobante_huerfano, pero por la otra puerta).
--    Además, created_at editable permitía saltarse el límite de 10
--    mensajes/minuto, y leido_admin editable permitía ocultarle al admin
--    los mensajes no leídos.
--
--    Arreglo: CHECK de formato exacto (<usuario_id>/<uuid>.<jpg|png|webp>,
--    lo único que genera subirComprobante()), created_at forzado a now() al
--    insertar, leido_admin solo lo toca un admin, imagen_path solo se puede
--    cambiar a NULL después de insertado, y el cron vuelve a validar la
--    ruta antes de llamar a Storage (defensa en profundidad).
--
-- 2) BAJA: mismo CHECK de formato para depositos_simulados.comprobante_path
--    (la policy solo exigía el prefijo 'uid/%', aceptaba 'uid/../x').
--
-- 3) MEDIA: políticas "qa test insert"/"qa test select" sobrantes de una
--    ronda de QA sobre el bucket qa-test-bucket: cualquiera, INCLUSO SIN
--    SESIÓN (anon), podía subir archivos sin límite de tamaño ni de tipo.
--
-- 4) BAJA: una solicitud de retiro ya procesada (pagado/rechazado) se podía
--    volver a 'pendiente' con un UPDATE directo (policy de admin) y pagarla
--    de nuevo, marcando como pagadas más ganancias de las retiradas. Ahora
--    el estado final es inmutable y monto/usuario/wallet no se editan.
--
-- 5) Higiene: se quita EXECUTE a anon/authenticated de funciones que solo
--    son de trigger.
-- ============================================================

-- 1) mensajes_soporte ------------------------------------------------------

alter table public.mensajes_soporte
  add constraint mensajes_soporte_imagen_path_formato check (
    imagen_path is null
    or imagen_path ~ (
      '^' || usuario_id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
    )
  );

create or replace function public.limitar_frecuencia_mensajes_soporte()
returns trigger as $$
declare
  v_recientes int;
begin
  -- Nadie elige la fecha de su mensaje: backdatear servía para saltarse
  -- este mismo límite y para que el cron de 5 días lo procesara ya.
  new.created_at := now();

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

create or replace function public.proteger_mensajes_soporte()
returns trigger as $$
begin
  if new.id is distinct from old.id
     or new.usuario_id is distinct from old.usuario_id
     or new.remitente_id is distinct from old.remitente_id
     or new.contenido is distinct from old.contenido
     or new.created_at is distinct from old.created_at then
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
    -- Defensa en profundidad: aunque el CHECK ya lo garantiza, nunca se
    -- manda a Storage (con la service_role key) una ruta que no sea
    -- exactamente <uuid>/<uuid>.<ext>.
    if r.imagen_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$' then
      perform net.http_delete(
        url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || r.imagen_path,
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_service_key,
          'apikey', v_service_key
        )
      );
    end if;

    update public.mensajes_soporte
    set imagen_path = null
    where id = r.id;
  end loop;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

-- 2) depositos_simulados ---------------------------------------------------

alter table public.depositos_simulados
  add constraint depositos_simulados_comprobante_path_formato check (
    comprobante_path is null
    or comprobante_path ~ (
      '^' || usuario_id::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
    )
  );

-- 3) bucket de QA abierto a anon -------------------------------------------

drop policy if exists "qa test insert" on storage.objects;
drop policy if exists "qa test select" on storage.objects;

-- 4) solicitudes_retiro: estado final inmutable ----------------------------

create or replace function public.proteger_solicitudes_retiro()
returns trigger as $$
begin
  if new.id is distinct from old.id
     or new.usuario_id is distinct from old.usuario_id
     or new.monto is distinct from old.monto
     or new.wallet_destino is distinct from old.wallet_destino
     or new.created_at is distinct from old.created_at then
    raise exception 'Los datos de una solicitud de retiro no se pueden modificar.';
  end if;

  if old.estado <> 'pendiente' and new.estado is distinct from old.estado then
    raise exception 'Esta solicitud ya fue procesada; su estado no se puede cambiar.';
  end if;

  return new;
end;
$$ language plpgsql
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_editar_solicitud_retiro on public.solicitudes_retiro;
create trigger antes_de_editar_solicitud_retiro
  before update on public.solicitudes_retiro
  for each row execute function public.proteger_solicitudes_retiro();

-- 5) funciones de trigger: no invocables por RPC ---------------------------

revoke execute on function public.cancelar_operacion_al_desactivar_cuenta() from public, anon, authenticated;
revoke execute on function public.revertir_saldo_al_borrar_deposito() from public, anon, authenticated;
revoke execute on function public.senales_congelar_cerradas() from public, anon, authenticated;
revoke execute on function public.proteger_solicitudes_retiro() from public, anon, authenticated;
