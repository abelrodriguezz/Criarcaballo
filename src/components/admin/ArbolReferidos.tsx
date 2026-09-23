import Link from "next/link";
import { formatearDinero } from "@/lib/format";

export interface NodoArbolReferido {
  id: string;
  email: string;
  id_corto: number | null;
}

interface ComisionResumen {
  monto: number;
  pagado: boolean;
}

// Recursivo a propósito: invitado_por apunta a otro usuario, así que la
// cadena puede tener varios niveles (A invita a B, B invita a C...), no
// solo el nivel directo que ya mostraba la lista plana de comisiones.
function nodo(
  usuario: NodoArbolReferido,
  profundidad: number,
  hijosPorPadre: Map<string, NodoArbolReferido[]>,
  depositoPorUsuario: Map<string, number>,
  comisionPorInvitado: Map<string, ComisionResumen>
) {
  const hijos = hijosPorPadre.get(usuario.id) ?? [];
  const deposito = depositoPorUsuario.get(usuario.id);
  const comision = comisionPorInvitado.get(usuario.id);

  return (
    <div key={usuario.id}>
      <div
        className="flex flex-wrap items-center gap-2 py-1.5 border-l-2 border-[var(--border)]"
        style={{ paddingLeft: `${profundidad * 20 + 12}px` }}
      >
        <Link
          href={`/usuarios/${usuario.id}`}
          className="text-sm font-medium hover:text-brand-primary break-all"
        >
          {usuario.email}
        </Link>
        {usuario.id_corto != null && (
          <span className="text-[11px] font-mono text-foreground-muted">
            #{usuario.id_corto}
          </span>
        )}

        {profundidad > 0 &&
          (comision ? (
            <span
              className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${
                comision.pagado
                  ? "bg-gain/15 text-gain"
                  : "bg-brand-secondary/15 text-brand-secondary"
              }`}
            >
              ${formatearDinero(comision.monto)}{" "}
              {comision.pagado ? "pagado" : "pendiente"}
            </span>
          ) : deposito != null ? (
            <span className="text-[10px] text-foreground-muted">
              depositó ${formatearDinero(deposito)}
            </span>
          ) : (
            <span className="text-[10px] text-foreground-muted">
              sin depósito todavía
            </span>
          ))}

        {hijos.length > 0 && (
          <span className="text-[10px] text-foreground-muted">
            · {hijos.length}{" "}
            {hijos.length === 1 ? "referido directo" : "referidos directos"}
          </span>
        )}
      </div>
      {hijos.map((hijo) =>
        nodo(hijo, profundidad + 1, hijosPorPadre, depositoPorUsuario, comisionPorInvitado)
      )}
    </div>
  );
}

export function ArbolReferidos({
  raices,
  hijosPorPadre,
  depositoPorUsuario,
  comisionPorInvitado,
}: {
  raices: NodoArbolReferido[];
  hijosPorPadre: Map<string, NodoArbolReferido[]>;
  depositoPorUsuario: Map<string, number>;
  comisionPorInvitado: Map<string, ComisionResumen>;
}) {
  if (raices.length === 0) {
    return (
      <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-8">
        Todavía no hay ninguna cadena de referidos.
      </p>
    );
  }

  return (
    <div className="border border-[var(--border)] rounded-2xl p-4 mb-8 overflow-x-auto">
      {raices.map((raiz) =>
        nodo(raiz, 0, hijosPorPadre, depositoPorUsuario, comisionPorInvitado)
      )}
    </div>
  );
}
