import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import type { Locale } from "@/lib/i18n";

// Mismo patrón que config-nosotros.ts / config-portada.ts: reutiliza la
// tabla genérica config_portada (clave/valor) bajo clave =
// "simulacion_deposito" — no hace falta una tabla nueva. El admin edita
// el mensaje en los dos idiomas a la vez; se reutiliza para cualquier
// simulación futura, no solo la de depósito.

export interface ConfigSimulacionAmbosIdiomas {
  mensaje: string;
  mensaje_en: string;
}

export const MENSAJE_SIMULACION_POR_DEFECTO =
  "Esto es una simulación — no se realizó ninguna transacción real ni se envió dinero a ninguna wallet.";

export const MENSAJE_SIMULACION_POR_DEFECTO_EN =
  "This is a simulation — no real transaction was made and no money was sent to any wallet.";

async function obtenerSimulacionGuardada(): Promise<
  Partial<ConfigSimulacionAmbosIdiomas>
> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("clave, valor")
    .eq("clave", "simulacion_deposito")
    .maybeSingle();

  return (
    (data?.valor as Partial<ConfigSimulacionAmbosIdiomas> | undefined) ?? {}
  );
}

/** Para el cuadro de diálogo que ve el usuario: solo el idioma activo. */
export async function obtenerMensajeSimulacion(
  locale: Locale = "es"
): Promise<string> {
  const guardado = await obtenerSimulacionGuardada();

  if (locale === "en") {
    return guardado.mensaje_en?.trim() || MENSAJE_SIMULACION_POR_DEFECTO_EN;
  }
  return guardado.mensaje?.trim() || MENSAJE_SIMULACION_POR_DEFECTO;
}

/** Panel de admin: los dos idiomas a la vez, para editar. */
export async function obtenerMensajeSimulacionCompleto(): Promise<ConfigSimulacionAmbosIdiomas> {
  const guardado = await obtenerSimulacionGuardada();

  return {
    mensaje: guardado.mensaje?.trim() || MENSAJE_SIMULACION_POR_DEFECTO,
    mensaje_en: guardado.mensaje_en?.trim() || MENSAJE_SIMULACION_POR_DEFECTO_EN,
  };
}
