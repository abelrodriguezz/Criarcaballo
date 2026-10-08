import { IconoMercado } from "@/components/ui/Iconos";
import { TarjetaActivo } from "@/components/mercado/TarjetaActivo";
import { AdminTextosModuloForm } from "@/components/admin/AdminTextosModuloForm";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import {
  obtenerVariosPreciosCripto,
  obtenerTopGanadoresCripto,
  obtenerVariosSparklinesCripto,
} from "@/lib/market/mexc";
import {
  obtenerTopGanadoresAcciones,
  obtenerTopPerdedoresAcciones,
} from "@/lib/market/acciones";
import {
  claveConfigTextosModulo,
  obtenerTextosModulo,
  obtenerTextosModuloCompleto,
} from "@/lib/config-textos-modulo";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";

const CLAVE_TEXTOS = claveConfigTextosModulo("mercado");
const TEXTOS_POR_DEFECTO = {
  titulo: "Vista de mercado",
  subtitulo:
    "Precios en tiempo real de cripto y acciones tokenizadas. Toca cualquier tarjeta para ver el gráfico en TradingView.",
};
const TEXTOS_POR_DEFECTO_EN = {
  titulo: "Market view",
  subtitulo:
    "Real-time prices for crypto and tokenized stocks. Tap any card to see the chart on TradingView.",
};

const PARES_CRIPTO = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "HBARUSDT"];

// Acciones tokenizadas reales (xStock — respaldadas 1:1 por la acción de
// verdad, no monedas meme) listadas en MEXC con la misma API que la
// cripto. Reemplaza a los índices (S&P 500/Nasdaq/Dow) que antes salían
// de Twelve Data: esa key nunca se configuró, y de todas formas un índice
// no existe como acción individual tokenizable.
const ACCIONES_TOKENIZADAS = [
  { simbolo: "AAPLXUSDT", nombre: "AAPL" },
  { simbolo: "TSLAXUSDT", nombre: "TSLA" },
  { simbolo: "NVDAXUSDT", nombre: "NVDA" },
  { simbolo: "GOOGLXUSDT", nombre: "GOOGL" },
  { simbolo: "METAXUSDT", nombre: "META" },
  { simbolo: "AMZNXUSDT", nombre: "AMZN" },
  { simbolo: "COINXUSDT", nombre: "COIN" },
];

export const revalidate = 30; // refresca los precios cada 30s como máximo

interface ActivoNormalizado {
  simbolo: string;
  precio: number;
  cambioPorc: number;
  tipo: "Cripto" | "Acción";
}

export default async function PaginaMercado() {
  const [usuario, t, locale] = await Promise.all([
    obtenerUsuarioActual(),
    obtenerDiccionario(),
    obtenerLocale(),
  ]);
  const usuarioEsAdmin = esAdmin(usuario);

  const [
    cripto,
    accionesTokenizadas,
    topCripto,
    topAcciones,
    topPerdedoresAcciones,
    textos,
    textosCompleto,
  ] = await Promise.all([
    obtenerVariosPreciosCripto(PARES_CRIPTO),
    obtenerVariosPreciosCripto(ACCIONES_TOKENIZADAS.map((a) => a.simbolo)),
    obtenerTopGanadoresCripto(5),
    obtenerTopGanadoresAcciones(5),
    obtenerTopPerdedoresAcciones(5),
    obtenerTextosModulo(CLAVE_TEXTOS, TEXTOS_POR_DEFECTO, TEXTOS_POR_DEFECTO_EN, locale),
    usuarioEsAdmin
      ? obtenerTextosModuloCompleto(CLAVE_TEXTOS, TEXTOS_POR_DEFECTO, TEXTOS_POR_DEFECTO_EN)
      : Promise.resolve(null),
  ]);
  const nombrePorSimbolo = new Map(
    ACCIONES_TOKENIZADAS.map((a) => [a.simbolo, a.nombre])
  );

  const sinDatos = cripto.length === 0 && accionesTokenizadas.length === 0;

  // Top ganadores del día mezclando cripto y acciones (no solo un tipo),
  // ordenado de mayor a menor subida.
  // El top de cripto sale de un listado cacheado hasta 30s; si el mismo par
  // está también en la sección "Cripto" (precio recién pedido), se usa ese
  // valor para que la misma moneda no muestre dos precios distintos en la
  // misma pantalla.
  const criptoFresco = new Map(cripto.map((c) => [c.simbolo, c]));
  const topGanadores: ActivoNormalizado[] = [
    ...topCripto.map((c) => {
      const fresco = criptoFresco.get(c.simbolo) ?? c;
      return {
        simbolo: c.simbolo,
        precio: fresco.precio,
        cambioPorc: fresco.cambioPorc24h,
        tipo: "Cripto" as const,
      };
    }),
    ...topAcciones.map((a) => ({
      simbolo: a.simbolo,
      precio: a.precio,
      cambioPorc: a.cambioPorc,
      tipo: "Acción" as const,
    })),
  ]
    .sort((a, b) => b.cambioPorc - a.cambioPorc)
    .slice(0, 6);

  // Mini-gráficos de tendencia: cripto Y acciones tokenizadas, las dos son
  // la misma API de MEXC (gratis e ilimitada) — antes esto solo alcanzaba
  // para cripto porque las acciones salían de Twelve Data (cuota extra).
  const simbolosParaSparkline = [
    ...new Set([
      ...cripto.map((c) => c.simbolo),
      ...accionesTokenizadas.map((a) => a.simbolo),
      ...topGanadores.filter((a) => a.tipo === "Cripto").map((a) => a.simbolo),
    ]),
  ];
  const sparklines = await obtenerVariosSparklinesCripto(simbolosParaSparkline);

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] flex items-center gap-2.5 mb-1.5">
        <IconoMercado className="w-6 h-6 text-brand-primary" />
        {textos.titulo}
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        {textos.subtitulo}
      </p>

      {usuarioEsAdmin && textosCompleto && (
        <AdminTextosModuloForm
          claveConfig={CLAVE_TEXTOS}
          textosActuales={textosCompleto}
          ta={t.admin}
        />
      )}

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
                sparkline={sparklines[activo.simbolo]}
              />
            ))}
          </div>
        </>
      )}

      {accionesTokenizadas.length > 0 && (
        <>
          <h2 className="text-[13px] font-semibold text-foreground-muted uppercase tracking-wide mb-1">
            {t.mercado.accionesTokenizadas}
          </h2>
          <p className="text-[12px] text-foreground-muted mb-3">
            {t.mercado.accionesTokenizadasAviso}
          </p>
          <div className="grid md:grid-cols-3 gap-4 mb-8">
            {accionesTokenizadas.map((activo) => (
              <TarjetaActivo
                key={activo.simbolo}
                simbolo={activo.simbolo}
                nombreMostrado={nombrePorSimbolo.get(activo.simbolo)}
                precio={activo.precio}
                cambioPorc={activo.cambioPorc24h}
                sparkline={sparklines[activo.simbolo]}
              />
            ))}
          </div>
        </>
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
