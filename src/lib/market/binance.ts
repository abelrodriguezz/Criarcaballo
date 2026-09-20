// Precios de cripto en tiempo real - API pública de Binance (no requiere key)

export interface PrecioCripto {
  simbolo: string;
  precio: number;
  cambioPorc24h: number;
}

export async function obtenerPrecioCripto(
  simbolo: string
): Promise<PrecioCripto> {
  // Timeout explícito en todas las llamadas a APIs externas: fetch sin
  // signal espera para siempre, y una página que depende de Binance se
  // quedaría cargando indefinidamente si la API no responde.
  const res = await fetch(
    `https://api.binance.com/api/v3/ticker/24hr?symbol=${encodeURIComponent(simbolo)}`,
    { cache: "no-store", signal: AbortSignal.timeout(10_000) }
  );

  if (!res.ok) {
    throw new Error(`No se pudo obtener el precio de ${simbolo}`);
  }

  const data = await res.json();
  const precio = parseFloat(data?.lastPrice);
  const cambio = parseFloat(data?.priceChangePercent);

  // Si Binance devuelve 200 con un cuerpo inesperado, parseFloat da NaN y
  // ese NaN se propaga hasta la tarjeta ("$NaN") o, peor, hasta el precio
  // de entrada de una operación. Mejor tratarlo como fallo del símbolo:
  // obtenerVariosPreciosCripto ya sabe omitir los que fallan.
  if (!Number.isFinite(precio)) {
    throw new Error(`Binance devolvió un precio inválido para ${simbolo}`);
  }

  return {
    simbolo,
    precio,
    cambioPorc24h: Number.isFinite(cambio) ? cambio : 0,
  };
}

/**
 * Trae varios precios de cripto. Si alguno falla (símbolo inválido,
 * Binance caído, etc.) no tumba el resto — simplemente se omite de la
 * lista de resultados.
 *
 * Una SOLA petición con el parámetro `symbols`, no una por símbolo: en
 * /perfil esta función recibe la lista completa de favoritos del usuario,
 * que puede llegar a 50 (el tope que impone el trigger de la migración
 * 021). Con una llamada por símbolo, cada visita a /perfil disparaba
 * hasta 50 peticiones salientes a Binance, y el límite de peticiones de
 * Binance es POR IP: en un despliegue serverless lo comparten todos los
 * usuarios de la plataforma, así que unos pocos perfiles cargando a la
 * vez bastaban para que Binance empezara a responder 418/429 y se cayeran
 * los precios de TODA la app.
 *
 * Si la petición agrupada falla (basta con que UN símbolo no exista en
 * Binance para que devuelva 400), se recae en las llamadas individuales,
 * que sí toleran fallos sueltos.
 */
export async function obtenerVariosPreciosCripto(
  simbolos: string[]
): Promise<PrecioCripto[]> {
  const unicos = [...new Set(simbolos)];
  if (unicos.length === 0) return [];
  if (unicos.length === 1) {
    try {
      return [await obtenerPrecioCripto(unicos[0])];
    } catch {
      return [];
    }
  }

  try {
    const res = await fetch(
      "https://api.binance.com/api/v3/ticker/24hr?symbols=" +
        encodeURIComponent(JSON.stringify(unicos)),
      { cache: "no-store", signal: AbortSignal.timeout(10_000) }
    );

    if (res.ok) {
      const cuerpo = await res.json();
      if (Array.isArray(cuerpo)) {
        const porSimbolo = new Map<string, PrecioCripto>();
        for (const t of cuerpo as Record<string, string>[]) {
          const precio = parseFloat(t?.lastPrice);
          const cambio = parseFloat(t?.priceChangePercent);
          if (typeof t?.symbol !== "string" || !Number.isFinite(precio)) continue;
          porSimbolo.set(t.symbol, {
            simbolo: t.symbol,
            precio,
            cambioPorc24h: Number.isFinite(cambio) ? cambio : 0,
          });
        }
        // Se respeta el orden en que se pidieron, no el que devuelva Binance.
        const ordenados = unicos
          .map((s) => porSimbolo.get(s))
          .filter((p): p is PrecioCripto => p !== undefined);
        if (ordenados.length > 0) return ordenados;
      }
    }
  } catch {
    // Timeout o red caída: se intenta símbolo a símbolo más abajo.
  }

  const resultados = await Promise.allSettled(
    unicos.map(obtenerPrecioCripto)
  );

  return resultados
    .filter(
      (r): r is PromiseFulfilledResult<PrecioCripto> => r.status === "fulfilled"
    )
    .map((r) => r.value);
}

// Volumen mínimo en 24h (en USDT) para que un par cuente como "top ganador".
// Sin este filtro, monedas casi sin liquidez pueden mostrar subidas de
// +500% que no reflejan nada real (un solo trade mueve el precio).
const VOLUMEN_MINIMO_USDT = 1_000_000;

