"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { cuentaActiva } from "@/lib/auth/sesion";
import { exito, fallo, type Resultado } from "@/lib/actions/resultado";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { MensajeSoporte } from "@/lib/types";

/**
 * Los ids de usuario llegan desde el cliente (campo oculto del formulario,
 * segmento de la URL). RLS y las claves foráneas ya bloquean lo que
 * importa, pero validar el formato evita que un valor arbitrario llegue a
 * la consulta y termine en un error de Postgres con detalles internos en
 * el mensaje, o en un revalidatePath con una ruta inventada.
 */
const FORMATO_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const TIPOS_IMAGEN_PERMITIDOS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
const TAMANO_MAXIMO_IMAGEN = 5 * 1024 * 1024; // 5 MB, igual que el bucket

/**
 * Sube el comprobante (si vino uno) a la carpeta de la conversación
 * (usuarioIdConversacion, no quien lo sube — así el admin puede subir
 * dentro del chat de un usuario). Devuelve el path guardado, o null si no
 * se adjuntó nada. Las políticas de storage.objects (migración 045) son
 * las que de verdad deciden quién puede escribir ahí — esto solo valida
 * tipo/tamaño para dar un mensaje de error claro antes de intentarlo.
 */
async function subirComprobante(
  supabase: SupabaseClient,
  usuarioIdConversacion: string,
  archivo: File
): Promise<{ path: string | null; error: string | null }> {
  if (archivo.size === 0) return { path: null, error: null };

  const extension = TIPOS_IMAGEN_PERMITIDOS[archivo.type];
  if (!extension) {
    return {
      path: null,
      error: "La imagen debe ser JPG, PNG o WEBP.",
    };
  }
  if (archivo.size > TAMANO_MAXIMO_IMAGEN) {
    return { path: null, error: "La imagen no puede pesar más de 5 MB." };
  }

  const path = `${usuarioIdConversacion}/${crypto.randomUUID()}.${extension}`;
  const { error } = await supabase.storage
    .from("comprobantes-soporte")
    .upload(path, archivo, { contentType: archivo.type });

  if (error) {
    return { path: null, error: "No se pudo subir la imagen. Intenta de nuevo." };
  }
  return { path, error: null };
}

async function esAdminActivo(
  supabase: SupabaseClient,
  userId: string
): Promise<boolean> {
  const { data: perfil } = await supabase
    .from("usuarios")
    .select("role, activo")
    .eq("id", userId)
    .single();

  return perfil?.role === "admin" && perfil.activo !== false;
}

/**
 * El trigger `limitar_frecuencia_mensajes_soporte` (migración 021) corta a
 * 10 mensajes por minuto y por remitente. Su mensaje ya está redactado en
 * español para el usuario final, así que se muestra tal cual en vez de
 * taparlo con un "No se pudo enviar el mensaje" que no explica nada y
 * hace que la persona reintente en bucle.
 */
function mensajeDeErrorDeInsercion(error: { message?: string }): string {
  const texto = (error.message ?? "").trim();
  if (!texto) return "No se pudo enviar el mensaje. Intenta de nuevo.";
  if (/demasiado r[aá]pido/i.test(texto)) return texto;
  if (/row-level security|violates/i.test(texto)) {
    return "No tienes permiso para escribir en esta conversación.";
  }
  return texto;
}

