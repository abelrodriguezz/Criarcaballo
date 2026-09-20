import type { AuthError } from "@supabase/supabase-js";

/**
 * Traduce los errores de Supabase Auth a algo que una persona entienda.
 *
 * Antes cualquier fallo se resumía en "No se pudo crear la cuenta. Intenta
 * de nuevo.", y el caso más frecuente en la vida real no es un fallo
 * transitorio sino `over_email_send_rate_limit`: sin un SMTP propio
 * configurado, Supabase usa su servicio compartido de correo, que tiene un
 * límite muy bajo de envíos por hora. Con el mensaje genérico la persona
 * reintenta en bucle sin saber que el problema es el correo, no su
 * contraseña.
 */
export function mensajeErrorAuth(
  error: AuthError | null,
  respaldo: string
): string {
  if (!error) return respaldo;

  const codigo = error.code ?? "";
  const texto = error.message ?? "";

  if (codigo === "over_email_send_rate_limit" || /email rate limit/i.test(texto)) {
    return "Se alcanzó el límite de correos por hora del servidor. Espera unos minutos y vuelve a intentarlo.";
  }
  if (codigo === "over_request_rate_limit" || error.status === 429) {
    return "Demasiados intentos seguidos. Espera un momento antes de volver a intentarlo.";
  }
  if (codigo === "weak_password" || /password should be at least/i.test(texto)) {
    return "La contraseña es demasiado débil. Usa al menos 8 caracteres.";
  }
  if (codigo === "email_address_invalid" || /email address .* is invalid/i.test(texto)) {
    return "Ese correo no parece válido. Revísalo e inténtalo de nuevo.";
  }
  if (codigo === "signup_disabled" || /signups not allowed/i.test(texto)) {
    return "El registro de cuentas nuevas está deshabilitado en este momento.";
  }
  if (codigo === "user_already_exists" || /already registered/i.test(texto)) {
    return "Ese correo ya tiene una cuenta.";
  }
  if (codigo === "email_not_confirmed") {
    return "Todavía no confirmaste tu correo. Revisa tu bandeja de entrada.";
  }
  if (/error sending/i.test(texto)) {
    return "No se pudo enviar el correo de confirmación. Inténtalo más tarde o escribe a soporte.";
  }

  return respaldo;
}
