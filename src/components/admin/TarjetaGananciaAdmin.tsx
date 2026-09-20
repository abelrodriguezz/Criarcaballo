"use client";

import { useState } from "react";
import { AdminGananciaForm } from "@/components/admin/AdminGananciaForm";
import { BotonEliminarAdmin } from "@/components/admin/BotonEliminarAdmin";
import { BotonPagoGanancia } from "@/components/admin/BotonPagoGanancia";
import { formatearDinero } from "@/lib/format";
import type { GananciaConcurso } from "@/lib/types";

export function TarjetaGananciaAdmin({
  ganancia,
  usuarioId,
}: {
  ganancia: GananciaConcurso;
  usuarioId: string;
}) {
  const [editando, setEditando] = useState(false);

  if (editando) {
    return (
      <AdminGananciaForm
        usuarioId={usuarioId}
        gananciaExistente={ganancia}
        onCancelar={() => setEditando(false)}
      />
    );
  }

  return (
    <div className="border border-[var(--border)] rounded-xl p-4 flex justify-between items-center">
      <div>
        <div className="flex items-center gap-2">
          <div className="font-display font-bold text-base tabular text-gain">
            +${formatearDinero(ganancia.monto)}
          </div>
          <span
            className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
              ganancia.pagado
                ? "bg-gain/15 text-gain"
                : "bg-brand-secondary/15 text-brand-secondary"
            }`}
          >
            {ganancia.pagado ? "Pagado" : "Pendiente"}
          </span>
        </div>
        <div className="text-[12px] text-foreground-muted">
          {ganancia.concepto || "Sin concepto"} ·{" "}
          {new Date(ganancia.created_at).toLocaleDateString("es-DO", {
            day: "numeric",
            month: "short",
            year: "numeric",
          })}
        </div>
      </div>
      <div className="flex gap-3 shrink-0">
        <BotonPagoGanancia gananciaId={ganancia.id} pagado={ganancia.pagado} />
        <button
          onClick={() => setEditando(true)}
          className="text-xs font-semibold text-brand-primary hover:underline"
        >
          Editar
        </button>
        <BotonEliminarAdmin
          tabla="ganancias_concursos"
          id={ganancia.id}
          textoConfirmacion="¿Eliminar esta ganancia del historial?"
        />
      </div>
    </div>
  );
}
