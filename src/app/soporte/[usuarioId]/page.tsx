import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { marcarLeidoPorAdmin } from "@/lib/actions/chat";
import { ChatBox } from "@/components/chat/ChatBox";
import type { MensajeSoporte } from "@/lib/types";

const FORMATO_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default async function PaginaSoporteConversacion({
  params,
}: {
  params: Promise<{ usuarioId: string }>;
}) {
  const { usuarioId } = await params;
  const usuario = await obtenerUsuarioActual();

  if (!usuario) redirect("/login");
  if (!usuario.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuario)) redirect("/soporte");

  // Un id mal escrito o de un usuario que ya no existe mostraba un chat
  // vacío con la caja de envío activa, y cada intento de responder
  // fallaba ("Conversación inválida" o error de clave foránea). Como los
  // mensajes se borran en cascada con el usuario, no hay conversación que
  // mostrar: se vuelve a la bandeja.
  if (!FORMATO_UUID.test(usuarioId)) redirect("/soporte");

  const supabase = await crearClienteSupabaseServidor();

  const [{ data: mensajes }, { data: perfilUsuario }] = await Promise.all([
    supabase
      .from("mensajes_soporte")
      .select("*")
      .eq("usuario_id", usuarioId)
      .order("created_at", { ascending: true })
      .returns<MensajeSoporte[]>(),
    supabase
      .from("usuarios")
      .select("email")
      .eq("id", usuarioId)
      .maybeSingle(),
  ]);

  if (!perfilUsuario) redirect("/soporte");

  await marcarLeidoPorAdmin(usuarioId);

  return (
    <div className="py-10">
      <Link
        href="/soporte"
        className="text-[13px] text-brand-primary font-semibold mb-4 inline-block"
      >
        ← Volver a la bandeja
      </Link>
      <h1 className="font-display font-semibold text-[22px] mb-6 truncate">
        {perfilUsuario?.email ?? "Conversación"}
      </h1>

      <ChatBox
        usuarioId={usuarioId}
        usuarioActualId={usuario.id}
        esAdmin={true}
        mensajesIniciales={mensajes ?? []}
      />
    </div>
  );
}
