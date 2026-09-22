import { IconoMercado } from "@/components/ui/Iconos";
import { TarjetaActivo } from "@/components/mercado/TarjetaActivo";
import {
  obtenerVariosPreciosCripto,
  obtenerTopGanadoresCripto,
  obtenerVariosSparklinesCripto,
} from "@/lib/market/binance";
import {
  obtenerVariosPreciosAcciones,
  obtenerTopGanadoresAcciones,
  obtenerTopPerdedoresAcciones,
} from "@/lib/market/acciones";
import { obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerDiccionario } from "@/lib/i18n/servidor";

const PARES_CRIPTO = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "HBARUSDT"];
const SIMBOLOS_INDICES = ["SPX", "IXIC", "DJI"];

export const revalidate = 30; // refresca los precios cada 30s como máximo

interface ActivoNormalizado {
  simbolo: string;
  precio: number;
  cambioPorc: number;
  tipo: "Cripto" | "Acción";
}

export default async function PaginaMercado() {
  const [usuario, t] = await Promise.all([
    obtenerUsuarioActual(),
    obtenerDiccionario(),
  ]);

  const [cripto, indices, favoritos, topCripto, topAcciones, topPerdedoresAcciones] =
    await Promise.all([
      obtenerVariosPreciosCripto(PARES_CRIPTO),
      obtenerVariosPreciosAcciones(SIMBOLOS_INDICES),
      usuario
        ? crearClienteSupabaseServidor().then((supabase) =>
            supabase
              .from("favoritos")
              .select("activo")
              .eq("usuario_id", usuario.id)
          )
        : Promise.resolve({ data: null }),
      obtenerTopGanadoresCripto(5),
      obtenerTopGanadoresAcciones(5),
      obtenerTopPerdedoresAcciones(5),
    ]);

  const setFavoritos = new Set(
    (favoritos.data ?? []).map((f) => f.activo as string)
  );

  const sinDatos = cripto.length === 0 && indices.length === 0;

  // Top ganadores del día mezclando cripto y acciones (no solo un tipo),
  // ordenado de mayor a menor subida.
  const topGanadores: ActivoNormalizado[] = [
    ...topCripto.map((c) => ({
      simbolo: c.simbolo,
      precio: c.precio,
      cambioPorc: c.cambioPorc24h,
      tipo: "Cripto" as const,
    })),
    ...topAcciones.map((a) => ({
      simbolo: a.simbolo,
      precio: a.precio,
      cambioPorc: a.cambioPorc,
      tipo: "Acción" as const,
    })),
  ]
    .sort((a, b) => b.cambioPorc - a.cambioPorc)
    .slice(0, 6);

  // Mini-gráficos de tendencia: solo para cripto (Binance es gratis e
  // ilimitado) — para acciones/índices costaría cuota extra de Twelve Data.
  const simbolosParaSparkline = [
    ...new Set([
      ...cripto.map((c) => c.simbolo),
      ...topGanadores.filter((a) => a.tipo === "Cripto").map((a) => a.simbolo),
    ]),
  ];
  const sparklines = await obtenerVariosSparklinesCripto(simbolosParaSparkline);

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] flex items-center gap-2.5 mb-1.5">
        <IconoMercado className="w-6 h-6 text-brand-primary" />
        {t.mercado.titulo}
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {t.mercado.subtitulo}
      </p>

      {sinDatos && (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-6">
          {t.mercado.sinDatos}
        </p>
      )}

      {topGanadores.length > 0 && (
        <>
          <h2 className="text-[13px] font-semibold text-foreground-muted uppercase tracking-wide mb-3">
            {t.mercado.masSubioHoy}
          </h2>
          <div className="grid md:grid-cols-3 gap-4 mb-8">
            {topGanadores.map((activo) => (
              <TarjetaActivo
                key={`top-${activo.tipo}-${activo.simbolo}`}
                simbolo={activo.simbolo}
                precio={activo.precio}
                cambioPorc={activo.cambioPorc}
                etiqueta={
                  activo.tipo === "Cripto"
                    ? t.mercado.criptoEtiqueta
                    : t.mercado.accionEtiqueta
                }
                mostrarFavorito={!!usuario && activo.tipo === "Cripto"}
                esFavoritoInicial={setFavoritos.has(activo.simbolo)}
                sparkline={sparklines[activo.simbolo]}
              />
            ))}
          </div>
        </>
      )}

      {cripto.length > 0 && (
        <>
          <h2 className="text-[13px] font-semibold text-foreground-muted uppercase tracking-wide mb-3">
            {t.mercado.cripto}
          </h2>
          <div className="grid md:grid-cols-3 gap-4 mb-8">
            {cripto.map((activo) => (
              <TarjetaActivo
                key={activo.simbolo}
                simbolo={activo.simbolo}
                precio={activo.precio}
                cambioPorc={activo.cambioPorc24h}
                mostrarFavorito={!!usuario}
                esFavoritoInicial={setFavoritos.has(activo.simbolo)}
                sparkline={sparklines[activo.simbolo]}
              />
            ))}
          </div>
        </>
      )}

      {indices.length > 0 ? (
        <>
          <h2 className="text-[13px] font-semibold text-foreground-muted uppercase tracking-wide mb-3">
            {t.mercado.indices}
          </h2>
          <div className="grid md:grid-cols-3 gap-4 mb-8">
            {indices.map((activo) => (
              <TarjetaActivo
                key={activo.simbolo}
                simbolo={activo.simbolo}
                precio={activo.precio}
                cambioPorc={activo.cambioPorc}
              />
            ))}
          </div>
        </>
      ) : (
        <p className="text-xs text-foreground-muted mt-2 mb-8">
          {process.env.MARKET_API_KEY
            ? t.mercado.sinIndicesConKey
            : (
              <>
                {t.mercado.sinIndicesSinKeyPre} <code>MARKET_API_KEY</code>{" "}
                {t.mercado.sinIndicesSinKeyPost}
              </>
            )}
        </p>
      )}

      {topAcciones.length > 0 && (
        <>
          <h2 className="text-[13px] font-semibold text-foreground-muted uppercase tracking-wide mb-3">
            {t.mercado.topGanadorAcciones}
          </h2>
          <div className="grid md:grid-cols-3 gap-4 mb-8">
            {topAcciones.map((activo) => (
              <TarjetaActivo
                key={`gainer-${activo.simbolo}`}
                simbolo={activo.simbolo}
                precio={activo.precio}
                cambioPorc={activo.cambioPorc}
              />
            ))}
          </div>
        </>
      )}

      {topPerdedoresAcciones.length > 0 && (
        <>
          <h2 className="text-[13px] font-semibold text-foreground-muted uppercase tracking-wide mb-3">
            {t.mercado.topPerdedorAcciones}
          </h2>
          <div className="grid md:grid-cols-3 gap-4">
            {topPerdedoresAcciones.map((activo) => (
              <TarjetaActivo
                key={`loser-${activo.simbolo}`}
                simbolo={activo.simbolo}
                precio={activo.precio}
                cambioPorc={activo.cambioPorc}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
