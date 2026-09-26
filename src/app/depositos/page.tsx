import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { marcarDepositosRevisados } from "@/lib/actions/depositos";
import { formatearDinero } from "@/lib/format";
import type { DepositoSimulado } from "@/lib/types";

type DepositoConUsuario = DepositoSimulado & {
  usuarios: { email: string; id_corto: number | null; nombre: string | null } | null;
};

export default async function PaginaDepositos() {
  const usuarioActual = await obtenerUsuarioActual();
  if (!usuarioActual) redirect("/login");
  if (!usuarioActual.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuarioActual)) redirect("/perfil");

  const supabase = await crearClienteSupabaseServidor();

  const { data: depositosRaw } = await supabase
    .from("depositos_simulados")
    .select("*, usuarios!usuario_id(email, id_corto, nombre)")
    .order("created_at", { ascending: false })
    .returns<DepositoConUsuario[]>();

  const depositos = depositosRaw ?? [];
  const sinRevisar = depositos.filter((d) => !d.revisado_por_admin);

  // Se marca todo como revisado al entrar a esta pantalla (mismo patrón
  // que marcarLeidoPorAdmin en /soporte/[usuarioId]) — hay que hacerlo
  // DESPUÉS de calcular sinRevisar de arriba, para que esta misma visita
  // todavía muestre cuáles eran los nuevos.
  await marcarDepositosRevisados();

  return (
    <div className="py-10">
      <Link
        href="/perfil"
        className="text-[13px] text-brand-primary font-semibold mb-4 inline-block"
      >
        ← Volver a perfil
      </Link>

      <h1 className="font-display font-semibold text-[26px] mb-1.5">Depósitos</h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Depósitos simulados que cada usuario registró (solo informativo —
        no mueve saldo de inversión, ver Gestión de usuarios para
        asignarlo a mano). {sinRevisar.length > 0 && `${sinRevisar.length} nuevo${sinRevisar.length === 1 ? "" : "s"} desde tu última visita.`}
      </p>

      {depositos.length === 0 ? (
        <p className="text-[13px] text-foreground-muted">
          Todavía no hay ningún depósito registrado.
        </p>
      ) : (
        <div className="flex flex-col gap-2">
          {depositos.map((d) => (
            <div
              key={d.id}
              className="border border-[var(--border)] rounded-xl p-4 flex justify-between items-center gap-3"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <div className="font-display font-bold text-base tabular text-gain">
                    ${formatearDinero(d.monto)}
                  </div>
                  {!d.revisado_por_admin && (
                    <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-brand-secondary/15 text-brand-secondary">
                      Nuevo
                    </span>
                  )}
                </div>
                <div className="text-[12px] text-foreground-muted truncate">
                  {d.usuarios?.nombre || d.usuarios?.email || "Usuario eliminado"}
                  {d.usuarios?.id_corto ? ` · ID ${d.usuarios.id_corto}` : ""} ·{" "}
                  {new Date(d.created_at).toLocaleDateString("es-DO", {
                    day: "numeric",
                    month: "short",
                    year: "numeric",
                  })}
                </div>
                {d.wallet_mostrada && (
                  <div className="text-[12px] text-foreground-muted font-mono truncate">
                    {d.wallet_mostrada}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
