"use client";

import { descargarCSV, filaCSV } from "@/lib/csv";

interface FilaReporte {
  idCorto: number | null;
  email: string;
  wallet: string | null;
  operoEseDia: boolean;
  numOperaciones: number;
  gananciaNeta: number;
}

export function BotonExportarCSV({
  filas,
  fecha,
}: {
  filas: FilaReporte[];
  fecha: string;
}) {
  function exportar() {
    const lineas = filas.map((f) =>
      filaCSV([
        f.idCorto ?? "",
        f.email,
        f.wallet ?? "",
        f.operoEseDia ? "Sí" : "No",
        f.numOperaciones,
        f.gananciaNeta.toFixed(2),
      ])
    );

    descargarCSV(
      `reporte-operaciones-${fecha}.csv`,
      ["ID", "Correo", "Wallet (USDT-ERC20)", "Operó ese día", "N° de operaciones", "Ganancia/Pérdida neta (USD)"],
      lineas
    );
  }

  return (
    <button
      onClick={exportar}
      disabled={filas.length === 0}
      className="border border-[var(--border)] text-sm font-semibold px-4 py-2.5 rounded-xl hover:bg-surface-hover transition-colors disabled:opacity-50"
    >
      Exportar a Excel (.csv)
    </button>
  );
}
