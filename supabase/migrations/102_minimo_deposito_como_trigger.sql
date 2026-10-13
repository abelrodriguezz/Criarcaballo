-- ============================================================
-- MIGRACIÓN 102: el mínimo de depósito pasa de CHECK a trigger BEFORE INSERT
-- Pegar en Supabase → SQL Editor → Run (después de 001-101)
--
-- QA con Opus (2026-10-12) sobre la migración 101: un `check (...) not
-- valid` no deja de aplicarse a las filas viejas -- NOT VALID solo evita el
-- escaneo de validación inicial al crear el constraint, pero CUALQUIER
-- UPDATE posterior sobre una fila vieja (aunque no toque la columna monto)
-- se revalida igual. Reproducido en una transacción revertida: un
-- `update ... set pagado = true` sobre una fila con monto < 500 fallaba con
-- "violates check constraint". Hoy no hay ninguna fila así en
-- depositos_simulados, así que no rompió nada en producción, pero
-- admin_alternar_pago_deposito y el UPDATE masivo de marcarDepositosRevisados
-- habrían quedado rotos (el segundo en silencio, sin tirar error) apenas
-- existiera una.
--
-- La intención real siempre fue "los depósitos NUEVOS tienen que ser de al
-- menos 500", no "toda fila de esta tabla, para siempre, incluso al
-- actualizar otra columna". Un trigger BEFORE INSERT (mismo patrón que la
-- migración 099 para wallet/comprobante) sí refleja eso: solo se evalúa al
-- crear la fila, nunca en un UPDATE.
-- ============================================================

alter table public.depositos_simulados
  drop constraint depositos_simulados_monto_minimo_check;

create or replace function public.validar_monto_minimo_deposito()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.monto < 500 then
    raise exception 'El depósito mínimo es 500 USDT.';
  end if;
  return new;
end;
$$;

drop trigger if exists antes_de_insertar_deposito_monto_minimo on public.depositos_simulados;
create trigger antes_de_insertar_deposito_monto_minimo
  before insert on public.depositos_simulados
  for each row execute function public.validar_monto_minimo_deposito();
