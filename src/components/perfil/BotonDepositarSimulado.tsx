"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { registrarDepositoSimulado } from "@/lib/actions/depositos";
import { CopiarBoton } from "@/components/ui/CopiarBoton";
import { IconoWallet, IconoImagen } from "@/components/ui/Iconos";
import { formatearDinero, parsearMontoUsuario } from "@/lib/format";
import type { Diccionario } from "@/lib/i18n";

// Tope del monto simulado. Tiene que coincidir con el `check` de la
// migración 027: así un monto absurdo se rechaza aquí con un mensaje
// claro en vez de llegar a la base y volver como un error de guardado
// genérico.
const MONTO_MAXIMO = 100_000_000;
const TIPOS_IMAGEN_ACEPTADOS = "image/jpeg,image/png,image/webp";
const TAMANO_MAXIMO_IMAGEN = 5 * 1024 * 1024; // 5 MB, igual que el bucket/servidor

export function BotonDepositarSimulado({
  walletsAdmin,
  mensajeSimulacion,
  depositoExistente,
  t,
}: {
  walletsAdmin: string[];
  mensajeSimulacion: string;
  depositoExistente: { monto: number; pagado: boolean } | null;
  t: Diccionario;
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [walletElegida, setWalletElegida] = useState<string | null>(null);
  const [monto, setMonto] = useState("");
  const [comprobante, setComprobante] = useState<File | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [enviado, setEnviado] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const inputArchivoRef = useRef<HTMLInputElement>(null);

  function abrir() {
    // Al azar cada vez que se abre, no solo una vez por carga de página.
    const elegida =
      walletsAdmin.length > 0
        ? walletsAdmin[Math.floor(Math.random() * walletsAdmin.length)]
        : null;
    setWalletElegida(elegida);
    setMonto("");
    setComprobante(null);
    setError(null);
    setEnviado(false);
    setAbierto(true);
  }

  function elegirComprobante(archivo: File | undefined) {
    if (!archivo) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(archivo.type)) {
      setError(t.perfil.depositarComprobanteTipoInvalido);
      return;
    }
    if (archivo.size > TAMANO_MAXIMO_IMAGEN) {
      setError(t.perfil.depositarComprobanteMuyPesada);
      return;
    }
    setError(null);
    setComprobante(archivo);
  }

  function cerrar() {
    setAbierto(false);
    // Si se acaba de registrar el depósito, refresca para que el resto de
    // la página (y este mismo componente) refleje el estado "ya hecho".
    if (enviado) router.refresh();
  }

  async function manejarEnviar() {
    if (enviando) return; // doble clic: un segundo envío no debe colarse
    const num = parsearMontoUsuario(monto);
    // La columna es numeric(14,2): redondear aquí igual que la base para
    // que un "0.004" no pase esta validación y muera después contra el
    // check (monto > 0) con un error de guardado sin explicación.
    const redondeado = Math.round(num * 100) / 100;
    if (!Number.isFinite(redondeado) || redondeado <= 0) {
      setError(t.perfil.depositarMontoInvalido);
      return;
    }
    if (redondeado > MONTO_MAXIMO) {
      setError(t.perfil.depositarMontoMaximo);
      return;
    }
    if (!comprobante) {
      setError(t.perfil.depositarComprobanteObligatorio);
      return;
    }
    setError(null);
    setEnviando(true);

    const formData = new FormData();
    formData.set("monto", String(redondeado));
    if (walletElegida) formData.set("walletMostrada", walletElegida);
    formData.set("comprobante", comprobante);

    const resultado = await registrarDepositoSimulado(formData);
    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.error);
      return;
    }
    setEnviado(true);
  }

  // registrarDepositoSimulado hace revalidatePath("/perfil"): Next.js
  // refresca este Server Component padre automáticamente apenas la Server
  // Action resuelve, ANTES de que el usuario alcance a ver la pantalla de
  // éxito de abajo. Sin este blindaje, `depositoExistente` llega no-nulo a
  // mitad del modal abierto y esta rama "ya hiciste tu depósito" se
  // adelantaba a tapar por completo el "Entendido"/"Ir al chat" (reproducido
  // consistentemente contra `next build && next start`, aunque no siempre
  // contra `next dev`). Mientras el modal siga abierto mostrando el éxito,
  // se ignora el prop recién refrescado; al cerrarlo (botón "Entendido"),
  // esta rama ya vuelve a aplicar normalmente.
  const mostrandoExito = abierto && enviado;

  if (depositoExistente && !mostrandoExito) {
    return (
      <div className="w-full border border-[var(--border)] rounded-2xl p-4 mb-3 flex items-center gap-3.5">
        <div className="shrink-0 w-10 h-10 rounded-[4px] bg-gain/10 text-gain flex items-center justify-center">
          <IconoWallet />
        </div>
        <div className="min-w-0 flex-1">
          <div className="font-medium text-sm">{t.perfil.depositarYaHecho}</div>
          <div className="text-[12px] text-foreground-muted tabular">
            {/* formatearDinero en vez de .toFixed: PostgREST devuelve un
                numeric no finito como string ("NaN"), y .toFixed sobre un
                string reventaba la página entera con un TypeError. */}
            ${formatearDinero(Number(depositoExistente.monto))} USDT
          </div>
          {/* Desde la migración 049 el saldo solo se acredita cuando el
              admin confirma el depósito — sin esto el usuario no tenía
              forma de saber si ya se lo acreditaron o sigue en revisión. */}
          <div
            className={`text-[12px] font-semibold mt-0.5 ${
              depositoExistente.pagado ? "text-gain" : "text-brand-secondary"
            }`}
          >
            {depositoExistente.pagado
              ? t.perfil.depositarEstadoAcreditado
              : t.perfil.depositarEstadoPendiente}
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
                <div className="flex gap-2">
                  <button
                    onClick={cerrar}
                    className="flex-1 bg-surface-hover hover:bg-surface border border-[var(--border)] text-foreground font-semibold text-sm py-3 rounded-xl transition-colors"
                  >
                    {t.perfil.depositarEntendido}
                  </button>
                  <Link
                    href="/soporte"
                    onClick={cerrar}
                    className="flex-1 text-center bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-sm py-3 rounded-xl transition-colors"
                  >
                    {t.perfil.depositarIrAlChat}
                  </Link>
                </div>
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

                <label className="block text-[12px] font-medium text-foreground-muted mb-1.5">
                  {t.perfil.depositarComprobanteLabel}
                </label>
                <input
                  ref={inputArchivoRef}
                  type="file"
                  accept={TIPOS_IMAGEN_ACEPTADOS}
                  onChange={(e) => elegirComprobante(e.target.files?.[0])}
                  className="hidden"
                  aria-label={t.perfil.depositarComprobanteLabel}
                />
                <button
                  type="button"
                  onClick={() => inputArchivoRef.current?.click()}
                  className="w-full flex items-center gap-2 px-3.5 py-2.5 mb-3 rounded-lg border border-dashed border-[var(--border)] text-[13px] text-foreground-muted hover:text-foreground hover:bg-surface-hover transition-colors"
                >
                  <IconoImagen className="w-4 h-4 shrink-0" />
                  <span className="flex-1 min-w-0 truncate text-left">
                    {comprobante ? comprobante.name : t.perfil.depositarComprobanteAdjuntar}
                  </span>
                </button>

                {error && <p className="text-loss text-[13px] mb-3">{error}</p>}

                <button
                  onClick={manejarEnviar}
                  disabled={enviando || !comprobante}
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
