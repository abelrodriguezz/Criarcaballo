-- ============================================================
-- MIGRACIÓN 067: Historial de señales consistente
-- Pegar en Supabase → SQL Editor → Run (después de 001-066)
--
-- QA funcional de /senales (2026-09-29). Tres correcciones:
--
-- 1) UNA SEÑAL CERRADA SE PODÍA EDITAR Y EL HISTORIAL QUEDABA INCOHERENTE.
--    El botón "Editar" seguía visible en las tarjetas ya cerradas. Al
--    cambiarle entrada o take profit a una señal con "TP tocado", la
--    tarjeta pública mostraba p. ej. "Entrada 90000 · TP 30000" junto a
--    "Cerró en 20000 (+76.31%)" — el precio de cierre y el porcentaje se
--    calcularon con los niveles viejos y nadie los recalcula. En la base
--    ya había un caso real así (TP 130000 con "cerró en 120000").
--    Ahora, una vez que la señal tiene resultado, sus niveles (par, tipo,
--    entrada, SL, TP) quedan congelados; la razón se puede seguir
--    corrigiendo. La UI además deja de mostrar "Editar" en las cerradas.
--
-- 2) LA FECHA DE CIERRE AUTOMÁTICO ERA LA DE LA VISITA, NO LA DEL TOQUE.
--    El chequeo de TP/SL corre al cargar /senales (no hay cron), así que
--    cerrado_en quedaba con la hora en que alguien abrió la página, que
--    puede ser horas o días después de que el precio tocara el nivel (se
--    vio una señal que tocó TP a la 01:31 UTC y quedó cerrada a las 13:17).
--    El filtro "desde/hasta" del historial usa esa fecha. Nueva versión de
--    cerrar_senal_automatica con un cuarto parámetro: la hora de la vela
--    que tocó el nivel, acotada entre la publicación de la señal y now().
--    La versión de 3 parámetros se conserva tal cual para que el servidor
--    ya desplegado siga funcionando hasta el próximo deploy.
--
-- 3) creado_por NUNCA SE LLENABA en senales (todas las filas en NULL): el
--    formulario del admin no lo manda. Se pone auth.uid() por defecto.
-- ============================================================

-- 1) Niveles congelados una vez cerrada ---------------------------------

create or replace function public.senales_congelar_cerradas()
returns trigger as $$
begin
  if old.resultado is not null and (
       new.par is distinct from old.par
    or new.tipo is distinct from old.tipo
    or new.entrada is distinct from old.entrada
    or new.stop_loss is distinct from old.stop_loss
    or new.take_profit is distinct from old.take_profit
  ) then
    raise exception 'Esta señal ya está cerrada: sus niveles no se pueden cambiar (solo la razón). Si hubo un error, elimínala y publícala de nuevo.';
  end if;
  return new;
end;
$$ language plpgsql
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists senales_congelar_cerradas on public.senales;
create trigger senales_congelar_cerradas
  before update on public.senales
  for each row execute function public.senales_congelar_cerradas();

-- 2) Cierre automático con la hora real del toque ------------------------

create or replace function public.cerrar_senal_automatica(
  p_senal_id uuid,
  p_resultado text,
  p_secreto text,
  p_tocado_en timestamptz
) returns void as $$
declare
  v_senal public.senales;
  v_precio numeric;
  v_porcentaje numeric;
  v_cerrado_en timestamptz;
begin
  if not public.secreto_servidor_ok(p_secreto) then
    raise exception 'Solo la aplicación puede cerrar señales automáticamente.';
  end if;
  if p_resultado not in ('tp', 'sl') then
    raise exception 'Resultado inválido.';
  end if;

  select * into v_senal
  from public.senales
  where id = p_senal_id and estado = 'activa' and resultado is null
  for update;

  if v_senal.id is null then
    return; -- ya estaba cerrada: no hay nada que hacer
  end if;

  v_precio := case when p_resultado = 'tp'
                   then v_senal.take_profit
                   else v_senal.stop_loss end;

  if v_precio is null then
    raise exception 'La señal no tiene definido ese nivel.';
  end if;

  v_porcentaje := case
    when v_senal.tipo = 'compra'
      then ((v_precio - v_senal.entrada) / v_senal.entrada) * 100
    else ((v_senal.entrada - v_precio) / v_senal.entrada) * 100
  end;

  -- La vela que tocó el nivel no puede ser anterior a la publicación ni
  -- posterior a ahora; sin dato, se usa now() como antes.
  v_cerrado_en := least(greatest(coalesce(p_tocado_en, now()), v_senal.created_at), now());

  update public.senales
  set estado = 'cerrada',
      resultado = p_resultado,
      precio_cierre = v_precio,
      porcentaje_resultado = v_porcentaje,
      cerrado_en = v_cerrado_en
  where id = p_senal_id;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke execute on function public.cerrar_senal_automatica(uuid, text, text, timestamptz) from public;
grant execute on function public.cerrar_senal_automatica(uuid, text, text, timestamptz) to anon, authenticated;

-- 3) Quién publicó la señal ---------------------------------------------

alter table public.senales alter column creado_por set default auth.uid();
