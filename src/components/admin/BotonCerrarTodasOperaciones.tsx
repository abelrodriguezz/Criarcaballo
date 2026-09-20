"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { adminCerrarTodasLasOperaciones } from "@/lib/actions/adminTrading";
import { parsearNumero } from "@/lib/format";

export function BotonCerrarTodasOperaciones({
  simbolos,
}: {
  simbolos: string[];
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [precios, setPrecios] = useState<Record<string, string>>({});
  const [cerrando, setCerrando] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setMensaje(null);

    const preciosNum: Record<string, number> = {};
    for (const simbolo of simbolos) {
      const num = parsearNumero(precios[simbolo] ?? "");
      if (!Number.isFinite(num) || num <= 0) {
        setMensaje(`Falta un precio de salida válido para ${simbolo}.`);
        return;
      }
      preciosNum[simbolo] = num;
    }

    if (
      !window.confirm(
        "¿Cerrar TODAS las operaciones abiertas con estos precios de salida? Esta acción no se puede deshacer."
      )
    ) {
      return;
    }

    setCerrando(true);
    try {
      // Fallo esperado = valor de retorno, no excepción: en producción
      // Next.js borra el mensaje de un Error que escape de una server
      // action (ver src/lib/actions/resultado.ts).
      const resultado = await adminCerrarTodasLasOperaciones(preciosNum);
      if (!resultado.ok) {
        setMensaje(resultado.error);
        return;
      }
      const { cerradas, fallidas, sinPrecio, motivoFallo } = resultado.datos;

      const partes: string[] = [];
      if (cerradas === 0 && fallidas === 0 && sinPrecio.length === 0) {
        partes.push("No había ninguna operación abierta.");
      } else {
        partes.push(`${cerradas} operación(es) cerrada(s).`);
      }
      if (fallidas > 0) {
        partes.push(
          motivoFallo
            ? `${fallidas} fallaron (${motivoFallo}).`
            : `${fallidas} fallaron.`
        );
      }
      // Alguien pudo abrir una operación de otro símbolo mientras esta
      // pantalla estaba abierta: sin precio para ese símbolo la operación
      // sigue abierta, y el admin tiene que saberlo en vez de asumir que
      // la sesión quedó liquidada del todo.
      if (sinPrecio.length > 0) {
        partes.push(
          `Quedaron abiertas operaciones de ${sinPrecio.join(", ")} (se abrieron después de cargar esta pantalla). Vuelve a abrir el formulario para cerrarlas.`
        );
      }

      setMensaje(partes.join(" "));
      setAbierto(false);
      setPrecios({});
      router.refresh();
    } catch {
      setMensaje(
        "No se pudo completar el cierre en este momento. Inténtalo de nuevo."
      );
    } finally {
      setCerrando(false);
    }
  }

  if (simbolos.length === 0) {
    return (
      <div className="mb-6">
        {/* El resumen del cierre se mostraba solo en la variante "hay
            símbolos abiertos", así que tras liquidar la sesión con éxito
            el router.refresh() traía esta otra variante y el admin se
            quedaba sin NINGUNA confirmación de lo que acababa de hacer:
            ni cuántas operaciones cerró ni si alguna falló. */}
        {mensaje && (
          <p className="text-[13px] text-foreground mb-1.5" role="status">
            {mensaje}
          </p>
        )}
        <p className="text-[12px] text-foreground-muted">
          No hay operaciones abiertas para cerrar.
        </p>
      </div>
    );
  }

  if (!abierto) {
    return (
      <div className="mb-6">
        <button
          onClick={() => setAbierto(true)}
          className="border border-loss text-loss text-sm font-semibold px-4 py-2.5 rounded-xl hover:bg-loss/5 transition-colors"
        >
          Cerrar todas las operaciones abiertas
        </button>
        {mensaje && (
          <p className="text-[12px] text-foreground-muted mt-1.5">{mensaje}</p>
        )}
      </div>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="mb-6 border border-loss/40 rounded-2xl p-4 flex flex-col gap-3"
    >
      <p className="text-sm font-semibold">
        Precio de salida por activo — se aplica al precio de entrada de
        cada usuario para calcular su ganancia/pérdida
      </p>
      {simbolos.map((simbolo) => (
        <div key={simbolo} className="flex items-center gap-2">
          <label className="text-sm font-mono w-28 shrink-0">{simbolo}</label>
          <input
            value={precios[simbolo] ?? ""}
            onChange={(e) =>
              setPrecios((p) => ({ ...p, [simbolo]: e.target.value }))
            }
            placeholder="Precio de salida"
            inputMode="decimal"
            className="flex-1 min-w-0 px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
      ))}

      {mensaje && <p className="text-loss text-[12px]">{mensaje}</p>}

      <div className="flex gap-3">
        <button
          type="submit"
          disabled={cerrando}
          className="bg-loss hover:opacity-90 disabled:opacity-60 text-white font-semibold text-sm px-4 py-2.5 rounded-lg transition-colors"
        >
          {cerrando ? "Cerrando..." : "Confirmar cierre"}
        </button>
        <button
          type="button"
          onClick={() => {
            setAbierto(false);
            setMensaje(null);
          }}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>
    </form>
  );
}
