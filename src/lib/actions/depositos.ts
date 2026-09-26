"use server";

import { crearClienteSupabaseServidor } from "@/lib/supabase/server";

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
