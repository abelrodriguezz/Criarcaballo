"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { parsearNumero } from "@/lib/format";
import type { ConfigPremioReferido } from "@/lib/config-referidos";

// Literal duplicado a propósito, no importado de "@/lib/config-referidos":
// ese módulo usa crearClienteSupabaseServidor() (next/headers), que rompe
// el build en cuanto lo toca un componente "use client" — mismo problema
// ya documentado con el split de i18n cliente/servidor.
const CLAVE_PREMIO_REFERIDO = "premio_referido";

export function AdminPremioReferidoForm({
  configActual,
}: {
  configActual: ConfigPremioReferido;
}) {
  const router = useRouter();
  const [editando, setEditando] = useState(false);
  const [porcentaje, setPorcentaje] = useState(String(configActual.porcentaje));
  const [bonoCada, setBonoCada] = useState(String(configActual.bonoCada));
  const [bonoMonto, setBonoMonto] = useState(String(configActual.bonoMonto));
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const porcentajeNum = parsearNumero(porcentaje);
    const bonoCadaNum = parsearNumero(bonoCada);
    const bonoMontoNum = parsearNumero(bonoMonto);

    if (!Number.isFinite(porcentajeNum) || porcentajeNum < 0 || porcentajeNum > 100) {
      setError("El porcentaje debe estar entre 0 y 100.");
      return;
    }
    if (!Number.isInteger(bonoCadaNum) || bonoCadaNum <= 0) {
      setError("La cantidad de referidos para el bono debe ser un entero mayor a cero.");
      return;
    }
    if (!Number.isFinite(bonoMontoNum) || bonoMontoNum < 0) {
      setError("El monto del bono debe ser un número igual o mayor a cero.");
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.from("config_portada").upsert(
      {
        clave: CLAVE_PREMIO_REFERIDO,
        valor: {
          porcentaje: porcentajeNum,
          bono_cada: bonoCadaNum,
          bono_monto: bonoMontoNum,
        },
      },
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
        ✎ Comisión {configActual.porcentaje}% por depósito · Bono $
        {configActual.bonoMonto.toFixed(2)} cada {configActual.bonoCada}{" "}
        referidos calificados (editar)
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
          Configuración de premios por referido
        </h3>
        <button
          type="button"
          onClick={() => {
            setEditando(false);
            setPorcentaje(String(configActual.porcentaje));
            setBonoCada(String(configActual.bonoCada));
            setBonoMonto(String(configActual.bonoMonto));
            setError(null);
          }}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>

      <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
        Comisión — % del depósito simulado del invitado
      </label>
      <input
        value={porcentaje}
        onChange={(e) => setPorcentaje(e.target.value)}
        inputMode="decimal"
        placeholder="Ej. 10"
        className="w-full px-3.5 py-2.5 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />

      <div className="grid grid-cols-2 gap-2.5 mb-2.5">
        <div>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
            Bono cada X referidos
          </label>
          <input
            value={bonoCada}
            onChange={(e) => setBonoCada(e.target.value)}
            inputMode="numeric"
            placeholder="Ej. 10"
            className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
        <div>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
            Monto del bono (USDT)
          </label>
          <input
            value={bonoMonto}
            onChange={(e) => setBonoMonto(e.target.value)}
            inputMode="decimal"
            placeholder="Ej. 1000"
            className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
      </div>

      <p className="text-[12px] text-foreground-muted mb-3">
        Cuando un invitado hace su depósito simulado, se le genera al
        instante a quien lo invitó una comisión pendiente por ese
        porcentaje. Al llegar a un múltiplo de la cantidad de referidos
        configurada (los que ya depositaron), se suma además el bono —
        se repite cada vez que se alcanza otro múltiplo. Los cambios solo
        aplican hacia adelante, no a lo ya otorgado.
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
