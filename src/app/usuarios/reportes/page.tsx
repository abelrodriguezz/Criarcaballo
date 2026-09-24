import { redirect } from "next/navigation";
import Link from "next/link";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { BotonExportarCSV } from "@/components/admin/BotonExportarCSV";
import {
  fechaEnNY,
  inicioDelDiaNY,
  finDelDiaNY,
} from "@/lib/horarioMercado";
import { formatearDinero } from "@/lib/format";
import { BotonPagoGanancia } from "@/components/admin/BotonPagoGanancia";
import type { GananciaConcurso } from "@/lib/types";

interface FilaAgregado {
  usuario_id: string;
  num_operaciones: number | string;
  ganancia_neta: number | string;
}

type GananciaPendiente = GananciaConcurso & {
  usuarios: { email: string; id_corto: number | null; wallet_usdt_erc20: string | null } | null;
};

export default async function PaginaReportes({
  searchParams,
}: {
  searchParams: Promise<{
    fecha?: string;
    usuarioId?: string;
    opero?: string;
  }>;
}) {
  const {
    fecha: fechaParam,
    usuarioId: usuarioIdParam,
    opero: operoParam,
  } = await searchParams;
  const usuarioActual = await obtenerUsuarioActual();

  if (!usuarioActual) redirect("/login");
  if (!usuarioActual.activo) redirect("/cuenta-desactivada");
  if (!esAdmin(usuarioActual)) redirect("/perfil");

  // El "día" del reporte es el día de la bolsa de Nueva York, no el día
  // UTC: antes se usaba `${fecha}T00:00:00.000Z` y una operación abierta
  // de noche hora de NY aparecía en el reporte del día siguiente. Estos
  // reportes son los que deciden a quién se le paga el premio, así que la
  // fecha tiene que significar lo que el admin cree que significa.
  const fechaValida = /^\d{4}-\d{2}-\d{2}$/.test(fechaParam ?? "");
  const fecha = fechaValida ? (fechaParam as string) : fechaEnNY();
  const usuarioIdFiltro = usuarioIdParam || "";
  // "" = todos, "si" = solo los que operaron, "no" = solo los que no
  const operoFiltro = operoParam === "si" || operoParam === "no" ? operoParam : "";

  const inicio = inicioDelDiaNY(fecha).toISOString();
  const fin = new Date(finDelDiaNY(fecha).getTime() - 1).toISOString();

  const supabase = await crearClienteSupabaseServidor();

  const [{ data: todosUsuarios }, { data: agregadosRaw }, resultadoPendientes] =
    await Promise.all([
      supabase
        .from("usuarios")
        .select("id, email, id_corto, wallet_usdt_erc20")
        .order("email"),
      supabase.rpc("reporte_operaciones_por_dia", {
        p_inicio: inicio,
        p_fin: fin,
      }) as unknown as Promise<{ data: FilaAgregado[] | null }>,
      supabase
        // "usuarios!usuario_id": ganancias_concursos tiene dos llaves
        // foráneas hacia usuarios (usuario_id y creado_por) — sin el hint,
        // PostgREST no sabe cuál usar y devuelve el error PGRST201 en vez
        // de datos (el filtro quedaba silenciosamente vacío).
        .from("ganancias_concursos")
        .select("*, usuarios!usuario_id(email, id_corto, wallet_usdt_erc20)")
        .eq("pagado", false)
        .order("created_at", { ascending: true })
        .returns<GananciaPendiente[]>(),
    ]);
  const pendientesRaw = resultadoPendientes.data;

  const mapaAgregados = new Map(
    (agregadosRaw ?? []).map((a) => [a.usuario_id, a])
  );

  const pendientes = pendientesRaw ?? [];
  const totalPendiente = pendientes.reduce((s, p) => s + p.monto, 0);

  const usuariosBase = usuarioIdFiltro
    ? (todosUsuarios ?? []).filter((u) => u.id === usuarioIdFiltro)
    : (todosUsuarios ?? []);

  const filas = usuariosBase.map((u) => {
    const agr = mapaAgregados.get(u.id);
    const numOperaciones = agr ? Number(agr.num_operaciones) : 0;
    return {
      id: u.id,
      idCorto: u.id_corto,
      email: u.email,
      wallet: u.wallet_usdt_erc20 ?? null,
      operoEseDia: numOperaciones > 0,
      numOperaciones,
      gananciaNeta: agr ? Number(agr.ganancia_neta) : 0,
    };
  });

  filas.sort((a, b) => {
    if (a.operoEseDia !== b.operoEseDia) return a.operoEseDia ? -1 : 1;
    return b.gananciaNeta - a.gananciaNeta;
  });

  // El resumen de arriba siempre refleja el filtro de fecha/usuario
  // completo — el filtro de "operó/no operó" solo recorta la lista de
  // abajo (y lo que se exporta), para no perder de vista el panorama
  // general al filtrar.
  const totalOperaron = filas.filter((f) => f.operoEseDia).length;
  const gananciaNetaTotal = filas.reduce((s, f) => s + f.gananciaNeta, 0);

  const filasFiltradas =
    operoFiltro === "si"
      ? filas.filter((f) => f.operoEseDia)
      : operoFiltro === "no"
        ? filas.filter((f) => !f.operoEseDia)
        : filas;

  return (
    <div className="py-10">
      <Link
        href="/perfil"
        className="text-[13px] text-brand-primary font-semibold mb-4 inline-block"
      >
        ← Volver a perfil
      </Link>

      <h1 className="font-display font-semibold text-[26px] mb-1.5">
        Reportes de operaciones
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Quién operó (Trade del día) en la fecha elegida, y su ganancia o
        pérdida neta ese día. El día se cuenta en horario de Nueva York,
        igual que el horario de mercado.
      </p>

      <h2 className="font-display font-semibold text-lg mb-3 flex items-center gap-2">
        Ganancias pendientes de pago
        {pendientes.length > 0 && (
          <span className="text-[11px] font-bold uppercase tracking-wide px-2 py-0.5 bg-brand-secondary/15 text-brand-secondary">
            {pendientes.length}
          </span>
        )}
      </h2>

      {pendientes.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] p-6 text-center mb-8">
          No hay ninguna ganancia pendiente de pago en este momento.
        </p>
      ) : (
        <>
          <div className="border border-[var(--border)] p-5 mb-4">
            <div className="text-[13px] text-foreground-muted mb-1">
              Total pendiente por pagar
            </div>
            <div className="font-display font-bold text-2xl tabular text-brand-secondary">
              ${formatearDinero(totalPendiente)} USD
            </div>
          </div>

          <div className="flex flex-col gap-2.5 mb-8">
            {pendientes.map((p) => (
              <div
                key={p.id}
                className="border border-[var(--border)] p-4 flex flex-wrap items-center justify-between gap-3"
              >
                <div className="min-w-0">
                  <Link
                    href={`/usuarios/${p.usuario_id}`}
                    className="text-sm font-medium break-all hover:text-brand-primary"
                  >
                    {p.usuarios?.email ?? "Usuario eliminado"}
                    {p.usuarios?.id_corto && (
                      <span className="text-foreground-muted font-normal font-mono text-[12px]">
                        {" "}
                        · ID {p.usuarios.id_corto}
                      </span>
                    )}
                  </Link>
                  <div className="text-[12px] text-foreground-muted">
                    {p.concepto || "Sin concepto"} ·{" "}
                    {new Date(p.created_at).toLocaleDateString("es-DO", {
                      day: "numeric",
                      month: "short",
                      year: "numeric",
                    })}
                  </div>
                  <div className="text-[11px] text-foreground-muted font-mono truncate">
                    {p.usuarios?.wallet_usdt_erc20 ?? "Sin wallet"}
                  </div>
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  <span className="font-display font-bold text-sm tabular text-brand-secondary">
                    ${formatearDinero(p.monto)}
                  </span>
                  <BotonPagoGanancia gananciaId={p.id} pagado={false} />
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      <h2 className="font-display font-semibold text-lg mb-3">
        Operaciones por día
      </h2>

      <form
        method="get"
        className="flex flex-wrap items-end gap-3 mb-6 border border-[var(--border)] rounded-2xl p-4"
      >
        <div>
          <label className="block text-[12px] text-foreground-muted mb-1">
            Fecha
          </label>
          <input
            type="date"
            name="fecha"
            defaultValue={fecha}
            className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          />
        </div>
        <div>
          <label className="block text-[12px] text-foreground-muted mb-1">
            Usuario
          </label>
          <select
            name="usuarioId"
            defaultValue={usuarioIdFiltro}
            className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm max-w-[220px]"
          >
            <option value="">Todos</option>
            {(todosUsuarios ?? []).map((u) => (
              <option key={u.id} value={u.id}>
                {u.email}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-[12px] text-foreground-muted mb-1">
            Estado
          </label>
          <select
            name="opero"
            defaultValue={operoFiltro}
            className="px-3 py-2 rounded-lg border border-[var(--border)] bg-background text-sm"
          >
            <option value="">Todos</option>
            <option value="si">Operaron</option>
            <option value="no">No operaron</option>
          </select>
        </div>
        <button
          type="submit"
          className="bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-sm px-5 py-2.5 rounded-lg transition-colors"
        >
          Generar reporte
        </button>
        <div className="ml-auto">
          <BotonExportarCSV filas={filasFiltradas} fecha={fecha} />
        </div>
      </form>

      <div className="grid grid-cols-2 gap-3 mb-6">
        <div className="border border-[var(--border)] rounded-2xl p-5">
          <div className="text-[13px] text-foreground-muted mb-1">
            Usuarios que operaron
          </div>
          <div className="font-display font-bold text-2xl tabular">
            {totalOperaron} / {filas.length}
          </div>
        </div>
        <div className="border border-[var(--border)] rounded-2xl p-5">
          <div className="text-[13px] text-foreground-muted mb-1">
            Ganancia/pérdida neta del día
          </div>
          <div
            className={`font-display font-bold text-2xl tabular ${
              gananciaNetaTotal >= 0 ? "text-gain" : "text-loss"
            }`}
          >
            {gananciaNetaTotal >= 0 ? "+" : ""}
            {formatearDinero(gananciaNetaTotal)} USD
          </div>
        </div>
      </div>

      {filasFiltradas.length === 0 ? (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center">
          No hay usuarios que coincidan con este filtro.
        </p>
      ) : (
        <div className="flex flex-col gap-2.5">
          {filasFiltradas.map((f) => (
            <div
              key={f.id}
              className="border border-[var(--border)] rounded-xl p-4 flex flex-wrap items-center justify-between gap-3"
            >
              <div className="min-w-0">
                <div className="text-sm font-medium break-all">
                  {f.email}
                  {f.idCorto && (
                    <span className="text-foreground-muted font-normal font-mono text-[12px]">
                      {" "}
                      · ID {f.idCorto}
                    </span>
                  )}
                </div>
                <div className="text-[12px] text-foreground-muted">
                  {f.numOperaciones}{" "}
                  {f.numOperaciones === 1 ? "operación" : "operaciones"} ese
                  día
                </div>
                <div className="text-[11px] text-foreground-muted font-mono truncate">
                  {f.wallet ?? "Sin wallet"}
                </div>
              </div>
              <div className="flex items-center gap-3 shrink-0">
                <span
                  className={`text-[11px] font-bold uppercase tracking-wide px-2 py-1 rounded-full ${
                    f.operoEseDia
                      ? "bg-gain/15 text-gain"
                      : "bg-foreground-muted/15 text-foreground-muted"
                  }`}
                >
                  {f.operoEseDia ? "Operó" : "No operó"}
                </span>
                {f.operoEseDia && (
                  <span
                    className={`font-display font-bold text-sm tabular ${
                      f.gananciaNeta >= 0 ? "text-gain" : "text-loss"
                    }`}
                  >
                    {f.gananciaNeta >= 0 ? "+" : ""}
                    {formatearDinero(f.gananciaNeta)} USD
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
