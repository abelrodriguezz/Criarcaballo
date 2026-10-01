"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { parsearMontoUsuario, formatearDinero } from "@/lib/format";
import { rellenar, type TextosAdmin } from "@/lib/i18n";
import type { ConfigPremioReferido } from "@/lib/config-referidos";

// Literal duplicado a propósito, no importado de "@/lib/config-referidos":
// ese módulo usa crearClienteSupabaseServidor() (next/headers), que rompe
// el build en cuanto lo toca un componente "use client" — mismo problema
// ya documentado con el split de i18n cliente/servidor.
const CLAVE_PREMIO_REFERIDO = "premio_referido";

export function AdminPremioReferidoForm({
  configActual,
  ta,
}: {
  configActual: ConfigPremioReferido;
  ta: TextosAdmin;
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

    // parsearMontoUsuario, no parsearNumero: este último borra TODAS las
    // comas (las trata siempre como separador de miles), así que "2,5"
    // (como se escribe en español) se leía como 25 en vez de 2.5 — mismo
    // bug ya encontrado y arreglado en AdminFeeRetiroForm.tsx.
    const porcentajeNum = Math.round(parsearMontoUsuario(porcentaje) * 100) / 100;
    const bonoCadaNum = Math.round(parsearMontoUsuario(bonoCada));
    const bonoMontoNum = Math.round(parsearMontoUsuario(bonoMonto) * 100) / 100;

    if (!Number.isFinite(porcentajeNum) || porcentajeNum < 0 || porcentajeNum > 100) {
      setError(ta.premioErrPorcentaje);
      return;
    }
    if (!Number.isInteger(bonoCadaNum) || bonoCadaNum <= 0) {
      setError(ta.premioErrBonoCada);
      return;
    }
    if (!Number.isFinite(bonoMontoNum) || bonoMontoNum < 0) {
      setError(ta.premioErrBonoMonto);
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
      setError(ta.errorPermiso);
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
        {rellenar(ta.premioResumen, {
          p: configActual.porcentaje,
          m: formatearDinero(configActual.bonoMonto),
          c: configActual.bonoCada,
        })}
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
          {ta.premioTitulo}
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
          {ta.cancelar}
        </button>
      </div>

      <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
        {ta.premioComisionLabel}
      </label>
      <input
        value={porcentaje}
        onChange={(e) => setPorcentaje(e.target.value)}
        inputMode="decimal"
        placeholder={`${ta.ejemplo} 10`}
        className="w-full px-3.5 py-2.5 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />

      <div className="grid grid-cols-2 gap-2.5 mb-2.5">
        <div>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
            {ta.premioBonoCadaLabel}
          </label>
          <input
            value={bonoCada}
            onChange={(e) => setBonoCada(e.target.value)}
            inputMode="numeric"
            placeholder={`${ta.ejemplo} 10`}
            className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
        <div>
          <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
            {ta.premioBonoMontoLabel}
          </label>
          <input
            value={bonoMonto}
            onChange={(e) => setBonoMonto(e.target.value)}
            inputMode="decimal"
            placeholder={`${ta.ejemplo} 1000`}
            className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
      </div>

      <p className="text-[12px] text-foreground-muted mb-3">
        {ta.premioAyuda}
      </p>

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? ta.guardando : ta.guardarCambios}
      </button>
    </form>
  );
}
