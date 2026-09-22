"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

export function BotonOtorgarPremioReferido({
  invitadorId,
  invitadoId,
  invitadoEmail,
  monto,
}: {
  invitadorId: string;
  invitadoId: string;
  invitadoEmail: string;
  monto: number;
}) {
  const router = useRouter();
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function otorgar() {
    if (
      !window.confirm(
        `¿Otorgar un premio de $${monto.toFixed(2)} USDT por invitar a ${invitadoEmail}? Quedará pendiente de pago en Reportes.`
      )
    ) {
      return;
    }

    setError(null);
    setGuardando(true);
    const supabase = crearClienteSupabase();
    const { error } = await supabase.from("ganancias_concursos").insert({
      usuario_id: invitadorId,
      monto,
      concepto: `Referido: ${invitadoEmail}`,
      origen: "referido",
      invitado_id: invitadoId,
    });
    setGuardando(false);

    if (error) {
      setError("No se pudo otorgar. Verifica tu permiso de admin.");
      return;
    }

    router.refresh();
  }

  return (
    <div>
      <button
        onClick={otorgar}
        disabled={guardando}
        className="text-xs font-semibold text-brand-primary hover:underline disabled:opacity-50"
      >
        {guardando ? "Otorgando..." : `Otorgar premio ($${monto.toFixed(2)})`}
      </button>
      {error && <p className="text-loss text-[11px] mt-0.5">{error}</p>}
    </div>
  );
}
