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
  textoBoton,
  textoEliminando,
}: {
  tabla: "senales" | "noticias" | "ganancias_concursos" | "depositos_simulados";
  id: string;
  textoConfirmacion: string;
  ta?: TextosAdmin;
  /** Para reusar este mismo botón (y su delete) con otra etiqueta — ej.
   * "Pago no realizado" en /depositos en vez de "Eliminar". */
  textoBoton?: string;
  textoEliminando?: string;
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
      {eliminando ? (textoEliminando ?? ta.eliminando) : (textoBoton ?? ta.eliminar)}
    </button>
  );
}
