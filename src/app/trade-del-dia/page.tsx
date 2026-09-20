import { redirect } from "next/navigation";
import { IconoReto, IconoInfo } from "@/components/ui/Iconos";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { AdminPickForm } from "@/components/admin/AdminPickForm";
import { AbrirOperacionForm } from "@/components/reto/AbrirOperacionForm";
import { BotonCerrarTodasOperaciones } from "@/components/admin/BotonCerrarTodasOperaciones";
import { formatearDinero, formatearPrecio } from "@/lib/format";
import { estaAbiertaBolsaNY } from "@/lib/horarioMercado";
import type { OperacionSimulada, PickDelDia } from "@/lib/types";

export default async function PaginaTradeDelDia() {
  const usuario = await obtenerUsuarioActual();
  if (!usuario) redirect("/login");
  if (!usuario.activo) redirect("/cuenta-desactivada");

  const supabase = await crearClienteSupabaseServidor();

  const [
    { data: pick },
    { data: saldo },
    { data: operacionAbierta },
    { data: historial },
    { data: simbolosAbiertosRaw },
  ] = await Promise.all([
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
    esAdmin(usuario)
      ? supabase
          .from("operaciones_simuladas")
          .select("activo")
          .eq("estado", "abierta")
      : Promise.resolve({ data: null }),
  ]);

  const simbolosAbiertos = [
    ...new Set((simbolosAbiertosRaw ?? []).map((o) => o.activo)),
  ];

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] flex items-center gap-2.5 mb-1.5">
        <IconoReto className="w-6 h-6 text-brand-primary" />
        Trade del día
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Practica con saldo virtual sobre el pick de hoy.
      </p>

      {esAdmin(usuario) && (
        <>
          <AdminPickForm />
          <BotonCerrarTodasOperaciones simbolos={simbolosAbiertos} />
        </>
      )}

      {!pick ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          El admin todavía no ha definido el pick de hoy.
        </p>
      ) : (
        <div className="grid md:grid-cols-[1.3fr_1fr] gap-4">
          <div className="border border-[var(--border)] rounded-2xl p-5 flex flex-col gap-3.5">
            <div className="flex justify-between items-baseline">
              <div>
                {/* Mismo nombre que en /perfil: la tarjeta se llamaba
                    "Saldo virtual" aquí y "Saldo de Inversión" allá, y
                    parecían dos cifras distintas. */}
                <div className="text-[13px] text-foreground-muted">
                  Saldo de Inversión
                </div>
                <div className="font-display font-bold text-[30px] tabular">
                  ${formatearDinero(saldo?.saldo_usd ?? 0)}
                </div>
              </div>
              <span className="bg-gain/15 text-gain text-xs font-bold px-3 py-1 rounded-full">
                Pick de hoy: {pick.activo}
              </span>
            </div>

            <div className="flex items-center gap-1.5 text-xs text-foreground-muted bg-surface px-3 py-2 rounded-lg">
              <IconoInfo />
              Saldo de práctica — sin valor monetario real.
            </div>

            {!operacionAbierta ? (
              <AbrirOperacionForm
                activo={pick.activo}
                saldoDisponible={saldo?.saldo_usd ?? 0}
                mercadoAbierto={estaAbiertaBolsaNY()}
                esAdmin={esAdmin(usuario)}
              />
            ) : (
              // Decía "Ciérrala para poder abrir otra", pero el usuario no
              // puede cerrar nada: la sesión la liquida el admin en bloque.
              <p className="text-[13px] text-foreground-muted">
                Ya tienes una operación abierta en {operacionAbierta.activo}.
                Podrás abrir otra cuando el admin cierre la sesión de hoy.
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
                <div className="text-[12px] text-foreground-muted">
                  Abierta a las{" "}
                  {new Date(operacionAbierta.created_at).toLocaleTimeString(
                    "es-DO",
                    { hour: "2-digit", minute: "2-digit" }
                  )}{" "}
                  ·{" "}
                  {new Date(operacionAbierta.created_at).toLocaleDateString(
                    "es-DO",
                    { day: "numeric", month: "short" }
                  )}
                </div>
                <div className="flex items-center gap-1.5 text-[12px] text-foreground-muted bg-surface px-3 py-2 rounded-lg">
                  <IconoInfo />
                  El resultado se define cuando el admin cierre la sesión —
                  hasta entonces no se muestra precio en vivo ni PNL
                  flotante.
                </div>
                <div className="font-display font-bold text-xl text-foreground-muted">
                  $0.00 flotante
                </div>
                <p className="text-[13px] text-foreground-muted mt-2">
                  Solo el admin puede cerrar operaciones (cierre masivo de
                  la sesión). Espera a que se liquide.
                </p>
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
                className="border border-[var(--border)] rounded-xl p-4 flex justify-between items-center gap-3"
              >
                <div className="min-w-0">
                  <div className="font-medium text-sm">
                    {op.activo} · {op.tipo === "compra" ? "Compra" : "Venta"}
                  </div>
                  <div className="text-[12px] text-foreground-muted">
                    Entrada ${formatearPrecio(op.precio_entrada)} → Salida $
                    {op.precio_salida != null ? formatearPrecio(op.precio_salida) : "—"}
                  </div>
                </div>
                {/* shrink-0 + whitespace-nowrap: en móvil el importe se
                    partía en dos líneas ("+622.04 / USD"). */}
                <span
                  className={`shrink-0 whitespace-nowrap font-display font-bold text-sm ${
                    (op.ganancia_perdida ?? 0) >= 0 ? "text-gain" : "text-loss"
                  }`}
                >
                  {/* ?? 0 también en el número: sin esto una operación
                      cerrada sin ganancia registrada mostraba "+ USD". */}
                  {(op.ganancia_perdida ?? 0) >= 0 ? "+" : ""}
                  {formatearDinero(op.ganancia_perdida ?? 0)} USD
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
