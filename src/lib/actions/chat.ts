"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { exigirActivo } from "@/lib/auth/sesion";
import type { SupabaseClient } from "@supabase/supabase-js";

async function exigirAdmin(supabase: SupabaseClient, userId: string) {
  const { data: perfil } = await supabase
    .from("usuarios")
    .select("role, activo")
    .eq("id", userId)
    .single();

  if (perfil?.role !== "admin" || perfil.activo === false) {
    throw new Error("Solo un admin puede hacer esto.");
  }
}

/** El usuario normal escribe en su propia (única) conversación de soporte. */
export async function enviarMensajeUsuario(formData: FormData) {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Debes iniciar sesión.");
  await exigirActivo(supabase, user.id);

  const contenido = String(formData.get("contenido") ?? "").trim();
  if (!contenido) return;
  if (contenido.length > 2000) {
    throw new Error("El mensaje es demasiado largo (máximo 2000 caracteres).");
  }

  const { error } = await supabase.from("mensajes_soporte").insert({
    usuario_id: user.id,
    remitente_id: user.id,
    contenido,
    leido_admin: false,
    leido_usuario: true, // el propio autor ya lo "leyó"
  });

  if (error) throw new Error("No se pudo enviar el mensaje.");

  revalidatePath("/soporte");
}

/** El admin responde dentro de la conversación de un usuario específico. */
export async function enviarMensajeAdmin(formData: FormData) {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Debes iniciar sesión.");
  await exigirAdmin(supabase, user.id);

  const usuarioId = String(formData.get("usuarioId"));
  const contenido = String(formData.get("contenido") ?? "").trim();
  if (!contenido || !usuarioId) return;
  if (contenido.length > 2000) {
    throw new Error("El mensaje es demasiado largo (máximo 2000 caracteres).");
  }

  const { error } = await supabase.from("mensajes_soporte").insert({
    usuario_id: usuarioId,
    remitente_id: user.id,
    contenido,
    leido_admin: true, // el propio admin ya lo "leyó"
    leido_usuario: false,
  });

  if (error) throw new Error("No se pudo enviar el mensaje.");

  revalidatePath(`/soporte/${usuarioId}`);
  revalidatePath("/soporte");
}

/** Marca como leídos por el admin todos los mensajes de un usuario. */
export async function marcarLeidoPorAdmin(usuarioId: string) {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Debes iniciar sesión.");
  await exigirAdmin(supabase, user.id);

  await supabase
    .from("mensajes_soporte")
    .update({ leido_admin: true })
    .eq("usuario_id", usuarioId)
    .eq("leido_admin", false);

  revalidatePath("/soporte");
}

/** Marca como leídos por el usuario los mensajes que le mandó el admin. */
export async function marcarLeidoPorUsuario(usuarioId: string) {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user || user.id !== usuarioId) return;

  const { data: perfil } = await supabase
    .from("usuarios")
    .select("activo")
    .eq("id", user.id)
    .single();
  if (perfil?.activo === false) return;

  await supabase
    .from("mensajes_soporte")
    .update({ leido_usuario: true })
    .eq("usuario_id", usuarioId)
    .eq("leido_usuario", false);
}
