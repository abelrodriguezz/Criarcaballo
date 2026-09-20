// Noticias reales de cripto/mercado sin necesitar ninguna cuenta ni API
// key — se leen directo de los feeds RSS públicos que estos medios ya
// publican para cualquiera. Nunca se inventa contenido: si un feed falla,
// simplemente se omite en vez de rellenar con algo falso.

import { urlSeguraParaEnlace } from "@/lib/url";

export interface NoticiaExterna {
  titulo: string;
  url: string;
  fuente: string;
}

/**
 * Tope de bytes que se leen de un feed. Lo que devuelve el servidor del
 * medio es un cuerpo de tamaño arbitrario: sin este límite, un feed
 * comprometido (o un intermediario) puede responder cientos de megas y
 * tumbar el proceso de Next.js por memoria — y la portada, que es
 * justamente la página pública, depende de esta llamada.
 */
const MAX_BYTES_FEED = 512 * 1024;

/** Ninguna noticia real tiene un titular de más de esto. */
const MAX_LARGO_TITULO = 300;

function decodificarEntidades(texto: string): string {
  return texto
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#x([0-9a-fA-F]{1,6});/g, (original, hex: string) =>
      codigoAtexto(parseInt(hex, 16), original)
    )
    .replace(/&#(\d{1,7});/g, (original, dec: string) =>
      codigoAtexto(parseInt(dec, 10), original)
    );
}

/**
 * String.fromCodePoint lanza RangeError con cualquier valor fuera de
 * 0..0x10FFFF o con un sustituto suelto. Antes eso abortaba el parseo del
 * feed entero (se comía el catch de arriba y la portada se quedaba sin
 * ticker); ahora la entidad inválida se deja tal cual y el resto sigue.
 */
function codigoAtexto(codigo: number, original: string): string {
  if (!Number.isInteger(codigo) || codigo < 0 || codigo > 0x10ffff) {
    return original;
  }
  try {
    return String.fromCodePoint(codigo);
  } catch {
    return original;
  }
}

/** Saca el contenido de una etiqueta simple, con o sin CDATA. */
function extraerCampo(bloque: string, etiqueta: "title" | "link"): string {
  // La etiqueta viene de este módulo (nunca del feed), así que no hay
  // inyección posible en el patrón; el tipo literal lo deja explícito.
  const regex = new RegExp(`<${etiqueta}[^>]*>([\\s\\S]*?)<\\/${etiqueta}>`, "i");
  const match = bloque.match(regex);
  if (!match) return "";
  const crudo = match[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/, "$1");
  return decodificarEntidades(crudo).trim();
}

/** Lee el cuerpo de la respuesta hasta MAX_BYTES_FEED y corta ahí. */
async function leerConTope(res: Response): Promise<string> {
  const cuerpo = res.body;
  if (!cuerpo) return "";

  const lector = cuerpo.getReader();
  const trozos: Uint8Array[] = [];
  let total = 0;

  try {
    for (;;) {
      const { done, value } = await lector.read();
      if (done) break;
      if (!value) continue;
      trozos.push(value);
      total += value.byteLength;
      if (total >= MAX_BYTES_FEED) break;
    }
  } finally {
    // cancel() libera la conexión aunque se haya cortado a la mitad.
    await lector.cancel().catch(() => {});
  }

  const buffer = new Uint8Array(total);
  let offset = 0;
  for (const t of trozos) {
    buffer.set(t, offset);
    offset += t.byteLength;
  }
  return new TextDecoder("utf-8").decode(buffer);
}

async function obtenerFeedRSS(
  url: string,
  fuente: string,
  limite: number
): Promise<NoticiaExterna[]> {
  try {
    const res = await fetch(url, {
      cache: "no-store",
      signal: AbortSignal.timeout(6_000),
      headers: { "User-Agent": "Mozilla/5.0" },
      // Un 30x que apunte a otro host convertiría esta llamada de servidor
      // en un SSRF hacia donde quiera el feed (incluida la red interna del
      // hosting o el endpoint de metadatos de la nube). Estos feeds son
      // URLs finales y estables: no hay ningún redirect legítimo que
      // seguir.
      redirect: "error",
    });
    if (!res.ok) return [];

    const xml = await leerConTope(res);
    // Cada <item> del RSS es una noticia — se parte el XML por esa
    // etiqueta en vez de usar un parser de XML completo, para no
    // agregarle una dependencia nueva al proyecto por un feed simple.
    const bloques = xml.split(/<item>/i).slice(1, limite + 1);

    return bloques
      .map((bloque) => ({
        titulo: extraerCampo(bloque, "title").slice(0, MAX_LARGO_TITULO),
        // El <link> del feed se renderiza como href en la portada: si no
        // es http/https se descarta la noticia entera (ver src/lib/url.ts).
        url: urlSeguraParaEnlace(extraerCampo(bloque, "link")),
        fuente,
      }))
      .filter((n): n is NoticiaExterna => !!n.titulo && n.url !== null);
  } catch {
    return [];
  }
}

const cache = new Map<string, { datos: NoticiaExterna[]; expira: number }>();
const TTL_MS = 10 * 60_000; // 10 min — son titulares, no hace falta al segundo

/** Noticias de cripto (Cointelegraph) y mercado/acciones (MarketWatch), intercaladas. */
export async function obtenerNoticiasExternas(
  limitePorFuente = 4
): Promise<NoticiaExterna[]> {
  const clave = `externas-${limitePorFuente}`;
  const cacheado = cache.get(clave);
  if (cacheado && cacheado.expira > Date.now()) return cacheado.datos;

  const [cripto, mercado] = await Promise.all([
    obtenerFeedRSS("https://cointelegraph.com/rss", "Cointelegraph", limitePorFuente),
    obtenerFeedRSS(
      "https://feeds.content.dowjones.io/public/rss/mw_topstories",
      "MarketWatch",
      limitePorFuente
    ),
  ]);

  // Intercaladas para que no salgan todas de la misma fuente seguidas.
  const resultado: NoticiaExterna[] = [];
  const max = Math.max(cripto.length, mercado.length);
  for (let i = 0; i < max; i++) {
    if (cripto[i]) resultado.push(cripto[i]);
    if (mercado[i]) resultado.push(mercado[i]);
  }

  cache.set(clave, { datos: resultado, expira: Date.now() + TTL_MS });
  return resultado;
}
