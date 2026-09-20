/**
 * Saneado de URLs que terminan en un `href`.
 *
 * Por qué existe: la portada y /noticias renderizan como enlace tanto lo
 * que el admin escribe en "URL de la fuente" como el campo <link> de los
 * RSS externos (Cointelegraph, MarketWatch). Ninguno de los dos es texto
 * de confianza:
 *
 *  · `javascript:alert(1)` en un href es XSS almacenado — se ejecuta en el
 *    navegador de CADA visitante que haga clic, incluido el del admin.
 *    React avisa por consola pero igual lo renderiza, y la CSP no lo
 *    bloquea porque este proyecto necesita 'unsafe-inline' en script-src.
 *  · `data:text/html,...` y `vbscript:` son variantes del mismo problema.
 *  · Un RSS se parsea con regex sobre lo que devuelva un servidor ajeno,
 *    así que basta con que ese feed se comprometa (o que alguien se meta
 *    en el medio) para inyectar cualquier cosa en ese campo.
 *
 * Se aceptan solo http/https absolutas y rutas internas que empiecen por
 * una sola "/" ("//evil.com" es una URL absoluta disfrazada, así que no).
 * Lo que no encaje devuelve null y quien llame decide si omite el enlace
 * o muestra el texto sin enlazar.
 */

/**
 * Caracteres de control ASCII (0x00-0x1F y 0x7F). Se usan justo para
 * partir el esquema y esquivar un filtro: "java\nscript:alert(1)" el
 * navegador lo sigue leyendo como javascript:.
 *
 * Escrito con \x..: antes el rango llevaba los bytes de control CRUDOS
 * dentro del literal (un NUL de verdad guardado en el archivo .ts).
 * Funcionaba, pero cualquier editor, copia/pega o herramienta que
 * normalice el fichero podía comérselos y dejar el filtro sin efecto sin
 * que nada fallara de forma visible.
 */
const CARACTERES_DE_CONTROL = /[\x00-\x1F\x7F]/g;

export function urlSeguraParaEnlace(valor: string | null | undefined): string | null {
  if (!valor) return null;

  const limpio = valor.replace(CARACTERES_DE_CONTROL, "").trim();
  if (!limpio) return null;

  // Ruta interna relativa: "/noticias", "/senales?x=1". "//host" no.
  if (limpio.startsWith("/") && !limpio.startsWith("//")) return limpio;

  let parseada: URL;
  try {
    parseada = new URL(limpio);
  } catch {
    return null;
  }

  if (parseada.protocol !== "http:" && parseada.protocol !== "https:") {
    return null;
  }

  return parseada.toString();
}
