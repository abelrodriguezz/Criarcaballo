-- ============================================================
-- MIGRACIÓN 018: Cierre automático de señales por TP/SL
-- Pegar en Supabase → SQL Editor → Run (después de 001-017)
--
-- Agrega dónde/cuándo se cerró la señal (precio exacto, % de resultado,
-- fecha) y una función que cualquier sesión (incluso sin ser admin)
-- puede llamar para marcar el cierre automático — la lógica de "¿de
-- verdad tocó el nivel?" vive en el código de Next.js (compara contra
-- las velas de Binance), esta función solo aplica el resultado ya
-- decidido, evitando que las políticas de "solo admin edita señales"
-- bloqueen el cierre automático cuando quien visita la página no es admin.
-- ============================================================

alter table public.senales
  add column precio_cierre numeric,
  add column porcentaje_resultado numeric,
  add column cerrado_en timestamptz;

create or replace function public.cerrar_senal_automatica(
  p_senal_id uuid,
  p_resultado text,
  p_precio_cierre numeric,
  p_porcentaje numeric
) returns void as $$
  update public.senales
  set estado = 'cerrada',
      resultado = p_resultado,
      precio_cierre = p_precio_cierre,
      porcentaje_resultado = p_porcentaje,
      cerrado_en = now()
  where id = p_senal_id
    and estado = 'activa'
    and p_resultado in ('tp', 'sl');
$$ language sql security definer;

grant execute on function public.cerrar_senal_automatica(uuid, text, numeric, numeric) to authenticated, anon;
