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
 * Top acciones que más subieron hoy (mercado de EE.UU.), vía el endpoint
 * de "market movers" de Twelve Data. Requiere una key con acceso a ese
 * endpoint — si no hay key, o el plan no lo incluye, se omite en silencio
 * igual que el resto de la sección de acciones/índices.
 */
export async function obtenerTopGanadoresAcciones(
  limite = 5
): Promise<PrecioActivo[]> {
  const apiKey = process.env.MARKET_API_KEY;
  if (!apiKey) return [];

  try {
    const res = await fetch(
      `https://api.twelvedata.com/market_movers/stocks?direction=gainers&country=United States&outputsize=${limite}&apikey=${apiKey}`,
      { cache: "no-store", signal: AbortSignal.timeout(10_000) }
    );
    if (!res.ok) return [];

    const data = await res.json();
    if (data.status === "error" || !Array.isArray(data.values)) return [];

    return data.values
      .map((v: Record<string, string>) => ({
        simbolo: v.symbol,
        nombre: v.name ?? v.symbol,
        precio: parseFloat(v.last),
        cambioPorc: parseFloat(v.percent_change),
      }))
      .filter((v: PrecioActivo) => !isNaN(v.precio) && !isNaN(v.cambioPorc));
  } catch {
    return [];
  }
}
