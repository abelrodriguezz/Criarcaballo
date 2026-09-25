import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { BotonProcesarRetiro } from "@/components/admin/BotonProcesarRetiro";
import { formatearDinero } from "@/lib/format";
import type { SolicitudRetiro } from "@/lib/types";

type SolicitudConUsuario = SolicitudRetiro & {
  usuarios: { email: string; id_corto: number | null; nombre: string | null } | null;
};

export default async function PaginaRetiros() {
  const usuarioActual = await obtenerUsuarioActual();
  if (!usuarioActual) redirect("/login");
  if (!usuarioActual.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuarioActual)) redirect("/perfil");

  const supabase = await crearClienteSupabaseServidor();

  // "usuarios!usuario_id": la tabla tiene dos llaves foráneas hacia
  // usuarios (usuario_id y procesado_por) — sin el hint, PostgREST no
  // sabe cuál usar (mismo problema ya resuelto antes en Reportes con
  // ganancias_concursos).
  const { data: solicitudesRaw } = await supabase
    .from("solicitudes_retiro")
    .select("*, usuarios!usuario_id(email, id_corto, nombre)")
    .order("created_at", { ascending: false })
    .returns<SolicitudConUsuario[]>();

  const solicitudes = solicitudesRaw ?? [];
  const pendientes = solicitudes.filter((s) => s.estado === "pendiente");
  const resueltas = solicitudes.filter((s) => s.estado !== "pendiente");

  function Fila({ s }: { s: SolicitudConUsuario }) {
    return (
      <div className="border border-[var(--border)] rounded-xl p-4 flex justify-between items-center gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <div className="font-display font-bold text-base tabular text-brand-secondary">
              ${formatearDinero(s.monto)}
            </div>
            <span
              className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
                s.estado === "pagado"
                  ? "bg-gain/15 text-gain"
                  : s.estado === "rechazado"
                    ? "bg-loss/15 text-loss"
                    : "bg-brand-secondary/15 text-brand-secondary"
              }`}
            >
              {s.estado === "pagado" ? "Pagado" : s.estado === "rechazado" ? "Rechazado" : "Pendiente"}
            </span>
          </div>
          <div className="text-[12px] text-foreground-muted truncate">
            {s.usuarios?.nombre || s.usuarios?.email || "Usuario eliminado"}
            {s.usuarios?.id_corto ? ` · ID ${s.usuarios.id_corto}` : ""} ·{" "}
            {new Date(s.created_at).toLocaleDateString("es-DO", {
              day: "numeric",
              month: "short",
              year: "numeric",
            })}
          </div>
          <div className="text-[12px] text-foreground-muted font-mono truncate">
            {s.wallet_destino}
          </div>
          {s.nota_admin && (
            <div className="text-[12px] text-loss mt-0.5">Motivo: {s.nota_admin}</div>
          )}
        </div>
        {s.estado === "pendiente" && <BotonProcesarRetiro solicitudId={s.id} />}
      </div>
    );
  }

  return (
    <div className="py-10">
      <Link
        href="/perfil"
        className="text-[13px] text-brand-primary font-semibold mb-4 inline-block"
      >
        ← Volver a perfil
      </Link>

      <h1 className="font-display font-semibold text-[26px] mb-1.5">Retiros</h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Solicitudes de retiro contra las ganancias pendientes de cada usuario
        (comisiones de referidos, premios de concursos, ganancias de Trade
        del día) — no contra su saldo de inversión/práctica. Se paga en
        USDT vía la wallet que el usuario tenía registrada al momento de
        pedirlo. Márcala como pagada aquí cuando ya le hayas transferido.
      </p>

      <h2 className="font-display font-semibold text-lg mb-3">
        Pendientes {pendientes.length > 0 && `(${pendientes.length})`}
      </h2>
      {pendientes.length === 0 ? (
        <p className="text-[13px] text-foreground-muted mb-7">
          No hay solicitudes de retiro pendientes.
        </p>
      ) : (
        <div className="flex flex-col gap-2 mb-7">
          {pendientes.map((s) => (
            <Fila key={s.id} s={s} />
          ))}
        </div>
      )}

      {resueltas.length > 0 && (
        <>
          <h2 className="font-display font-semibold text-lg mb-3">Historial</h2>
          <div className="flex flex-col gap-2">
            {resueltas.map((s) => (
              <Fila key={s.id} s={s} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
