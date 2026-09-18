"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import type { GananciaConcurso } from "@/lib/types";

interface AdminGananciaFormProps {
  usuarioId: string;
  gananciaExistente?: GananciaConcurso;
  onCancelar?: () => void;
}

export function AdminGananciaForm({
  usuarioId,
  gananciaExistente,
  onCancelar,
}: AdminGananciaFormProps) {
  const router = useRouter();
  const esEdicion = !!gananciaExistente;

  const [monto, setMonto] = useState(
    gananciaExistente ? String(gananciaExistente.monto) : ""
  );
  const [concepto, setConcepto] = useState(
    gananciaExistente?.concepto ?? ""
  );
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [abierto, setAbierto] = useState(esEdicion);

  function cerrar() {
    setAbierto(false);
    onCancelar?.();
  }

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const montoNum = parseFloat(monto);
    if (isNaN(montoNum) || montoNum <= 0) {
      setError("El monto debe ser un número mayor a cero.");
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();

    const { error } = esEdicion
      ? await supabase
          .from("ganancias_concursos")
          .update({ monto: montoNum, concepto: concepto || null })
          .eq("id", gananciaExistente.id)
      : await supabase.from("ganancias_concursos").insert({
          usuario_id: usuarioId,
          monto: montoNum,
          concepto: concepto || null,
        });

    setGuardando(false);

    if (error) {
      setError("No se pudo guardar. Verifica tu permiso de admin.");
      return;
    }

    if (esEdicion) {
      onCancelar?.();
    } else {
      setMonto("");
      setConcepto("");
      setAbierto(false);
    }
    router.refresh();
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-4 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        + Agregar ganancia
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-4"
    >
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-display font-semibold text-sm">
          {esEdicion ? "Editar ganancia" : "Agregar ganancia"}
        </h3>
        <button
          type="button"
          onClick={cerrar}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>

      <div className="grid grid-cols-2 gap-2.5 mb-2.5">
        <input
          required
          value={monto}
          onChange={(e) => setMonto(e.target.value)}
          aria-label="Monto en USD"
          placeholder="Monto (USD)"
          inputMode="decimal"
          className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
        <input
          value={concepto}
          onChange={(e) => setConcepto(e.target.value)}
          aria-label="Concepto"
          placeholder="Concepto (ej. Concurso enero)"
          className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
      </div>

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? "Guardando..." : esEdicion ? "Guardar cambios" : "Agregar"}
      </button>
    </form>
  );
}
