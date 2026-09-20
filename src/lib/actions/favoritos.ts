"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { cuentaActiva } from "@/lib/auth/sesion";
import { exito, fallo, type Resultado } from "@/lib/actions/resultado";

/**
 * Mismo formato que exigen el pick del día y las señales: un par de
 * Binance. Antes esto no se validaba y el símbolo llegaba tal cual desde
 * el formulario, así que con la anon key (o un formData a mano) se podía
 * guardar texto arbitrario y sin límite de cantidad. Cada favorito se
 * traduce en una petición a Binance al renderizar /perfil, así que una
 * lista inflada convierte una sola visita a esa página en cientos de
 * llamadas salientes — y el saldo de peticiones de Binance lo comparten
 * todos los usuarios de la plataforma.
 */
const FORMATO_SIMBOLO = /^[A-Z0-9]{5,20}$/;

function normalizarSimbolo(formData: FormData): string | null {
  const activo = String(formData.get("activo") ?? "")
    .trim()
    .toUpperCase();

  return FORMATO_SIMBOLO.test(activo) ? activo : null;
}

/**
 * Los fallos se devuelven en vez de lanzarse: en producción Next.js borra
 * el mensaje de un Error que escape de una Server Action, y el tope de 50
 * favoritos (trigger de la migración 021) tiene que poder explicarse en la
 * interfaz. Ver src/lib/actions/resultado.ts.
 */
export async function agregarFavorito(
  formData: FormData
): Promise<Resultado<null>> {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fallo("Debes iniciar sesión.");
  if (!(await cuentaActiva(supabase, user.id))) {
    return fallo("Tu cuenta está desactivada.");
  }

  const activo = normalizarSimbolo(formData);
  if (!activo) return fallo("Símbolo de activo inválido.");

  const { error } = await supabase
    .from("favoritos")
    .upsert(
      { usuario_id: user.id, activo },
      { onConflict: "usuario_id,activo", ignoreDuplicates: true }
    );

  // El tope por usuario lo aplica un trigger en la base (migración 021),
  // que es donde no se puede saltar: hay que mostrar su mensaje.
  if (error) {
    return fallo(error.message || "No se pudo guardar el favorito.");
  }

  revalidatePath("/mercado");
  revalidatePath("/perfil");
  return exito();
}

export async function quitarFavorito(
  formData: FormData
): Promise<Resultado<null>> {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fallo("Debes iniciar sesión.");
  if (!(await cuentaActiva(supabase, user.id))) {
    return fallo("Tu cuenta está desactivada.");
  }

  const activo = normalizarSimbolo(formData);
  if (!activo) return fallo("Símbolo de activo inválido.");

  const { error } = await supabase
    .from("favoritos")
    .delete()
    .eq("usuario_id", user.id)
    .eq("activo", activo);

  if (error) {
    return fallo(error.message || "No se pudo quitar el favorito.");
  }

  revalidatePath("/mercado");
  revalidatePath("/perfil");
  return exito();
}
