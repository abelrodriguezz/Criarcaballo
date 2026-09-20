/**
 * parseFloat tolerante a comas de miles (ej. "-4,987.928" o "10,000").
 * parseFloat por sí solo se detiene en la primera coma y trunca el
 * número — "-4,987.928" se leería como -4. Usar esto en cualquier input
 * de texto donde el usuario pueda copiar/escribir un monto con comas.
 */
export function parsearNumero(texto: string): number {
  return parseFloat(texto.replace(/,/g, "").trim());
}

/**
 * Formato para importes en dólares (saldo virtual, ganancias, premios):
 * SIEMPRE 2 decimales.
 *
 * Ojo con usar toLocaleString con solo `minimumFractionDigits: 2`: el
 * máximo por defecto no es 2, es max(minimo, 3), así que un saldo de
 * 14624.0114 se mostraba como "$14,624.011" — tres decimales en una
 * cantidad de dinero. El saldo virtual queda con muchos decimales de
 * forma natural porque la ganancia se calcula como
 * (salida - entrada) * (monto / entrada).
 */
export function formatearDinero(valor: number): string {
  const numero = Number.isFinite(valor) ? valor : 0;
  return numero.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

/** Formato consistente para precios de mercado en toda la app (2 a 6 decimales, según haga falta). */
export function formatearPrecio(valor: number): string {
  return valor.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  });
}

/**
 * Link directo al gráfico interactivo del activo en TradingView. Se usa
 * /chart/?symbol=... (no /symbols/.../) a propósito — esa otra ruta es una
 * vista previa que obliga a darle click a "Full chart" para entrar al
 * gráfico real, un paso extra confuso para quien no conoce TradingView.
 * Funciona tanto para pares de cripto (ej. BTCUSDT) como para índices
 * (ej. SPX, IXIC, DJI) — TradingView resuelve el símbolo "pelado" al
 * mercado correcto sin necesitar el prefijo del exchange.
 */
export function urlGraficoTradingView(simbolo: string): string {
  return `https://www.tradingview.com/chart/?symbol=${encodeURIComponent(simbolo)}`;
}
