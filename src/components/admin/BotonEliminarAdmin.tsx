"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

export function BotonEliminarAdmin({
  tabla,
  id,
  textoConfirmacion,
}: {
  tabla: "senales" | "noticias" | "ganancias_concursos" | "depositos_simulados";
  id: string;
  textoConfirmacion: string;
}) {
  const router = useRouter();
  const [eliminando, setEliminando] = useState(false);

  async function eliminar() {
    if (!window.confirm(textoConfirmacion)) return;

    setEliminando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.from(tabla).delete().eq("id", id);
    setEliminando(false);

    if (error) {
      alert("No se pudo eliminar. Verifica tu permiso de admin.");
      return;
    }

    router.refresh();
  }

  return (
    <button
      onClick={eliminar}
      disabled={eliminando}
      className="text-xs font-semibold text-loss hover:underline disabled:opacity-50"
    >
      {eliminando ? "Eliminando..." : "Eliminar"}
    </button>
  );
}
