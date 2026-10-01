-- ============================================================
-- MIGRACIÓN 083: el pick se borra solo cuando se cierra su última
-- operación abierta, y nunca se puede borrar con operaciones pendientes
-- Pegar en Supabase → SQL Editor → Run (después de 001-082)
--
-- Hallazgo real del dueño del proyecto (2026-10-01): con la migración 082
-- sola, un usuario que YA había operado un pick quedaba bloqueado de
-- repetirlo, pero alguien que nunca había operado ESE pick sí podía
-- abrir una posición nueva sobre él después de que el admin liquidó la
-- sesión de los demás -- el pick seguía "vigente" en pantalla hasta que
-- el admin lo borrara a mano.
--
-- Decisión del dueño del proyecto: en vez de agregar un estado "cerrado"
-- al pick (lo que se había planteado primero), que el pick se BORRE solo,
-- automáticamente, en el mismo momento en que se cierra su última
-- operación abierta -- así no hay ventana de tiempo ni paso manual que el
-- admin se pueda saltar. abrir_operacion YA rechaza cualquier apertura si
-- no hay un pick vigente ("Ese activo no es el pick del día vigente."),
-- así que borrar el pick alcanza por sí solo, sin tocar esa función.
--
-- La trazabilidad que pidió el dueño del proyecto (saber por cuál pick se
-- pagó una ganancia, aunque el pick ya no exista) no se pierde: el símbolo
-- (activo) queda guardado directo en operaciones_simuladas.activo y en
-- ganancias_concursos.concepto ("Trade del día — BITCOIN"), columnas de
-- texto independientes de la fila de pick_del_dia.
--
-- Seguro adicional: un trigger BEFORE DELETE en pick_del_dia bloquea CUALQUIER
-- borrado (manual, desde el botón "Eliminar" del admin, o por SQL directo)
-- mientras ese pick todavía tenga una operación en estado 'abierta' -- el
-- problema real que se reportó fue causado por borrar el pick ANTES de
-- cerrar la operación de praxedes@gmail.com; con este seguro eso ya no se
-- puede repetir ni por accidente. El borrado automático de más abajo nunca
-- choca con este seguro porque solo se dispara cuando ya no queda NINGUNA
-- operación abierta de ese pick.
-- ============================================================

create or replace function public.proteger_borrado_pick_del_dia()
returns trigger as $$
begin
  if exists (
    select 1 from public.operaciones_simuladas
    where pick_id = old.id and estado = 'abierta'
  ) then
    raise exception 'Este pick todavía tiene operaciones abiertas. Ciérralas primero desde "Cerrar todas las operaciones abiertas".';
  end if;
  return old;
end;
$$ language plpgsql
   set search_path = pg_catalog, public, pg_temp;

drop trigger if exists antes_de_borrar_pick_del_dia on public.pick_del_dia;
create trigger antes_de_borrar_pick_del_dia
  before delete on public.pick_del_dia
  for each row execute function public.proteger_borrado_pick_del_dia();

revoke execute on function public.proteger_borrado_pick_del_dia() from public, anon, authenticated;

create or replace function public.admin_cerrar_operacion(
  p_operacion_id uuid,
  p_precio_entrada numeric,
  p_precio_salida numeric,
  p_hora_entrada timestamptz default null,
  p_hora_cierre timestamptz default null
) returns public.operaciones_simuladas as $$
declare
  v_operacion public.operaciones_simuladas;
  v_cantidad numeric;
  v_ganancia numeric;
  v_cerrado_en timestamptz := coalesce(p_hora_cierre, now());
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede cerrar la operación de otro usuario.';
  end if;
  if p_precio_entrada is null or p_precio_entrada = 'NaN'::numeric or p_precio_entrada <= 0 then
    raise exception 'El precio de entrada debe ser mayor a cero.';
  end if;
  if p_precio_salida is null or p_precio_salida = 'NaN'::numeric or p_precio_salida <= 0 then
    raise exception 'El precio de salida debe ser mayor a cero.';
  end if;
  if p_hora_entrada is not null and p_hora_cierre is not null
     and p_hora_entrada >= p_hora_cierre then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  select * into v_operacion
  from public.operaciones_simuladas
  where id = p_operacion_id and estado = 'abierta'
  for update;

  if v_operacion.id is null then
    raise exception 'Operación no encontrada o ya cerrada.';
  end if;

  if coalesce(p_hora_entrada, v_operacion.created_at) >= v_cerrado_en then
    raise exception 'La hora de entrada debe ser anterior a la hora de cierre.';
  end if;

  v_cantidad := v_operacion.monto_usado / p_precio_entrada;

  v_ganancia := case
    when v_operacion.tipo = 'compra'
      then (p_precio_salida - p_precio_entrada) * v_cantidad
    else (p_precio_entrada - p_precio_salida) * v_cantidad
  end;
  v_ganancia := floor(v_ganancia * 100) / 100;
  v_ganancia := greatest(v_ganancia, -v_operacion.monto_usado);

  update public.operaciones_simuladas
  set precio_entrada = p_precio_entrada,
      cantidad = v_cantidad,
      precio_salida = p_precio_salida,
      ganancia_perdida = v_ganancia,
      estado = 'cerrada',
      cerrado_en = v_cerrado_en,
      created_at = coalesce(p_hora_entrada, created_at)
  where id = p_operacion_id
  returning * into v_operacion;

  update public.saldo_virtual
  set saldo_usd = greatest(0, saldo_usd + v_operacion.monto_usado),
      actualizado_en = now()
  where usuario_id = v_operacion.usuario_id;

  if v_ganancia > 0 then
    insert into public.ganancias_concursos (
      usuario_id, monto, concepto, creado_por, origen, operacion_id
    ) values (
      v_operacion.usuario_id, v_ganancia, 'Trade del día — ' || v_operacion.activo,
      auth.uid(), 'trade', v_operacion.id
    );
  end if;

  -- El núcleo del arreglo: si esta era la última operación abierta de su
  -- pick, el pick se borra solo -- nadie (haya operado o no) puede abrir
  -- nada sobre él porque abrir_operacion ya rechaza cuando no hay pick
  -- vigente. El trigger de arriba nunca bloquea este DELETE porque la
  -- condición "not exists" ya garantiza cero operaciones abiertas.
  if v_operacion.pick_id is not null
     and not exists (
       select 1 from public.operaciones_simuladas
       where pick_id = v_operacion.pick_id and estado = 'abierta'
     ) then
    delete from public.pick_del_dia where id = v_operacion.pick_id;
  end if;

  return v_operacion;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;
