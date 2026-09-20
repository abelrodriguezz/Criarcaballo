"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { esAdmin } from "@/lib/auth/sesion";
import { obtenerPrecioCripto } from "@/lib/market/binance";
import { estaAbiertaBolsaNY } from "@/lib/horarioMercado";
import { obtenerSecretoServidor } from "@/lib/supabase/secretoServidor";
import { parsearNumero } from "@/lib/format";
import { exito, fallo, type Resultado } from "@/lib/actions/resultado";

const FORMATO_SIMBOLO = /^[A-Z0-9]{5,20}$/;

/**
 * Los fallos esperados se DEVUELVEN, no se lanzan: en producción Next.js
 * borra el mensaje de cualquier Error que escape de una Server Action
 * (ver src/lib/actions/resultado.ts), así que lanzarlos dejaría al usuario
 * con un texto genérico en inglés en vez de "El mercado está cerrado...".
 */
export async function abrirOperacion(
  formData: FormData
): Promise<Resultado<null>> {
  const supabase = await crearClienteSupabaseServidor();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fallo("Debes iniciar sesión.");

  const { data: perfilTrading } = await supabase
    .from("usuarios")
    .select("trading_habilitado, role, activo")
    .eq("id", user.id)
    .single();

  if (perfilTrading?.activo === false) {
    return fallo("Tu cuenta está desactivada.");
  }
  if (perfilTrading?.trading_habilitado === false) {
    return fallo("Un administrador deshabilitó el trading para tu cuenta.");
  }

  const usuarioEsAdmin = esAdmin({
    id: user.id,
    email: user.email ?? "",
    role: perfilTrading?.role === "admin" ? "admin" : "user",
    activo: perfilTrading?.activo ?? true,
  });
  if (!usuarioEsAdmin && !estaAbiertaBolsaNY()) {
    return fallo(
      "El mercado está cerrado. Solo se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York."
    );
  }

  const activo = String(formData.get("activo")).toUpperCase();
  const tipo = String(formData.get("tipo"));
  // parsearNumero (no parseFloat) por si el navegador/autocompletado manda
  // el monto con comas de miles: parseFloat("10,000") devuelve 10.
  const montoUsado = parsearNumero(String(formData.get("monto")));

  if (!FORMATO_SIMBOLO.test(activo)) {
    return fallo("Símbolo de activo inválido.");
  }
  if (tipo !== "compra" && tipo !== "venta") {
    return fallo("Tipo de operación inválido.");
  }
  if (!Number.isFinite(montoUsado) || montoUsado <= 0) {
    return fallo("El monto debe ser mayor a cero.");
  }

  // Verifica que el activo sea realmente el pick del día vigente —
  // evita que alguien manipule el campo oculto del formulario para
  // operar un símbolo distinto al autorizado.
  const { data: pickVigente } = await supabase
    .from("pick_del_dia")
    .select("activo")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!pickVigente || pickVigente.activo.toUpperCase() !== activo) {
    return fallo("Ese activo ya no es el pick del día vigente.");
  }

  // El precio SIEMPRE se obtiene aquí, en el servidor — nunca confiar en un
  // precio que venga del formulario/navegador, para que no se pueda manipular.
  //
  // Si Binance falla, responde con un cuerpo raro o tarda demasiado, hay
  // que abortar con un mensaje entendible: guardar una operación con
  // precio_entrada 0 o NaN dividiría por cero al calcular la cantidad, o
  // daría una ganancia absurda al liquidarla.
  let precio: number;
  try {
    ({ precio } = await obtenerPrecioCripto(activo));
  } catch {
    return fallo(
      `No se pudo obtener el precio de ${activo} en este momento. Inténtalo de nuevo en unos segundos.`
    );
  }

  if (!Number.isFinite(precio) || precio <= 0) {
    return fallo(
      `No se pudo obtener un precio válido de ${activo} en este momento. Inténtalo de nuevo.`
    );
  }

  // Abrir la operación y descontar el saldo pasa por una función de base de
  // datos (abrir_operacion, ver migraciones 010 y 019) que hace todo en una
  // sola transacción atómica con bloqueo de fila — así dos clics rápidos o
  // dos pestañas no pueden abrir dos operaciones ni descontar el saldo dos
  // veces. El p_secreto es lo que le prueba a Postgres que la llamada viene
  // de este servidor y no de alguien usando la anon key desde el navegador
  // con un precio de entrada inventado (ver migración 019).
  const { error } = await supabase.rpc("abrir_operacion", {
    p_activo: activo,
    p_tipo: tipo,
    p_precio: precio,
    p_monto: montoUsado,
    p_secreto: obtenerSecretoServidor(),
  });

  if (error) {
    return fallo(error.message || "No se pudo abrir la operación.");
  }

  revalidatePath("/trade-del-dia");
  return exito();
}
