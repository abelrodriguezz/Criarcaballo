// Top ganadores/perdedores de acciones vía Yahoo Finance (gratis, sin key).
// Antes también había precios de índices (S&P 500/Nasdaq/Dow) vía Twelve
// Data, pero esa key nunca se configuró (requiere plan pago para lo que se
// necesitaba) — se quitó esa parte; los índices individuales ahora se
// reemplazan en /mercado por acciones tokenizadas reales (AAPL, TSLA,
// NVIDIA...) vía MEXC, ver src/lib/market/mexc.ts.

export interface PrecioActivo {
  simbolo: string;
  nombre: string;
  precio: number;
  cambioPorc: number;
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
      )
      // Yahoo hoy ya los devuelve ordenados, pero es una API no oficial:
      // no se depende de eso. Ganadores: mayor subida primero; perdedores:
      // mayor caída primero.
      .sort((a, b) =>
        scrId === "day_gainers"
          ? b.cambioPorc - a.cambioPorc
          : a.cambioPorc - b.cambioPorc
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
