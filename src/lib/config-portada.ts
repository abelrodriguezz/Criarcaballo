import { crearClienteSupabaseServidor } from "@/lib/supabase/server";

export interface ConfigHero {
  badge: string;
  titulo_linea1: string;
  titulo_linea2: string;
  subtitulo: string;
}

export const HERO_POR_DEFECTO: ConfigHero = {
  badge: "● Datos en vivo, sin promesas de rendimiento",
  titulo_linea1: "Entiende el mercado.",
  titulo_linea2: "Practica sin riesgo.",
  subtitulo:
    "Análisis diario, precios en tiempo real y un modo de práctica con saldo virtual — aprende a operar antes de arriesgar capital real.",
};

export async function obtenerConfigPortada(): Promise<{ hero: ConfigHero }> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("clave, valor")
    .eq("clave", "hero")
    .maybeSingle();

  // Fallback campo por campo (no solo objeto completo): si el admin borró
  // un campo del hero y guardó, ese campo puntual vuelve al default en vez
  // de renderizarse vacío en la portada pública.
  const heroGuardado = data?.valor as Partial<ConfigHero> | undefined;
  const hero: ConfigHero = {
    badge: heroGuardado?.badge?.trim() || HERO_POR_DEFECTO.badge,
    titulo_linea1:
      heroGuardado?.titulo_linea1?.trim() || HERO_POR_DEFECTO.titulo_linea1,
    titulo_linea2:
      heroGuardado?.titulo_linea2?.trim() || HERO_POR_DEFECTO.titulo_linea2,
    subtitulo: heroGuardado?.subtitulo?.trim() || HERO_POR_DEFECTO.subtitulo,
  };

  return { hero };
}
