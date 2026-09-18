"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { exigirActivo } from "@/lib/auth/sesion";
import { obtenerPrecioCripto } from "@/lib/market/binance";

const FORMATO_SIMBOLO = /^[A-Z0-9]{5,20}$/;

export async function abrirOperacion(formData: FormData) {
  const supabase = await crearClienteSupabaseServidor();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Debes iniciar sesión.");
  await exigirActivo(supabase, user.id);

  const activo = String(formData.get("activo")).toUpperCase();
  const tipo = String(formData.get("tipo"));
  const montoUsado = parseFloat(String(formData.get("monto")));

  if (!FORMATO_SIMBOLO.test(activo)) {
    throw new Error("Símbolo de activo inválido.");
  }
  if (tipo !== "compra" && tipo !== "venta") {
    throw new Error("Tipo de operación inválido.");
  }
  if (!montoUsado || montoUsado <= 0) {
    throw new Error("El monto debe ser mayor a cero.");
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
    throw new Error("Ese activo ya no es el pick del día vigente.");
  }

  // El precio SIEMPRE se obtiene aquí, en el servidor — nunca confiar en un
  // precio que venga del formulario/navegador, para que no se pueda manipular.
  const { precio } = await obtenerPrecioCripto(activo);

  // Abrir la operación y descontar el saldo pasa por una función de base de
  // datos (abrir_operacion, ver migración 010) que hace todo en una sola
  // transacción atómica con bloqueo de fila — así dos clics rápidos o dos
  // pestañas no pueden abrir dos operaciones ni descontar el saldo dos veces.
  const { error } = await supabase.rpc("abrir_operacion", {
    p_activo: activo,
    p_tipo: tipo,
    p_precio: precio,
    p_monto: montoUsado,
  });

  if (error) {
    throw new Error(error.message || "No se pudo abrir la operación.");
  }

  revalidatePath("/reto-del-dia");
}

export async function cerrarOperacion(formData: FormData) {
  const supabase = await crearClienteSupabaseServidor();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Debes iniciar sesión.");
  await exigirActivo(supabase, user.id);

  const operacionId = String(formData.get("operacionId"));

  const { data: operacion } = await supabase
    .from("operaciones_simuladas")
    .select("activo")
    .eq("id", operacionId)
    .eq("usuario_id", user.id)
    .eq("estado", "abierta")
    .maybeSingle();

  if (!operacion) throw new Error("Operación no encontrada o ya cerrada.");

  // De nuevo: el precio de cierre se calcula en el servidor, en este instante.
  const { precio: precioSalida } = await obtenerPrecioCripto(operacion.activo);

  const { error } = await supabase.rpc("cerrar_operacion", {
    p_operacion_id: operacionId,
    p_precio_salida: precioSalida,
  });

  if (error) {
    throw new Error(error.message || "No se pudo cerrar la operación.");
  }

  revalidatePath("/reto-del-dia");
}
