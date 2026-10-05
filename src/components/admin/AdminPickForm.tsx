"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { fechaEnNY } from "@/lib/horarioMercado";
import { eliminarPickDelDia, editarPickDelDia } from "@/lib/actions/adminTrading";
import type { PickDelDia } from "@/lib/types";

const MAX_LARGO_ACTIVO = 30;

export function AdminPickForm({
  pickVigente,
}: {
  pickVigente: PickDelDia | null;
}) {
  const router = useRouter();
  const [activo, setActivo] = useState("");
  const [nota, setNota] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [abierto, setAbierto] = useState(false);
  const [eliminando, setEliminando] = useState(false);
  const [editando, setEditando] = useState(false);
  const [activoEditado, setActivoEditado] = useState("");
  const [errorEdicion, setErrorEdicion] = useState<string | null>(null);
  const [guardandoEdicion, setGuardandoEdicion] = useState(false);

  async function manejarEliminar() {
    if (
      !window.confirm(
        `¿Eliminar el pick de hoy (${pickVigente?.activo})? Los usuarios ya no podrán abrir operaciones nuevas hasta que definas otro.`
      )
    ) {
      return;
    }
    if (!pickVigente) return;
    setEliminando(true);
    let resultado: Awaited<ReturnType<typeof eliminarPickDelDia>>;
    try {
      resultado = await eliminarPickDelDia(pickVigente.id);
    } catch {
      window.alert("No se pudo eliminar. Revisa tu conexión e inténtalo de nuevo.");
      return;
    } finally {
      setEliminando(false);
    }
    if (!resultado.ok) {
      window.alert(resultado.error);
      return;
    }
    router.refresh();
  }

  function abrirEdicion() {
    setActivoEditado(pickVigente?.activo ?? "");
    setErrorEdicion(null);
    setEditando(true);
  }

  async function manejarGuardarEdicion() {
    if (!pickVigente) return;
    setErrorEdicion(null);

    const nuevo = activoEditado.trim().toUpperCase();
    if (!nuevo) {
      setErrorEdicion("Ingresa el nombre del activo.");
      return;
    }
    if (nuevo.length > MAX_LARGO_ACTIVO) {
      setErrorEdicion(`El nombre del activo no puede tener más de ${MAX_LARGO_ACTIVO} caracteres.`);
      return;
    }

    setGuardandoEdicion(true);
    // try/finally: si la llamada al Server Action falla a nivel de red (o
    // el servidor lanza en vez de devolver fallo()), el botón quedaba
    // pegado en "Guardando..." para siempre y sin ningún mensaje.
    let resultado: Awaited<ReturnType<typeof editarPickDelDia>>;
    try {
      resultado = await editarPickDelDia(pickVigente.id, nuevo);
    } catch {
      setErrorEdicion("No se pudo guardar. Revisa tu conexión e inténtalo de nuevo.");
      return;
    } finally {
      setGuardandoEdicion(false);
    }

    if (!resultado.ok) {
      setErrorEdicion(resultado.error);
      return;
    }

    setEditando(false);
    router.refresh();
  }

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    // Campo de texto libre a propósito: el pick ya no es necesariamente un
    // par de Binance (acciones, forex, materias primas, etc. no existen
    // ahí), y desde que el admin fija precio de entrada/salida a mano al
    // cerrar (migración 056), tampoco depende de que Binance reconozca el
    // símbolo para nada — así que no se valida contra ninguna API externa.
    const activoNormalizado = activo.trim().toUpperCase();
    if (!activoNormalizado) {
      setError("Ingresa el nombre del activo.");
      return;
    }
    // Mismo límite que abrirOperacion() (paperTrading.ts) y que el CHECK de
    // pick_del_dia (migración 061): sin esto se podía guardar un pick que
    // después ningún usuario podía operar ("Símbolo de activo inválido").
    if (activoNormalizado.length > MAX_LARGO_ACTIVO) {
      setError(`El nombre del activo no puede tener más de ${MAX_LARGO_ACTIVO} caracteres.`);
      return;
    }

    setGuardando(true);

    const supabase = crearClienteSupabase();
    const { error } = await supabase.from("pick_del_dia").insert({
      activo: activoNormalizado,
      nota_admin: nota || null,
      // El día de la bolsa de Nueva York, no el día UTC: definiendo el
      // pick después de las 8pm hora de NY, toISOString() ya devolvía la
      // fecha de mañana y el pick quedaba fechado un día adelantado
      // respecto a los reportes (que sí cuentan el día en horario NY).
      fecha: fechaEnNY(),
    });

    setGuardando(false);

    if (error) {
      setError("No se pudo guardar. Verifica tu permiso de admin.");
      return;
    }

    setActivo("");
    setNota("");
    setAbierto(false);
    router.refresh();
  }

  // Con un pick ya vigente hoy, se muestra ese en vez del botón de
  // "definir" — solo queda un pick a la vez en vez de ir acumulando filas
  // sin fin en la tabla (lo que reportó el usuario: "el pick no vence,
  // siempre está el pick"). Para cambiar el ACTIVO sin perder el pick (y
  // sin afectar a quien ya operó), "Editar" renombra en el sitio; "Eliminar"
  // sigue existiendo para cuando de verdad se quiere cerrar el día sin
  // publicar otro todavía.
  if (!abierto && pickVigente) {
    if (editando) {
      return (
        <div className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-4 mb-6">
          <div className="text-[12px] text-foreground-muted mb-1.5">
            Editar nombre del pick de hoy
          </div>
          <input
            autoFocus
            value={activoEditado}
            onChange={(e) => setActivoEditado(e.target.value)}
            maxLength={MAX_LARGO_ACTIVO}
            aria-label="Nuevo nombre del activo"
            className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
          {errorEdicion && (
            <p className="text-loss text-[13px] mb-2">{errorEdicion}</p>
          )}
          <div className="flex gap-2">
            <button
              onClick={manejarGuardarEdicion}
              disabled={guardandoEdicion}
              className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-4 py-2 rounded-xl transition-colors"
            >
              {guardandoEdicion ? "Guardando..." : "Guardar"}
            </button>
            <button
              type="button"
              onClick={() => setEditando(false)}
              className="text-xs text-foreground-muted"
            >
              Cancelar
            </button>
          </div>
        </div>
      );
    }

    return (
      // flex-wrap + break-words (no truncate): con los DOS botones (Editar y
      // Eliminar) al lado, en un celular de 360px el nombre quedaba cortado
      // en ~96px ("OPERACION D…") — ahora los botones bajan de línea.
      <div className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-4 mb-6 flex flex-wrap justify-between items-center gap-3">
        <div className="min-w-0">
          <div className="text-[12px] text-foreground-muted">Pick de hoy</div>
          <div className="font-display font-semibold text-base break-words">
            {pickVigente.activo}
          </div>
        </div>
        <div className="shrink-0 flex gap-2">
          <button
            onClick={abrirEdicion}
            className="border border-[var(--border)] text-foreground text-sm font-semibold px-4 py-2 rounded-xl hover:bg-surface-hover transition-colors"
          >
            Editar
          </button>
          <button
            onClick={manejarEliminar}
            disabled={eliminando}
            className="border border-loss text-loss text-sm font-semibold px-4 py-2 rounded-xl hover:bg-loss/5 disabled:opacity-60 transition-colors"
          >
            {eliminando ? "Eliminando..." : "Eliminar"}
          </button>
        </div>
      </div>
    );
  }

  if (!abierto) {
    return (
      <button
        onClick={() => setAbierto(true)}
        className="border border-dashed border-[var(--brand-primary)] text-brand-primary text-sm font-semibold px-4 py-2.5 rounded-xl mb-6 hover:bg-[var(--brand-primary)]/5 transition-colors"
      >
        + Definir pick del día (admin)
      </button>
    );
  }

  return (
    <form
      onSubmit={manejarEnvio}
      className="border border-[var(--brand-primary)] bg-[var(--brand-primary)]/5 rounded-2xl p-5 mb-6"
    >
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-display font-semibold text-sm">
          Pick del día
        </h3>
        <button
          type="button"
          onClick={() => setAbierto(false)}
          className="text-xs text-foreground-muted"
        >
          Cancelar
        </button>
      </div>

      <input
        required
        value={activo}
        onChange={(e) => setActivo(e.target.value)}
        maxLength={MAX_LARGO_ACTIVO}
        aria-label="Nombre del activo"
        placeholder="Nombre del activo (ej. BTCUSDT, GOLDUSD, AAPL)"
        className="w-full px-3 py-2 mb-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
      />
      <textarea
        value={nota}
        onChange={(e) => setNota(e.target.value)}
        aria-label="Nota" placeholder="Nota (opcional) — por qué se eligió"
        rows={2}
        className="w-full px-3 py-2 mb-3 rounded-lg border border-[var(--border)] bg-background text-sm resize-none"
      />

      {error && <p className="text-loss text-[13px] mb-2">{error}</p>}

      <button
        type="submit"
        disabled={guardando}
        className="bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
      >
        {guardando ? "Guardando..." : "Definir como pick de hoy"}
      </button>
    </form>
  );
}
