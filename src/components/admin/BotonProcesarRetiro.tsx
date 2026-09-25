"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

export function BotonProcesarRetiro({ solicitudId }: { solicitudId: string }) {
  const router = useRouter();
  const [guardando, setGuardando] = useState(false);
  const [refrescando, startTransition] = useTransition();
  const deshabilitado = guardando || refrescando;

  async function marcarPagado() {
    if (
      !window.confirm("¿Confirmas que ya transferiste el USDT a la wallet del usuario?")
    ) {
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    // Esta RPC (migración 043) marca la solicitud pagada Y reconcilia
    // las ganancias correspondientes en ganancias_concursos en la misma
    // transacción — sin esto, ese mismo dinero podía volver a pagarse
    // desde Usuarios → Reportes sin que nadie se diera cuenta.
    const { error } = await supabase.rpc("admin_marcar_retiro_pagado", {
      p_solicitud_id: solicitudId,
    });
    setGuardando(false);

    if (error) {
      alert(error.message || "No se pudo actualizar. Verifica tu permiso de admin.");
      startTransition(() => router.refresh());
      return;
    }

    startTransition(() => router.refresh());
  }

  async function rechazar() {
    const notaAdmin = window.prompt("Motivo del rechazo (opcional):", "") || null;

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
        estado: "rechazado",
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
        onClick={marcarPagado}
        disabled={deshabilitado}
        className="text-xs font-semibold text-gain hover:underline disabled:opacity-50"
      >
        {deshabilitado ? "..." : "Marcar pagado"}
      </button>
      <button
        onClick={rechazar}
        disabled={deshabilitado}
        className="text-xs font-semibold text-loss hover:underline disabled:opacity-50"
      >
        {deshabilitado ? "..." : "Rechazar"}
      </button>
    </div>
  );
}
