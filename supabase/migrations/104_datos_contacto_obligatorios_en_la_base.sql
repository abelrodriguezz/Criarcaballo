-- ============================================================
-- MIGRACIÓN 104: nombre/apellido/cédula/teléfono obligatorios TAMBIÉN
-- en la base, no solo en el formulario
-- Pegar en Supabase → SQL Editor → Run (después de 001-103)
--
-- QA con Opus (2026-10-13) sobre la migración de ayer (DatosContactoForm
-- ahora exige los 4 campos): confirmó que es un hueco real -- un usuario
-- autenticado puede llamar
-- `supabase.from("usuarios").update({ nombre: null, ... })` directo con
-- su propio JWT (sin pasar por el formulario) y la base lo acepta sin
-- problema. También se podía guardar "   " (solo espacios), o un
-- teléfono tipo "abc" que no respeta el formato.
--
-- Trigger BEFORE UPDATE (mismo patrón que la migración 099 para
-- wallet/comprobante de depósito): solo se dispara cuando alguno de
-- estos 4 campos CAMBIA en el UPDATE (comparación IS DISTINCT FROM) --
-- así no afecta ningún otro update de la fila (rol, saldo, activo,
-- wallet...) ni rompe cuentas viejas/de prueba que ya tenían estos
-- campos en null y nadie los está tocando. En cuanto alguien intenta
-- cambiar cualquiera de los 4, exige que los 4 queden completos y bien
-- formados en la fila resultante -- igual que ya hace el formulario,
-- que siempre manda los 4 juntos.
--
-- A propósito NO se toca el INSERT de handle_new_user(): esa función
-- también la usan las cuentas creadas por fuera del formulario público
-- (Admin API con el service_role, el mecanismo que se usó para crear
-- todas las cuentas de prueba de este proyecto, incluida admin-tester) y
-- exigir estos campos ahí rompería ese flujo. El registro público
-- (RegistroForm.tsx) ya los exige del lado del cliente; este trigger
-- cierra el hueco de EDITAR, que es lo que encontró la QA.
-- ============================================================

create or replace function public.validar_datos_contacto_usuario()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.nombre is not distinct from old.nombre
     and new.apellido is not distinct from old.apellido
     and new.cedula is not distinct from old.cedula
     and new.telefono is not distinct from old.telefono then
    return new;
  end if;

  if new.nombre is null or trim(new.nombre) = '' then
    raise exception 'Ingresa tu nombre.';
  end if;
  if new.apellido is null or trim(new.apellido) = '' then
    raise exception 'Ingresa tu apellido.';
  end if;
  if new.cedula is null or new.cedula !~ '^[0-9]{3}-[0-9]{7}-[0-9]$' then
    raise exception 'La cédula debe tener el formato 001-1234567-8.';
  end if;
  if new.telefono is null or trim(new.telefono) = ''
     or new.telefono !~ '^[0-9+\-\s()]{6,30}$' then
    raise exception 'Ese teléfono no parece válido.';
  end if;

  return new;
end;
$$;

drop trigger if exists antes_de_actualizar_datos_contacto on public.usuarios;
create trigger antes_de_actualizar_datos_contacto
  before update on public.usuarios
  for each row execute function public.validar_datos_contacto_usuario();
