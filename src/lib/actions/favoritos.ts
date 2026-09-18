"use server";

import { revalidatePath } from "next/cache";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { exigirActivo } from "@/lib/auth/sesion";

export async function agregarFavorito(formData: FormData) {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Debes iniciar sesión.");
  await exigirActivo(supabase, user.id);

  const activo = String(formData.get("activo"));

  await supabase
    .from("favoritos")
    .upsert(
      { usuario_id: user.id, activo },
      { onConflict: "usuario_id,activo", ignoreDuplicates: true }
    );

  revalidatePath("/mercado");
  revalidatePath("/perfil");
}

export async function quitarFavorito(formData: FormData) {
  const supabase = await crearClienteSupabaseServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Debes iniciar sesión.");
  await exigirActivo(supabase, user.id);

  const activo = String(formData.get("activo"));

  await supabase
    .from("favoritos")
    .delete()
    .eq("usuario_id", user.id)
    .eq("activo", activo);

  revalidatePath("/mercado");
  revalidatePath("/perfil");
}
