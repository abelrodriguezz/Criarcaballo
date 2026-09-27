-- ============================================================
-- MIGRACIÓN 054: comprobante de imagen obligatorio al depositar
-- Pegar en Supabase → SQL Editor → Run (después de 001-053)
--
-- Nueva columna con el path del comprobante en el mismo bucket privado que
-- ya usa el chat de soporte (comprobantes-soporte, migración 045). Se deja
-- NULLABLE a nivel de tabla a propósito: los depósitos ya existentes (antes
-- de este cambio) no tienen comprobante y no hay forma de pedírselo
-- retroactivamente. La obligatoriedad se impone solo en el INSERT (deposito
-- nuevo) vía la policy de abajo, nunca en el UPDATE — así
-- admin_alternar_pago_deposito puede seguir marcando como pagado un
-- depósito viejo sin comprobante sin que un CHECK de tabla lo bloquee.
-- ============================================================

alter table public.depositos_simulados
  add column if not exists comprobante_path text;

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
  );
