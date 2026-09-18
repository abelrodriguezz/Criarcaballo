import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { marcarLeidoPorUsuario } from "@/lib/actions/chat";
import { ChatBox } from "@/components/chat/ChatBox";
import type { MensajeSoporte } from "@/lib/types";

export default async function PaginaSoporte() {
  const usuario = await obtenerUsuarioActual();
  if (!usuario) redirect("/login");
  if (!usuario.activo) redirect("/cuenta-desactivada");

  const supabase = await crearClienteSupabaseServidor();

  // ── Vista ADMIN: bandeja con todas las conversaciones ──────────────────
  if (esAdmin(usuario)) {
    type FilaConversacionRpc = {
      usuario_id: string;
      email: string | null;
      no_leidos: number;
      primer_no_leido: string | null;
      ultimo_mensaje: string;
    };

    // La agregación (no leídos, último mensaje) se hace en la base de
    // datos (ver migración 011) en vez de traer cada mensaje de cada
    // conversación de la plataforma a este Server Component.
    const { data: conversacionesRaw } = (await supabase.rpc(
      "listar_conversaciones_soporte"
    )) as { data: FilaConversacionRpc[] | null };

    type Conversacion = {
      usuarioId: string;
      email: string;
      noLeidos: number;
      primerNoLeido: string | null;
      ultimoMensaje: string;
    };

    const lista: Conversacion[] = (conversacionesRaw ?? []).map((c) => ({
      usuarioId: c.usuario_id,
      email: c.email ?? "(usuario eliminado)",
      noLeidos: Number(c.no_leidos),
      primerNoLeido: c.primer_no_leido,
      ultimoMensaje: c.ultimo_mensaje,
    }));

    // Orden de llegada: las conversaciones con mensajes sin leer más
    // antiguos van primero (cola FIFO); el resto, por actividad reciente.
    lista.sort((a, b) => {
      if (a.primerNoLeido && b.primerNoLeido) {
        return (
          new Date(a.primerNoLeido).getTime() -
          new Date(b.primerNoLeido).getTime()
        );
      }
      if (a.primerNoLeido) return -1;
      if (b.primerNoLeido) return 1;
      return (
        new Date(b.ultimoMensaje).getTime() -
        new Date(a.ultimoMensaje).getTime()
      );
    });

    return (
      <div className="py-10">
        <h1 className="font-display font-semibold text-[26px] mb-1.5">
          Soporte
        </h1>
        <p className="text-foreground-muted text-[15px] mb-7">
          Conversaciones ordenadas por orden de llegada — los mensajes sin
          responder más antiguos aparecen primero.
        </p>

        {lista.length === 0 ? (
          <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
            Todavía no hay conversaciones de soporte.
          </p>
        ) : (
          <div className="flex flex-col gap-2">
            {lista.map((c) => (
              <Link
                key={c.usuarioId}
                href={`/soporte/${c.usuarioId}`}
                className="border border-[var(--border)] rounded-xl p-4 flex items-center justify-between hover:bg-surface-hover transition-colors"
              >
                <span className="text-sm font-medium truncate">
                  {c.email}
                </span>
                {c.noLeidos > 0 && (
                  <span className="shrink-0 bg-brand-secondary text-white text-xs font-bold px-2.5 py-1 rounded-full ml-3">
                    {c.noLeidos} sin responder
                  </span>
                )}
              </Link>
            ))}
          </div>
        )}
      </div>
    );
  }

  // ── Vista USUARIO: su única conversación con soporte ────────────────────
  const { data: mensajes } = await supabase
    .from("mensajes_soporte")
    .select("*")
    .eq("usuario_id", usuario.id)
    .order("created_at", { ascending: true })
    .returns<MensajeSoporte[]>();

  await marcarLeidoPorUsuario(usuario.id);

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] mb-1.5">
        Soporte
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        ¿Alguna duda? Escríbenos — el equipo responde en orden de llegada,
        puede tomar un poco de tiempo.
      </p>

      <ChatBox
        usuarioId={usuario.id}
        usuarioActualId={usuario.id}
        esAdmin={false}
        mensajesIniciales={mensajes ?? []}
      />
    </div>
  );
}
