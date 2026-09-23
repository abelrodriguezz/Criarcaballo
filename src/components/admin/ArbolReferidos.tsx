import Link from "next/link";
import { formatearDinero } from "@/lib/format";

export interface NodoArbolReferido {
  id: string;
  email: string;
  nombre: string | null;
  id_corto: number | null;
}

interface ComisionResumen {
  monto: number;
  pagado: boolean;
}

// Ancho fijo (px) de cada tramo de línea conectora entre un nodo y la
// columna de sus hijos — mismo valor en los dos lugares donde se dibuja
// (el tramo padre→columna y el tramo columna→cada hijo) para que las
// líneas queden a la misma altura y no se vean cortadas.
const ANCHO_CONECTOR = 28;

type PosicionEntreHermanos = "unico" | "primero" | "medio" | "ultimo";

// El tramo de línea entre la "columna vertebral" (la vertical que agrupa
// a todos los hermanos) y la caja de un hijo puntual. La vertical solo
// cubre desde el centro del primer hermano hasta el centro del último —
// por eso el primero solo pinta hacia abajo, el último solo hacia
// arriba, y un hijo único no pinta ninguna vertical.
function TramoHaciaHijo({ posicion }: { posicion: PosicionEntreHermanos }) {
  return (
    <div className="relative shrink-0" style={{ width: ANCHO_CONECTOR }}>
      <div className="absolute left-0 right-0 top-1/2 h-px bg-[var(--foreground-muted)]" />
      {posicion !== "unico" && (
        <div
          className="absolute left-0 w-px bg-[var(--foreground-muted)]"
          style={{
            top: posicion === "primero" ? "50%" : 0,
            bottom: posicion === "ultimo" ? "50%" : 0,
          }}
        />
      )}
    </div>
  );
}

