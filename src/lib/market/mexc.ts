// Precios en tiempo real vía la API pública de MEXC (no requiere key).
//
// Antes esto era Binance — se cambió porque Railway corre en el Sudeste
// Asiático (necesario para que Binance no bloquee la IP del servidor, ver
// comentario histórico más abajo) y Supabase está en EE.UU.: cada consulta
// a la base de datos cruza medio planeta y de ahí salía la lentitud real
// al navegar. MEXC no bloquea por región igual que Binance, así que el
// servidor puede volver a vivir cerca de la base de datos sin perder los
// precios de cripto. El formato de respuesta de MEXC es casi idéntico al
// de Binance (mismos nombres de campo, mismo símbolo "BTCUSDT", mismo
// formato de velas) — la única diferencia real es que el % de cambio lo
// da como fracción (0.0015) en vez de porcentaje (0.15), por eso se
// multiplica por 100 abajo.
//
// De paso, MEXC también lista "xStock"/"Ondo" — acciones tokenizadas
// reales (AAPLX, TSLAX, etc., respaldadas 1:1 por la acción de verdad, no
// monedas meme) — así que la misma API sirve también para la sección de
// Acciones en vez de depender de Twelve Data (que nunca llegó a
// configurarse, ver acciones.ts).

export interface PrecioCripto {
  simbolo: string;
  precio: number;
  cambioPorc24h: number;
}

const BASE_URL = "https://api.mexc.com/api/v3";

export async function obtenerPrecioCripto(
  simbolo: string
): Promise<PrecioCripto> {
  // Timeout explícito en todas las llamadas a APIs externas: fetch sin
  // signal espera para siempre, y una página que depende de MEXC se
  // quedaría cargando indefinidamente si la API no responde.
  const res = await fetch(
    `${BASE_URL}/ticker/24hr?symbol=${encodeURIComponent(simbolo)}`,
    { cache: "no-store", signal: AbortSignal.timeout(10_000) }
  );

  if (!res.ok) {
    throw new Error(`No se pudo obtener el precio de ${simbolo}`);
  }

  const data = await res.json();
  const precio = parseFloat(data?.lastPrice);
  // MEXC da el % de cambio como fracción (0.0015 = 0.15%), no como
  // porcentaje ya multiplicado (Binance sí lo daba así).
  const cambio = parseFloat(data?.priceChangePercent) * 100;

  // Si MEXC devuelve 200 con un cuerpo inesperado, parseFloat da NaN y ese
  // NaN se propaga hasta la tarjeta ("$NaN") o, peor, hasta el precio de
  // entrada de una operación. Mejor tratarlo como fallo del símbolo:
  // obtenerVariosPreciosCripto ya sabe omitir los que fallan.
  if (!Number.isFinite(precio)) {
    throw new Error(`MEXC devolvió un precio inválido para ${simbolo}`);
  }

  return {
    simbolo,
    precio,
    cambioPorc24h: Number.isFinite(cambio) ? cambio : 0,
  };
}

/**
 * Trae varios precios (cripto o acciones tokenizadas, es la misma API) de
 * una sola vez cuando se puede, con fallback a llamadas individuales.
 *
 * MEXC no soporta un parámetro "symbols" tipo Binance para pedir varios a
 * la vez con un filtro — se prueba igual por si lo llegara a soportar en
 * el futuro, pero en la práctica siempre cae al fallback de abajo, que sí
 * tolera que un símbolo falle sin tumbar el resto.
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
      `${BASE_URL}/ticker/24hr?symbols=` +
        encodeURIComponent(JSON.stringify(unicos)),
      { cache: "no-store", signal: AbortSignal.timeout(10_000) }
    );

    if (res.ok) {
      const cuerpo = await res.json();
      if (Array.isArray(cuerpo)) {
        const porSimbolo = new Map<string, PrecioCripto>();
        for (const t of cuerpo as Record<string, string>[]) {
          const precio = parseFloat(t?.lastPrice);
          const cambio = parseFloat(t?.priceChangePercent) * 100;
          if (typeof t?.symbol !== "string" || !Number.isFinite(precio)) continue;
          porSimbolo.set(t.symbol, {
            simbolo: t.symbol,
            precio,
            cambioPorc24h: Number.isFinite(cambio) ? cambio : 0,
          });
        }
        // Se respeta el orden en que se pidieron, no el que devuelva MEXC.
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
 * Esa llamada devuelve ~1900 pares de MEXC (varios MB) y /mercado es una
 * ruta dinámica, así que sin este caché se pediría en CADA visita. Con
 * varios usuarios eso es tráfico enorme y arriesga el límite de
 * peticiones de MEXC.
 */
let cacheTickers: { datos: unknown[]; expira: number } | null = null;
const TTL_TICKERS_MS = 30_000;

/**
 * Top ganadores del día entre TODOS los pares USDT de MEXC (no solo el
 * watchlist fijo de la portada) — trae los ~1900 tickers en una sola
 * llamada pública (sin key) y ordena por % de cambio en 24h.
 *
 * Nunca lanza: esta sección es un extra de /mercado, y si MEXC falla,
 * limita peticiones o tarda demasiado, la página tiene que seguir
 * mostrando el resto.
 */
export async function obtenerTopGanadoresCripto(
  limite = 5
): Promise<PrecioCripto[]> {
  let data: unknown[];

  if (cacheTickers && cacheTickers.expira > Date.now()) {
    data = cacheTickers.datos;
  } else {
    try {
      const res = await fetch(`${BASE_URL}/ticker/24hr`, {
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
        // Excluye acciones tokenizadas (xStock/Ondo) y pares no-USDT del
        // top de cripto — ese top es solo para cripto de verdad. También
        // excluye símbolos con caracteres fuera del formato que exigen
        // favoritos/pick/señales (/^[A-Z0-9]{5,20}$/).
        /^[A-Z0-9]{1,16}USDT$/.test(t.symbol) &&
        !t.symbol.endsWith("XUSDT") &&
        !t.symbol.endsWith("ONUSDT") &&
        parseFloat(t.quoteVolume) >= VOLUMEN_MINIMO_USDT
    )
    .map((t) => ({
      simbolo: t.symbol,
      precio: parseFloat(t.lastPrice),
      cambioPorc24h: parseFloat(t.priceChangePercent) * 100,
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
      `${BASE_URL}/klines?symbol=${encodeURIComponent(simbolo)}&interval=60m&limit=${horas}`,
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