/**
 * Caché en memoria del listado completo de tickers.
 *
 * Esa llamada devuelve los ~3000 pares de Binance (varios MB) y /mercado
 * es una ruta dinámica — lee la sesión del usuario, así que el
 * `export const revalidate = 30` de la página no aplica y se pedía en
 * CADA visita. Con varios usuarios eso es tráfico enorme y, sobre todo,
 * el límite de peticiones de Binance (418/429), que era justo lo que
 * hacía fallar la página.
 */
let cacheTickers: { datos: unknown[]; expira: number } | null = null;
const TTL_TICKERS_MS = 30_000;

/**
 * Top ganadores del día entre TODOS los pares USDT de Binance (no solo el
 * watchlist fijo de la portada) — trae los ~2000+ tickers en una sola
 * llamada pública (sin key) y ordena por % de cambio en 24h.
 *
 * Nunca lanza: esta sección es un extra de /mercado, y si Binance falla,
 * limita peticiones o tarda demasiado, la página tiene que seguir
 * mostrando el resto. Antes no tenía try/catch y un fallo de Binance
 * tumbaba /mercado entera con un error 500.
 */
export async function obtenerTopGanadoresCripto(
  limite = 5
): Promise<PrecioCripto[]> {
  let data: unknown[];

  if (cacheTickers && cacheTickers.expira > Date.now()) {
    data = cacheTickers.datos;
  } else {
    try {
      const res = await fetch("https://api.binance.com/api/v3/ticker/24hr", {
        cache: "no-store",
        signal: AbortSignal.timeout(12_000),
      });
      if (!res.ok) return [];

      const cuerpo = await res.json();
      if (!Array.isArray(cuerpo)) return [];

      data = cuerpo;
      cacheTickers = { datos: cuerpo, expira: Date.now() + TTL_TICKERS_MS };
    } catch {
      // Timeout, red caída o respuesta ilegible: se devuelve la última
      // lista buena si todavía la tenemos, o nada.
      return cacheTickers ? procesarTickers(cacheTickers.datos, limite) : [];
    }
  }

  return procesarTickers(data, limite);
}

function procesarTickers(data: unknown[], limite: number): PrecioCripto[] {
  return (data as Record<string, string>[])
    .filter(
      (t) =>
        typeof t?.symbol === "string" &&
        t.symbol.endsWith("USDT") &&
        parseFloat(t.quoteVolume) >= VOLUMEN_MINIMO_USDT
    )
    .map((t) => ({
      simbolo: t.symbol,
      precio: parseFloat(t.lastPrice),
      cambioPorc24h: parseFloat(t.priceChangePercent),
    }))
    // Un par sin precio/porcentaje usable ensuciaría el top con "$NaN".
    .filter(
      (t) => Number.isFinite(t.precio) && Number.isFinite(t.cambioPorc24h)
    )
    .sort((a, b) => b.cambioPorc24h - a.cambioPorc24h)
    .slice(0, limite);
}

/**
 * Serie de precios de cierre de las últimas `horas` (una vela de 1h por
 * punto) — para dibujar un mini-gráfico de tendencia (sparkline) en la
 * tarjeta de cada activo. Si falla, devuelve un array vacío en vez de
 * tumbar la tarjeta completa.
 */
export async function obtenerSparklineCripto(
  simbolo: string,
  horas = 24
): Promise<number[]> {
  try {
    const res = await fetch(
      `https://api.binance.com/api/v3/klines?symbol=${encodeURIComponent(simbolo)}&interval=1h&limit=${horas}`,
      { cache: "no-store", signal: AbortSignal.timeout(10_000) }
    );
    if (!res.ok) return [];

    const velas = (await res.json()) as unknown[];
    if (!Array.isArray(velas)) return [];

    // Índice 4 = precio de cierre. Se descarta cualquier punto no numérico
    // para que el sparkline no intente dibujar un NaN.
    return velas
      .map((v) => parseFloat(String((v as string[])?.[4])))
      .filter((n) => Number.isFinite(n));
  } catch {
    return [];
  }
}

/** Igual que obtenerSparklineCripto pero para varios símbolos en paralelo. */
export async function obtenerVariosSparklinesCripto(
  simbolos: string[],
  horas = 24
): Promise<Record<string, number[]>> {
  const resultados = await Promise.allSettled(
    simbolos.map((s) => obtenerSparklineCripto(s, horas))
  );

  const mapa: Record<string, number[]> = {};
  simbolos.forEach((simbolo, i) => {
    const r = resultados[i];
    mapa[simbolo] = r.status === "fulfilled" ? r.value : [];
  });
  return mapa;
}
