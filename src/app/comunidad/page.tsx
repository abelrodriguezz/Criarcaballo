import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { IconoComunidad } from "@/components/ui/Iconos";
import { CopiarBoton } from "@/components/ui/CopiarBoton";
import { obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerDiccionario } from "@/lib/i18n/servidor";

export default async function PaginaComunidad() {
  const usuario = await obtenerUsuarioActual();
  if (!usuario) redirect("/login");
  if (!usuario.activo) redirect("/cuenta-desactivada");

  const supabase = await crearClienteSupabaseServidor();

  const [{ data: perfil }, { data: totalInvitados }, t] = await Promise.all([
    supabase
      .from("usuarios")
      .select("codigo_invitacion")
      .eq("id", usuario.id)
      .single(),
    supabase.rpc("contar_invitados"),
    obtenerDiccionario(),
  ]);

  const headersList = await headers();
  const host = headersList.get("host") ?? "";
  const protocolo = host.startsWith("localhost") ? "http" : "https";
  const codigo = perfil?.codigo_invitacion ?? "";
  const linkInvitacion = codigo
    ? `${protocolo}://${host}/registro?ref=${codigo}`
    : "";

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] flex items-center gap-2.5 mb-1.5">
        <IconoComunidad className="w-6 h-6 text-brand-primary" />
        {t.comunidad.titulo}
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {t.comunidad.subtitulo}
      </p>

      {!codigo ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-4">
          {t.comunidad.sinCodigo}
        </p>
      ) : (
        <div className="border border-[var(--border)] rounded-2xl p-5 mb-4">
          <label className="block text-[13px] font-medium text-foreground-muted mb-1.5">
            {t.comunidad.enlaceInvitacion}
          </label>
          <div className="flex gap-2 mb-4">
            <input
              readOnly
              value={linkInvitacion}
              className="flex-1 min-w-0 px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-surface text-sm text-foreground-muted truncate"
            />
            <CopiarBoton texto={linkInvitacion} t={t} />
          </div>

          <label className="block text-[13px] font-medium text-foreground-muted mb-1.5">
            {t.comunidad.codigoInvitacion}
          </label>
          <div className="flex gap-2">
            <input
              readOnly
              value={codigo}
              className="flex-1 min-w-0 px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-surface text-sm font-display font-semibold"
            />
            <CopiarBoton texto={codigo} t={t} />
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 gap-4">
        <div className="border border-[var(--border)] rounded-2xl p-4.5 text-center">
          <div className="font-display font-bold text-2xl">
            {totalInvitados ?? 0}
          </div>
          <div className="text-[13px] text-foreground-muted">
            {t.comunidad.miembrosInvitados}
          </div>
        </div>
        <div className="border border-[var(--border)] rounded-2xl p-4.5 text-center">
          <div className="font-display font-bold text-2xl">$0.00</div>
          <div className="text-[13px] text-foreground-muted">
            {t.comunidad.comisionesInvitar}
          </div>
        </div>
      </div>
    </div>
  );
}
