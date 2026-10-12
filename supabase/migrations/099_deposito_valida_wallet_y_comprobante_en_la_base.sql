-- ============================================================
-- MIGRACIÓN 099: la wallet "mostrada" y el comprobante de un depósito se
-- validan en la BASE, no solo en la Server Action
-- Pegar en Supabase → SQL Editor → Run (después de 001-098)
--
-- Hallazgo de QA (2026-10-12) sobre el commit d6dfa0c: el fix de
-- registrarDepositoSimulado() (solo guardar wallet_mostrada si coincide con
-- obtener_wallets_admin()) se podía saltar por completo insertando DIRECTO
-- en depositos_simulados vía PostgREST con la anon key + el JWT del propio
-- usuario: la policy "usuario registra su propia simulacion" (057) no mira
-- wallet_mostrada para nada. Reproducido contra la base real con una cuenta
-- descartable:
--   insert into depositos_simulados (usuario_id, monto, wallet_mostrada,
--     comprobante_path) values (auth.uid(), 5, '0xINVENTADA...',
--     '<uid>/<uuid cualquiera>.png')
--   → aceptado, con la wallet inventada guardada tal cual.
-- El mismo insert también demostró que el comprobante "obligatorio" (054)
-- se puede saltar: el check de formato (057) solo valida el TEXTO del path,
-- no que la imagen exista en el bucket — un path con un UUID inventado
-- pasa, y el admin recibe un depósito sin ninguna imagen detrás.
--
-- Fix (trigger BEFORE INSERT, aplica a cualquier camino de inserción):
--   - wallet_mostrada que no esté entre las wallets de depósito
--     configuradas AHORA (obtener_wallets_admin) → se guarda null. Misma
--     regla que la Server Action: es un campo informativo, no se rechaza
--     el depósito por esto.
--   - comprobante_path que no exista como objeto en el bucket
--     comprobantes-soporte → se rechaza el insert. La Server Action sube la
--     imagen ANTES de insertar, así que el flujo normal nunca choca con
--     esto (y si chocara, su rama de error ya limpia la imagen huérfana).
-- ============================================================

create or replace function public.validar_deposito_simulado_al_insertar()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.wallet_mostrada is not null
     and not (new.wallet_mostrada = any(public.obtener_wallets_admin())) then
    new.wallet_mostrada := null;
  end if;

  if new.comprobante_path is not null
     and not exists (
       select 1 from storage.objects
       where bucket_id = 'comprobantes-soporte'
         and name = new.comprobante_path
     ) then
    raise exception 'El comprobante del depósito no existe. Vuelve a adjuntar la imagen.';
  end if;

  return new;
end;
$$;

revoke all on function public.validar_deposito_simulado_al_insertar() from public, anon, authenticated;

drop trigger if exists antes_de_insertar_deposito_simulado on public.depositos_simulados;
create trigger antes_de_insertar_deposito_simulado
  before insert on public.depositos_simulados
  for each row execute function public.validar_deposito_simulado_al_insertar();
