"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { CopiarBoton } from "@/components/ui/CopiarBoton";
import { IconoWallet } from "@/components/ui/Iconos";
import type { Diccionario } from "@/lib/i18n";

export function BotonDepositarSimulado({
  usuarioId,
  walletsAdmin,
  mensajeSimulacion,
  depositoExistente,
  t,
}: {
  usuarioId: string;
  walletsAdmin: string[];
  mensajeSimulacion: string;
  depositoExistente: { monto: number } | null;
  t: Diccionario;
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [walletElegida, setWalletElegida] = useState<string | null>(null);
  const [monto, setMonto] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [enviado, setEnviado] = useState(false);
  const [enviando, setEnviando] = useState(false);

  function abrir() {
    // Al azar cada vez que se abre, no solo una vez por carga de página.
    const elegida =
      walletsAdmin.length > 0
        ? walletsAdmin[Math.floor(Math.random() * walletsAdmin.length)]
        : null;
    setWalletElegida(elegida);
    setMonto("");
    setError(null);
    setEnviado(false);
    setAbierto(true);
  }

  function cerrar() {
    setAbierto(false);
    // Si se acaba de registrar el depósito, refresca para que el resto de
    // la página (y este mismo componente) refleje el estado "ya hecho".
    if (enviado) router.refresh();
  }

  async function manejarEnviar() {
    const num = Number(monto.replace(",", "."));
    if (!Number.isFinite(num) || num <= 0) {
      setError(t.perfil.depositarMontoInvalido);
      return;
    }
    setError(null);
    setEnviando(true);
    // Sigue siendo una simulación (no se mueve dinero real ni se llama a
    // ninguna wallet) — pero ahora sí queda registrado el monto para que
    // el admin lo vea en Gestión de usuarios. El unique(usuario_id) en la
    // tabla es lo que impone "una sola vez" a nivel de base de datos.
    const supabase = crearClienteSupabase();
    const { error: dbError } = await supabase.from("depositos_simulados").insert({
      usuario_id: usuarioId,
      monto: num,
      wallet_mostrada: walletElegida,
    });
    setEnviando(false);

    if (dbError) {
      setError(t.perfil.depositarErrorGuardar);
      return;
    }
    setEnviado(true);
  }

  if (depositoExistente) {
    return (
      <div className="w-full border border-[var(--border)] rounded-2xl p-4 mb-3 flex items-center gap-3.5">
        <div className="shrink-0 w-10 h-10 rounded-[4px] bg-gain/10 text-gain flex items-center justify-center">
          <IconoWallet />
        </div>
        <div className="min-w-0 flex-1">
          <div className="font-medium text-sm">{t.perfil.depositarYaHecho}</div>
          <div className="text-[12px] text-foreground-muted tabular">
            ${depositoExistente.monto.toFixed(2)} USDT
          </div>
        </div>
      </div>
    );
  }

  return (
    <>
      <button
        onClick={abrir}
        className="w-full text-left border border-[var(--border)] rounded-2xl p-4 mb-3 flex items-center gap-3.5 hover:bg-surface-hover hover:border-brand-primary/40 transition-colors"
      >
        <div className="shrink-0 w-10 h-10 rounded-[4px] bg-gain/10 text-gain flex items-center justify-center">
          <IconoWallet />
        </div>
        <div className="min-w-0 flex-1">
          <div className="font-medium text-sm">{t.perfil.depositar}</div>
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
                {t.perfil.depositarModalTitulo}
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
                <p className="text-sm mb-4">{mensajeSimulacion}</p>
                <button
                  onClick={cerrar}
                  className="w-full bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-sm py-3 rounded-xl transition-colors"
                >
                  {t.perfil.depositarEntendido}
                </button>
              </>
            ) : walletElegida ? (
              <>
                <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
                  {t.perfil.depositarWalletLabel}
                </label>
                <div className="flex gap-2 mb-4">
                  <input
                    readOnly
                    value={walletElegida}
                    className="flex-1 min-w-0 px-3 py-2.5 rounded-lg border border-[var(--border)] bg-background text-[13px] font-mono truncate"
                  />
                  <CopiarBoton texto={walletElegida} t={t} />
                </div>

                <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
                  {t.perfil.depositarMontoLabel}
                </label>
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
                  {t.perfil.depositarEnviar}
                </button>
              </>
            ) : (
              <p className="text-sm text-foreground-muted">
                {t.perfil.depositarSinWallets}
              </p>
            )}
          </div>
        </div>
      )}
    </>
  );
}
