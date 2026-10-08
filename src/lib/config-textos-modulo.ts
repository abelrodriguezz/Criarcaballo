import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import type { Locale } from "@/lib/i18n";

/**
 * Título y subtítulo editables por el admin para una página — mismo
 * patrón que config-nosotros.ts (reutiliza config_portada, clave/valor,
 * sin migración nueva), generalizado para no repetirlo 4 veces (Trade
 * del día, Comunidad, Señales, Mercado). El resto del texto de cada
 * página (etiquetas de datos, botones, errores) sigue en el diccionario
 * i18n a propósito — no es "contenido", es funcionalidad.
 */
export interface TextosModulo {
  titulo: string;
  subtitulo: string;
}

export interface TextosModuloAmbosIdiomas {
  titulo: string;
  titulo_en: string;
  subtitulo: string;
  subtitulo_en: string;
}

/** clave real en config_portada — con prefijo para no chocar con otras claves ya usadas (ej. "nosotros", "premio_referido"). */
export function claveConfigTextosModulo(
  modulo: "trade_del_dia" | "comunidad" | "senales" | "mercado"
): string {
  return `textos_${modulo}`;
}

async function obtenerGuardado(
  claveConfig: string
): Promise<Partial<TextosModuloAmbosIdiomas>> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("valor")
    .eq("clave", claveConfig)
    .maybeSingle();

  return (data?.valor as Partial<TextosModuloAmbosIdiomas> | undefined) ?? {};
}

/** Página pública: solo el idioma activo, con fallback a los textos por defecto. */
export async function obtenerTextosModulo(
  claveConfig: string,
  defecto: TextosModulo,
  defectoEn: TextosModulo,
  locale: Locale = "es"
): Promise<TextosModulo> {
  const guardado = await obtenerGuardado(claveConfig);
  const base = locale === "en" ? defectoEn : defecto;

  const titulo =
    (locale === "en" ? guardado.titulo_en : guardado.titulo)?.trim() || base.titulo;
  const subtitulo =
    (locale === "en" ? guardado.subtitulo_en : guardado.subtitulo)?.trim() ||
    base.subtitulo;

  return { titulo, subtitulo };
}

/** Panel de admin: los dos idiomas a la vez, para editar. */
export async function obtenerTextosModuloCompleto(
  claveConfig: string,
  defecto: TextosModulo,
  defectoEn: TextosModulo
): Promise<TextosModuloAmbosIdiomas> {
  const guardado = await obtenerGuardado(claveConfig);

  return {
    titulo: guardado.titulo?.trim() || defecto.titulo,
    titulo_en: guardado.titulo_en?.trim() || defectoEn.titulo,
    subtitulo: guardado.subtitulo?.trim() || defecto.subtitulo,
    subtitulo_en: guardado.subtitulo_en?.trim() || defectoEn.subtitulo,
  };
}
