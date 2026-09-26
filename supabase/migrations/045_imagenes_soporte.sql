-- ============================================================
-- MIGRACIÓN 045: imágenes de comprobante en el chat de soporte
-- Pegar en Supabase → SQL Editor → Run (después de 001-044)
--
-- Bucket privado (no público): un comprobante de pago no debe quedar
-- accesible por link directo a cualquiera que lo adivine. Se sirve
-- siempre por URL firmada de corta duración, generada bajo las mismas
-- políticas de RLS de abajo.
--
-- Convención de ruta: {usuario_id_de_la_conversación}/{uuid}.{ext} — NO
-- el id de quien sube el archivo. Así el admin puede subir dentro de la
-- conversación de un usuario, y las políticas de lectura/escritura se
-- basan en esa carpeta, no en quién es el remitente.
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'comprobantes-soporte',
  'comprobantes-soporte',
  false,
  5242880, -- 5 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy "sube comprobante a su conversacion, admin a cualquiera"
  on storage.objects for insert
  with check (
    bucket_id = 'comprobantes-soporte'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.es_admin())
  );

create policy "ve comprobante de su conversacion, admin ve todos"
  on storage.objects for select
  using (
    bucket_id = 'comprobantes-soporte'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.es_admin())
  );

alter table public.mensajes_soporte
  add column if not exists imagen_path text;
