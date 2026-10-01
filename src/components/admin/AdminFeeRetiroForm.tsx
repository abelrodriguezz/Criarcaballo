"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { parsearMontoUsuario } from "@/lib/format";

// Literal duplicado a propósito, no importado de "@/lib/config-retiros":
// ese módulo usa crearClienteSupabaseServidor() (next/headers), que rompe
// el build en cuanto lo toca un componente "use client" — mismo patrón ya
// usado en AdminPremioReferidoForm.tsx.
const CLAVE_FEE_RETIRO = "fee_retiro";

export function AdminFeeRetiroForm({ feeActual }: { feeActual: number }) {
  const router = useRouter();
  const [editando, setEditando] = useState(false);
  const [porcentaje, setPorcentaje] = useState(String(feeActual));
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    // parsearMontoUsuario y no parsearNumero: este último borra TODAS las
    // comas (las trata como separador de miles), así que "2,5" (como se
    // escribe en español) se guardaba como 25% en vez de 2.5%, y además
    // aceptaba basura con prefijo numérico ("10abc" → 10) por parseFloat.
    const leido = parsearMontoUsuario(porcentaje.replace(/%\s*$/, ""));
    // Máximo 2 decimales (ej. 2.75%): más precisión no tiene sentido y
    // ensucia el desglose que ven el usuario y el admin.
    const porcentajeNum = Math.round(leido * 100) / 100;
    if (!Number.isFinite(porcentajeNum) || porcentajeNum < 0 || porcentajeNum > 100) {
      setError("Ingresa un porcentaje entre 0 y 100.");
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.from("config_portada").upsert(
      { clave: CLAVE_FEE_RETIRO, valor: { porcentaje: porcentajeNum } },
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
        className="w-full text-left border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-4 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        {feeActual > 0
          ? `Fee de retiro: ${feeActual}% (se le descuenta al usuario del monto pedido)`
          : "Sin fee de retiro configurado — toca para agregar uno"}
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-4"
    >
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-display font-semibold text-sm">Fee de retiro</h3>
        <button
          type="button"
          onClick={() => {
            setEditando(false);
            setPorcentaje(String(feeActual));
            setError(null);
          }}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>

      <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
        Porcentaje sobre el monto pedido
      </label>
      <input
        value={porcentaje}
        onChange={(e) => setPorcentaje(e.target.value)}
        inputMode="decimal"
        placeholder="Ej. 10"
        className="w-full px-3.5 py-2.5 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />

      <p className="text-[12px] text-foreground-muted mb-3">
        Se le resta al usuario del monto que pide, no al fondo de ganancias
        pendientes: si pide $50 con un fee del 10%, se le transfieren $45.
        Las solicitudes ya hechas (pendientes o pagadas) conservan el % con
        el que se pidieron, aunque cambies este valor después.
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
