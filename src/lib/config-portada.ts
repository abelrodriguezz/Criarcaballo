import { crearClienteSupabaseServidor } from "@/lib/supabase/server";

export interface ConfigHero {
  badge: string;
  titulo_linea1: string;
  titulo_linea2: string;
  subtitulo: string;
}

export interface EstadisticaPortada {
  num: string;
  label: string;
}

export const HERO_POR_DEFECTO: ConfigHero = {
  badge: "● Datos en vivo, sin promesas de rendimiento",
  titulo_linea1: "Entiende el mercado.",
  titulo_linea2: "Practica sin riesgo.",
  subtitulo:
    "Análisis diario, precios en tiempo real y un modo de práctica con saldo virtual — aprende a operar antes de arriesgar capital real.",
};

export const ESTADISTICAS_POR_DEFECTO: EstadisticaPortada[] = [
  { num: "12.4K", label: "operaciones simuladas" },
  { num: "86", label: "señales publicadas" },
  { num: "4.8/5", label: "valoración usuarios" },
];

export async function obtenerConfigPortada(): Promise<{
  hero: ConfigHero;
  estadisticas: EstadisticaPortada[];
}> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("clave, valor")
    .in("clave", ["hero", "estadisticas"]);

  const filaHero = data?.find((f) => f.clave === "hero");
  const filaStats = data?.find((f) => f.clave === "estadisticas");

  // Fallback campo por campo (no solo objeto completo): si el admin borró
  // un campo del hero y guardó, ese campo puntual vuelve al default en vez
  // de renderizarse vacío en la portada pública.
  const heroGuardado = filaHero?.valor as Partial<ConfigHero> | undefined;
  const hero: ConfigHero = {
    badge: heroGuardado?.badge?.trim() || HERO_POR_DEFECTO.badge,
    titulo_linea1:
      heroGuardado?.titulo_linea1?.trim() || HERO_POR_DEFECTO.titulo_linea1,
    titulo_linea2:
      heroGuardado?.titulo_linea2?.trim() || HERO_POR_DEFECTO.titulo_linea2,
    subtitulo: heroGuardado?.subtitulo?.trim() || HERO_POR_DEFECTO.subtitulo,
  };

  const statsGuardadas = filaStats?.valor as
    | Partial<EstadisticaPortada>[]
    | undefined;
  const estadisticas: EstadisticaPortada[] =
    statsGuardadas && statsGuardadas.length > 0
      ? statsGuardadas.map((stat, i) => ({
          num: stat?.num?.trim() || ESTADISTICAS_POR_DEFECTO[i]?.num || "",
          label:
            stat?.label?.trim() || ESTADISTICAS_POR_DEFECTO[i]?.label || "",
        }))
      : ESTADISTICAS_POR_DEFECTO;

  return { hero, estadisticas };
}
