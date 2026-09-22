"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { parsearNumero } from "@/lib/format";

// Literal duplicado a propósito, no importado de "@/lib/config-referidos":
// ese módulo usa crearClienteSupabaseServidor() (next/headers), que rompe
// el build en cuanto lo toca un componente "use client" — mismo problema
// ya documentado con el split de i18n cliente/servidor.
const CLAVE_PREMIO_REFERIDO = "premio_referido";

export function AdminPremioReferidoForm({
  montoActual,
}: {
  montoActual: number;
}) {
  const router = useRouter();
  const [editando, setEditando] = useState(false);
  const [monto, setMonto] = useState(String(montoActual));
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const montoNum = parsearNumero(monto);
    if (!Number.isFinite(montoNum) || montoNum <= 0) {
      setError("El monto debe ser un número mayor a cero.");
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase
      .from("config_portada")
      .upsert(
        { clave: CLAVE_PREMIO_REFERIDO, valor: { monto: montoNum } },
        { onConflict: "clave" }
      );
    setGuardando(false);

    if (error) {
      setError("No se pudo guardar. Verifica tu permiso de admin.");
      return;
    }

    setEditando(false);
    router.refresh();
  }

  if (!editando) {
    return (
      <button
        onClick={() => setEditando(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-4 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        ✎ Premio actual por referido: ${montoActual.toFixed(2)} USDT (editar)
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
          Premio por cada referido (USDT)
        </h3>
        <button
          type="button"
          onClick={() => {
            setEditando(false);
            setMonto(String(montoActual));
            setError(null);
          }}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>

      <input
        value={monto}
        onChange={(e) => setMonto(e.target.value)}
        inputMode="decimal"
        placeholder="Monto en USDT"
        className="w-full px-3.5 py-2.5 mb-2 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <p className="text-[12px] text-foreground-muted mb-3">
        Este monto se usa como sugerencia al otorgar un premio nuevo — no
        cambia los premios ya otorgados.
      </p>

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? "Guardando..." : "Guardar cambios"}
      </button>
    </form>
  );
}
