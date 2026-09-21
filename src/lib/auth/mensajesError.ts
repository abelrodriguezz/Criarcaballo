import type { AuthError } from "@supabase/supabase-js";
import type { Locale } from "@/lib/i18n";
import { es } from "@/lib/i18n/diccionarios/es";
import { en } from "@/lib/i18n/diccionarios/en";

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
  respaldo: string,
  locale: Locale = "es"
): string {
  if (!error) return respaldo;

  const errores = locale === "en" ? en.errores : es.errores;
  const codigo = error.code ?? "";
  const texto = error.message ?? "";

  if (codigo === "over_email_send_rate_limit" || /email rate limit/i.test(texto)) {
    return errores.limiteCorreo;
  }
  if (codigo === "over_request_rate_limit" || error.status === 429) {
    return errores.limiteIntentos;
  }
  if (codigo === "weak_password" || /password should be at least/i.test(texto)) {
    return errores.contrasenaDebil;
  }
  if (codigo === "email_address_invalid" || /email address .* is invalid/i.test(texto)) {
    return errores.correoInvalido;
  }
  if (codigo === "signup_disabled" || /signups not allowed/i.test(texto)) {
    return errores.registroDeshabilitado;
  }
  if (codigo === "user_already_exists" || /already registered/i.test(texto)) {
    return errores.correoYaRegistrado;
  }
  if (codigo === "email_not_confirmed") {
    return errores.correoSinConfirmar;
  }
  if (/error sending/i.test(texto)) {
    return errores.errorEnvioCorreo;
  }

  return respaldo;
}
