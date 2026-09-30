"use client";

import { useState } from "react";
import { abrirOperacion } from "@/lib/actions/paperTrading";
import { formatearDinero } from "@/lib/format";
import type { Diccionario } from "@/lib/i18n";

export function AbrirOperacionForm({
  activo,
  saldoDisponible,
  mercadoAbierto,
  mensajeMercadoCerrado,
  tradingHabilitado,
  esAdmin,
  t,
}: {
  activo: string;
  saldoDisponible: number;
  mercadoAbierto: boolean;
  /** Horario configurado (migración 064), ya formateado en el idioma actual. */
  mensajeMercadoCerrado?: string;
  /** Antes solo se sabía al intentar abrir (mensaje de la server action);
   * ahora se avisa de entrada, sin esperar al clic. */
  tradingHabilitado: boolean;
  esAdmin: boolean;
  t: Diccionario;
}) {
  const puedeOperar = (mercadoAbierto || esAdmin) && tradingHabilitado;
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Se opera siempre con el saldo completo — el campo se deja visible pero
  // de solo lectura (no "disabled": un input disabled no se manda en el
  // FormData, y la server action necesita recibir este valor igual).
  const montoCompleto = Math.floor(saldoDisponible * 100) / 100;

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
      setError(t.abrirOperacion.errorGenerico);
    } finally {
      setEnviando(false);
    }
  }

  return (
    <form action={accion} className="flex flex-col gap-3">
      <input type="hidden" name="activo" value={activo} />

      <div className="py-2 rounded-lg text-sm font-semibold border bg-gain/15 border-gain text-gain text-center">
        {t.tradeDelDia.compra}
      </div>
      <input type="hidden" name="tipo" value="compra" />

      <div>
        <input
          name="monto"
          type="number"
          readOnly
          value={montoCompleto}
          aria-label={t.abrirOperacion.montoPlaceholder}
          className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-surface text-sm text-foreground-muted cursor-not-allowed"
        />
        <p className="text-[12px] text-foreground-muted mt-1">
          {t.abrirOperacion.disponible}: ${formatearDinero(saldoDisponible)}
        </p>
      </div>

      {!mercadoAbierto && (
        <p className="text-[12px] text-brand-secondary bg-brand-secondary/10 rounded-lg px-3 py-2">
          {esAdmin
            ? t.abrirOperacion.mercadoCerradoAdmin
            : mensajeMercadoCerrado || t.abrirOperacion.mercadoCerrado}
        </p>
      )}

      {!tradingHabilitado && (
        <p className="text-[12px] text-loss bg-loss/10 rounded-lg px-3 py-2">
          {t.errores.tradingDeshabilitado}
        </p>
      )}

      {saldoDisponible <= 0 && (
        <p className="text-[12px] text-brand-secondary bg-brand-secondary/10 rounded-lg px-3 py-2">
          {t.abrirOperacion.sinSaldo}
        </p>
      )}

      {error && <p className="text-loss text-[13px]">{error}</p>}

      <button
        type="submit"
        disabled={enviando || saldoDisponible <= 0 || !puedeOperar}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {enviando ? t.abrirOperacion.abriendo : t.abrirOperacion.abrirOperacion}
      </button>
    </form>
  );
}
