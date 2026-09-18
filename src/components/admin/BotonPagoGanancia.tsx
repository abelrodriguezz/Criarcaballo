"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";

export function BotonPagoGanancia({
  gananciaId,
  pagado,
}: {
  gananciaId: string;
  pagado: boolean;
}) {
  const router = useRouter();
  const [guardando, setGuardando] = useState(false);
  // isPending se queda true hasta que router.refresh() termine de traer
  // props frescos del servidor — evita el doble clic sin necesitar un
  // useEffect que dispare un setState (regla react-hooks/set-state-in-effect).
  const [refrescando, startTransition] = useTransition();
  const deshabilitado = guardando || refrescando;

  async function alternarPago() {
    if (
      !pagado &&
      !window.confirm(
        "¿Confirmas que ya transferiste el USDT a la wallet del usuario?"
      )
    ) {
      return;
    }

    setGuardando(true);
    const supabase = crearClienteSupabase();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    // .eq("pagado", pagado) además del id: si otro admin ya cambió el
    // estado justo antes (o un doble clic disparó esto dos veces), el
    // update no afecta ninguna fila en vez de pisar silenciosamente el
    // pagado_en/pagado_por que el otro admin acaba de dejar.
    const { data, error } = await supabase
      .from("ganancias_concursos")
      .update({
        pagado: !pagado,
        pagado_en: !pagado ? new Date().toISOString() : null,
        pagado_por: !pagado ? (user?.id ?? null) : null,
      })
      .eq("id", gananciaId)
      .eq("pagado", pagado)
      .select("id")
      .maybeSingle();

    setGuardando(false);

    if (error) {
      alert("No se pudo actualizar. Verifica tu permiso de admin.");
      return;
    }

    if (!data) {
      alert("Este pago ya fue actualizado por otro admin, se refrescará la página.");
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
