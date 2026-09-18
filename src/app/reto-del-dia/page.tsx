import { redirect } from "next/navigation";
import { IconoReto, IconoInfo } from "@/components/ui/Iconos";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerPrecioCripto } from "@/lib/market/binance";
import { AdminPickForm } from "@/components/admin/AdminPickForm";
import { AbrirOperacionForm } from "@/components/reto/AbrirOperacionForm";
import { CerrarOperacionBoton } from "@/components/reto/CerrarOperacionBoton";
import { formatearPrecio } from "@/lib/format";
import type { OperacionSimulada, PickDelDia } from "@/lib/types";

export default async function PaginaRetoDelDia() {
  const usuario = await obtenerUsuarioActual();
  if (!usuario) redirect("/login");
  if (!usuario.activo) redirect("/cuenta-desactivada");

  const supabase = await crearClienteSupabaseServidor();

  const [{ data: pick }, { data: saldo }, { data: operacionAbierta }, { data: historial }] =
    await Promise.all([
      supabase
        .from("pick_del_dia")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle<PickDelDia>(),
      supabase
        .from("saldo_virtual")
        .select("saldo_usd")
        .eq("usuario_id", usuario.id)
        .single(),
      supabase
        .from("operaciones_simuladas")
        .select("*")
        .eq("usuario_id", usuario.id)
        .eq("estado", "abierta")
        .maybeSingle<OperacionSimulada>(),
      supabase
        .from("operaciones_simuladas")
        .select("*")
        .eq("usuario_id", usuario.id)
        .eq("estado", "cerrada")
        .order("cerrado_en", { ascending: false })
        .limit(5)
        .returns<OperacionSimulada[]>(),
    ]);

  // Ganancia/pérdida flotante: se calcula en cada carga con el precio real actual.
  let flotante: number | null = null;
  let precioActual: number | null = null;
  if (operacionAbierta) {
    try {
      const { precio } = await obtenerPrecioCripto(operacionAbierta.activo);
      precioActual = precio;
      flotante =
        operacionAbierta.tipo === "compra"
          ? (precio - operacionAbierta.precio_entrada) * operacionAbierta.cantidad
          : (operacionAbierta.precio_entrada - precio) * operacionAbierta.cantidad;
    } catch {
      // si falla la consulta de precio, simplemente no mostramos el flotante
    }
  }

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] flex items-center gap-2.5 mb-1.5">
        <IconoReto className="w-6 h-6 text-brand-primary" />
        Reto del día
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Practica con saldo virtual sobre el pick de hoy.
      </p>

      {esAdmin(usuario) && <AdminPickForm />}

      {!pick ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          El admin todavía no ha definido el pick de hoy.
        </p>
      ) : (
        <div className="grid md:grid-cols-[1.3fr_1fr] gap-4">
          <div className="border border-[var(--border)] rounded-2xl p-5 flex flex-col gap-3.5">
            <div className="flex justify-between items-baseline">
              <div>
                <div className="text-[13px] text-foreground-muted">
                  Saldo virtual
                </div>
                <div className="font-display font-bold text-[30px] tabular">
                  $
                  {(saldo?.saldo_usd ?? 0).toLocaleString("en-US", {
                    minimumFractionDigits: 2,
                  })}
                </div>
              </div>
              <span className="bg-gain/15 text-gain text-xs font-bold px-3 py-1 rounded-full">
                Pick de hoy: {pick.activo}
              </span>
            </div>

            <div className="flex items-center gap-1.5 text-xs text-foreground-muted bg-surface px-3 py-2 rounded-lg">
              <IconoInfo />
              Saldo virtual — sin valor monetario real.
            </div>

            {!operacionAbierta ? (
              <AbrirOperacionForm
                activo={pick.activo}
                saldoDisponible={saldo?.saldo_usd ?? 0}
              />
            ) : (
              <p className="text-[13px] text-foreground-muted">
                Ya tienes una operación abierta en {operacionAbierta.activo}.
                Ciérrala para poder abrir otra.
              </p>
            )}
          </div>

          <div className="border border-[var(--border)] rounded-2xl p-5 flex flex-col gap-2">
            {operacionAbierta ? (
              <>
                <div className="text-[13px] text-foreground-muted mb-0.5">
                  Operación abierta
                </div>
                <div className="font-display font-semibold text-base">
                  {operacionAbierta.activo} ·{" "}
                  {operacionAbierta.tipo === "compra" ? "Compra" : "Venta"}
                </div>
                <div className="text-[13px] text-foreground-muted">
                  Entrada ${formatearPrecio(operacionAbierta.precio_entrada)} ·
                  Cantidad {operacionAbierta.cantidad.toFixed(6)}
                </div>
                {precioActual && (
                  <div className="text-[13px] text-foreground-muted">
                    Precio actual: ${formatearPrecio(precioActual)}
                  </div>
                )}
                {flotante !== null && (
                  <div
                    className={`font-display font-bold text-xl ${
                      flotante >= 0 ? "text-gain" : "text-loss"
                    }`}
                  >
                    {flotante >= 0 ? "+" : ""}
                    {flotante.toFixed(2)} USD flotante
                  </div>
                )}
                <div className="mt-2">
                  <CerrarOperacionBoton operacionId={operacionAbierta.id} />
                </div>
              </>
            ) : (
              <p className="text-sm text-foreground-muted">
                No tienes ninguna operación abierta en este momento.
              </p>
            )}
          </div>
        </div>
      )}

      {historial && historial.length > 0 && (
        <div className="mt-8">
          <h2 className="font-display font-semibold text-lg mb-3">
            Historial reciente
          </h2>
          <div className="flex flex-col gap-2.5">
            {historial.map((op) => (
              <div
                key={op.id}
                className="border border-[var(--border)] rounded-xl p-4 flex justify-between items-center"
              >
                <div>
                  <div className="font-medium text-sm">
                    {op.activo} · {op.tipo === "compra" ? "Compra" : "Venta"}
                  </div>
                  <div className="text-[12px] text-foreground-muted">
                    Entrada ${formatearPrecio(op.precio_entrada)} → Salida $
                    {op.precio_salida != null ? formatearPrecio(op.precio_salida) : "—"}
                  </div>
                </div>
                <span
                  className={`font-display font-bold text-sm ${
                    (op.ganancia_perdida ?? 0) >= 0 ? "text-gain" : "text-loss"
                  }`}
                >
                  {(op.ganancia_perdida ?? 0) >= 0 ? "+" : ""}
                  {op.ganancia_perdida?.toFixed(2)} USD
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
