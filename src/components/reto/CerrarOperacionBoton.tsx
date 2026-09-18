"use client";

import { useState } from "react";
import { cerrarOperacion } from "@/lib/actions/paperTrading";

export function CerrarOperacionBoton({ operacionId }: { operacionId: string }) {
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function accion(formData: FormData) {
    setError(null);
    setEnviando(true);
    try {
      await cerrarOperacion(formData);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al cerrar la operación.");
    } finally {
      setEnviando(false);
    }
  }

  return (
    <form action={accion}>
      <input type="hidden" name="operacionId" value={operacionId} />
      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}
      <button
        type="submit"
        disabled={enviando}
        className="w-full border border-[var(--border)] hover:bg-surface-hover disabled:opacity-60 font-semibold text-sm py-2.5 rounded-xl transition-colors"
      >
        {enviando ? "Cerrando..." : "Cerrar operación"}
      </button>
    </form>
  );
}
