import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { marcarDepositosRevisados } from "@/lib/actions/depositos";
import { BotonPagoDeposito } from "@/components/admin/BotonPagoDeposito";
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

  const [{ data: depositosRaw }, { data: saldosRaw }] = await Promise.all([
    supabase
      .from("depositos_simulados")
      .select("*, usuarios!usuario_id(email, id_corto, nombre)")
      .order("created_at", { ascending: false })
      .returns<DepositoConUsuario[]>(),
    // Solo para poder avisarle al admin, al revertir un depósito ya
    // pagado, si el usuario ya gastó ese saldo (una operación abierta usa
    // el saldo completo) y la reversión no le va a quedar exacta.
    supabase.from("saldo_virtual").select("usuario_id, saldo_usd"),
  ]);

  const depositos = depositosRaw ?? [];
  const saldoPorUsuario = new Map(
    (saldosRaw ?? []).map((s) => [s.usuario_id, Number(s.saldo_usd)])
  );

  // URL firmada por depósito (bucket privado, igual que en el chat de
  // soporte) — se resuelve aquí en el servidor porque esta pantalla ya es
  // solo-admin y las políticas de storage.objects dejan al admin ver
  // cualquier comprobante.
  const urlsComprobante: Record<string, string> = {};
  await Promise.all(
    depositos
      .filter((d) => d.comprobante_path)
      .map(async (d) => {
        const { data } = await supabase.storage
          .from("comprobantes-soporte")
          .createSignedUrl(d.comprobante_path!, 3600);
        if (data?.signedUrl) urlsComprobante[d.id] = data.signedUrl;
      })
  );
  const sinRevisar = depositos.filter((d) => !d.revisado_por_admin);
  const pendientes = depositos.filter((d) => !d.pagado);
  const pagados = depositos.filter((d) => d.pagado);

  // Se marca todo como revisado al entrar a esta pantalla (mismo patrón
  // que marcarLeidoPorAdmin en /soporte/[usuarioId]) — hay que hacerlo
  // DESPUÉS de calcular sinRevisar de arriba, para que esta misma visita
  // todavía muestre cuáles eran los nuevos.
  await marcarDepositosRevisados();

  function Fila({ d }: { d: DepositoConUsuario }) {
    return (
      <div className="border border-[var(--border)] rounded-xl p-4 flex justify-between items-center gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <div className="font-display font-bold text-base tabular text-gain">
              ${formatearDinero(d.monto)}
            </div>
            <span
              className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
                d.pagado ? "bg-gain/15 text-gain" : "bg-brand-secondary/15 text-brand-secondary"
              }`}
            >
              {d.pagado ? "Pagado" : "Pendiente"}
            </span>
            {!d.revisado_por_admin && (
              <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-loss/15 text-loss">
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
          {urlsComprobante[d.id] && (
            <a
              href={urlsComprobante[d.id]}
              target="_blank"
              rel="noopener noreferrer"
              className="text-[12px] text-brand-primary font-semibold hover:underline"
            >
              Ver comprobante
            </a>
          )}
        </div>
        <BotonPagoDeposito
          depositoId={d.id}
          pagado={d.pagado}
          monto={Number(d.monto)}
          saldoActual={saldoPorUsuario.get(d.usuario_id) ?? 0}
        />
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

      <h1 className="font-display font-semibold text-[26px] mb-1.5">Depósitos</h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Depósitos simulados que cada usuario registró (cada usuario solo
        puede hacer uno en toda su existencia). Confirma primero que el
        dinero llegó de verdad a la wallet — al marcarlo como pagado, ese
        monto exacto se le suma automáticamente a su saldo de inversión.
        {sinRevisar.length > 0 &&
          ` ${sinRevisar.length} nuevo${sinRevisar.length === 1 ? "" : "s"} desde tu última visita.`}
      </p>

      <h2 className="font-display font-semibold text-lg mb-3">
        Pendientes {pendientes.length > 0 && `(${pendientes.length})`}
      </h2>
      {pendientes.length === 0 ? (
        <p className="text-[13px] text-foreground-muted mb-7">
          No hay depósitos pendientes de asignar.
        </p>
      ) : (
        <div className="flex flex-col gap-2 mb-7">
          {pendientes.map((d) => (
            <Fila key={d.id} d={d} />
          ))}
        </div>
      )}

      {pagados.length > 0 && (
        <>
          <h2 className="font-display font-semibold text-lg mb-3">Historial</h2>
          <div className="flex flex-col gap-2">
            {pagados.map((d) => (
              <Fila key={d.id} d={d} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
