import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerConfigPremioReferido } from "@/lib/config-referidos";
import { AdminPremioReferidoForm } from "@/components/admin/AdminPremioReferidoForm";
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

  const [{ data: invitados }, { data: premiosReferidos }, config] =
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
      obtenerConfigPremioReferido(),
    ]);

  const filas = invitados ?? [];

  // Comisiones (una por invitado_id) vs. bonos por meta (invitado_id null,
  // pertenecen al invitador — usuario_id).
  const comisiones = (premiosReferidos ?? []).filter((p) => p.invitado_id);
  const bonos = (premiosReferidos ?? []).filter((p) => !p.invitado_id);
  const comisionPorInvitado = new Map(comisiones.map((p) => [p.invitado_id, p]));

  // Self-join por id de PostgREST resultó poco confiable — dos consultas
  // y un mapa en el servidor, igual que ya resuelve
  // /usuarios/[usuarioId]/page.tsx con obtenerEmailPorId.
  const idsInvitadores = [
    ...new Set([...filas.map((f) => f.invitado_por), ...bonos.map((b) => b.usuario_id)]),
  ];
  const { data: invitadores } = idsInvitadores.length
    ? await supabase.from("usuarios").select("id, email").in("id", idsInvitadores)
    : { data: [] as { id: string; email: string }[] };
  const emailPorUsuario = new Map((invitadores ?? []).map((u) => [u.id, u.email]));

  const { data: depositos } = await supabase
    .from("depositos_simulados")
    .select("usuario_id, monto")
    .in("usuario_id", filas.length ? filas.map((f) => f.id) : ["00000000-0000-0000-0000-000000000000"]);
  const depositoPorInvitado = new Map((depositos ?? []).map((d) => [d.usuario_id, Number(d.monto)]));

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
        . Cuando un invitado hace su depósito simulado, se le genera
        automáticamente a quien lo invitó una comisión pendiente de pago
        — se paga en USDT vía tarjeta de regalo (gift card), fuera de la
        plataforma. Márcala como pagada aquí cuando ya se la hayas
        enviado.
      </p>

      <AdminPremioReferidoForm configActual={config} />

      {filas.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          Todavía nadie se ha registrado con un código de invitación.
        </p>
      ) : (
        <div className="flex flex-col gap-2.5 mb-8">
          {filas.map((f) => {
            const comision = comisionPorInvitado.get(f.id);
            const deposito = depositoPorInvitado.get(f.id);
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
                      {emailPorUsuario.get(f.invitado_por) ?? "—"}
                    </Link>{" "}
                    ·{" "}
                    {new Date(f.created_at).toLocaleDateString("es-DO", {
                      day: "numeric",
                      month: "short",
                      year: "numeric",
                    })}
                  </div>
                  <div className="text-[12px] text-foreground-muted">
                    {deposito != null
                      ? `Depósito simulado: $${formatearDinero(deposito)}`
                      : "Todavía no hizo su depósito simulado"}
                  </div>
                </div>

                <div className="shrink-0">
                  {!comision ? (
                    <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-foreground-muted/15 text-foreground-muted">
                      Sin comisión todavía
                    </span>
                  ) : (
                    <div className="flex items-center gap-3">
                      <span
                        className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
                          comision.pagado
                            ? "bg-gain/15 text-gain"
                            : "bg-brand-secondary/15 text-brand-secondary"
                        }`}
                      >
                        {comision.pagado ? "Pagado" : "Pendiente"} · $
                        {formatearDinero(comision.monto)}
                      </span>
                      <BotonPagoGanancia
                        gananciaId={comision.id}
                        pagado={comision.pagado}
                      />
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {bonos.length > 0 && (
        <>
          <h2 className="font-display font-semibold text-lg mb-3">
            Bonos por meta de referidos
          </h2>
          <div className="flex flex-col gap-2.5">
            {bonos.map((b) => (
              <div
                key={b.id}
                className="border border-[var(--border)] rounded-xl p-4 flex flex-wrap items-center justify-between gap-3"
              >
                <div className="min-w-0">
                  <div className="text-sm font-medium break-all">
                    {emailPorUsuario.get(b.usuario_id) ?? "Usuario"}
                  </div>
                  <div className="text-[12px] text-foreground-muted">
                    {b.concepto} ·{" "}
                    {new Date(b.created_at).toLocaleDateString("es-DO", {
                      day: "numeric",
                      month: "short",
                      year: "numeric",
                    })}
                  </div>
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  <span
                    className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
                      b.pagado
                        ? "bg-gain/15 text-gain"
                        : "bg-brand-secondary/15 text-brand-secondary"
                    }`}
                  >
                    {b.pagado ? "Pagado" : "Pendiente"} · $
                    {formatearDinero(b.monto)}
                  </span>
                  <BotonPagoGanancia gananciaId={b.id} pagado={b.pagado} />
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
