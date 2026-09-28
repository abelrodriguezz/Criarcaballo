"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { esAdmin } from "@/lib/auth/sesion";
import { estaAbiertaBolsaNY, fechaEnNY } from "@/lib/horarioMercado";
import { obtenerHorarioMercado, formatearHorarioMercado } from "@/lib/config-horario-mercado";
import { obtenerSecretoServidor } from "@/lib/supabase/secretoServidor";
import { parsearNumero } from "@/lib/format";
import { exito, fallo, type Resultado } from "@/lib/actions/resultado";

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
  // Horario configurable por el admin (migración 064) — antes estaba fijo
  // en el código (lunes a viernes, 9:30am-4:00pm hora de NY).
  const horarioMercado = await obtenerHorarioMercado();
  if (!usuarioEsAdmin && !estaAbiertaBolsaNY(horarioMercado)) {
    return fallo(formatearHorarioMercado(horarioMercado, "es"));
  }

  const activo = String(formData.get("activo")).toUpperCase().trim();
  const tipo = String(formData.get("tipo"));
  // parsearNumero (no parseFloat) por si el navegador/autocompletado manda
  // el monto con comas de miles: parseFloat("10,000") devuelve 10.
  const montoUsado = parsearNumero(String(formData.get("monto")));

  // Sin formato de "par de Binance": el pick ya puede ser cualquier activo
  // (acciones, forex, materias primas), así que solo se valida que no
  // venga vacío ni absurdamente largo. La verificación real de seguridad
  // es la que sigue abajo (coincide con el pick vigente), no la forma del
  // texto.
  if (!activo || activo.length > 30) {
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
  // operar un símbolo distinto al autorizado. Solo cuenta el pick si es de
  // HOY (hora de NY): la RPC (migración 062) re-valida esto mismo, esto
  // solo evita una petición innecesaria si acá ya sabemos que no aplica.
  const { data: pickVigente } = await supabase
    .from("pick_del_dia")
    .select("activo")
    .eq("fecha", fechaEnNY())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!pickVigente || pickVigente.activo.toUpperCase() !== activo) {
    return fallo("Ese activo ya no es el pick del día vigente.");
  }

  // Ya no se busca ningún precio en vivo (ni Binance ni ninguna otra
  // fuente) al abrir: desde la migración 056, el precio de entrada que
  // cuenta de verdad es el que el admin fija a mano al cerrar la operación
  // en bloque — el que se capturara aquí al abrir nunca se usaba para el
  // cálculo final. Abrir una operación queda igual para el usuario, solo
  // que ya no depende de ninguna API externa para funcionar.
  //
  // Abrir la operación y descontar el saldo pasa por una función de base de
  // datos (abrir_operacion, ver migraciones 010, 019 y 060) que hace todo
  // en una sola transacción atómica con bloqueo de fila — así dos clics
  // rápidos o dos pestañas no pueden abrir dos operaciones ni descontar el
  // saldo dos veces. El p_secreto es lo que le prueba a Postgres que la
  // llamada viene de este servidor y no de alguien usando la anon key
  // desde el navegador (ver migración 019).
  const { error } = await supabase.rpc("abrir_operacion", {
    p_activo: activo,
    p_tipo: tipo,
    p_monto: montoUsado,
    p_secreto: obtenerSecretoServidor(),
  });

  if (error) {
    return fallo(error.message || "No se pudo abrir la operación.");
  }

  revalidatePath("/trade-del-dia");
  return exito();
}
