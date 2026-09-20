// Precios de índices vía el endpoint público (no oficial, sin key) de
// Yahoo Finance. A diferencia de Twelve Data, no requiere registrarse —
// mismo espíritu que Binance para cripto. Contrapartida: no es una API
// documentada/soportada oficialmente, así que puede cambiar o bloquear
// peticiones sin aviso. Si eso pasa, esta función simplemente devuelve
// null y quien la llame debe mostrar un estado vacío, no romper la página.

export interface PrecioIndice {
  simbolo: string;
  precio: number;
  cambioPorc: number;
  sparkline: number[];
}

// Caché corta en memoria: esta función se llama en la portada pública,
// que no tiene sesión que la vuelva "dinámica sin caché" — pero igual es
// buena práctica no pedirle a Yahoo el mismo dato en cada visita.
const cache = new Map<string, { datos: PrecioIndice; expira: number }>();
const TTL_MS = 60_000;

export async function obtenerPrecioIndice(
  simboloYahoo: string
): Promise<PrecioIndice | null> {
  const cacheado = cache.get(simboloYahoo);
  if (cacheado && cacheado.expira > Date.now()) return cacheado.datos;

  try {
    // interval=15m&range=1d: además del precio actual, esto trae ~27
    // puntos del día para el mini-gráfico de tendencia — sin esto la
    // tarjeta quedaba con un hueco vacío donde la de cripto sí tiene su
    // sparkline.
    const res = await fetch(
      `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(simboloYahoo)}?interval=15m&range=1d`,
      {
        cache: "no-store",
        signal: AbortSignal.timeout(8_000),
        // Sin un User-Agent de navegador, Yahoo a veces rechaza la
        // petición asumiendo que es un bot/script.
        headers: { "User-Agent": "Mozilla/5.0" },
        // Este es un endpoint NO oficial: no hay contrato sobre a dónde
        // puede redirigir. Seguir un 30x desde el servidor convertiría
        // esta llamada en un SSRF hacia donde diga Yahoo (incluida la red
        // interna del hosting o el endpoint de metadatos de la nube).
        // Si algún día redirige, esta función devuelve null y la portada
        // muestra el estado vacío, que ya está contemplado.
        redirect: "error",
      }
    );
    if (!res.ok) return null;

    const data = await res.json();
    const result = data?.chart?.result?.[0];
    const meta = result?.meta;
    const precio = Number(meta?.regularMarketPrice);
    const cierreAnterior = Number(
      meta?.chartPreviousClose ?? meta?.previousClose
    );

    if (
      !Number.isFinite(precio) ||
      !Number.isFinite(cierreAnterior) ||
      cierreAnterior === 0
    ) {
      return null;
    }

    const cierres: unknown[] = result?.indicators?.quote?.[0]?.close ?? [];
    const sparkline = cierres
      .map((v) => Number(v))
      .filter((v) => Number.isFinite(v));

    const resultado: PrecioIndice = {
      simbolo: simboloYahoo.replace(/^\^/, ""),
      precio,
      cambioPorc: ((precio - cierreAnterior) / cierreAnterior) * 100,
      sparkline,
    };

    cache.set(simboloYahoo, { datos: resultado, expira: Date.now() + TTL_MS });
    return resultado;
  } catch {
    return null;
  }
}
