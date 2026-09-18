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

  const res = await fetch(
    `https://api.twelvedata.com/quote?symbol=${simbolo}&apikey=${apiKey}`,
    { cache: "no-store" }
  );

  if (!res.ok) return null;

  const data = await res.json();

  if (data.status === "error" || !data.close) return null;

  return {
    simbolo: data.symbol,
    nombre: data.name ?? data.symbol,
    precio: parseFloat(data.close),
    cambioPorc: parseFloat(data.percent_change),
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
