"use client";

import { descargarCSV, filaCSV } from "@/lib/csv";
import type { DepositoResumen, NodoArbolReferido } from "@/components/admin/ArbolReferidos";
import type { TextosAdmin } from "@/lib/i18n";

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
  ta,
}: {
  raices: UsuarioConInvitador[];
  hijosPorPadre: Map<string, UsuarioConInvitador[]>;
  depositoPorUsuario: Map<string, DepositoResumen>;
  comisionPorInvitado: Map<string, ComisionResumen>;
  emailPorUsuario: Map<string, string>;
  nombrePorUsuario: Map<string, string | null>;
  ta: TextosAdmin;
}) {
  function exportar() {
    const lineas: string[] = [];

    // `ancestros` corta los ciclos en la cadena de invitado_por (A invitado
    // por B y B por A, o alguien invitado por sí mismo). El registro normal
    // no los produce, pero un admin sí puede escribirlos en la columna, y
    // sin este corte la recursión revienta con "Maximum call stack size
    // exceeded" y el export nunca se descarga. Es por rama, no global: si
    // la misma persona aparece bajo dos raíces distintas (pasa al buscar)
    // se sigue exportando en las dos, como hasta ahora.
    function aplanar(
      usuario: UsuarioConInvitador,
      nivel: number,
      ancestros: ReadonlySet<string>
    ) {
      if (ancestros.has(usuario.id)) return;
      const ancestrosConEste = new Set(ancestros).add(usuario.id);

      const deposito = depositoPorUsuario.get(usuario.id);
      const comision = comisionPorInvitado.get(usuario.id);
      const estado = comision
        ? comision.pagado
          ? ta.pagado
          : ta.pendiente
        : deposito == null
          ? ta.csvSinDeposito
          : deposito.pagado
            ? ta.csvSinComision
            : ta.csvDepositoSinConfirmar;

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
          deposito != null ? deposito.monto.toFixed(2) : "",
          estado,
          comision ? comision.monto.toFixed(2) : "",
        ])
      );

      for (const hijo of hijosPorPadre.get(usuario.id) ?? []) {
        aplanar(hijo, nivel + 1, ancestrosConEste);
      }
    }

    for (const raiz of raices) {
      aplanar(raiz, 1, new Set());
    }

    descargarCSV(
      `${ta.csvArchivo}-${new Date().toISOString().slice(0, 10)}.csv`,
      [
        ta.csvNivel,
        ta.csvNombre,
        ta.csvCorreo,
        ta.csvId,
        ta.csvInvitadoPor,
        ta.csvDeposito,
        ta.csvEstado,
        ta.csvMonto,
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
      {ta.exportarArbol}
    </button>
  );
}
