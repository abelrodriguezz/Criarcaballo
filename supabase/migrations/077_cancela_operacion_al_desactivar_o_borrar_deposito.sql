-- ============================================================
-- MIGRACIÓN 077: cancela la operación abierta al desactivar una cuenta o
-- al borrar el depósito que la financiaba
-- Pegar en Supabase → SQL Editor → Run (después de 001-076)
--
-- Duda de negocio de la fase de Gestión de usuarios (2026-09-29), resuelta:
-- desactivar una cuenta (o borrar un depósito ya gastado en una operación)
-- dejaba esa operación "abierta" para siempre, sin que nadie pudiera
-- cerrarla nunca (el usuario no puede, y el cierre en bloque del admin
-- exige que el símbolo siga siendo el pick vigente). Decisión: cancelarla
-- automáticamente.
--
-- Dos casos, con reglas de saldo distintas:
--   1) Desactivar la cuenta: el dinero sigue siendo legítimamente del
--      usuario (nada se revirtió), así que se le REPONE su monto_usado al
--      saldo — queda listo para cuando lo reactiven.
--   2) Borrar un depósito ya pagado: el fondeo mismo desaparece, así que
--      la operación se cancela SIN reponer nada (si se repusiera, sería
--      dinero que ya no existe).
-- En ambos casos: estado = 'cancelada' (se agrega como valor válido),
-- precio_salida y ganancia_perdida quedan en null/0 -- no es un resultado
-- de trading, es una anulación administrativa.
-- ============================================================

alter table public.operaciones_simuladas
  drop constraint if exists operaciones_simuladas_estado_check;

alter table public.operaciones_simuladas
  add constraint operaciones_simuladas_estado_check
  check (estado in ('abierta', 'cerrada', 'cancelada'));

-- 1) Desactivar la cuenta cancela su operación abierta y repone el saldo --

create or replace function public.cancelar_operacion_al_desactivar_cuenta()
returns trigger as $$
declare
  v_monto numeric;
begin
  if new.activo = false and old.activo = true then
    update public.operaciones_simuladas
    set estado = 'cancelada', cerrado_en = now(),
        precio_salida = null, ganancia_perdida = 0
    where usuario_id = new.id and estado = 'abierta'
    returning monto_usado into v_monto;

    if v_monto is not null then
      update public.saldo_virtual
      set saldo_usd = saldo_usd + v_monto, actualizado_en = now()
      where usuario_id = new.id;
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists cancelar_operacion_al_desactivar on public.usuarios;
create trigger cancelar_operacion_al_desactivar
  after update on public.usuarios
  for each row execute function public.cancelar_operacion_al_desactivar_cuenta();

-- 2) Borrar un depósito pagado cancela la operación SIN reponer el monto --
-- (mismo cuerpo que la 066, con este paso agregado al final).

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

    -- Con una sola operación abierta por usuario y esa operación usando
    -- siempre el saldo COMPLETO (migración 032), si hay una abierta es
    -- porque el dinero de este depósito (u otro) está atrapado ahí. El
    -- depósito que se está borrando ya no existe, así que ese dinero
    -- tampoco -- se anula la operación sin devolver nada.
    update public.operaciones_simuladas
    set estado = 'cancelada', cerrado_en = now(),
        precio_salida = null, ganancia_perdida = 0
    where usuario_id = old.usuario_id and estado = 'abierta';
  end if;

  return old;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
