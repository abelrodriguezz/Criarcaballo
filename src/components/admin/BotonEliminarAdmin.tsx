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
  soloSiPendiente = false,
}: {
  tabla: "senales" | "noticias" | "ganancias_concursos" | "depositos_simulados";
  id: string;
  textoConfirmacion: string;
  ta?: TextosAdmin;
  /** Para reusar este mismo botón (y su delete) con otra etiqueta — ej.
   * "Pago no realizado" en /depositos en vez de "Eliminar". */
  textoBoton?: string;
  textoEliminando?: string;
  /** Solo borra si la fila sigue con pagado = false. Para "Pago no
   * realizado": si otro admin (u otra pestaña) ya marcó el depósito como
   * pagado después de cargar la página, el botón viejo NO debe borrar un
   * depósito ya acreditado (el trigger revertiría el saldo, cancelaría su
   * operación abierta y borraría la comisión del referido sin aviso). */
  soloSiPendiente?: boolean;
}) {
  const router = useRouter();
  const [eliminando, setEliminando] = useState(false);

  async function eliminar() {
    if (!window.confirm(textoConfirmacion)) return;

    setEliminando(true);
    const supabase = crearClienteSupabase();
    let consulta = supabase.from(tabla).delete().eq("id", id);
    if (soloSiPendiente) consulta = consulta.eq("pagado", false);
    // .select() para saber cuántas filas se borraron de verdad: un DELETE
    // que no encuentra la fila (o que RLS filtra) no devuelve error.
    const { data, error } = await consulta.select("id");
    setEliminando(false);

    if (error) {
      alert(ta.errorEliminar);
      return;
    }

    if (soloSiPendiente && (data?.length ?? 0) === 0) {
      alert(
        "No se eliminó nada: este registro ya no está pendiente (otro admin lo marcó como pagado o ya fue eliminado). Se actualizó la lista."
      );
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
