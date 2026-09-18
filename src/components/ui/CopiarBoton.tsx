"use client";

import { useState } from "react";

export function CopiarBoton({ texto }: { texto: string }) {
  const [copiado, setCopiado] = useState(false);

  async function copiar() {
    try {
      await navigator.clipboard.writeText(texto);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 1800);
    } catch {
      // el navegador puede bloquear el portapapeles; no rompemos la UI por eso
    }
  }

  return (
    <button
      onClick={copiar}
      disabled={!texto}
      className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-semibold px-4 py-2 rounded-lg transition-colors whitespace-nowrap"
    >
      {copiado ? "¡Copiado!" : "Copiar"}
    </button>
  );
}
