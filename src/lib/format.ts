/** Formato consistente para precios de mercado en toda la app (2 a 6 decimales, según haga falta). */
export function formatearPrecio(valor: number): string {
  return valor.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  });
}
