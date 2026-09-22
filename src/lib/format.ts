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
 * Lee un monto tecleado a mano, donde la coma puede ser decimal ("1,50"
 * = uno con cincuenta, como se escribe en español) o separador de miles
 * ("1,000" = mil). parsearNumero() asume siempre lo segundo — correcto
 * para montos que la app imprime en formato en-US, pero no para lo que
 * escribe un usuario hispanohablante: ahí "1,50" se leería como 150.
 *
 * Regla: si aparecen los dos separadores, el ÚLTIMO es el decimal
 * ("1.000,50" → 1000.50). Si solo hay comas, una sola coma seguida de 1
 * o 2 dígitos es decimal ("1,50" → 1.5) y cualquier otro caso son miles
 * ("1,000" → 1000). Devuelve NaN si el texto no es un número limpio, en
 * vez de quedarse con el prefijo numérico como hace parseFloat.
 */
export function parsearMontoUsuario(texto: string): number {
  const limpio = texto.replace(/\s/g, "");
  if (!/^[+-]?[\d.,]+$/.test(limpio)) return NaN;

  const ultimaComa = limpio.lastIndexOf(",");
  const ultimoPunto = limpio.lastIndexOf(".");

  let comaEsDecimal: boolean;
  if (ultimaComa >= 0 && ultimoPunto >= 0) {
    comaEsDecimal = ultimaComa > ultimoPunto;
  } else {
    comaEsDecimal = ultimaComa >= 0 && /^[+-]?\d+,\d{1,2}$/.test(limpio);
  }

  const normalizado = comaEsDecimal
    ? limpio.replace(/\./g, "").replace(",", ".")
    : limpio.replace(/,/g, "");

  return Number(normalizado);
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
