/**
 * Desglose de un retiro con fee: cuánto es el fee y cuánto se le transfiere
 * de verdad al usuario. Un solo cálculo para el formulario del usuario y la
 * cola del admin en /retiros, así nunca muestran centavos distintos.
 *
 * Se calcula en centavos enteros (no `monto * pct / 100` en dólares) para
 * que el redondeo a medio centavo sea siempre hacia arriba y no dependa de
 * errores de punto flotante (ej. 0.15 * 0.1 = 0.015000000000000001).
 */
export function calcularFeeRetiro(
  monto: number,
  feePorcentaje: number
): { fee: number; neto: number } {
  const montoCentavos = Math.round(monto * 100);
  const feeCentavos = Math.round((montoCentavos * feePorcentaje) / 100);
  return {
    fee: feeCentavos / 100,
    neto: (montoCentavos - feeCentavos) / 100,
  };
}
