import type { Locale } from "@/lib/i18n";
import { es } from "@/lib/i18n/diccionarios/es";
import { en } from "@/lib/i18n/diccionarios/en";

/**
 * Los RPC/triggers de Postgres solo pueden levantar el mensaje fijo en
 * español con el que se escribieron (ver abrir_operacion, migración 021 de
 * favoritos) — no conocen el idioma de la app. Antes ese texto le llegaba
 * tal cual a un usuario con la app en inglés. El mapeo es por texto exacto,
 * a propósito: si el mensaje no está en la tabla, se devuelve sin tocar (más
 * seguro que adivinar una traducción de un error que no se previó).
 */
const MAPA_ES_A_CLAVE: Record<string, keyof typeof es.errores> = {
  "Debes iniciar sesión.": "debesIniciarSesion",
  "Tu cuenta está desactivada.": "cuentaDesactivadaAccion",
  "Símbolo de activo inválido.": "simboloInvalido",
  "Tipo de operación inválido.": "tipoOperacionInvalido",
  "El monto debe ser mayor a cero.": "montoInvalido",
  "Ese activo ya no es el pick del día vigente.": "pickNoVigente",
  "Ese activo no es el pick del día vigente.": "pickNoVigente",
  "Saldo virtual insuficiente.": "saldoInsuficiente",
  "Ya tienes una operación abierta. Podrás abrir otra cuando el admin cierre la sesión.":
    "operacionYaAbierta",
  "Un administrador deshabilitó el trading para tu cuenta.": "tradingDeshabilitado",
  "Ya operaste el pick de hoy. Espera a que el admin publique uno nuevo.": "pickYaOperado",
  "El mercado está cerrado en este momento.": "mercadoCerrado",
  "No se pudo abrir la operación.": "noPudoAbrirOperacion",
  "Llegaste al máximo de 50 activos favoritos. Quita alguno antes de agregar otro.":
    "topeFavoritos",
  "No se pudo guardar el favorito.": "noPudoGuardarFavorito",
  "No se pudo quitar el favorito.": "noPudoQuitarFavorito",
};

export function traducirErrorConocido(mensaje: string, locale: Locale): string {
  const clave = MAPA_ES_A_CLAVE[mensaje];
  if (!clave) return mensaje;
  return (locale === "en" ? en.errores : es.errores)[clave];
}
