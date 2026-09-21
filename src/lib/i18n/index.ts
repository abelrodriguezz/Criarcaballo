import { es } from "./diccionarios/es";
import { en } from "./diccionarios/en";

export type Locale = "es" | "en";
export type Diccionario = typeof es;

export const COOKIE_IDIOMA = "trade4u-lang";

export const diccionarios: Record<Locale, Diccionario> = { es, en };
