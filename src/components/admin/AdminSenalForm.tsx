"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { parsearNumero } from "@/lib/format";
import type { Senal } from "@/lib/types";

// Mismo formato que exige AdminPickForm: el par completo de Binance. Si no
// existe en Binance, el cierre automático por velas (verificarTpSl.ts) no
// puede revisar la señal nunca.
const FORMATO_PAR = /^[A-Z0-9]{5,20}$/;

interface AdminSenalFormProps {
  senalExistente?: Senal;
  onCancelar?: () => void;
}

export function AdminSenalForm({
  senalExistente,
  onCancelar,
}: AdminSenalFormProps) {
  const router = useRouter();
  const esEdicion = !!senalExistente;

  const [par, setPar] = useState(senalExistente?.par ?? "");
  const [tipo, setTipo] = useState<"compra" | "venta">(
    senalExistente?.tipo ?? "compra"
  );
  const [entrada, setEntrada] = useState(
    senalExistente ? String(senalExistente.entrada) : ""
  );
  const [stopLoss, setStopLoss] = useState(
    senalExistente?.stop_loss != null ? String(senalExistente.stop_loss) : ""
  );
  const [takeProfit, setTakeProfit] = useState(
    senalExistente?.take_profit != null
      ? String(senalExistente.take_profit)
      : ""
  );
  const [razon, setRazon] = useState(senalExistente?.razon ?? "");
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

    const parNormalizado = par.trim().toUpperCase();
    if (!FORMATO_PAR.test(parNormalizado)) {
      setError(
        "Debe ser el par completo de Binance (moneda + moneda de cotización), " +
          "ej. BTCUSDT — no solo BTC. Si el par no existe en Binance, el " +
          "cierre automático por TP/SL nunca se va a poder aplicar."
      );
      return;
    }

    const entradaNum = parsearNumero(entrada);
    if (!Number.isFinite(entradaNum) || entradaNum <= 0) {
      setError("El precio de entrada debe ser un número mayor a cero.");
      return;
    }

    // Campos opcionales: vacío = null, pero un texto que no sea un número
    // NO puede pasar como null silencioso (antes, escribir "abc" en el
    // stop loss lo guardaba sin stop loss y sin avisar).
    const stopLossNum = stopLoss.trim() ? parsearNumero(stopLoss) : null;
    const takeProfitNum = takeProfit.trim() ? parsearNumero(takeProfit) : null;

    if (stopLossNum !== null && (!Number.isFinite(stopLossNum) || stopLossNum <= 0)) {
      setError("El stop loss debe ser un número mayor a cero (o dejarse vacío).");
      return;
    }
    if (
      takeProfitNum !== null &&
      (!Number.isFinite(takeProfitNum) || takeProfitNum <= 0)
    ) {
      setError("El take profit debe ser un número mayor a cero (o dejarse vacío).");
      return;
    }

    // Los niveles tienen que estar del lado correcto de la entrada. Sin
    // esta validación, una compra con el TP por debajo de la entrada la
    // cerraba sola el chequeo de velas como "TP tocado" con porcentaje
    // negativo en la primera vela revisada. La base de datos también lo
    // rechaza (constraint senales_niveles_coherentes, migración 019),
    // pero aquí el mensaje es entendible.
    const esCompra = tipo === "compra";
    if (takeProfitNum !== null) {
      if (esCompra && takeProfitNum <= entradaNum) {
        setError("En una señal de compra el take profit tiene que estar POR ENCIMA de la entrada.");
        return;
      }
      if (!esCompra && takeProfitNum >= entradaNum) {
        setError("En una señal de venta el take profit tiene que estar POR DEBAJO de la entrada.");
        return;
      }
    }
    if (stopLossNum !== null) {
      if (esCompra && stopLossNum >= entradaNum) {
        setError("En una señal de compra el stop loss tiene que estar POR DEBAJO de la entrada.");
        return;
      }
      if (!esCompra && stopLossNum <= entradaNum) {
        setError("En una señal de venta el stop loss tiene que estar POR ENCIMA de la entrada.");
        return;
      }
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const datos = {
      par: parNormalizado,
      tipo,
      entrada: entradaNum,
      stop_loss: stopLossNum,
      take_profit: takeProfitNum,
      razon: razon || null,
    };

    const { error } = esEdicion
      ? await supabase
          .from("senales")
          .update(datos)
          .eq("id", senalExistente.id)
      : await supabase.from("senales").insert(datos);

    setGuardando(false);

    if (error) {
      setError(
        error.message
          ? `No se pudo guardar: ${error.message}`
          : "No se pudo guardar. Verifica tu permiso de admin."
      );
      return;
    }

    if (esEdicion) {
      onCancelar?.();
    } else {
      setPar("");
      setEntrada("");
      setStopLoss("");
      setTakeProfit("");
      setRazon("");
      setAbierto(false);
    }
    router.refresh();
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-6 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        + Publicar señal (admin)
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
          {esEdicion ? "Editar señal" : "Publicar señal"}
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
          value={par}
          onChange={(e) => setPar(e.target.value)}
          aria-label="Par"
          placeholder="Par (ej. BTCUSDT)"
          className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
        <select
          aria-label="Tipo de señal"
          value={tipo}
          onChange={(e) => setTipo(e.target.value as "compra" | "venta")}
          className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
        >
          <option value="compra">Compra</option>
          <option value="venta">Venta</option>
        </select>
      </div>

      <div className="grid grid-cols-3 gap-2.5 mb-2.5">
        <input
          required
          value={entrada}
          onChange={(e) => setEntrada(e.target.value)}
          aria-label="Precio de entrada"
          placeholder="Entrada"
          inputMode="decimal"
          className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
        <input
          value={stopLoss}
          onChange={(e) => setStopLoss(e.target.value)}
          aria-label="Stop loss"
          placeholder="Stop loss"
          inputMode="decimal"
          className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
        <input
          value={takeProfit}
          onChange={(e) => setTakeProfit(e.target.value)}
          aria-label="Take profit"
          placeholder="Take profit"
          inputMode="decimal"
          className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
        />
      </div>

      <textarea
        value={razon ?? ""}
        onChange={(e) => setRazon(e.target.value)}
        aria-label="Razón del análisis"
        placeholder="Razón del análisis (opcional)"
        rows={2}
        className="w-full px-3 py-2 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
      />

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? "Guardando..." : esEdicion ? "Guardar cambios" : "Publicar"}
      </button>
    </form>
  );
}
