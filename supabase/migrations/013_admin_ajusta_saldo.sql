-- ============================================================
-- MIGRACIÓN 013: Admin puede ajustar el saldo virtual de un usuario
-- Pegar en Supabase → SQL Editor → Run (después de 001-012)
--
-- Desde la migración 010, nadie puede hacer UPDATE directo a
-- saldo_virtual (solo los RPC abrir_operacion/cerrar_operacion, que
-- siempre operan sobre auth.uid() — el propio usuario). Esta función es
-- la única forma de que un admin le sume o reste saldo virtual a OTRO
-- usuario (ej. para corregir un error o darle más saldo de práctica).
-- ============================================================

create or replace function public.admin_agregar_saldo(
  p_usuario_id uuid,
  p_monto numeric
) returns public.saldo_virtual as $$
declare
  v_saldo public.saldo_virtual;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede ajustar el saldo de otro usuario.';
  end if;
  if p_monto is null or p_monto = 0 then
    raise exception 'El monto debe ser distinto de cero.';
  end if;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + p_monto),
      actualizado_en = now()
  where usuario_id = p_usuario_id
  returning * into v_saldo;

  if v_saldo.usuario_id is null then
    raise exception 'Este usuario no tiene saldo virtual inicializado.';
  end if;

  return v_saldo;
end;
$$ language plpgsql security definer;

grant execute on function public.admin_agregar_saldo(uuid, numeric) to authenticated;
