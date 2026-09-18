"use client";

import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

export function CerrarSesionBoton() {
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
      Cerrar sesión
    </button>
  );
}
