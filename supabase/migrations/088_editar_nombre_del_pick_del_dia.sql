-- ============================================================
-- MIGRACIÓN 088: el admin puede editar el nombre del pick del día
-- Pegar en Supabase → SQL Editor → Run (después de 001-087)
--
-- Pedido del dueño del proyecto (2026-10-05): antes, para cambiarle el
-- nombre a un pick ya creado había que eliminarlo y crear uno nuevo —
-- pero migración 083 ya hace eso automáticamente cuando se cierra su
-- última operación, así que "eliminar para renombrar" en realidad
-- bloqueaba a cualquiera que ya hubiera operado (abrir_operacion exige
-- que el pick siga existiendo). Ahora se puede renombrar sin borrar nada.
--
-- Las operaciones ya CERRADAS conservan su nombre histórico tal cual
-- (nunca se reescribe el pasado). Las que siguen ABIERTAS sí se renombran
-- junto con el pick: el formulario de "cerrar todas las operaciones"
-- agrupa por el texto `activo` de cada operación, no por pick_id — sin
-- este renombrado en cascada, cambiar el nombre a mitad del día dejaría
-- dos grupos distintos para cerrar (el nombre viejo y el nuevo) aunque
-- sea la misma señal, obligando al admin a escribir el mismo precio dos
-- veces.
-- ============================================================

create or replace function public.admin_editar_pick_del_dia(
  p_pick_id uuid,
  p_nuevo_activo text
) returns public.pick_del_dia as $$
declare
  v_activo text;
  v_pick public.pick_del_dia;
begin
  if not public.es_admin() then
    raise exception 'Solo un admin puede editar el pick del día.';
  end if;

  v_activo := upper(trim(coalesce(p_nuevo_activo, '')));
  if v_activo = '' then
    raise exception 'Ingresa el nombre del activo.';
  end if;
  if length(v_activo) > 30 then
    raise exception 'El nombre del activo no puede tener más de 30 caracteres.';
  end if;

  update public.pick_del_dia
  set activo = v_activo
  where id = p_pick_id
  returning * into v_pick;

  if v_pick.id is null then
    raise exception 'Pick no encontrado.';
  end if;

  update public.operaciones_simuladas
  set activo = v_activo
  where pick_id = p_pick_id and estado = 'abierta';

  return v_pick;
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp;

revoke all on function public.admin_editar_pick_del_dia(uuid, text) from public, anon;
grant execute on function public.admin_editar_pick_del_dia(uuid, text) to authenticated;
