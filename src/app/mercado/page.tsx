import { IconoMercado } from "@/components/ui/Iconos";
import { BotonFavorito } from "@/components/mercado/BotonFavorito";
import { obtenerVariosPreciosCripto } from "@/lib/market/binance";
import { obtenerVariosPreciosAcciones } from "@/lib/market/acciones";
import { obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { formatearPrecio } from "@/lib/format";

const PARES_CRIPTO = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "HBARUSDT"];
const SIMBOLOS_INDICES = ["SPX", "IXIC", "DJI"];

export const revalidate = 30; // refresca los precios cada 30s como máximo

export default async function PaginaMercado() {
  const usuario = await obtenerUsuarioActual();

  const [cripto, indices, favoritos] = await Promise.all([
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
  ]);

  const setFavoritos = new Set(
    (favoritos.data ?? []).map((f) => f.activo as string)
  );

  const sinDatos = cripto.length === 0 && indices.length === 0;

  return (
    <div className="py-10">
      <h1 className="font-display font-semibold text-[26px] flex items-center gap-2.5 mb-1.5">
        <IconoMercado className="w-6 h-6 text-brand-primary" />
        Vista de mercado
      </h1>
      <p className="text-foreground-muted text-[15px] mb-7">
        Precios en tiempo real de cripto, índices y acciones.
      </p>

      {sinDatos && (
        <p className="text-foreground-muted text-sm border border-dashed border-[var(--border)] rounded-2xl p-6 text-center mb-6">
          No se pudieron cargar los precios en este momento. Si estás
          probando en local, revisa tu conexión a internet.
        </p>
      )}

      {cripto.length > 0 && (
        <>
          <h2 className="text-[13px] font-semibold text-foreground-muted uppercase tracking-wide mb-3">
            Cripto
          </h2>
          <div className="grid md:grid-cols-3 gap-4 mb-8">
            {cripto.map((activo) => {
              const subiendo = activo.cambioPorc24h >= 0;
              return (
                <div
                  key={activo.simbolo}
                  className="border border-[var(--border)] rounded-2xl p-4.5"
                >
                  <div className="flex justify-between mb-2.5">
                    <span className="font-semibold text-sm flex items-center gap-1.5">
                      {usuario && (
                        <BotonFavorito
                          activo={activo.simbolo}
                          esFavoritoInicial={setFavoritos.has(activo.simbolo)}
                        />
                      )}
                      {activo.simbolo}
                    </span>
                    <span
                      className={`text-sm font-semibold ${
                        subiendo ? "text-gain" : "text-loss"
                      }`}
                    >
                      {subiendo ? "+" : ""}
                      {activo.cambioPorc24h.toFixed(2)}%
                    </span>
                  </div>
                  <div className="font-display font-bold text-[19px] tabular">
                    ${formatearPrecio(activo.precio)}
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}

      {indices.length > 0 ? (
        <>
          <h2 className="text-[13px] font-semibold text-foreground-muted uppercase tracking-wide mb-3">
            Índices
          </h2>
          <div className="grid md:grid-cols-3 gap-4">
            {indices.map((activo) => {
              const subiendo = activo.cambioPorc >= 0;
              return (
                <div
                  key={activo.simbolo}
                  className="border border-[var(--border)] rounded-2xl p-4.5"
                >
                  <div className="flex justify-between mb-2.5">
                    <span className="font-semibold text-sm">
                      {activo.simbolo}
                    </span>
                    <span
                      className={`text-sm font-semibold ${
                        subiendo ? "text-gain" : "text-loss"
                      }`}
                    >
                      {subiendo ? "+" : ""}
                      {activo.cambioPorc.toFixed(2)}%
                    </span>
                  </div>
                  <div className="font-display font-bold text-[19px] tabular">
                    {activo.precio.toLocaleString("en-US", {
                      minimumFractionDigits: 2,
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </>
      ) : (
        <p className="text-xs text-foreground-muted mt-2">
          {process.env.MARKET_API_KEY
            ? "No se pudieron cargar los índices en este momento (verifica tu plan de Twelve Data o los símbolos usados)."
            : (
              <>
                Índices y acciones: falta configurar <code>MARKET_API_KEY</code> en{" "}
                <code>.env.local</code> con una key de Twelve Data (plan
                gratuito en twelvedata.com).
              </>
            )}
        </p>
      )}
    </div>
  );
}
