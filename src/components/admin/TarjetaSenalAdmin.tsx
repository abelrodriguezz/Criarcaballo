"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AdminSenalForm } from "@/components/admin/AdminSenalForm";
import { BotonEliminarAdmin } from "@/components/admin/BotonEliminarAdmin";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { urlGraficoTradingView } from "@/lib/format";
import { IconoTendenciaSubida } from "@/components/ui/Iconos";
import type { Senal } from "@/lib/types";
import type { Diccionario, Locale } from "@/lib/i18n";

export function TarjetaSenalAdmin({
  senal,
  esAdmin,
  t,
  locale = "es",
}: {
  senal: Senal;
  esAdmin: boolean;
  t: Diccionario;
  locale?: Locale;
}) {
  const router = useRouter();
  const [editando, setEditando] = useState(false);
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function marcarResultado(resultado: "tp" | "sl") {
    const precioCierre = resultado === "tp" ? senal.take_profit : senal.stop_loss;

    // Sin el nivel definido no hay a qué precio darla por cerrada: se
    // guardaba resultado = "tp" con precio_cierre y porcentaje en null, y
    // la tarjeta terminaba mostrando "Cerró en " sin ningún número.
    if (precioCierre == null) {
      setError(
        resultado === "tp"
          ? "Esta señal no tiene take profit definido. Edítala y agrégalo primero."
          : "Esta señal no tiene stop loss definido. Edítala y agrégalo primero."
      );
      return;
    }

    const porcentaje =
      senal.tipo === "compra"
        ? ((precioCierre - senal.entrada) / senal.entrada) * 100
        : ((senal.entrada - precioCierre) / senal.entrada) * 100;

    setError(null);
    setGuardando(true);
    const supabase = crearClienteSupabase();
    // .eq("estado", "activa") además del id: si el chequeo automático de
    // TP/SL la cerró justo antes (corre en cada carga de la página), este
    // update no pisa el resultado que ya se calculó contra las velas.
    const { data, error: errorSupabase } = await supabase
      .from("senales")
      .update({
        resultado,
        estado: "cerrada",
        precio_cierre: precioCierre,
        porcentaje_resultado: porcentaje,
        cerrado_en: new Date().toISOString(),
      })
      .eq("id", senal.id)
      .eq("estado", "activa")
      .select("id")
      .maybeSingle();
    setGuardando(false);

    if (errorSupabase) {
      setError("No se pudo guardar. Verifica tu permiso de admin.");
      return;
    }
    if (!data) {
      setError("Esta señal ya estaba cerrada; se refrescará la página.");
    }
    router.refresh();
  }

  if (editando) {
    return (
      <AdminSenalForm
        senalExistente={senal}
        onCancelar={() => setEditando(false)}
      />
    );
  }

  const esCompra = senal.tipo === "compra";

  const resultadoInfo = senal.resultado && (
    <div className="text-[13px] text-foreground-muted mt-1">
      {senal.precio_cierre != null
        ? `${t.senales.cerroEn} ${senal.precio_cierre}`
        : t.senales.cerradaManual}
      {senal.porcentaje_resultado != null && (
        <span
          className={senal.porcentaje_resultado >= 0 ? "text-gain" : "text-loss"}
        >
          {" "}
          ({senal.porcentaje_resultado >= 0 ? "+" : ""}
          {senal.porcentaje_resultado.toFixed(2)}%)
        </span>
      )}
      {senal.cerrado_en && (
        <>
          {" · "}
          {new Date(senal.cerrado_en).toLocaleDateString(
            locale === "en" ? "en-US" : "es-DO",
            { day: "numeric", month: "short", year: "numeric" }
          )}
        </>
      )}
    </div>
  );

  const botonesAdmin = esAdmin && (
    <div className="flex flex-wrap gap-3 mt-2.5">
      {!senal.resultado && (
        <>
          <button
            onClick={() => marcarResultado("tp")}
            disabled={guardando}
            className="text-xs font-semibold text-gain hover:underline disabled:opacity-50"
          >
            Marcar TP tocado
          </button>
          <button
            onClick={() => marcarResultado("sl")}
            disabled={guardando}
            className="text-xs font-semibold text-loss hover:underline disabled:opacity-50"
          >
            Marcar SL tocado
          </button>
        </>
      )}
      <button
        onClick={() => setEditando(true)}
        className="text-xs font-semibold text-brand-primary hover:underline"
      >
        Editar
      </button>
      <BotonEliminarAdmin
        tabla="senales"
        id={senal.id}
        textoConfirmacion={`¿Eliminar la señal de ${senal.par}?`}
      />
      {error && (
        <p className="text-loss text-[12px] basis-full">{error}</p>
      )}
    </div>
  );

  const linkGrafico = (
    <a
      href={urlGraficoTradingView(senal.par)}
      target="_blank"
      rel="noopener noreferrer"
      className="absolute inset-0 rounded-[4px]"
      aria-label={`Ver gráfico de ${senal.par} en TradingView`}
    />
  );

  // Antes de cerrarse, el acento sigue la dirección del trade (compra/venta).
  // Ya cerrada, sigue el resultado real (tp/sl) — más útil que la dirección
  // una vez que lo que importa es si ganó o perdió.
  const colorAcento = senal.resultado
    ? senal.resultado === "tp"
      ? "var(--gain)"
      : "var(--loss)"
    : esCompra
      ? "var(--gain)"
      : "var(--loss)";

  return (
    <div
      className="relative border-l-4 p-5 overflow-hidden bg-surface transition-transform hover:-translate-y-0.5"
      style={{ borderColor: colorAcento }}
    >
      {linkGrafico}
      <div className="relative z-10">
        <div className="flex items-center justify-between mb-3.5 gap-2">
          <div className="flex items-center gap-2.5 min-w-0">
            <div
              className="w-10 h-10 rounded-[4px] flex items-center justify-center text-white shrink-0"
              style={{ background: colorAcento }}
            >
              <IconoTendenciaSubida
                className={`w-5 h-5 ${esCompra ? "" : "scale-y-[-1]"}`}
              />
            </div>
            <div className="font-display font-bold text-xl truncate">
              {senal.par}
            </div>
          </div>
          <div className="flex flex-col items-end gap-1 shrink-0">
            <span
              className={`text-xs font-bold px-2.5 py-0.5 whitespace-nowrap ${
                esCompra ? "bg-gain/15 text-gain" : "bg-loss/15 text-loss"
              }`}
            >
              {esCompra ? t.senales.compra : t.senales.venta}
            </span>
            {senal.resultado && (
              <span
                className={`text-[11px] font-bold uppercase tracking-wide px-2.5 py-0.5 whitespace-nowrap ${
                  senal.resultado === "tp"
                    ? "bg-gain/15 text-gain"
                    : "bg-loss/15 text-loss"
                }`}
              >
                {senal.resultado === "tp" ? t.senales.tpTocado : t.senales.slTocado}
              </span>
            )}
          </div>
        </div>

        <div className="grid grid-cols-3 gap-2 mb-3.5">
          <div className="bg-background px-2.5 py-2 text-center">
            <div className="text-[10px] uppercase tracking-wide text-foreground-muted">
              {t.senales.entrada}
            </div>
            <div className="font-display font-bold text-sm tabular">
              {senal.entrada}
            </div>
          </div>
          <div className="bg-loss/10 px-2.5 py-2 text-center">
            <div className="text-[10px] uppercase tracking-wide text-loss">
              {t.senales.stopLoss}
            </div>
            <div className="font-display font-bold text-sm tabular text-loss">
              {senal.stop_loss ?? "—"}
            </div>
          </div>
          <div className="bg-gain/10 px-2.5 py-2 text-center">
            <div className="text-[10px] uppercase tracking-wide text-gain">
              {t.senales.takeProfit}
            </div>
            <div className="font-display font-bold text-sm tabular text-gain">
              {senal.take_profit ?? "—"}
            </div>
          </div>
        </div>

        {senal.razon && (
          <p className="text-[13px] text-foreground-muted">{senal.razon}</p>
        )}
        {resultadoInfo}
        {botonesAdmin}
      </div>
    </div>
  );
}
