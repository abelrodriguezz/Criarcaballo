"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  adminCerrarTodasLasOperaciones,
  type DatosCierreSimbolo,
} from "@/lib/actions/adminTrading";
import { parsearNumero } from "@/lib/format";

interface CamposSimbolo {
  precioEntrada: string;
  precioSalida: string;
  horaEntrada: string;
  horaCierre: string;
}

const CAMPOS_VACIOS: CamposSimbolo = {
  precioEntrada: "",
  precioSalida: "",
  horaEntrada: "",
  horaCierre: "",
};

/** input[type=datetime-local] ("2026-09-27T14:30") a ISO en UTC, o undefined si está vacío. */
function horaAIso(valor: string): string | undefined {
  if (!valor) return undefined;
  const fecha = new Date(valor);
  return Number.isNaN(fecha.getTime()) ? undefined : fecha.toISOString();
}

export function BotonCerrarTodasOperaciones({
  simbolos,
}: {
  simbolos: string[];
}) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const [campos, setCampos] = useState<Record<string, CamposSimbolo>>({});
  const [cerrando, setCerrando] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);

  function actualizarCampo(
    simbolo: string,
    campo: keyof CamposSimbolo,
    valor: string
  ) {
    setCampos((c) => ({
      ...c,
      [simbolo]: { ...(c[simbolo] ?? CAMPOS_VACIOS), [campo]: valor },
    }));
  }

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setMensaje(null);

    const datosPorSimbolo: Record<string, DatosCierreSimbolo> = {};
    for (const simbolo of simbolos) {
      const c = campos[simbolo] ?? CAMPOS_VACIOS;
      const precioEntrada = parsearNumero(c.precioEntrada);
      const precioSalida = parsearNumero(c.precioSalida);
      if (!Number.isFinite(precioEntrada) || precioEntrada <= 0) {
        setMensaje(`Falta un precio de entrada válido para ${simbolo}.`);
        return;
      }
      if (!Number.isFinite(precioSalida) || precioSalida <= 0) {
        setMensaje(`Falta un precio de salida válido para ${simbolo}.`);
        return;
      }
      const horaEntrada = horaAIso(c.horaEntrada);
      const horaCierre = horaAIso(c.horaCierre);
      // Mismo chequeo que hace el servidor, para avisar antes del confirm.
      // Sin hora de cierre se usa "ahora", así que una entrada futura
      // también es inválida.
      const cierreEfectivo = horaCierre ? Date.parse(horaCierre) : Date.now();
      if (horaCierre && cierreEfectivo > Date.now()) {
        setMensaje(`${simbolo}: la hora de cierre no puede ser en el futuro.`);
        return;
      }
      if (horaEntrada && Date.parse(horaEntrada) >= cierreEfectivo) {
        setMensaje(
          `${simbolo}: la hora de entrada debe ser anterior a la hora de cierre.`
        );
        return;
      }
      datosPorSimbolo[simbolo] = {
        precioEntrada,
        precioSalida,
        horaEntrada,
        horaCierre,
      };
    }

    if (
      !window.confirm(
        "¿Cerrar TODAS las operaciones abiertas con estos precios? Esto reemplaza el precio de entrada capturado al abrir y recalcula la ganancia/pérdida de cada usuario. Esta acción no se puede deshacer."
      )
    ) {
      return;
    }

    setCerrando(true);
    try {
      // Fallo esperado = valor de retorno, no excepción: en producción
      // Next.js borra el mensaje de un Error que escape de una server
      // action (ver src/lib/actions/resultado.ts).
      const resultado = await adminCerrarTodasLasOperaciones(datosPorSimbolo);
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
      setCampos({});
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
        Precio de entrada y salida por activo — reemplazan el precio
        capturado al abrir y se aplican al monto invertido de cada usuario
        para calcular su ganancia/pérdida. Las horas son opcionales.
      </p>
      {simbolos.map((simbolo) => {
        const c = campos[simbolo] ?? CAMPOS_VACIOS;
        return (
          <div
            key={simbolo}
            className="border border-[var(--border)] rounded-xl p-3 flex flex-col gap-2"
          >
            <label className="text-sm font-mono font-semibold">{simbolo}</label>
            <div className="flex gap-2">
              <input
                value={c.precioEntrada}
                onChange={(e) => actualizarCampo(simbolo, "precioEntrada", e.target.value)}
                placeholder="Precio de entrada"
                inputMode="decimal"
                className="flex-1 min-w-0 px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
              />
              <input
                value={c.precioSalida}
                onChange={(e) => actualizarCampo(simbolo, "precioSalida", e.target.value)}
                placeholder="Precio de salida"
                inputMode="decimal"
                className="flex-1 min-w-0 px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
              />
            </div>
            <div className="flex gap-2">
              <div className="flex-1 min-w-0">
                <label className="block text-[11px] text-foreground-muted mb-1">
                  Hora de entrada (opcional)
                </label>
                <input
                  type="datetime-local"
                  value={c.horaEntrada}
                  onChange={(e) => actualizarCampo(simbolo, "horaEntrada", e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
                />
              </div>
              <div className="flex-1 min-w-0">
                <label className="block text-[11px] text-foreground-muted mb-1">
                  Hora de cierre (opcional)
                </label>
                <input
                  type="datetime-local"
                  value={c.horaCierre}
                  onChange={(e) => actualizarCampo(simbolo, "horaCierre", e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
                />
              </div>
            </div>
          </div>
        );
      })}

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
