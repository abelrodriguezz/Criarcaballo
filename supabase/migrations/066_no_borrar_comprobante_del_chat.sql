-- ============================================================
-- MIGRACIÓN 066: borrar un depósito ya NO borra la foto del chat de soporte
-- Pegar en Supabase → SQL Editor → Run (después de 001-065)
--
-- Decisión explícita del usuario (2026-09-28): cuando el admin borra un
-- depósito (típicamente para dejar que el usuario reintente), la foto que
-- quedó espejada en el chat de soporte debe conservarse como registro de
-- la conversación -- no debe desaparecer.
--
-- Se quita del trigger AFTER DELETE (revertir_saldo_al_borrar_deposito,
-- migración 053, extendido en 057) la parte que borraba el archivo físico
-- del bucket (net.http_delete) y la que ponía en null
-- mensajes_soporte.imagen_path. Se conserva intacta la reversión de saldo
-- y de comisión de referido -- eso sigue siendo correcto y necesario.
--
-- Efecto en la limpieza automática de 5 días (limpiar_comprobantes_
-- vencidos, migración 046/055): una vez borrado el depósito, su
-- comprobante_path ya no existe en depositos_simulados, así que esa foto
-- vuelve a ser un adjunto de chat normal -- si pasan 5 días, el cron la
-- limpia como cualquier otra imagen de soporte (esto es correcto: mientras
-- el depósito existía, la foto era un comprobante permanente; una vez
-- borrado el depósito, ya no hay nada financiero que proteger para
-- siempre, pero se mantiene visible en el chat como conversación normal).
-- ============================================================

create or replace function public.revertir_saldo_al_borrar_deposito()
returns trigger as $$
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

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
