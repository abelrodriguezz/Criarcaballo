import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerPremioReferido } from "@/lib/config-referidos";
import { AdminPremioReferidoForm } from "@/components/admin/AdminPremioReferidoForm";
import { BotonOtorgarPremioReferido } from "@/components/admin/BotonOtorgarPremioReferido";
import { BotonPagoGanancia } from "@/components/admin/BotonPagoGanancia";
import { formatearDinero } from "@/lib/format";
import type { GananciaConcurso } from "@/lib/types";

interface FilaInvitado {
  id: string;
  email: string;
  created_at: string;
  invitado_por: string;
}

export default async function PaginaReferidos() {
  const usuarioActual = await obtenerUsuarioActual();
  if (!usuarioActual) redirect("/login");
  if (!usuarioActual.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuarioActual)) redirect("/perfil");

  const supabase = await crearClienteSupabaseServidor();

  const [{ data: invitados }, { data: premiosReferidos }, premioSugerido] =
    await Promise.all([
      supabase
        .from("usuarios")
        .select("id, email, created_at, invitado_por")
        .not("invitado_por", "is", null)
        .order("created_at", { ascending: false })
        .returns<FilaInvitado[]>(),
      supabase
        .from("ganancias_concursos")
        .select("*")
        .eq("origen", "referido")
        .returns<GananciaConcurso[]>(),
      obtenerPremioReferido(),
    ]);

  const premiosPorInvitado = new Map(
    (premiosReferidos ?? []).map((p) => [p.invitado_id, p])
  );

  const filas = invitados ?? [];

  // Self-join por id de PostgREST (usuarios!invitado_por) resultó poco
  // confiable — dos consultas y un mapa en el servidor, igual que ya
  // resuelve /usuarios/[usuarioId]/page.tsx con obtenerEmailPorId.
  const idsInvitadores = [...new Set(filas.map((f) => f.invitado_por))];
  const { data: invitadores } = idsInvitadores.length
    ? await supabase.from("usuarios").select("id, email").in("id", idsInvitadores)
    : { data: [] as { id: string; email: string }[] };
  const emailPorInvitador = new Map(
    (invitadores ?? []).map((u) => [u.id, u.email])
  );

  return (
    <div className="py-10">
      <Link
        href="/perfil"
        className="text-[13px] text-brand-primary font-semibold mb-4 inline-block"
      >
        ← Volver a perfil
      </Link>

      <h1 className="font-display font-semibold text-[26px] mb-1.5">
        Referidos
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {filas.length}{" "}
        {filas.length === 1
          ? "persona se registró por invitación"
          : "personas se registraron por invitación"}
        . El premio se paga en USDT vía tarjeta de regalo (gift card), fuera
        de la plataforma — esto solo lleva el registro de a quién y cuánto.
      </p>

      <AdminPremioReferidoForm montoActual={premioSugerido} />

      {filas.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          Todavía nadie se ha registrado con un código de invitación.
        </p>
      ) : (
        <div className="flex flex-col gap-2.5">
          {filas.map((f) => {
            const premio = premiosPorInvitado.get(f.id);
            return (
              <div
                key={f.id}
                className="border border-[var(--border)] rounded-xl p-4 flex flex-wrap items-center justify-between gap-3"
              >
                <div className="min-w-0">
                  <div className="text-sm font-medium break-all">
                    {f.email}
                  </div>
                  <div className="text-[12px] text-foreground-muted break-all">
                    Invitado por{" "}
                    <Link
                      href={`/usuarios/${f.invitado_por}`}
                      className="font-medium hover:text-brand-primary"
                    >
                      {emailPorInvitador.get(f.invitado_por) ?? "—"}
                    </Link>{" "}
                    ·{" "}
                    {new Date(f.created_at).toLocaleDateString("es-DO", {
                      day: "numeric",
                      month: "short",
                      year: "numeric",
                    })}
                  </div>
                </div>

                <div className="shrink-0">
                  {!premio ? (
                    <BotonOtorgarPremioReferido
                      invitadorId={f.invitado_por}
                      invitadoId={f.id}
                      invitadoEmail={f.email}
                      monto={premioSugerido}
                    />
                  ) : (
                    <div className="flex items-center gap-3">
                      <span
                        className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
                          premio.pagado
                            ? "bg-gain/15 text-gain"
                            : "bg-brand-secondary/15 text-brand-secondary"
                        }`}
                      >
                        {premio.pagado ? "Pagado" : "Pendiente"} · $
                        {formatearDinero(premio.monto)}
                      </span>
                      <BotonPagoGanancia
                        gananciaId={premio.id}
                        pagado={premio.pagado}
                      />
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
