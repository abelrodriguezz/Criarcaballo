"use client";

import { useEffect, useRef, useState } from "react";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { enviarMensajeUsuario, enviarMensajeAdmin } from "@/lib/actions/chat";
import type { MensajeSoporte } from "@/lib/types";

export function ChatBox({
  usuarioId,
  usuarioActualId,
  esAdmin,
  mensajesIniciales,
}: {
  usuarioId: string; // dueño de la conversación
  usuarioActualId: string; // quién está viendo el chat ahora mismo
  esAdmin: boolean;
  mensajesIniciales: MensajeSoporte[];
}) {
  const [mensajes, setMensajes] = useState(mensajesIniciales);
  const [texto, setTexto] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [conexionPerdida, setConexionPerdida] = useState(false);
  const finRef = useRef<HTMLDivElement>(null);

  // Se suscribe a mensajes nuevos de esta conversación en tiempo real.
  // Si la conexión se cae (red inestable, pestaña en segundo plano mucho
  // tiempo), se avisa y se reintenta en vez de quedar "vivo" en apariencia
  // pero sin recibir nada nuevo.
  useEffect(() => {
    const supabase = crearClienteSupabase();
    let cancelado = false;
    let reintentoTimeout: ReturnType<typeof setTimeout> | null = null;
    let canal: ReturnType<typeof supabase.channel> | null = null;

    function conectar() {
      canal = supabase
        .channel(`mensajes_soporte_${usuarioId}_${Date.now()}`)
        .on(
          "postgres_changes",
          {
            event: "INSERT",
            schema: "public",
            table: "mensajes_soporte",
            filter: `usuario_id=eq.${usuarioId}`,
          },
          (payload) => {
            const nuevo = payload.new as MensajeSoporte;
            setMensajes((actuales) =>
              actuales.some((m) => m.id === nuevo.id)
                ? actuales
                : [...actuales, nuevo]
            );
          }
        )
        .subscribe((estado) => {
          if (cancelado) return;
          if (estado === "SUBSCRIBED") {
            setConexionPerdida(false);
          } else if (estado === "CHANNEL_ERROR" || estado === "TIMED_OUT" || estado === "CLOSED") {
            setConexionPerdida(true);
            if (canal) supabase.removeChannel(canal);
            reintentoTimeout = setTimeout(conectar, 4000);
          }
        });
    }

    conectar();

    return () => {
      cancelado = true;
      if (reintentoTimeout) clearTimeout(reintentoTimeout);
      if (canal) supabase.removeChannel(canal);
    };
  }, [usuarioId]);

  useEffect(() => {
    finRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [mensajes.length]);

  async function manejarEnvio(e: React.FormEvent) {
    e.preventDefault();
    const contenido = texto.trim();
    if (!contenido) return;

    setError(null);
    setTexto("");
    setEnviando(true);

    const formData = new FormData();
    formData.set("contenido", contenido);
    if (esAdmin) formData.set("usuarioId", usuarioId);

    try {
      if (esAdmin) {
        await enviarMensajeAdmin(formData);
      } else {
        await enviarMensajeUsuario(formData);
      }
    } catch (e) {
      setError(
        e instanceof Error ? e.message : "No se pudo enviar el mensaje."
      );
      setTexto(contenido); // devuelve el texto al input para que no se pierda
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="flex flex-col border border-[var(--border)] rounded-2xl overflow-hidden h-[70vh] max-h-[600px]">
      {conexionPerdida && (
        <div className="bg-brand-secondary/10 text-brand-secondary text-[12px] text-center py-1.5">
          Conexión perdida, reconectando...
        </div>
      )}
      <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-2.5">
        {mensajes.length === 0 && (
          <p className="text-center text-[13px] text-foreground-muted my-auto">
            {esAdmin
              ? "Todavía no hay mensajes en esta conversación."
              : "Escribe tu duda y el equipo te responderá lo antes posible."}
          </p>
        )}
        {mensajes.map((m) => {
          const esMio = m.remitente_id === usuarioActualId;
          return (
            <div
              key={m.id}
              className={`max-w-[80%] px-3.5 py-2 rounded-2xl text-sm ${
                esMio
                  ? "self-end bg-brand-primary text-white rounded-br-sm"
                  : "self-start bg-surface rounded-bl-sm"
              }`}
            >
              {m.contenido}
            </div>
          );
        })}
        <div ref={finRef} />
      </div>

      <form
        onSubmit={manejarEnvio}
        className="flex flex-col gap-2 p-3 border-t border-[var(--border)]"
      >
        {error && <p className="text-loss text-[12px]">{error}</p>}
        <div className="flex gap-2">
          <input
            value={texto}
            onChange={(e) => setTexto(e.target.value)}
            placeholder="Escribe un mensaje..."
            maxLength={2000}
            className="flex-1 min-w-0 px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
          <button
            type="submit"
            disabled={enviando || !texto.trim()}
            className="shrink-0 bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-50 text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
          >
            Enviar
          </button>
        </div>
      </form>
    </div>
  );
}
