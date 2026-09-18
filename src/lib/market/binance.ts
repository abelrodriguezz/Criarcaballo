// Precios de cripto en tiempo real - API pública de Binance (no requiere key)

export interface PrecioCripto {
  simbolo: string;
  precio: number;
  cambioPorc24h: number;
}

export async function obtenerPrecioCripto(
  simbolo: string
): Promise<PrecioCripto> {
  const res = await fetch(
    `https://api.binance.com/api/v3/ticker/24hr?symbol=${simbolo}`,
    { cache: "no-store" }
  );

  if (!res.ok) {
    throw new Error(`No se pudo obtener el precio de ${simbolo}`);
  }

  const data = await res.json();

  return {
    simbolo,
    precio: parseFloat(data.lastPrice),
    cambioPorc24h: parseFloat(data.priceChangePercent),
  };
}

/**
 * Trae varios precios de cripto en paralelo. Si alguno falla (símbolo
 * inválido, Binance caído, etc.) no tumba el resto — simplemente se omite
 * de la lista de resultados.
 */
export async function obtenerVariosPreciosCripto(
  simbolos: string[]
): Promise<PrecioCripto[]> {
  const resultados = await Promise.allSettled(
    simbolos.map(obtenerPrecioCripto)
  );

  return resultados
    .filter(
      (r): r is PromiseFulfilledResult<PrecioCripto> => r.status === "fulfilled"
    )
    .map((r) => r.value);
}
