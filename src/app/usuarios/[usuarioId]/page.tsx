import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { AdminGananciaForm } from "@/components/admin/AdminGananciaForm";
import { TarjetaGananciaAdmin } from "@/components/admin/TarjetaGananciaAdmin";
import type { GananciaConcurso, Usuario } from "@/lib/types";

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

  const [{ data: perfil }, { data: ganancias }] = await Promise.all([
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
  ]);

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
        <p className="text-[13px] text-foreground-muted font-mono mb-7 break-all">
          Wallet: {perfil.wallet_usdt_erc20}
        </p>
      ) : (
        <p className="text-[13px] text-foreground-muted mb-7">
          Este usuario no ha agregado su wallet todavía.
        </p>
      )}

      <div className="grid grid-cols-2 gap-3 mb-6">
        <div className="border border-[var(--border)] rounded-2xl p-5">
          <div className="text-[13px] text-foreground-muted mb-1">
            Total ganado
          </div>
          <div className="font-display font-bold text-2xl tabular text-gain">
            +${total.toLocaleString("en-US", { minimumFractionDigits: 2 })}
          </div>
        </div>
        <div className="border border-[var(--border)] rounded-2xl p-5">
          <div className="text-[13px] text-foreground-muted mb-1">
            Pendiente por pagar
          </div>
          <div className="font-display font-bold text-2xl tabular text-brand-secondary">
            ${pendiente.toLocaleString("en-US", { minimumFractionDigits: 2 })}
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
        <div className="flex flex-col gap-2.5">
          {ganancias.map((g) => (
            <TarjetaGananciaAdmin key={g.id} ganancia={g} usuarioId={usuarioId} />
          ))}
        </div>
      )}
    </div>
  );
}
