"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { es } from "@/lib/i18n/diccionarios/es";
import type { TextosAdmin } from "@/lib/i18n";

export function BotonEliminarAdmin({
  tabla,
  id,
  textoConfirmacion,
  ta = es.admin,
}: {
  tabla: "senales" | "noticias" | "ganancias_concursos" | "depositos_simulados";
  id: string;
  textoConfirmacion: string;
  ta?: TextosAdmin;
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
      alert(ta.errorEliminar);
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
      {eliminando ? ta.eliminando : ta.eliminar}
    </button>
  );
}
