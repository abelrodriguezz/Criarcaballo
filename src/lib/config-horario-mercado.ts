import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import type { ConfigHorarioMercado } from "@/lib/horarioMercado";
import type { Locale } from "@/lib/i18n";

// Mismo patrón que config-simulacion.ts: reutiliza la tabla genérica
// config_portada (clave/valor) bajo clave = "horario_mercado" — no hace
// falta una tabla nueva. Sin fila guardada, se usan los valores por
// defecto de abajo, que son exactamente el horario que estaba fijo en el
// código hasta ahora (lunes a viernes, 9:30am-4:00pm hora de NY).

export type { ConfigHorarioMercado };

export const HORARIO_MERCADO_POR_DEFECTO: ConfigHorarioMercado = {
  apertura: "09:30",
  cierre: "16:00",
  dias: [1, 2, 3, 4, 5],
  abierto_siempre: false,
};

const NOMBRES_DIA: Record<Locale, string[]> = {
  // Índice 0 sin usar — los días son ISO (1-7).
  es: ["", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"],
  en: ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
};

async function obtenerHorarioGuardado(): Promise<Partial<ConfigHorarioMercado>> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("valor")
    .eq("clave", "horario_mercado")
    .maybeSingle();

  return (data?.valor as Partial<ConfigHorarioMercado> | undefined) ?? {};
}

export async function obtenerHorarioMercado(): Promise<ConfigHorarioMercado> {
  const guardado = await obtenerHorarioGuardado();

  return {
    apertura: guardado.apertura || HORARIO_MERCADO_POR_DEFECTO.apertura,
    cierre: guardado.cierre || HORARIO_MERCADO_POR_DEFECTO.cierre,
    dias: guardado.dias?.length ? guardado.dias : HORARIO_MERCADO_POR_DEFECTO.dias,
    abierto_siempre: guardado.abierto_siempre ?? HORARIO_MERCADO_POR_DEFECTO.abierto_siempre,
  };
}

/** "9:30 a.m." / "9:30 AM" a partir de "09:30". */
function formatearHora(horaHHMM: string, locale: Locale): string {
  const [h, m] = horaHHMM.split(":").map(Number);
  const fecha = new Date(2000, 0, 1, h, m);
  return fecha.toLocaleTimeString(locale === "en" ? "en-US" : "es-DO", {
    hour: "numeric",
    minute: "2-digit",
  });
}

function listaConY(items: string[], locale: Locale): string {
  if (items.length === 0) return "";
  if (items.length === 1) return items[0];
  const y = locale === "en" ? "and" : "y";
  return `${items.slice(0, -1).join(", ")} ${y} ${items[items.length - 1]}`;
}

/**
 * Mensaje legible del horario configurado, para mostrarle al usuario por
 * qué no puede operar ahora mismo. Se arma acá (no en SQL) porque formatear
 * texto natural en PL/pgSQL es mucho más trabajo — la excepción de la base
 * (abrir_operacion, migración 064) se deja con un mensaje genérico, este es
 * el que de verdad ve el usuario en el flujo normal.
 */
export function formatearHorarioMercado(
  config: ConfigHorarioMercado,
  locale: Locale
): string {
  const dias = listaConY(
    [...config.dias].sort().map((d) => NOMBRES_DIA[locale][d] ?? ""),
    locale
  );
  const apertura = formatearHora(config.apertura, locale);
  const cierre = formatearHora(config.cierre, locale);

  return locale === "en"
    ? `The market is closed. You can trade ${dias}, ${apertura} to ${cierre} New York time.`
    : `El mercado está cerrado. Se puede operar ${dias}, ${apertura} a ${cierre} hora de Nueva York.`;
}