/** El usuario normal escribe en su propia (única) conversación de soporte. */
export async function enviarMensajeUsuario(
  formData: FormData
): Promise<Resultado<MensajeSoporte | null>> {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fallo("Debes iniciar sesión.");
  if (!(await cuentaActiva(supabase, user.id))) {
    return fallo("Tu cuenta está desactivada.");
  }

  const contenido = String(formData.get("contenido") ?? "").trim();
  if (contenido.length > 2000) {
    return fallo("El mensaje es demasiado largo (máximo 2000 caracteres).");
  }

  const archivo = formData.get("imagen");
  let imagenPath: string | null = null;
  if (archivo instanceof File && archivo.size > 0) {
    const resultado = await subirComprobante(supabase, user.id, archivo);
    if (resultado.error) return fallo(resultado.error);
    imagenPath = resultado.path;
  }

  // Un mensaje sin texto NI imagen no tiene nada que guardar — pero uno
  // con solo imagen sí es válido (comprobante sin comentario).
  if (!contenido && !imagenPath) return exito(null);

  // .select().single(): la fila insertada vuelve al cliente para pintarla
  // de inmediato. Antes el chat dependía SOLO del evento de Realtime para
  // mostrar el mensaje recién enviado, así que si la suscripción todavía no
  // estaba autenticada (o Realtime fallaba) el mensaje se guardaba pero no
  // aparecía en pantalla — parecía que se había perdido.
  const { data, error } = await supabase
    .from("mensajes_soporte")
    .insert({
      usuario_id: user.id,
      remitente_id: user.id,
      contenido,
      imagen_path: imagenPath,
      leido_admin: false,
      leido_usuario: true, // el propio autor ya lo "leyó"
    })
    .select("*")
    .single<MensajeSoporte>();

  if (error) return fallo(mensajeDeErrorDeInsercion(error));

  revalidatePath("/soporte");
  return exito(data);
}

/** El admin responde dentro de la conversación de un usuario específico. */
export async function enviarMensajeAdmin(
  formData: FormData
): Promise<Resultado<MensajeSoporte | null>> {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fallo("Debes iniciar sesión.");
  if (!(await esAdminActivo(supabase, user.id))) {
    return fallo("Solo un admin puede hacer esto.");
  }

  const usuarioId = String(formData.get("usuarioId") ?? "");
  const contenido = String(formData.get("contenido") ?? "").trim();
  if (!FORMATO_UUID.test(usuarioId)) {
    return fallo("Conversación inválida.");
  }
  if (contenido.length > 2000) {
    return fallo("El mensaje es demasiado largo (máximo 2000 caracteres).");
  }

  const archivo = formData.get("imagen");
  let imagenPath: string | null = null;
  if (archivo instanceof File && archivo.size > 0) {
    const resultado = await subirComprobante(supabase, usuarioId, archivo);
    if (resultado.error) return fallo(resultado.error);
    imagenPath = resultado.path;
  }

  if (!contenido && !imagenPath) return exito(null);

  const { data, error } = await supabase
    .from("mensajes_soporte")
    .insert({
      usuario_id: usuarioId,
      remitente_id: user.id,
      contenido,
      imagen_path: imagenPath,
      leido_admin: true, // el propio admin ya lo "leyó"
      leido_usuario: false,
    })
    .select("*")
    .single<MensajeSoporte>();

  if (error) return fallo(mensajeDeErrorDeInsercion(error));

  revalidatePath(`/soporte/${usuarioId}`);
  revalidatePath("/soporte");
  return exito(data);
}

/**
 * Marca como leídos por el admin todos los mensajes de un usuario.
 * Se llama durante el render de /soporte/[usuarioId]: no debe lanzar nunca,
 * porque tumbaría la página entera por un contador de "no leídos".
 */
export async function marcarLeidoPorAdmin(usuarioId: string): Promise<void> {
  if (!FORMATO_UUID.test(usuarioId)) return;

  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return;
  if (!(await esAdminActivo(supabase, user.id))) return;

  await supabase
    .from("mensajes_soporte")
    .update({ leido_admin: true })
    .eq("usuario_id", usuarioId)
    .eq("leido_admin", false);
}

/** Marca como leídos por el usuario los mensajes que le mandó el admin. */
export async function marcarLeidoPorUsuario(usuarioId: string): Promise<void> {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user || user.id !== usuarioId) return;
  if (!(await cuentaActiva(supabase, user.id))) return;

  await supabase
    .from("mensajes_soporte")
    .update({ leido_usuario: true })
    .eq("usuario_id", usuarioId)
    .eq("leido_usuario", false);
}
