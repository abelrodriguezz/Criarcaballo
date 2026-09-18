import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Usuario } from "@/lib/types";

export interface SesionUsuario {
  id: string;
  email: string;
  role: Usuario["role"];
  activo: boolean;
}

/** Un admin desactivado no debe seguir viéndose/tratándose como admin. */
export function esAdmin(usuario: SesionUsuario | null): boolean {
  return !!usuario && usuario.role === "admin" && usuario.activo;
}

/**
 * Devuelve el usuario autenticado (con su rol de la tabla `usuarios`),
 * o null si no hay sesión activa. Usar solo en Server Components/Actions.
 */
export async function obtenerUsuarioActual(): Promise<SesionUsuario | null> {
  const supabase = await crearClienteSupabaseServidor();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  const { data: perfil } = await supabase
    .from("usuarios")
    .select("role, activo")
    .eq("id", user.id)
    .single();

  return {
    id: user.id,
    email: user.email ?? "",
    role: (perfil?.role as Usuario["role"]) ?? "user",
    activo: perfil?.activo ?? true,
  };
}

/**
 * Lanza si la cuenta del usuario está desactivada. Usar en toda server
 * action que mute datos, justo después de confirmar que hay sesión —
 * las páginas ya redirigen a /cuenta-desactivada, pero una server action
 * se puede invocar directo (sin pasar por la página), así que necesita
 * su propio chequeo.
 */
export async function exigirActivo(
  supabase: SupabaseClient,
  userId: string
): Promise<void> {
  const { data: perfil } = await supabase
    .from("usuarios")
    .select("activo")
    .eq("id", userId)
    .single();

  if (perfil?.activo === false) {
    throw new Error("Tu cuenta está desactivada.");
  }
}
