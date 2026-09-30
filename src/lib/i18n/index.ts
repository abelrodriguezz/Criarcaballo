import { es } from "./diccionarios/es";
import { en } from "./diccionarios/en";

export type Locale = "es" | "en";
export type Diccionario = typeof es;

export const COOKIE_IDIOMA = "trade4u-lang";

export const diccionarios: Record<Locale, Diccionario> = { es, en };

export type TextosAdmin = Diccionario["admin"];

/** Reemplaza cada {clave} del texto por su valor. */
export function rellenar(texto: string, valores: Record<string, string | number>): string {
  return texto.replace(/\{(\w+)\}/g, (marca, clave: string) =>
    clave in valores ? String(valores[clave]) : marca
  );
}
