import type { SupabaseClient } from "@supabase/supabase-js";

// Sin "use server": este módulo solo exporta helpers que importan las
// Server Actions de verdad (chat.ts, depositos.ts). Un archivo "use server"
// solo puede exportar funciones async, así que las constantes de abajo no
// podrían vivir ahí.

export const TIPOS_IMAGEN_PERMITIDOS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
export const TAMANO_MAXIMO_IMAGEN = 5 * 1024 * 1024; // 5 MB, igual que el bucket

/** ¿Los primeros bytes del archivo son de verdad un JPG/PNG/WEBP? */
export async function firmaCoincide(archivo: File, tipo: string): Promise<boolean> {
  const b = new Uint8Array(await archivo.slice(0, 12).arrayBuffer());
  if (tipo === "image/jpeg") return b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
  if (tipo === "image/png")
    return b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47;
  if (tipo === "image/webp")
    return (
      String.fromCharCode(...b.slice(0, 4)) === "RIFF" &&
      String.fromCharCode(...b.slice(8, 12)) === "WEBP"
    );
  return false;
}

/**
 * Sube un comprobante (chat de soporte o depósito) a la carpeta de la
 * conversación/usuario (usuarioIdCarpeta, no necesariamente quien lo sube —
 * así el admin puede subir dentro de la conversación de un usuario).
 * Devuelve el path guardado, o un error si algo no pasó validación. Las
 * políticas de storage.objects (migración 045) son las que de verdad deciden
 * quién puede escribir ahí — esto solo valida tipo/tamaño para dar un
 * mensaje de error claro antes de intentarlo.
 */
export async function subirComprobante(
  supabase: SupabaseClient,
  usuarioIdCarpeta: string,
  archivo: File,
  // Opcional: el flujo de depósito (i18n ES/EN) pasa sus textos traducidos;
  // sin esto un usuario en inglés veía el rechazo de un archivo falso en
  // español. El chat de soporte sigue usando los textos por defecto.
  mensajes: { tipoInvalido: string; muyPesada: string } = {
    tipoInvalido: "La imagen debe ser JPG, PNG o WEBP.",
    muyPesada: "La imagen no puede pesar más de 5 MB.",
  }
): Promise<{ path: string | null; error: string | null }> {
  if (archivo.size === 0) return { path: null, error: null };

  const extension = TIPOS_IMAGEN_PERMITIDOS[archivo.type];
  if (!extension) {
    return { path: null, error: mensajes.tipoInvalido };
  }
  if (archivo.size > TAMANO_MAXIMO_IMAGEN) {
    return { path: null, error: mensajes.muyPesada };
  }
  // archivo.type lo pone el navegador según la EXTENSIÓN: un PDF (o
  // cualquier cosa) renombrado a .png pasaba como image/png, se guardaba
  // en el bucket y salía como imagen rota. Se comprueba la firma real.
  if (!(await firmaCoincide(archivo, archivo.type))) {
    return { path: null, error: mensajes.tipoInvalido };
  }

  const path = `${usuarioIdCarpeta}/${crypto.randomUUID()}.${extension}`;
  const { error } = await supabase.storage
    .from("comprobantes-soporte")
    .upload(path, archivo, { contentType: archivo.type });

  if (error) {
    return { path: null, error: "No se pudo subir la imagen. Intenta de nuevo." };
  }
  return { path, error: null };
}
