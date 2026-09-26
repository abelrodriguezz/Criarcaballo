"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { fechaEnNY } from "@/lib/horarioMercado";

const FORMATO_PAR = /^[A-Z0-9]{5,20}$/;

export function AdminPickForm() {
  const router = useRouter();
  const [activo, setActivo] = useState("");
  const [nota, setNota] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [abierto, setAbierto] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const activoNormalizado = activo.trim().toUpperCase();
    if (!FORMATO_PAR.test(activoNormalizado)) {
      setError(
        "Debe ser el par completo de Binance (moneda + moneda de cotización), ej. BTCUSDT — no solo BTC."
      );
      return;
    }

    setGuardando(true);

    // El regex de arriba solo valida forma (largo/mayúsculas), no que el
    // par realmente exista en Binance — un typo como "BTCUSD" (sin la
    // "T") pasaba igual y dejaba a todos sin poder operar hasta que
    // alguien lo notara al intentar abrir una operación. Se confirma
    // contra la misma API pública que usa el resto de la app antes de
    // guardar.
    try {
      const resPrecio = await fetch(
        `https://api.binance.com/api/v3/ticker/price?symbol=${encodeURIComponent(activoNormalizado)}`,
        { signal: AbortSignal.timeout(8_000) }
      );
      if (!resPrecio.ok) {
        setGuardando(false);
        setError(
          `"${activoNormalizado}" no existe en Binance. Revisa que sea el par completo (ej. BTCUSDT, no BTCUSD).`
        );
        return;
      }
    } catch {
      // Binance responde el 400 de "Invalid symbol" SIN cabecera CORS, así
      // que el navegador lo convierte en un error de red y el `!res.ok` de
      // arriba nunca se ve. Para distinguir "par inexistente" de "no hay
      // conexión con Binance" se prueba un par que seguro existe.
      const binanceResponde = await fetch(
        "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT",
        { signal: AbortSignal.timeout(8_000) }
      )
        .then((r) => r.ok)
        .catch(() => false);
      setGuardando(false);
      setError(
        binanceResponde
          ? `"${activoNormalizado}" no existe en Binance. Revisa que sea el par completo (ej. BTCUSDT, no BTCUSD).`
          : "No se pudo verificar el par contra Binance. Intenta de nuevo."
      );
      return;
    }

    const supabase = crearClienteSupabase();
    const { error } = await supabase.from("pick_del_dia").insert({
      activo: activoNormalizado,
      nota_admin: nota || null,
      // El día de la bolsa de Nueva York, no el día UTC: definiendo el
      // pick después de las 8pm hora de NY, toISOString() ya devolvía la
      // fecha de mañana y el pick quedaba fechado un día adelantado
      // respecto a los reportes (que sí cuentan el día en horario NY).
      fecha: fechaEnNY(),
    });

    setGuardando(false);

    if (error) {
      setError("No se pudo guardar. Verifica tu permiso de admin.");
      return;
    }

    setActivo("");
    setNota("");
    setAbierto(false);
    router.refresh();
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-6 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        + Definir pick del día (admin)
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-6"
    >
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-display font-semibold text-sm">
          Pick del día
        </h3>
        <button
          type="button"
          onClick={() => setAbierto(false)}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>

      <input
        required
        value={activo}
        onChange={(e) => setActivo(e.target.value)}
        aria-label="Par de Binance" placeholder="Par completo de Binance (ej. BTCUSDT, no solo BTC)"
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <textarea
        value={nota}
        onChange={(e) => setNota(e.target.value)}
        aria-label="Nota" placeholder="Nota (opcional) — por qué se eligió"
        rows={2}
        className="w-full px-3 py-2 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
      />

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? "Guardando..." : "Definir como pick de hoy"}
      </button>
    </form>
  );
}
