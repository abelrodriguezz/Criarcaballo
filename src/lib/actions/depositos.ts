"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { cuentaActiva } from "@/lib/auth/sesion";
import { obtenerDiccionario } from "@/lib/i18n/servidor";
import { exito, fallo, type Resultado } from "@/lib/actions/resultado";
import { subirComprobante } from "@/lib/actions/comprobantes";
import type { DepositoSimulado } from "@/lib/types";

// Mismo tope que valida el cliente (BotonDepositarSimulado.tsx) y que ya
// impone el check de la migración 027 — repetido aquí como segunda capa,
// no como única fuente de verdad.
const MONTO_MAXIMO = 100_000_000;

/**
 * Registra el único depósito simulado del usuario, con su comprobante de
 * imagen obligatorio (migración 054). Antes esto era un insert directo
 * desde el cliente; pasa a ser una Server Action porque subir la imagen al
 * bucket privado necesita las mismas validaciones de tipo/tamaño/firma real
 * que ya usa el chat de soporte (lib/actions/comprobantes.ts).
 *
 * Además de guardar el depósito, copia el mismo comprobante como un mensaje
 * en el chat de soporte del usuario (mismo path, no se sube dos veces) para
 * que tanto el usuario como el admin lo vean ahí de inmediato — así lo pidió
 * el usuario al agregar el botón "Ir al chat" tras depositar.
 */
export async function registrarDepositoSimulado(
  formData: FormData
): Promise<Resultado<DepositoSimulado | null>> {
  const supabase = await crearClienteSupabaseServidor();
  const t = await obtenerDiccionario();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return fallo("Debes iniciar sesión.");
  if (!(await cuentaActiva(supabase, user.id))) {
    return fallo("Tu cuenta está desactivada.");
  }

  const montoTexto = String(formData.get("monto") ?? "");
  const monto = Math.round(Number(montoTexto) * 100) / 100;
  if (!Number.isFinite(monto) || monto <= 0) {
    return fallo(t.perfil.depositarMontoInvalido);
  }
  if (monto > MONTO_MAXIMO) {
    return fallo(t.perfil.depositarMontoMaximo);
  }

  const walletMostrada = formData.get("walletMostrada");

  const archivo = formData.get("comprobante");
  if (!(archivo instanceof File) || archivo.size === 0) {
    return fallo(t.perfil.depositarComprobanteObligatorio);
  }

  const { path: comprobantePath, error: errorSubida } = await subirComprobante(
    supabase,
    user.id,
    archivo
  );
  if (errorSubida || !comprobantePath) {
    return fallo(errorSubida ?? t.perfil.depositarComprobanteObligatorio);
  }

  // Sigue siendo una simulación (no se mueve dinero real ni se llama a
  // ninguna wallet) — pero queda registrado el monto y el comprobante para
  // que el admin lo revise en /depositos. El unique(usuario_id) es lo que
  // impone "una sola vez" a nivel de base de datos.
  const { data, error } = await supabase
    .from("depositos_simulados")
    .insert({
      usuario_id: user.id,
      monto,
      wallet_mostrada: typeof walletMostrada === "string" ? walletMostrada : null,
      comprobante_path: comprobantePath,
    })
    .select("*")
    .single<DepositoSimulado>();

  if (error) {
    // 23505 = unique(usuario_id): ya existe su depósito (ej. lo registró
    // desde otra pestaña). "Intenta de nuevo" ahí es engañoso.
    return fallo(
      error.code === "23505" ? t.perfil.depositarYaHecho : t.perfil.depositarErrorGuardar
    );
  }

  // Mismo path, ningún re-upload: el chat solo referencia el comprobante
  // que ya se subió arriba. Si esto falla, el depósito ya quedó guardado —
  // no vale la pena tumbar todo el flujo por un mensaje de chat que es
  // secundario al registro del depósito en sí.
  await supabase.from("mensajes_soporte").insert({
    usuario_id: user.id,
    remitente_id: user.id,
    contenido: t.perfil.depositarComprobanteMensajeChat,
    imagen_path: comprobantePath,
    leido_admin: false,
    leido_usuario: true,
  });

  revalidatePath("/perfil");
  revalidatePath("/soporte");
  return exito(data);
}

/**
 * Marca todos los depósitos como revisados por el admin. Se llama durante
 * el render de /depositos (mismo patrón que marcarLeidoPorAdmin en
 * lib/actions/chat.ts) — no debe lanzar nunca, un contador de "sin
 * revisar" no puede tumbar la página entera.
 */
export async function marcarDepositosRevisados(): Promise<void> {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return;

  const { data: perfil } = await supabase
    .from("usuarios")
    .select("role, activo")
    .eq("id", user.id)
    .single();
  if (perfil?.role !== "admin" || perfil.activo === false) return;

  await supabase
    .from("depositos_simulados")
    .update({ revisado_por_admin: true })
    .eq("revisado_por_admin", false);
}
