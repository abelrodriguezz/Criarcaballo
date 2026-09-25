"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

export function BotonProcesarRetiro({ solicitudId }: { solicitudId: string }) {
  const router = useRouter();
  const [guardando, setGuardando] = useState(false);
  const [refrescando, startTransition] = useTransition();
  const deshabilitado = guardando || refrescando;

  async function procesar(estado: "pagado" | "rechazado") {
    if (
      estado === "pagado" &&
      !window.confirm("¿Confirmas que ya transferiste el USDT a la wallet del usuario?")
    ) {
      return;
    }
    let notaAdmin: string | null = null;
    if (estado === "rechazado") {
      notaAdmin = window.prompt("Motivo del rechazo (opcional):", "") || null;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    // .eq("estado", "pendiente") ademas del id: si otro admin ya la
    // proceso justo antes, el update no afecta ninguna fila en vez de
    // pisar silenciosamente lo que el otro admin acaba de dejar.
    const { data, error } = await supabase
      .from("solicitudes_retiro")
      .update({
        estado,
        nota_admin: notaAdmin,
        procesado_en: new Date().toISOString(),
        procesado_por: user?.id ?? null,
      })
      .eq("id", solicitudId)
      .eq("estado", "pendiente")
      .select("id")
      .maybeSingle();

    setGuardando(false);

    if (error) {
      alert("No se pudo actualizar. Verifica tu permiso de admin.");
      return;
    }
    if (!data) {
      alert("Esta solicitud ya fue procesada por otro admin, se refrescará la página.");
      startTransition(() => router.refresh());
      return;
    }

    startTransition(() => router.refresh());
  }

  return (
    <div className="flex gap-3 shrink-0">
      <button
        onClick={() => procesar("pagado")}
        disabled={deshabilitado}
        className="text-xs font-semibold text-gain hover:underline disabled:opacity-50"
      >
        {deshabilitado ? "..." : "Marcar pagado"}
      </button>
      <button
        onClick={() => procesar("rechazado")}
        disabled={deshabilitado}
        className="text-xs font-semibold text-loss hover:underline disabled:opacity-50"
      >
        {deshabilitado ? "..." : "Rechazar"}
      </button>
    </div>
  );
}
