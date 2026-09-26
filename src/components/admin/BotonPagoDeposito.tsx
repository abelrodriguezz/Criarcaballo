"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

export function BotonPagoDeposito({
  depositoId,
  pagado,
}: {
  depositoId: string;
  pagado: boolean;
}) {
  const router = useRouter();
  const [guardando, setGuardando] = useState(false);
  const [refrescando, startTransition] = useTransition();
  const deshabilitado = guardando || refrescando;

  async function alternarPago() {
    const confirmacion = pagado
      ? window.confirm(
          "¿Revertir a pendiente? Esto le RESTA el monto de este depósito al saldo de inversión del usuario."
        )
      : window.confirm(
          "¿Confirmas que el dinero llegó de verdad? Esto le SUMA el monto de este depósito al saldo de inversión del usuario."
        );
    if (!confirmacion) return;

    setGuardando(true);
    const supabase = crearClienteSupabase();
    // Esta RPC (migración 049/050) marca el depósito Y ajusta saldo_virtual
    // en la misma transacción — nunca un UPDATE directo de "pagado" solo,
    // porque el saldo tiene que moverse exactamente junto con el estado.
    // Se manda el estado DESEADO (no un toggle): si otro admin u otra
    // pestaña ya lo cambió, la RPC falla en vez de revertirlo.
    const { error } = await supabase.rpc("admin_alternar_pago_deposito", {
      p_deposito_id: depositoId,
      p_pagado: !pagado,
    });
    setGuardando(false);

    if (error) {
      alert(error.message || "No se pudo actualizar. Verifica tu permiso de admin.");
      startTransition(() => router.refresh());
      return;
    }

    startTransition(() => router.refresh());
  }

  if (pagado) {
    return (
      <button
        onClick={alternarPago}
        disabled={deshabilitado}
        className="text-xs font-semibold text-foreground-muted hover:underline disabled:opacity-50"
      >
        {deshabilitado ? "..." : "Marcar como pendiente"}
      </button>
    );
  }

  return (
    <button
      onClick={alternarPago}
      disabled={deshabilitado}
      className="text-xs font-semibold text-brand-primary hover:underline disabled:opacity-50"
    >
      {deshabilitado ? "Guardando..." : "Marcar como pagado"}
    </button>
  );
}
