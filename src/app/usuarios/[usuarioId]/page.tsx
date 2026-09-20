import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { AdminGananciaForm } from "@/components/admin/AdminGananciaForm";
import { TarjetaGananciaAdmin } from "@/components/admin/TarjetaGananciaAdmin";
import { AdminSaldoForm } from "@/components/admin/AdminSaldoForm";
import { formatearDinero, formatearPrecio } from "@/lib/format";
import type { GananciaConcurso, OperacionSimulada, Usuario } from "@/lib/types";

async function obtenerEmailPorId(
  supabase: Awaited<ReturnType<typeof crearClienteSupabaseServidor>>,
  id: string | null
): Promise<string | null> {
  if (!id) return null;
  const { data } = await supabase
    .from("usuarios")
    .select("email")
    .eq("id", id)
    .maybeSingle();
  return data?.email ?? null;
}

export default async function PaginaDetalleUsuario({
  params,
}: {
  params: Promise<{ usuarioId: string }>;
}) {
  const { usuarioId } = await params;
  const usuarioActual = await obtenerUsuarioActual();

  if (!usuarioActual) redirect("/login");
  if (!usuarioActual.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuarioActual)) redirect("/perfil");

  const supabase = await crearClienteSupabaseServidor();

  const [
    { data: perfil },
    { data: ganancias },
    { data: saldo },
    { count: cantidadInvitados },
    { data: operaciones },
  ] = await Promise.all([
    supabase
      .from("usuarios")
      .select("*")
      .eq("id", usuarioId)
      .single<Usuario>(),
    supabase
      .from("ganancias_concursos")
      .select("*")
      .eq("usuario_id", usuarioId)
      .order("created_at", { ascending: false })
      .returns<GananciaConcurso[]>(),
    supabase
      .from("saldo_virtual")
      .select("saldo_usd")
      .eq("usuario_id", usuarioId)
      .maybeSingle(),
    supabase
      .from("usuarios")
      .select("id", { count: "exact", head: true })
      .eq("invitado_por", usuarioId),
    supabase
      .from("operaciones_simuladas")
      .select("*")
      .eq("usuario_id", usuarioId)
      .order("created_at", { ascending: false })
      .limit(20)
      .returns<OperacionSimulada[]>(),
  ]);

  const emailInvitador = await obtenerEmailPorId(supabase, perfil?.invitado_por ?? null);

  const total = (ganancias ?? []).reduce((suma, g) => suma + g.monto, 0);
  const pendiente = (ganancias ?? [])
    .filter((g) => !g.pagado)
    .reduce((suma, g) => suma + g.monto, 0);

  return (
    <div className="py-10">
      <Link
        href="/usuarios"
        className="text-[13px] text-brand-primary font-semibold mb-4 inline-block"
      >
        ← Volver a usuarios
      </Link>

      {perfil?.id_corto && (
        <div className="text-[12px] font-mono text-brand-primary font-semibold mb-0.5">
          ID: {perfil.id_corto}
        </div>
      )}
      <h1 className="font-display font-semibold text-[22px] mb-1 break-all">
        {perfil?.email ?? "Usuario"}
      </h1>
      {perfil?.wallet_usdt_erc20 ? (
        <p className="text-[13px] text-foreground-muted font-mono mb-4 break-all">
          Wallet: {perfil.wallet_usdt_erc20}
        </p>
      ) : (
        <p className="text-[13px] text-foreground-muted mb-4">
          Este usuario no ha agregado su wallet todavía.
        </p>
      )}

      <div className="border border-[var(--border)] rounded-2xl p-5 mb-6 grid grid-cols-2 gap-y-3 gap-x-4">
        <div>
          <div className="text-[12px] text-foreground-muted mb-0.5">
            Saldo de Inversión (práctica)
          </div>
          <div className="font-display font-bold text-lg tabular">
            ${formatearDinero(saldo?.saldo_usd ?? 0)}
          </div>
          <AdminSaldoForm usuarioId={usuarioId} />
        </div>
        <div>
          <div className="text-[12px] text-foreground-muted mb-0.5">
            Trading
          </div>
          <span
            className={`inline-block text-xs font-bold px-2.5 py-1 rounded-full ${
              perfil?.trading_habilitado
                ? "bg-brand-primary/15 text-brand-primary"
                : "bg-loss/15 text-loss"
            }`}
          >
            {perfil?.trading_habilitado ? "Habilitado" : "Bloqueado"}
          </span>
        </div>
        <div>
          <div className="text-[12px] text-foreground-muted mb-0.5">
            Invitado por
          </div>
          <div className="text-sm font-medium break-all">
            {emailInvitador ?? "Nadie (registro directo)"}
          </div>
        </div>
        <div>
          <div className="text-[12px] text-foreground-muted mb-0.5">
            Personas invitadas
          </div>
          <div className="text-sm font-medium">{cantidadInvitados ?? 0}</div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 mb-6">
        <div className="border border-[var(--border)] rounded-2xl p-5">
          <div className="text-[13px] text-foreground-muted mb-1">
            Total ganado
          </div>
          <div className="font-display font-bold text-2xl tabular text-gain">
            +${formatearDinero(total)}
          </div>
        </div>
        <div className="border border-[var(--border)] rounded-2xl p-5">
          <div className="text-[13px] text-foreground-muted mb-1">
            Pendiente por pagar
          </div>
          <div className="font-display font-bold text-2xl tabular text-brand-secondary">
            ${formatearDinero(pendiente)}
          </div>
        </div>
      </div>

      <h2 className="font-display font-semibold text-lg mb-3">
        Historial de ganancias
      </h2>

      <AdminGananciaForm usuarioId={usuarioId} />

      {!ganancias || ganancias.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          Todavía no se le ha registrado ninguna ganancia.
        </p>
      ) : (
        <div className="flex flex-col gap-2.5 mb-8">
          {ganancias.map((g) => (
            <TarjetaGananciaAdmin key={g.id} ganancia={g} usuarioId={usuarioId} />
          ))}
        </div>
      )}

      <h2 className="font-display font-semibold text-lg mb-3">
        Historial de operaciones (Trade del día)
      </h2>

      {!operaciones || operaciones.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          Este usuario todavía no ha abierto ninguna operación simulada.
        </p>
      ) : (
        <div className="flex flex-col gap-2.5">
          {operaciones.map((op) => (
            <div
              key={op.id}
              className="border border-[var(--border)] rounded-xl p-4 flex justify-between items-center gap-3"
            >
              <div className="min-w-0">
                <div className="font-medium text-sm flex items-center gap-1.5">
                  {op.activo} · {op.tipo === "compra" ? "Compra" : "Venta"}
                  {op.estado === "abierta" && (
                    <span className="text-[10px] font-bold uppercase tracking-wide text-brand-primary bg-brand-primary/15 px-1.5 py-0.5 rounded">
                      Abierta
                    </span>
                  )}
                </div>
                <div className="text-[12px] text-foreground-muted">
                  Entrada ${formatearPrecio(op.precio_entrada)}
                  {op.precio_salida != null &&
                    ` → Salida $${formatearPrecio(op.precio_salida)}`}{" "}
                  · {new Date(op.created_at).toLocaleString("es-DO", {
                    day: "numeric",
                    month: "short",
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </div>
              </div>
              {op.ganancia_perdida != null && (
                <span
                  className={`shrink-0 whitespace-nowrap font-display font-bold text-sm ${
                    op.ganancia_perdida >= 0 ? "text-gain" : "text-loss"
                  }`}
                >
                  {op.ganancia_perdida >= 0 ? "+" : ""}
                  {formatearDinero(op.ganancia_perdida)} USD
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
