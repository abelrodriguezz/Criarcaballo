"use client";

import { useState } from "react";
import { AdminSenalForm } from "@/components/admin/AdminSenalForm";
import { BotonEliminarAdmin } from "@/components/admin/BotonEliminarAdmin";
import type { Senal } from "@/lib/types";

export function TarjetaSenalAdmin({
  senal,
  esAdmin,
}: {
  senal: Senal;
  esAdmin: boolean;
}) {
  const [editando, setEditando] = useState(false);

  if (editando) {
    return (
      <AdminSenalForm
        senalExistente={senal}
        onCancelar={() => setEditando(false)}
      />
    );
  }

  return (
    <div className="border border-[var(--border)] rounded-2xl p-5 flex justify-between items-start">
      <div>
        <div className="font-display font-semibold text-base mb-1.5">
          {senal.par}
        </div>
        <div className="text-[13px] text-foreground-muted">
          Entrada {senal.entrada}
          {senal.stop_loss ? ` · SL ${senal.stop_loss}` : ""}
          {senal.take_profit ? ` · TP ${senal.take_profit}` : ""}
        </div>
        {senal.razon && (
          <p className="text-[13px] text-foreground-muted mt-1.5">
            {senal.razon}
          </p>
        )}
        {esAdmin && (
          <div className="flex gap-3 mt-2.5">
            <button
              onClick={() => setEditando(true)}
              className="text-xs font-semibold text-brand-primary hover:underline"
            >
              Editar
            </button>
            <BotonEliminarAdmin
              tabla="senales"
              id={senal.id}
              textoConfirmacion={`¿Eliminar la señal de ${senal.par}?`}
            />
          </div>
        )}
      </div>
      <span
        className={`text-xs font-bold px-3 py-1 rounded-full whitespace-nowrap ${
          senal.tipo === "compra"
            ? "bg-gain/15 text-gain"
            : "bg-loss/15 text-loss"
        }`}
      >
        {senal.tipo === "compra" ? "Compra" : "Venta"}
      </span>
    </div>
  );
}
