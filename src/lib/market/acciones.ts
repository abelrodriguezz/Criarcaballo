// Precios de acciones/índices - API de Twelve Data (requiere API key gratuita)
// Consigue una key gratis en https://twelvedata.com y ponla en MARKET_API_KEY (.env.local)

export interface PrecioActivo {
  simbolo: string;
  nombre: string;
  precio: number;
  cambioPorc: number;
}

export async function obtenerPrecioAccion(
  simbolo: string
): Promise<PrecioActivo | null> {
  const apiKey = process.env.MARKET_API_KEY;

  if (!apiKey) {
    // Sin key configurada todavía — se omite en vez de romper la página.
    return null;
  }

  // Timeout explícito: sin signal, fetch espera indefinidamente y /mercado
  // se quedaría cargando si Twelve Data no responde.
  const res = await fetch(
    `https://api.twelvedata.com/quote?symbol=${encodeURIComponent(simbolo)}&apikey=${apiKey}`,
    { cache: "no-store", signal: AbortSignal.timeout(10_000) }
  );

  if (!res.ok) return null;

  const data = await res.json();

  if (data.status === "error" || !data.close) return null;

  const precio = parseFloat(data.close);
  const cambio = parseFloat(data.percent_change);
  if (!Number.isFinite(precio)) return null;

  return {
    simbolo: data.symbol,
    nombre: data.name ?? data.symbol,
    precio,
    cambioPorc: Number.isFinite(cambio) ? cambio : 0,
  };
}

export async function obtenerVariosPreciosAcciones(
  simbolos: string[]
): Promise<PrecioActivo[]> {
  const resultados = await Promise.allSettled(
    simbolos.map(obtenerPrecioAccion)
  );

  return resultados
    .filter(
      (r): r is PromiseFulfilledResult<PrecioActivo | null> =>
        r.status === "fulfilled"
    )
    .map((r) => r.value)
    .filter((v): v is PrecioActivo => v !== null);
}

/**
 * Top acciones que más subieron/bajaron hoy (mercado de EE.UU.) — vía el
 * screener no oficial (sin key) de Yahoo Finance, NO Twelve Data.
 *
 * Se probó primero con el endpoint "market_movers" de Twelve Data, pero
 * ese endpoint está bloqueado para el plan Basic/gratuito (requiere el
 * plan Grow, USD 29/mes) — con una key gratis simplemente nunca hubiera
 * devuelto nada. Mismo espíritu que src/lib/market/yahoo.ts para el S&P
 * 500: no es una API oficial/documentada, así que puede cambiar o
 * bloquear peticiones sin aviso; si eso pasa, devuelve un arreglo vacío
 * y la sección correspondiente simplemente no se muestra.
 */
async function obtenerMovidasAccionesYahoo(
  scrId: "day_gainers" | "day_losers",
  limite: number
): Promise<PrecioActivo[]> {
  try {
    const res = await fetch(
      `https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved?formatted=false&lang=en-US&region=US&scrIds=${scrId}&count=${limite}&corsDomain=finance.yahoo.com`,
      {
        cache: "no-store",
        signal: AbortSignal.timeout(10_000),
        headers: { "User-Agent": "Mozilla/5.0" },
      }
    );
    if (!res.ok) return [];

    const data = await res.json();
    const quotes: unknown[] = data?.finance?.result?.[0]?.quotes;
    if (!Array.isArray(quotes)) return [];

    return quotes
      .map((q) => {
        const r = q as Record<string, unknown>;
        return {
          simbolo: String(r.symbol ?? ""),
          nombre: String(r.shortName ?? r.symbol ?? ""),
          precio: Number(r.regularMarketPrice),
          cambioPorc: Number(r.regularMarketChangePercent),
        };
      })
      .filter(
        (v): v is PrecioActivo =>
          v.simbolo !== "" && Number.isFinite(v.precio) && Number.isFinite(v.cambioPorc)
      );
  } catch {
    return [];
  }
}

export function obtenerTopGanadoresAcciones(limite = 5): Promise<PrecioActivo[]> {
  return obtenerMovidasAccionesYahoo("day_gainers", limite);
}

export function obtenerTopPerdedoresAcciones(limite = 5): Promise<PrecioActivo[]> {
  return obtenerMovidasAccionesYahoo("day_losers", limite);
}
