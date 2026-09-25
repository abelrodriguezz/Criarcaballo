"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { IconoWallet } from "@/components/ui/Iconos";
import { formatearDinero, parsearMontoUsuario } from "@/lib/format";
import type { Diccionario } from "@/lib/i18n";
import type { SolicitudRetiro } from "@/lib/types";

export function BotonSolicitarRetiro({
  disponible,
  walletActual,
  solicitudPendiente,
  historial,
  t,
}: {
  disponible: number;
  walletActual: string | null;
  solicitudPendiente: SolicitudRetiro | null;
  historial: SolicitudRetiro[];
  t: Diccionario;
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [monto, setMonto] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [enviado, setEnviado] = useState(false);
  const [enviando, setEnviando] = useState(false);

  function abrir() {
    setMonto("");
    setError(null);
    setEnviado(false);
    setAbierto(true);
  }

  function cerrar() {
    setAbierto(false);
    if (enviado) router.refresh();
  }

  async function manejarEnviar() {
    if (enviando) return;
    const num = parsearMontoUsuario(monto);
    const redondeado = Math.round(num * 100) / 100;
    if (!Number.isFinite(redondeado) || redondeado <= 0) {
      setError(t.perfil.retirarMontoInvalido);
      return;
    }
    if (redondeado > disponible) {
      setError(t.perfil.retirarMontoExcedeDisponible);
      return;
    }
    setError(null);
    setEnviando(true);
    // La validacion real (disponible, wallet registrada, sin otra
    // pendiente) vuelve a correr server-side dentro de esta RPC —
    // nunca confiar en los chequeos del formulario para dinero.
    const supabase = crearClienteSupabase();
    const { error: dbError } = await supabase.rpc("solicitar_retiro", {
      p_monto: redondeado,
    });
    setEnviando(false);

    if (dbError) {
      setError(dbError.message || t.perfil.retirarErrorGuardar);
      return;
    }
    setEnviado(true);
  }

  const sinWallet = !walletActual || walletActual.trim() === "";

  return (
    <>
      <button
        onClick={abrir}
        className="w-full text-left border border-[var(--border)] rounded-2xl p-4 mb-3 flex items-center gap-3.5 hover:bg-surface-hover hover:border-brand-primary/40 transition-colors"
      >
        <div className="shrink-0 w-10 h-10 rounded-[4px] bg-brand-secondary/10 text-brand-secondary flex items-center justify-center">
          <IconoWallet />
        </div>
        <div className="min-w-0 flex-1">
          <div className="font-medium text-sm">{t.perfil.retirar}</div>
          {solicitudPendiente ? (
            <div className="text-[12px] text-brand-secondary tabular">
              ${formatearDinero(solicitudPendiente.monto)} — {t.perfil.pendiente}
            </div>
          ) : disponible > 0 ? (
            <div className="text-[12px] text-foreground-muted tabular">
              {t.perfil.retirarDisponibleLabel}: ${formatearDinero(disponible)}
            </div>
          ) : null}
        </div>
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
          className="w-4 h-4 shrink-0 text-foreground-muted"
        >
          <polyline points="9 18 15 12 9 6" />
        </svg>
      </button>

      {abierto && (
        <div
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
          onClick={cerrar}
        >
          <div
            className="bg-surface border border-[var(--border)] rounded-2xl p-5 max-w-[380px] w-full"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex justify-between items-center mb-3">
              <h3 className="font-display font-semibold text-base">
                {t.perfil.retirarModalTitulo}
              </h3>
              <button
                onClick={cerrar}
                className="text-foreground-muted text-sm"
                aria-label="Cerrar"
              >
                ✕
              </button>
            </div>

            {enviado ? (
              <>
                <p className="text-sm mb-4">{t.perfil.retirarEnviado}</p>
                <button
                  onClick={cerrar}
                  className="w-full bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-sm py-3 rounded-xl transition-colors"
                >
                  {t.perfil.retirarEntendido}
                </button>
              </>
            ) : solicitudPendiente ? (
              <p className="text-sm text-foreground-muted">
                {t.perfil.retirarYaPendiente}
              </p>
            ) : sinWallet ? (
              <p className="text-sm text-foreground-muted">
                {t.perfil.retirarSinWallet}
              </p>
            ) : disponible <= 0 ? (
              <p className="text-sm text-foreground-muted">
                {t.perfil.retirarSinDisponible}
              </p>
            ) : (
              <>
                <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
                  {t.perfil.retirarWalletLabel}
                </label>
                <input
                  readOnly
                  value={walletActual ?? ""}
                  className="w-full px-3 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-[13px] font-mono truncate"
                />

                <div className="flex justify-between items-center mb-1.5">
                  <label className="text-[12px] font-medium text-foreground-muted">
                    {t.perfil.retirarMontoLabel}
                  </label>
                  <button
                    type="button"
                    onClick={() => setMonto(String(disponible))}
                    className="text-[12px] font-semibold text-brand-primary"
                  >
                    {t.perfil.retirarDisponibleLabel}: ${formatearDinero(disponible)}
                  </button>
                </div>
                <input
                  value={monto}
                  onChange={(e) => setMonto(e.target.value)}
                  inputMode="decimal"
                  placeholder="0.00"
                  className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm font-mono"
                />

                {error && <p className="text-loss text-[13px] mb-3">{error}</p>}

                <button
                  onClick={manejarEnviar}
                  disabled={enviando}
                  className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
                >
                  {enviando ? "..." : t.perfil.retirarEnviar}
                </button>
              </>
            )}

            {historial.length > 0 && !enviado && (
              <div className="mt-4 pt-4 border-t border-[var(--border)]">
                <div className="text-[12px] font-medium text-foreground-muted mb-2">
                  {t.perfil.retirarHistorialTitulo}
                </div>
                <div className="flex flex-col gap-1.5">
                  {historial.map((s) => (
                    <div
                      key={s.id}
                      className="flex justify-between items-center text-[12px]"
                    >
                      <span className="text-foreground-muted">
                        {new Date(s.created_at).toLocaleDateString("es-DO", {
                          day: "numeric",
                          month: "short",
                        })}
                      </span>
                      <span
                        className={
                          s.estado === "pagado"
                            ? "text-gain"
                            : s.estado === "rechazado"
                              ? "text-loss"
                              : "text-brand-secondary"
                        }
                      >
                        ${formatearDinero(s.monto)} ·{" "}
                        {s.estado === "pagado"
                          ? t.perfil.pagado
                          : s.estado === "rechazado"
                            ? t.perfil.retirarRechazado
                            : t.perfil.pendiente}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}
