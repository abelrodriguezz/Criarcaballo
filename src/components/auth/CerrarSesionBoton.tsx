"use client";

import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { Diccionario } from "@/lib/i18n";

export function CerrarSesionBoton({ t }: { t: Diccionario }) {
  const router = useRouter();

  async function cerrarSesion() {
    const supabase = crearClienteSupabase();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <button
      onClick={cerrarSesion}
      className="text-sm font-semibold text-loss hover:underline"
    >
      {t.perfil.cerrarSesion}
    </button>
  );
}