function CajaNodo({
  usuario,
  posicion,
  comision,
  deposito,
  cantidadHijos,
  onSeleccionar,
}: {
  usuario: NodoArbolReferido;
  posicion: number | null;
  comision: ComisionResumen | undefined;
  deposito: number | undefined;
  cantidadHijos: number;
  onSeleccionar: (id: string) => void;
}) {
  return (
    <div className="flex items-center gap-1.5 shrink-0">
      {posicion != null && (
        <span className="shrink-0 w-5 h-5 rounded-full bg-brand-primary/15 text-brand-primary text-[10px] font-bold flex items-center justify-center">
          {posicion}
        </span>
      )}
      <div className="border border-[var(--border)] bg-surface rounded-lg px-3 py-2 flex flex-wrap items-center gap-x-2 gap-y-1 max-w-[320px]">
        {/* El nombre pone a esta persona como raíz de la vista (ver a
            quién invitó ella) — no navega. Para ir al perfil de verdad
            está el enlace "Perfil" aparte, más chico. */}
        <button
          type="button"
          onClick={() => onSeleccionar(usuario.id)}
          title="Ver la red de referidos de esta persona"
          className="text-sm font-medium hover:text-brand-primary break-all text-left"
        >
          {usuario.nombre ? `${usuario.nombre} · ${usuario.email}` : usuario.email}
        </button>
        {usuario.id_corto != null && (
          <span className="text-[11px] font-mono text-foreground-muted">
            #{usuario.id_corto}
          </span>
        )}
        <Link
          href={`/usuarios/${usuario.id}`}
          className="text-[10px] text-foreground-muted hover:text-brand-primary underline shrink-0"
        >
          Perfil
        </Link>
        {comision ? (
          <span
            className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${
              comision.pagado
                ? "bg-gain/15 text-gain"
                : "bg-brand-secondary/15 text-brand-secondary"
            }`}
          >
            ${formatearDinero(comision.monto)} {comision.pagado ? "pagado" : "pendiente"}
          </span>
        ) : deposito != null ? (
          <span className="text-[10px] text-foreground-muted">
            depositó ${formatearDinero(deposito)}
          </span>
        ) : posicion != null ? (
          <span className="text-[10px] text-foreground-muted">sin depósito todavía</span>
        ) : null}
        {cantidadHijos > 0 && (
          <span className="text-[10px] text-foreground-muted">
            · {cantidadHijos} {cantidadHijos === 1 ? "referido directo" : "referidos directos"}
          </span>
        )}
      </div>
    </div>
  );
}

// Recursivo a propósito: invitado_por apunta a otro usuario, así que la
// cadena puede tener varios niveles (A invita a B, B invita a C...), no
// solo el nivel directo que ya mostraba la lista plana de comisiones.
// El layout es horizontal tipo diagrama de flujo: la caja del invitador
// queda centrada verticalmente contra el bloque completo de sus
// referidos, conectada con líneas en vez de solo indentación.
function Nodo({
  usuario,
  posicion,
  hijosPorPadre,
  depositoPorUsuario,
  comisionPorInvitado,
  onSeleccionar,
}: {
  usuario: NodoArbolReferido;
  posicion: number | null;
  hijosPorPadre: Map<string, NodoArbolReferido[]>;
  depositoPorUsuario: Map<string, number>;
  comisionPorInvitado: Map<string, ComisionResumen>;
  onSeleccionar: (id: string) => void;
}) {
  const hijos = hijosPorPadre.get(usuario.id) ?? [];
  const deposito = depositoPorUsuario.get(usuario.id);
  const comision = comisionPorInvitado.get(usuario.id);

  return (
    <div className="flex items-stretch">
      <div className="flex items-center">
        <CajaNodo
          usuario={usuario}
          posicion={posicion}
          comision={comision}
          deposito={deposito}
          cantidadHijos={hijos.length}
          onSeleccionar={onSeleccionar}
        />
      </div>

      {hijos.length > 0 && (
        <>
          {/* Tramo del invitador hacia la columna vertebral de sus hijos —
              se estira a la altura completa del subárbol (flex-stretch
              del padre) y centra la línea ahí, para salir justo del medio. */}
          <div className="flex items-center shrink-0" style={{ width: ANCHO_CONECTOR }}>
            <div className="w-full h-px bg-[var(--foreground-muted)]" />
          </div>

          <div className="flex flex-col">
            {hijos.map((hijo, i) => {
              const posicionEntreHermanos: PosicionEntreHermanos =
                hijos.length === 1
                  ? "unico"
                  : i === 0
                    ? "primero"
                    : i === hijos.length - 1
                      ? "ultimo"
                      : "medio";
              return (
                <div key={hijo.id} className="flex items-stretch">
                  <TramoHaciaHijo posicion={posicionEntreHermanos} />
                  <div className="py-1.5">
                    <Nodo
                      usuario={hijo}
                      posicion={i + 1}
                      hijosPorPadre={hijosPorPadre}
                      depositoPorUsuario={depositoPorUsuario}
                      comisionPorInvitado={comisionPorInvitado}
                      onSeleccionar={onSeleccionar}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}

export function ArbolReferidos({
  raices,
  hijosPorPadre,
  depositoPorUsuario,
  comisionPorInvitado,
  onSeleccionar,
}: {
  raices: NodoArbolReferido[];
  hijosPorPadre: Map<string, NodoArbolReferido[]>;
  depositoPorUsuario: Map<string, number>;
  comisionPorInvitado: Map<string, ComisionResumen>;
  onSeleccionar: (id: string) => void;
}) {
  if (raices.length === 0) {
    return (
      <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-8">
        Todavía no hay ninguna cadena de referidos.
      </p>
    );
  }

  return (
    <div className="border border-[var(--border)] rounded-2xl p-5 mb-8 overflow-x-auto">
      <div className="flex flex-col gap-6 w-fit">
        {raices.map((raiz) => (
          <Nodo
            key={raiz.id}
            usuario={raiz}
            posicion={null}
            hijosPorPadre={hijosPorPadre}
            depositoPorUsuario={depositoPorUsuario}
            comisionPorInvitado={comisionPorInvitado}
            onSeleccionar={onSeleccionar}
          />
        ))}
      </div>
    </div>
  );
}
