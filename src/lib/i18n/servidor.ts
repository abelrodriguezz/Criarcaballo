import { cookies } from "next/headers";
import { COOKIE_IDIOMA, diccionarios, type Diccionario, type Locale } from "./index";

// Aparte de index.ts a propósito: next/headers no puede importarse desde
// ningún archivo que un Client Component llegue a importar (aunque solo use
// los tipos), o el build falla — "You're importing a module that depends on
// next/headers... in the Pages Router" (en realidad ocurre en App Router
// también cuando el import se cuela dentro del bundle de cliente).

/** Español por defecto — solo cambia si la persona ya eligió inglés antes. */
export async function obtenerLocale(): Promise<Locale> {
  const store = await cookies();
  return store.get(COOKIE_IDIOMA)?.value === "en" ? "en" : "es";
}

export async function obtenerDiccionario(): Promise<Diccionario> {
  return diccionarios[await obtenerLocale()];
}
