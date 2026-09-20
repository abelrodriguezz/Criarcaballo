"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { parsearNumero } from "@/lib/format";

export function AdminSaldoForm({ usuarioId }: { usuarioId: string }) {
  const router = useRouter();
  const [monto, setMonto] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [abierto, setAbierto] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const montoNum = parsearNumero(monto);
    if (isNaN(montoNum) || montoNum === 0) {
      setError("El monto debe ser un número distinto de cero.");
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.rpc("admin_agregar_saldo", {
      p_usuario_id: usuarioId,
      p_monto: montoNum,
    });
    setGuardando(false);

    if (error) {
      setError(error.message || "No se pudo ajustar el saldo.");
      return;
    }

    setMonto("");
    setAbierto(false);
    router.refresh();
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="text-xs font-semibold text-brand-primary hover:underline"
      >
        Ajustar saldo de inversión
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="mt-2 flex flex-col gap-2 border border-[var(--border)] rounded-xl p-3"
    >
      <div className="flex gap-2">
        <input
          autoFocus
          value={monto}
          onChange={(e) => setMonto(e.target.value)}
          aria-label="Monto a agregar o quitar"
          placeholder="Ej. 5000 o -1000"
          inputMode="decimal"
          className="flex-1 min-w-0 px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
        <button
          type="submit"
          disabled={guardando}
          className="shrink-0 bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-xs px-4 py-2 rounded-lg transition-colors"
        >
          {guardando ? "..." : "Aplicar"}
        </button>
        <button
          type="button"
          onClick={() => {
            setAbierto(false);
            setError(null);
            setMonto("");
          }}
          className="shrink-0 text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>
      <p className="text-[11px] text-foreground-muted">
        Positivo para agregar, negativo para quitar (ej. -1000). Nunca baja
        de $0.
      </p>
      {error && <p className="text-loss text-[12px]">{error}</p>}
    </form>
  );
}
