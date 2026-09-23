"use client";

import { descargarCSV, filaCSV } from "@/lib/csv";
import type { NodoArbolReferido } from "@/components/admin/ArbolReferidos";

interface UsuarioConInvitador extends NodoArbolReferido {
  invitado_por: string | null;
}

interface ComisionResumen {
  monto: number;
  pagado: boolean;
}

// Exporta exactamente lo que se ve en pantalla en ese momento: si hay una
// búsqueda activa o se seleccionó a alguien como principal, se exportan
// solo esas raíces con su red completa hacia abajo — no todo el árbol.
export function BotonExportarArbolReferidos({
  raices,
  hijosPorPadre,
  depositoPorUsuario,
  comisionPorInvitado,
  emailPorUsuario,
  nombrePorUsuario,
}: {
  raices: UsuarioConInvitador[];
  hijosPorPadre: Map<string, UsuarioConInvitador[]>;
  depositoPorUsuario: Map<string, number>;
  comisionPorInvitado: Map<string, ComisionResumen>;
  emailPorUsuario: Map<string, string>;
  nombrePorUsuario: Map<string, string | null>;
}) {
  function exportar() {
    const lineas: string[] = [];

    function aplanar(usuario: UsuarioConInvitador, nivel: number) {
      const deposito = depositoPorUsuario.get(usuario.id);
      const comision = comisionPorInvitado.get(usuario.id);
      const estado = comision
        ? comision.pagado
          ? "Pagado"
          : "Pendiente"
        : deposito != null
          ? "Sin comisión"
          : "Sin depósito";

      const nombreInvitador = usuario.invitado_por
        ? nombrePorUsuario.get(usuario.invitado_por)
        : null;
      const emailInvitador = usuario.invitado_por
        ? (emailPorUsuario.get(usuario.invitado_por) ?? "")
        : "";
      const invitadoPor = usuario.invitado_por
        ? nombreInvitador
          ? `${nombreInvitador} (${emailInvitador})`
          : emailInvitador
        : "—";

      lineas.push(
        filaCSV([
          nivel,
          usuario.nombre ?? "",
          usuario.email,
          usuario.id_corto ?? "",
          invitadoPor,
          deposito != null ? deposito.toFixed(2) : "",
          estado,
          comision ? comision.monto.toFixed(2) : "",
        ])
      );

      for (const hijo of hijosPorPadre.get(usuario.id) ?? []) {
        aplanar(hijo, nivel + 1);
      }
    }

    for (const raiz of raices) {
      aplanar(raiz, 1);
    }

    descargarCSV(
      `arbol-referidos-${new Date().toISOString().slice(0, 10)}.csv`,
      [
        "Nivel",
        "Nombre",
        "Correo",
        "ID",
        "Invitado por",
        "Depósito simulado (USD)",
        "Estado comisión",
        "Monto comisión (USD)",
      ],
      lineas
    );
  }

  return (
    <button
      onClick={exportar}
      disabled={raices.length === 0}
      className="border border-[var(--border)] text-sm font-semibold px-4 py-2.5 rounded-xl hover:bg-surface-hover transition-colors disabled:opacity-50"
    >
      Exportar árbol a Excel (.csv)
    </button>
  );
}
