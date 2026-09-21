import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import type { Locale } from "@/lib/i18n";

export interface ConfigHero {
  badge: string;
  titulo_linea1: string;
  titulo_linea2: string;
  subtitulo: string;
}

// El admin edita ambos idiomas a la vez (ver AdminPortadaForm), guardados
// en el mismo registro JSON con las claves en inglés sufijadas "_en".
export interface ConfigHeroAmbosIdiomas extends ConfigHero {
  badge_en: string;
  titulo_linea1_en: string;
  titulo_linea2_en: string;
  subtitulo_en: string;
}

export const HERO_POR_DEFECTO: ConfigHero = {
  badge: "● Datos en vivo, sin promesas de rendimiento",
  titulo_linea1: "Entiende el mercado.",
  titulo_linea2: "Practica sin riesgo.",
  subtitulo:
    "Análisis diario, precios en tiempo real y un modo de práctica con saldo virtual — aprende a operar antes de arriesgar capital real.",
};

export const HERO_POR_DEFECTO_EN: ConfigHero = {
  badge: "● Live data, no return promises",
  titulo_linea1: "Understand the market.",
  titulo_linea2: "Practice without risk.",
  subtitulo:
    "Daily analysis, real-time prices and a practice mode with virtual balance — learn to trade before risking real capital.",
};

async function obtenerHeroGuardado(): Promise<Partial<ConfigHeroAmbosIdiomas>> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("clave, valor")
    .eq("clave", "hero")
    .maybeSingle();

  return (data?.valor as Partial<ConfigHeroAmbosIdiomas> | undefined) ?? {};
}

/** Portada pública: solo el idioma activo, con fallback a los textos por defecto. */
export async function obtenerConfigPortada(
  locale: Locale = "es"
): Promise<{ hero: ConfigHero }> {
  const heroGuardado = await obtenerHeroGuardado();

  // Fallback campo por campo (no solo objeto completo): si el admin borró
  // un campo del hero y guardó, ese campo puntual vuelve al default en vez
  // de renderizarse vacío en la portada pública. Igual para inglés: si el
  // admin nunca llenó esos campos, se usa el default en inglés, NUNCA el
  // texto en español (mostrar español en la versión EN de la portada era
  // justo el problema reportado).
  const hero: ConfigHero =
    locale === "en"
      ? {
          badge: heroGuardado.badge_en?.trim() || HERO_POR_DEFECTO_EN.badge,
          titulo_linea1:
            heroGuardado.titulo_linea1_en?.trim() ||
            HERO_POR_DEFECTO_EN.titulo_linea1,
          titulo_linea2:
            heroGuardado.titulo_linea2_en?.trim() ||
            HERO_POR_DEFECTO_EN.titulo_linea2,
          subtitulo:
            heroGuardado.subtitulo_en?.trim() || HERO_POR_DEFECTO_EN.subtitulo,
        }
      : {
          badge: heroGuardado.badge?.trim() || HERO_POR_DEFECTO.badge,
          titulo_linea1:
            heroGuardado.titulo_linea1?.trim() || HERO_POR_DEFECTO.titulo_linea1,
          titulo_linea2:
            heroGuardado.titulo_linea2?.trim() || HERO_POR_DEFECTO.titulo_linea2,
          subtitulo:
            heroGuardado.subtitulo?.trim() || HERO_POR_DEFECTO.subtitulo,
        };

  return { hero };
}

/** Panel de admin: los 8 campos (ES + EN) para editar ambos a la vez. */
export async function obtenerConfigPortadaCompleta(): Promise<ConfigHeroAmbosIdiomas> {
  const heroGuardado = await obtenerHeroGuardado();

  return {
    badge: heroGuardado.badge?.trim() || HERO_POR_DEFECTO.badge,
    titulo_linea1: heroGuardado.titulo_linea1?.trim() || HERO_POR_DEFECTO.titulo_linea1,
    titulo_linea2: heroGuardado.titulo_linea2?.trim() || HERO_POR_DEFECTO.titulo_linea2,
    subtitulo: heroGuardado.subtitulo?.trim() || HERO_POR_DEFECTO.subtitulo,
    badge_en: heroGuardado.badge_en?.trim() || HERO_POR_DEFECTO_EN.badge,
    titulo_linea1_en:
      heroGuardado.titulo_linea1_en?.trim() || HERO_POR_DEFECTO_EN.titulo_linea1,
    titulo_linea2_en:
      heroGuardado.titulo_linea2_en?.trim() || HERO_POR_DEFECTO_EN.titulo_linea2,
    subtitulo_en: heroGuardado.subtitulo_en?.trim() || HERO_POR_DEFECTO_EN.subtitulo,
  };
}
