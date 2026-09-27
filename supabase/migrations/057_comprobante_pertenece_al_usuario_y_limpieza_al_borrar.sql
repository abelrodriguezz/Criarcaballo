-- ============================================================
-- MIGRACIÓN 057: el comprobante de depósito debe pertenecer al usuario que
-- deposita, y borrar un depósito limpia la foto vieja (storage + chat)
-- Pegar en Supabase → SQL Editor → Run (después de 001-056)
--
-- Hallazgo del QA de hoy (Fase 2, comprobante obligatorio): la policy de
-- INSERT (migración 054) exigía que `comprobante_path` no fuera null, pero
-- no validaba que esa ruta perteneciera de verdad al usuario que deposita.
-- Alguien saltándose el formulario (llamando la API directo) podía mandar
-- una ruta inventada o la de OTRO usuario. Impacto bajo en la práctica
-- (un depósito por usuario en toda su existencia, y nada se acredita sin
-- que el admin confirme viendo la foto primero), pero el usuario pidió
-- cerrarlo de todos modos.
--
-- Fix 1: la policy ahora exige que el path empiece con el propio
-- auth.uid() (misma convención de carpeta que ya usa subirComprobante() en
-- lib/actions/comprobantes.ts: "{usuario_id}/{uuid}.ext").
--
-- Fix 2 (pedido explícito del usuario): cuando el admin borra un depósito
-- (típicamente para dejar que el usuario intente de nuevo, ya que solo
-- puede depositar una vez), la foto vieja del comprobante NO debe quedar
-- dando vueltas ni en el bucket ni en el mensaje de chat que la espejaba.
-- Se extiende el trigger AFTER DELETE de la migración 053
-- (revertir_saldo_al_borrar_deposito) para que, además de revertir el
-- saldo si estaba pagado, borre el archivo físico vía la API de Storage
-- (mismo mecanismo que el cron de limpieza de 5 días, migración 046 —
-- Supabase no permite borrar storage.objects por SQL directo) y limpie la
-- referencia en mensajes_soporte, sin importar si el depósito estaba
-- pagado o no.
-- ============================================================

drop policy if exists "usuario registra su propia simulacion" on public.depositos_simulados;
create policy "usuario registra su propia simulacion"
  on public.depositos_simulados for insert
  with check (
    usuario_id = auth.uid()
    and not public.es_admin()
    and pagado = false
    and pagado_en is null
    and pagado_por is null
    and revisado_por_admin = false
    and comprobante_path is not null
    and comprobante_path like (auth.uid()::text || '/%')
  );

create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
declare
  v_service_key text;
begin
  if old.pagado then
    update public.saldo_virtual
    set saldo_usd = greatest(0, saldo_usd - old.monto),
        actualizado_en = now()
    where usuario_id = old.usuario_id;

    delete from public.ganancias_concursos
    where invitado_id = old.usuario_id
      and origen = 'referido'
      and pagado = false;
  end if;

  -- El comprobante de ESTE depósito ya no tiene ningún registro que lo
  -- respalde: se borra el archivo físico (igual que limpiar_comprobantes_
  -- vencidos, migración 046) y se limpia su espejo en el chat, sin
  -- importar si el depósito estaba pagado o no.
  if old.comprobante_path is not null then
    select valor into v_service_key
    from public.config_servidor
    where clave = 'supabase_service_role_key';

    if v_service_key is not null and v_service_key <> 'FALTA-CONFIGURAR-ESTA-CLAVE' then
      perform net.http_delete(
        url := 'https://uxldpbefitjgxhhsjttb.supabase.co/storage/v1/object/comprobantes-soporte/' || old.comprobante_path,
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_service_key,
          'apikey', v_service_key
        )
      );
    end if;

    update public.mensajes_soporte
    set imagen_path = null
    where imagen_path = old.comprobante_path;
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;
