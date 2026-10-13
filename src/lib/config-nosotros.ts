import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import type { Locale } from "@/lib/i18n";

export interface ConfigNosotros {
  titulo: string;
  parrafos: string[];
  disclaimerTitulo: string;
  disclaimer: string;
}

// Mismo patrón que ConfigHero en config-portada.ts: el admin edita ambos
// idiomas a la vez, guardados en el mismo registro de config_portada
// (reutiliza esa tabla genérica clave/valor — no hace falta migración
// nueva) bajo clave = "nosotros".
export interface ConfigNosotrosAmbosIdiomas {
  titulo: string;
  titulo_en: string;
  parrafos: string[];
  parrafos_en: string[];
  disclaimerTitulo: string;
  disclaimerTitulo_en: string;
  disclaimer: string;
  disclaimer_en: string;
}

export const NOSOTROS_POR_DEFECTO: ConfigNosotros = {
  titulo: "Sobre Trade4U",
  parrafos: [
    "Trade4U nació para darle a cualquier persona acceso a datos de mercado reales — cripto, acciones e índices — sin adornos ni promesas de rendimiento. Creemos que entender el mercado antes de arriesgar dinero real es la base de cualquier decisión de trading responsable.",
    "Por eso construimos un espacio para seguir análisis publicados a diario con su razonamiento incluido, y medir tu progreso con el tiempo — todo con precios en tiempo real, directo de la fuente.",
  ],
  disclaimerTitulo: "Aviso importante",
  disclaimer:
    "Trade4U no solicita inversiones ni depósitos a través de mensajes privados o redes sociales. Todas nuestras operaciones y comunicaciones oficiales se realizan exclusivamente a través de esta página web. No confíes en personas que se hagan pasar por representantes de Trade4U y te contacten por otros medios.",
};

export const NOSOTROS_POR_DEFECTO_EN: ConfigNosotros = {
  titulo: "About Trade4U",
  parrafos: [
    "Trade4U was built to give anyone access to real market data — crypto, stocks and indices — without decoration or promises of returns. We believe understanding the market before risking real money is the foundation of any responsible trading decision.",
    "That's why we built a space to follow daily analysis with the reasoning included, and track your progress over time — all with real-time prices, straight from the source.",
  ],
  disclaimerTitulo: "Important notice",
  disclaimer:
    "Trade4U does not solicit investments or deposits through private messages or social media. All our official operations and communications take place exclusively through this website. Do not trust people who impersonate Trade4U representatives and contact you through other channels.",
};

async function obtenerNosotrosGuardado(): Promise<
  Partial<ConfigNosotrosAmbosIdiomas>
> {
  const supabase = await crearClienteSupabaseServidor();
  const { data } = await supabase
    .from("config_portada")
    .select("clave, valor")
    .eq("clave", "nosotros")
    .maybeSingle();

  return (
    (data?.valor as Partial<ConfigNosotrosAmbosIdiomas> | undefined) ?? {}
  );
}

/** Página pública: solo el idioma activo, con fallback a los textos por defecto. */
export async function obtenerConfigNosotros(
  locale: Locale = "es"
): Promise<ConfigNosotros> {
  const guardado = await obtenerNosotrosGuardado();
  const defecto = locale === "en" ? NOSOTROS_POR_DEFECTO_EN : NOSOTROS_POR_DEFECTO;

  const titulo =
    (locale === "en" ? guardado.titulo_en : guardado.titulo)?.trim() ||
    defecto.titulo;

  const parrafosGuardados = locale === "en" ? guardado.parrafos_en : guardado.parrafos;
  // Si el admin dejó el arreglo vacío a propósito (borró todos los
  // párrafos), se respeta — solo se usa el default si NUNCA se guardó nada.
  const parrafosCrudos =
    parrafosGuardados !== undefined ? parrafosGuardados : defecto.parrafos;

  // Al agregar un párrafo, el form de admin lo suma en los DOS idiomas a
  // la vez (misma posición = mismo tema) para que el admin pueda ir
  // traduciéndolo con calma — pero si todavía no lo tradujo, ese lado
  // queda como cadena vacía. Sin este filtro, la página pública renderiza
  // un <p> vacío (hueco visible) hasta que se complete la traducción.
  const parrafos = parrafosCrudos.filter((p) => p.trim().length > 0);

  const disclaimerTitulo =
    (locale === "en" ? guardado.disclaimerTitulo_en : guardado.disclaimerTitulo)?.trim() ||
    defecto.disclaimerTitulo;
  const disclaimer =
    (locale === "en" ? guardado.disclaimer_en : guardado.disclaimer)?.trim() ||
    defecto.disclaimer;

  return { titulo, parrafos, disclaimerTitulo, disclaimer };
}

/** Panel de admin: los dos idiomas a la vez, para editar/agregar/eliminar párrafos. */
export async function obtenerConfigNosotrosCompleto(): Promise<ConfigNosotrosAmbosIdiomas> {
  const guardado = await obtenerNosotrosGuardado();

  return {
    titulo: guardado.titulo?.trim() || NOSOTROS_POR_DEFECTO.titulo,
    titulo_en: guardado.titulo_en?.trim() || NOSOTROS_POR_DEFECTO_EN.titulo,
    parrafos: guardado.parrafos ?? NOSOTROS_POR_DEFECTO.parrafos,
    parrafos_en: guardado.parrafos_en ?? NOSOTROS_POR_DEFECTO_EN.parrafos,
    disclaimerTitulo: guardado.disclaimerTitulo?.trim() || NOSOTROS_POR_DEFECTO.disclaimerTitulo,
    disclaimerTitulo_en:
      guardado.disclaimerTitulo_en?.trim() || NOSOTROS_POR_DEFECTO_EN.disclaimerTitulo,
    disclaimer: guardado.disclaimer?.trim() || NOSOTROS_POR_DEFECTO.disclaimer,
    disclaimer_en: guardado.disclaimer_en?.trim() || NOSOTROS_POR_DEFECTO_EN.disclaimer,
  };
}
