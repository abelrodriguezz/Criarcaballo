import { BotonFavorito } from "@/components/mercado/BotonFavorito";
import { SparklineChart } from "@/components/mercado/SparklineChart";
import { formatearPrecio, urlGraficoTradingView } from "@/lib/format";

/** "BTCUSDT" -> "BTC", "SPX" -> "SPX" — para la insignia circular. */
function simboloCorto(simbolo: string): string {
  return simbolo.replace(/USDT$|USD$/, "").slice(0, 4);
}

/**
 * Tarjeta de precio para /mercado — deliberadamente distinta a las tarjetas
 * de señales: sin borde de color ni franja superior, en vez de eso un
 * degradado sutil en la esquina + mini-gráfico de tendencia real (cuando
 * hay datos de sparkline) para que se sienta como un tablero de mercado,
 * no como una ficha de señal.
 */
export function TarjetaActivo({
  simbolo,
  precio,
  cambioPorc,
  etiqueta,
  mostrarFavorito,
  esFavoritoInicial,
  sparkline,
}: {
  simbolo: string;
  precio: number;
  cambioPorc: number;
  etiqueta?: string;
  mostrarFavorito?: boolean;
  esFavoritoInicial?: boolean;
  sparkline?: number[];
}) {
  const subiendo = cambioPorc >= 0;
  const colorGlow = subiendo ? "var(--gain)" : "var(--loss)";

  return (
    <div
      className="relative rounded-2xl border border-[var(--border)] p-4.5 overflow-hidden transition-transform hover:-translate-y-0.5 hover:shadow-lg"
      style={{
        background: `radial-gradient(130% 100% at 100% 0%, color-mix(in srgb, ${colorGlow} 12%, var(--surface)) 0%, var(--surface) 55%)`,
      }}
    >
      <a
        href={urlGraficoTradingView(simbolo)}
        target="_blank"
        rel="noopener noreferrer"
        className="absolute inset-0 rounded-2xl"
        aria-label={`Ver gráfico de ${simbolo} en TradingView`}
      />

      <div className="relative z-10 flex items-start justify-between gap-2 mb-3">
        <div className="flex items-center gap-2.5 min-w-0">
          <div
            className="w-9 h-9 rounded-full flex items-center justify-center text-[10px] font-display font-bold shrink-0 text-white"
            style={{ background: colorGlow }}
          >
            {simboloCorto(simbolo)}
          </div>
          <div className="min-w-0">
            <div className="font-semibold text-sm flex items-center gap-1.5">
              {mostrarFavorito && (
                <span className="relative z-10">
                  <BotonFavorito
                    activo={simbolo}
                    esFavoritoInicial={!!esFavoritoInicial}
                  />
                </span>
              )}
              <span className="truncate">{simbolo}</span>
            </div>
            {etiqueta && (
              <span className="text-[10px] font-bold uppercase tracking-wide text-foreground-muted">
                {etiqueta}
              </span>
            )}
          </div>
        </div>

        <span
          className={`shrink-0 flex items-center gap-0.5 text-[11px] font-bold px-2 py-1 rounded-full ${
            subiendo ? "bg-gain/15 text-gain" : "bg-loss/15 text-loss"
          }`}
        >
          {subiendo ? "▲" : "▼"}
          {subiendo ? "+" : ""}
          {cambioPorc.toFixed(2)}%
        </span>
      </div>

      <div className="relative z-10 font-display font-bold text-[22px] tabular mb-1">
        ${formatearPrecio(precio)}
      </div>

      {sparkline && sparkline.length > 1 && (
        <div className="relative z-10 -mx-1.5 -mb-1.5">
          <SparklineChart data={sparkline} subiendo={subiendo} />
        </div>
      )}
    </div>
  );
}
