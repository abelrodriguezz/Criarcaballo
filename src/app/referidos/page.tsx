import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerConfigPremioReferido } from "@/lib/config-referidos";
import { AdminPremioReferidoForm } from "@/components/admin/AdminPremioReferidoForm";
import { ArbolReferidos, type NodoArbolReferido } from "@/components/admin/ArbolReferidos";
import { BotonPagoGanancia } from "@/components/admin/BotonPagoGanancia";
import { formatearDinero } from "@/lib/format";
import type { GananciaConcurso } from "@/lib/types";

interface FilaUsuarioCompleta extends NodoArbolReferido {
  created_at: string;
  invitado_por: string | null;
}

export default async function PaginaReferidos() {
  const usuarioActual = await obtenerUsuarioActual();
  if (!usuarioActual) redirect("/login");
  if (!usuarioActual.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuarioActual)) redirect("/perfil");

  const supabase = await crearClienteSupabaseServidor();

  // Se trae la tabla completa (id/email/id_corto/invitado_por) de una —
  // es lo que hace falta para armar el árbol completo (una cadena puede
  // tener varios niveles: A invita a B, B invita a C...), no alcanza con
  // pedir solo "los que tienen invitado_por".
  const [{ data: todosUsuarios }, { data: premiosReferidos }, config] =
    await Promise.all([
      supabase
        .from("usuarios")
        .select("id, email, id_corto, invitado_por, created_at")
        .order("created_at", { ascending: true })
        .returns<FilaUsuarioCompleta[]>(),
      supabase
        .from("ganancias_concursos")
        .select("*")
        .eq("origen", "referido")
        .returns<GananciaConcurso[]>(),
      obtenerConfigPremioReferido(),
    ]);

  const todos = todosUsuarios ?? [];
  const filas = todos.filter((u) => u.invitado_por);

  // Comisiones (una por invitado_id) vs. bonos por meta (invitado_id null,
  // pertenecen al invitador — usuario_id).
  const comisiones = (premiosReferidos ?? []).filter((p) => p.invitado_id);
  const bonos = (premiosReferidos ?? []).filter((p) => !p.invitado_id);
  const comisionPorInvitado = new Map(
    comisiones.map((p) => [p.invitado_id as string, { monto: p.monto, pagado: p.pagado }])
  );

  const emailPorUsuario = new Map(todos.map((u) => [u.id, u.email]));

  const hijosPorPadre = new Map<string, FilaUsuarioCompleta[]>();
  for (const u of filas) {
    const padre = u.invitado_por as string;
    if (!hijosPorPadre.has(padre)) hijosPorPadre.set(padre, []);
    hijosPorPadre.get(padre)!.push(u);
  }
  const raices = todos.filter((u) => !u.invitado_por && hijosPorPadre.has(u.id));

  const { data: depositos } = await supabase
    .from("depositos_simulados")
    .select("usuario_id, monto");
  const depositoPorUsuario = new Map(
    (depositos ?? []).map((d) => [d.usuario_id, Number(d.monto)])
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
        . Cuando un invitado hace su depósito simulado, se le genera
        automáticamente a quien lo invitó una comisión pendiente de pago
        — se paga en USDT vía tarjeta de regalo (gift card), fuera de la
        plataforma. Márcala como pagada aquí cuando ya se la hayas
        enviado.
      </p>

      <h2 className="font-display font-semibold text-lg mb-3">
        Configuración
      </h2>
      <AdminPremioReferidoForm configActual={config} />

      <h2 className="font-display font-semibold text-lg mb-3 mt-4">
        Árbol de referidos
      </h2>
      <p className="text-foreground-muted text-[13px] mb-3">
        Quién invitó a quién, en cadena — no solo el nivel directo. Cada
        línea muestra cuántos referidos directos tiene esa persona.
      </p>
      <ArbolReferidos
        raices={raices}
        hijosPorPadre={hijosPorPadre}
        depositoPorUsuario={depositoPorUsuario}
        comisionPorInvitado={comisionPorInvitado}
      />

      <h2 className="font-display font-semibold text-lg mb-3">
        Comisiones por referido
      </h2>
      {filas.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-8">
          Todavía nadie se ha registrado con un código de invitación.
        </p>
      ) : (
        <div className="flex flex-col gap-2.5 mb-8">
          {filas.map((f) => {
            const comision = comisionPorInvitado.get(f.id);
            const deposito = depositoPorUsuario.get(f.id);
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
                      {emailPorUsuario.get(f.invitado_por as string) ?? "—"}
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
                        gananciaId={
                          comisiones.find((c) => c.invitado_id === f.id)!.id
                        }
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

      <h2 className="font-display font-semibold text-lg mb-3">
        Bonos por meta de referidos
      </h2>
      {bonos.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          Todavía no se alcanzó ninguna meta de referidos calificados.
        </p>
      ) : (
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
      )}
    </div>
  );
}
