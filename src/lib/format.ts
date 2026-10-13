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
 * ("1,000" → 1000) — EXCEPTO una sola coma seguida de exactamente 3
 * dígitos ("499,999", "65,000"): ahí es genuinamente ambiguo (¿casi 500,
 * con coma decimal como se escribe en español, o casi medio millón, con
 * coma de miles?) y se devuelve NaN en vez de adivinar, para no registrar
 * un depósito/retiro por un monto muy distinto al que la persona quiso
 * escribir (hallazgo de QA, 2026-10-12). Mismo criterio que ya usa
 * parsearPrecioAdmin para precios. Devuelve NaN si el texto no es un
 * número limpio, en vez de quedarse con el prefijo numérico como hace
 * parseFloat.
 */
export function parsearMontoUsuario(texto: string): number {
  const limpio = texto.replace(/\s/g, "");
  if (!/^[+-]?[\d.,]+$/.test(limpio)) return NaN;

  const ultimaComa = limpio.lastIndexOf(",");
  const ultimoPunto = limpio.lastIndexOf(".");

  let comaEsDecimal: boolean;
  if (ultimaComa >= 0 && ultimoPunto >= 0) {
    comaEsDecimal = ultimaComa > ultimoPunto;
  } else if (ultimaComa >= 0) {
    if (/^[+-]?\d+,\d{3}$/.test(limpio)) return NaN; // ambiguo
    comaEsDecimal = /^[+-]?\d+,\d{1,2}$/.test(limpio);
  } else {
    comaEsDecimal = false;
  }

  const normalizado = comaEsDecimal
    ? limpio.replace(/\./g, "").replace(",", ".")
    : limpio.replace(/,/g, "");

  return Number(normalizado);
}

/**
 * Lee un PRECIO tecleado a mano por el admin (cierre en bloque de Trade
 * del día). No sirve parsearMontoUsuario: un precio puede tener más de 2
 * decimales ("0,12345"), y ahí esa función lo leería como miles (12345).
 * Tampoco parsearNumero: "1,5" se leía como 15 y, con entrada "185.5" y
 * salida "186,20", la ganancia salía de +9.938% en vez de +0,38%.
 *
 * Reglas:
 *  - Con los dos separadores, el ÚLTIMO es el decimal ("1.234,56", "1,234.56").
 *  - Varias comas o varios puntos solos = miles ("1,234,567", "1.234.567").
 *  - Un solo punto = decimal ("185.5").
 *  - Una sola coma = decimal ("185,5", "0,12345"), SALVO que lleve justo 3
 *    dígitos detrás ("65,000"): eso es ambiguo (¿65 mil o 65?) y se
 *    devuelve NaN para que el formulario pida escribirlo sin ambigüedad.
 */
export function parsearPrecioAdmin(texto: string): number {
  const limpio = texto.replace(/\s/g, "");
  if (!/^\d[\d.,]*$/.test(limpio) || /[.,]$/.test(limpio)) return NaN;

  const comas = (limpio.match(/,/g) ?? []).length;
  const puntos = (limpio.match(/\./g) ?? []).length;

  let normalizado: string;
  if (comas > 0 && puntos > 0) {
    const comaEsDecimal = limpio.lastIndexOf(",") > limpio.lastIndexOf(".");
    const [miles, decimal] = comaEsDecimal ? [".", ","] : [",", "."];
    if (limpio.split(decimal).length !== 2) return NaN;
    normalizado = limpio.split(miles).join("").replace(decimal, ".");
  } else if (comas > 1 || puntos > 1) {
    const sep = comas > 1 ? "," : ".";
    const grupos = limpio.split(sep);
    if (grupos.slice(1).some((g) => g.length !== 3)) return NaN;
    normalizado = grupos.join("");
  } else if (comas === 1) {
    if (/^\d+,\d{3}$/.test(limpio)) return NaN; // ambiguo
    normalizado = limpio.replace(",", ".");
  } else {
    normalizado = limpio;
  }

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
