"use client";

import { useState } from "react";
import { abrirOperacion } from "@/lib/actions/paperTrading";
import { formatearDinero } from "@/lib/format";

export function AbrirOperacionForm({
  activo,
  saldoDisponible,
  mercadoAbierto,
  esAdmin,
}: {
  activo: string;
  saldoDisponible: number;
  mercadoAbierto: boolean;
  esAdmin: boolean;
}) {
  const puedeOperar = mercadoAbierto || esAdmin;
  const [tipo, setTipo] = useState<"compra" | "venta">("compra");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function accion(formData: FormData) {
    setError(null);
    setEnviando(true);
    try {
      // La server action DEVUELVE el fallo esperado (mercado cerrado, saldo
      // insuficiente...). Si lo lanzara, en producción el mensaje real
      // nunca llegaría hasta aquí — ver src/lib/actions/resultado.ts.
      const resultado = await abrirOperacion(formData);
      if (!resultado.ok) setError(resultado.error);
    } catch {
      setError(
        "No se pudo abrir la operación en este momento. Inténtalo de nuevo."
      );
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
          // El saldo tiene muchos decimales (la ganancia es diferencia de
          // precio × cantidad) y con step="0.01" el navegador rechazaría
          // por "paso inválido" un monto igual al máximo exacto: se
          // redondea hacia abajo a centavos.
          max={Math.floor(saldoDisponible * 100) / 100}
          step="0.01"
          required
          placeholder="Monto de tu saldo de inversión a usar (USD)"
          className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
        <p className="text-[12px] text-foreground-muted mt-1">
          Disponible: ${formatearDinero(saldoDisponible)}
        </p>
      </div>

      {!mercadoAbierto && (
        <p className="text-[12px] text-brand-secondary bg-brand-secondary/10 rounded-lg px-3 py-2">
          {esAdmin
            ? "El mercado está cerrado — como admin puedes operar igual."
            : "El mercado está cerrado. Se puede operar de lunes a viernes, 9:30am a 4:00pm hora de Nueva York."}
        </p>
      )}

      {error && <p className="text-loss text-[13px]">{error}</p>}

      <button
        type="submit"
        disabled={enviando || saldoDisponible <= 0 || !puedeOperar}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {enviando ? "Abriendo..." : "Abrir operación"}
      </button>
    </form>
  );
}
