"use client";

import { useState } from "react";
import { abrirOperacion } from "@/lib/actions/paperTrading";

export function AbrirOperacionForm({
  activo,
  saldoDisponible,
}: {
  activo: string;
  saldoDisponible: number;
}) {
  const [tipo, setTipo] = useState<"compra" | "venta">("compra");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function accion(formData: FormData) {
    setError(null);
    setEnviando(true);
    try {
      await abrirOperacion(formData);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al abrir la operación.");
    } finally {
      setEnviando(false);
    }
  }

  return (
    <form action={accion} className="flex flex-col gap-3">
      <input type="hidden" name="activo" value={activo} />

      <div className="grid grid-cols-2 gap-2.5">
        <button
          type="button"
          onClick={() => setTipo("compra")}
          className={`py-2 rounded-lg text-sm font-semibold border transition-colors ${
            tipo === "compra"
              ? "bg-gain/15 border-gain text-gain"
              : "border-[var(--border)] text-foreground-muted"
          }`}
        >
          Compra
        </button>
        <button
          type="button"
          onClick={() => setTipo("venta")}
          className={`py-2 rounded-lg text-sm font-semibold border transition-colors ${
            tipo === "venta"
              ? "bg-loss/15 border-loss text-loss"
              : "border-[var(--border)] text-foreground-muted"
          }`}
        >
          Venta
        </button>
      </div>
      <input type="hidden" name="tipo" value={tipo} />

      <div>
        <input
          name="monto"
          type="number"
          min="1"
          max={saldoDisponible}
          step="0.01"
          required
          placeholder="Monto de tu saldo virtual a usar (USD)"
          className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
        <p className="text-[12px] text-foreground-muted mt-1">
          Disponible: $
          {saldoDisponible.toLocaleString("en-US", {
            minimumFractionDigits: 2,
          })}
        </p>
      </div>

      {error && <p className="text-loss text-[13px]">{error}</p>}

      <button
        type="submit"
        disabled={enviando || saldoDisponible <= 0}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {enviando ? "Abriendo..." : "Abrir operación simulada"}
      </button>
    </form>
  );
}
