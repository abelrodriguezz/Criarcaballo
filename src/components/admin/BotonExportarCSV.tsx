"use client";

interface FilaReporte {
  idCorto: number | null;
  email: string;
  wallet: string | null;
  operoEseDia: boolean;
  numOperaciones: number;
  gananciaNeta: number;
}

/**
 * Exporta a .csv (no .xlsx binario) — Excel lo abre nativo con doble
 * clic, sin depender de ninguna librería pesada en el proyecto. El BOM
 * al inicio es para que Excel detecte UTF-8 y no rompa acentos/ñ.
 */
export function BotonExportarCSV({
  filas,
  fecha,
}: {
  filas: FilaReporte[];
  fecha: string;
}) {
  function exportar() {
    const encabezados = [
      "ID",
      "Correo",
      "Wallet (USDT-ERC20)",
      "Operó ese día",
      "N° de operaciones",
      "Ganancia/Pérdida neta (USD)",
    ];

    // Además de escapar las comillas, se neutraliza la inyección de
    // fórmulas: Excel/LibreOffice interpretan como fórmula cualquier celda
    // que empiece por = + - @ (o tab/CR), así que alguien que se registre
    // con un correo tipo =HYPERLINK(...) podría ejecutar algo en la
    // máquina del admin al abrir el reporte. Anteponer un apóstrofo lo
    // deja como texto plano sin cambiar lo que se lee.
    // Un número negativo ("-22.07") empieza por "-" pero es un valor
    // legítimo: se deja pasar para que la columna siga siendo numérica en
    // Excel. Solo se neutraliza lo que NO es un número.
    const esNumero = (t: string) => /^-?\d+(\.\d+)?$/.test(t);

    const escapar = (v: string | number) => {
      const texto = String(v);
      const seguro =
        /^[=+\-@\t\r]/.test(texto) && !esNumero(texto) ? `'${texto}` : texto;
      return `"${seguro.replace(/"/g, '""')}"`;
    };

    const lineas = filas.map((f) =>
      [
        escapar(f.idCorto ?? ""),
        escapar(f.email),
        escapar(f.wallet ?? ""),
        escapar(f.operoEseDia ? "Sí" : "No"),
        escapar(f.numOperaciones),
        escapar(f.gananciaNeta.toFixed(2)),
      ].join(",")
    );

    const csv = [encabezados.join(","), ...lineas].join("\r\n");
    const blob = new Blob(["﻿" + csv], {
      type: "text/csv;charset=utf-8;",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `reporte-operaciones-${fecha}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
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
