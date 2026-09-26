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
    if (
      !pagado &&
      !window.confirm(
        "¿Confirmas que ya le asignaste el saldo de inversión a este usuario en Gestión de usuarios?"
      )
    ) {
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    // .eq("pagado", pagado) además del id: mismo motivo que
    // BotonPagoGanancia.tsx — evita pisar el pagado_en/pagado_por de otro
    // admin si dos personas tocan el mismo depósito casi a la vez.
    const { data, error } = await supabase
      .from("depositos_simulados")
      .update({
        pagado: !pagado,
        pagado_en: !pagado ? new Date().toISOString() : null,
        pagado_por: !pagado ? (user?.id ?? null) : null,
      })
      .eq("id", depositoId)
      .eq("pagado", pagado)
      .select("id")
      .maybeSingle();

    setGuardando(false);

    if (error) {
      alert("No se pudo actualizar. Verifica tu permiso de admin.");
      return;
    }

    if (!data) {
      alert("Este depósito ya fue actualizado por otro admin, se refrescará la página.");
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
