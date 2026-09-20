/**
 * Forma estándar en que las Server Actions de este proyecto devuelven un
 * fallo esperado (saldo insuficiente, mercado cerrado, límite de mensajes
 * alcanzado...) en vez de lanzarlo.
 *
 * POR QUÉ NO SE LANZA UN Error CON EL MENSAJE:
 * en un build de producción, React/Next.js NO envían al navegador el
 * mensaje de un Error que escapa de una Server Action — lo reemplazan por
 * "An error occurred in the Server Components render. The specific message
 * is omitted in production builds to avoid leaking sensitive details...".
 * En `next dev` sí se ve el mensaje real, así que un error cuidadosamente
 * redactado en español se ve perfecto mientras se programa y se convierte
 * en un muro de texto en inglés en cuanto se despliega.
 *
 * La propia documentación de Next.js 16 lo dice explícitamente para los
 * errores esperados: "avoid using try/catch blocks and throw errors.
 * Instead, model expected errors as return values"
 * (node_modules/next/dist/docs/01-app/01-getting-started/10-error-handling.md).
 *
 * Los errores INESPERADOS (bug, base caída) sí se dejan propagar: para
 * esos el mensaje genérico y el `digest` del servidor son lo correcto.
 */
export type Resultado<T = null> =
  | { ok: true; datos: T }
  | { ok: false; error: string };

export function exito(): Resultado<null>;
export function exito<T>(datos: T): Resultado<T>;
export function exito<T>(datos?: T): Resultado<T | null> {
  return { ok: true, datos: datos ?? null };
}

export function fallo(error: string): Resultado<never> {
  return { ok: false, error };
}

/**
 * Mensaje mostrable a partir de lo que devuelva una Server Action que ya
 * use `Resultado`, o de una excepción inesperada que se haya escapado.
 * En producción el `.message` de una excepción ya viene censurado, así que
 * en ese caso se usa el respaldo en español.
 */
export function mensajeDeFallo(
  resultado: Resultado<unknown> | undefined,
  respaldo: string
): string | null {
  if (!resultado) return respaldo;
  return resultado.ok ? null : resultado.error || respaldo;
}
