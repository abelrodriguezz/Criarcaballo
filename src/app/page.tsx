import Link from "next/link";
import { IconoTendenciaSubida } from "@/components/ui/Iconos";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { obtenerConfigPortada, obtenerConfigPortadaCompleta } from "@/lib/config-portada";
import { AdminPortadaForm } from "@/components/admin/AdminPortadaForm";
import { obtenerPrecioIndice } from "@/lib/market/yahoo";
import { obtenerNoticiasExternas } from "@/lib/noticias/feedExterno";
import { formatearPrecio } from "@/lib/format";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { TickerNoticias, type ItemTicker } from "@/components/ui/TickerNoticias";
import { SparklineChart } from "@/components/mercado/SparklineChart";
import { urlSeguraParaEnlace } from "@/lib/url";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";
import type { Noticia } from "@/lib/types";

export default async function PaginaInicio() {
  const supabase = await crearClienteSupabaseServidor();
  const [usuario, locale, sp500, { data: noticiasPropias }, noticiasExternas, t] =
    await Promise.all([
      obtenerUsuarioActual(),
      obtenerLocale(),
      obtenerPrecioIndice("^GSPC"),
      supabase
        .from("noticias")
        .select("*")
        .order("destacada", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(6)
        .returns<Noticia[]>(),
      obtenerNoticiasExternas(4),
      obtenerDiccionario(),
    ]);
  const usuarioEsAdmin = esAdmin(usuario);
  const [{ hero }, heroCompleto] = await Promise.all([
    obtenerConfigPortada(locale),
    usuarioEsAdmin ? obtenerConfigPortadaCompleta() : Promise.resolve(null),
  ]);

  // Primero lo que tú publicaste (con estrella si está destacada), luego
  // titulares reales de Cointelegraph/MarketWatch para que el ticker
  // nunca se vea vacío mientras todavía no publicas las tuyas.
  const itemsTicker: ItemTicker[] = [
    ...(noticiasPropias ?? []).map((n) => ({
      id: n.id,
      titulo: n.titulo,
      url: n.url_fuente || "/noticias",
      destacada: n.destacada,
    })),
    ...noticiasExternas.map((n, i) => ({
      id: `ext-${i}`,
      titulo: `${n.titulo} — ${n.fuente}`,
      url: n.url,
      externo: true,
    })),
  ];

  // Noticias importantes en forma de card (Cointelegraph = cripto,
  // MarketWatch = stocks) — solo externas, así la etiqueta Cripto/Stocks
  // siempre es correcta (las propias del admin no traen esa distinción).
  const noticiasCards = noticiasExternas
    .slice(0, 6)
    .map((n) => ({
      titulo: n.titulo,
      fuente: n.fuente,
      esCripto: n.fuente === "Cointelegraph",
      url: urlSeguraParaEnlace(n.url),
    }))
    .filter((n): n is typeof n & { url: string } => n.url !== null);

  return (
    <div className="pt-10 pb-20">
      {usuarioEsAdmin && heroCompleto && (
        <AdminPortadaForm heroActual={heroCompleto} />
      )}

      <div className="grid md:grid-cols-2 gap-10 md:gap-12 items-center">
        <div>
          <div className="inline-flex items-center gap-2 bg-[var(--brand-primary-tint)] text-brand-primary text-[13px] font-semibold px-3.5 py-1.5 rounded-full mb-5">
            {hero.badge}
          </div>
          <h1 className="font-display font-bold text-[32px] sm:text-[40px] md:text-[52px] leading-[1.12] md:leading-[1.08] tracking-tight mb-4">
            {hero.titulo_linea1}
            <br />
            {hero.titulo_linea2}
          </h1>
          <p className="text-foreground-muted text-[15px] sm:text-[17px] leading-relaxed max-w-[460px] mb-8">
            {hero.subtitulo}
          </p>
          <div className="flex flex-col sm:flex-row gap-3 mb-9">
            <Link
              href="/registro"
              className="bg-brand-primary hover:bg-brand-primary-hover text-white font-semibold text-[15px] px-6 py-3.5 rounded-xl transition-colors text-center"
            >
              {t.home.ctaCrearCuenta}
            </Link>
            <Link
              href="/trade-del-dia"
              className="border-2 border-brand-primary text-brand-primary bg-brand-primary/10 font-semibold text-[15px] px-6 py-3.5 rounded-xl hover:bg-brand-primary/20 transition-colors text-center"
            >
              {t.home.ctaTradeDelDia}
            </Link>
          </div>
        </div>

        <div className="relative">
          <div className="bg-surface border border-[var(--border)] rounded-[6px] p-6 relative min-h-[212px] flex flex-col">
            {sp500 ? (
              <>
                <div
                  className={`absolute -top-3.5 right-6 text-white text-xs font-bold px-3.5 py-1.5 rounded-full ${
                    sp500.cambioPorc >= 0 ? "bg-gain" : "bg-loss"
                  }`}
                >
                  {sp500.cambioPorc >= 0 ? "▲" : "▼"}{" "}
                  {sp500.cambioPorc >= 0 ? "+" : ""}
                  {sp500.cambioPorc.toFixed(2)}% {t.home.hoy}
                </div>
                <div className="font-display font-semibold text-[15px]">
                  S&P 500
                </div>
                <div className="font-display font-bold text-[28px] tabular mb-4">
                  {formatearPrecio(sp500.precio)}
                </div>
                {sp500.sparkline.length > 1 && (
                  <div className="flex-1 min-h-[100px]">
                    <SparklineChart
                      data={sp500.sparkline}
                      subiendo={sp500.cambioPorc >= 0}
                    />
                  </div>
                )}
              </>
            ) : (
              <div className="flex-1 flex flex-col items-center justify-center text-center gap-1.5">
                <div className="font-display font-semibold text-[15px] text-foreground-muted">
                  S&P 500
                </div>
                <p className="text-[13px] text-foreground-muted max-w-[220px]">
                  {t.home.sp500Proximamente}
                </p>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="mt-8">
        <TickerNoticias items={itemsTicker} etiqueta={t.home.noticiasEtiqueta} />
      </div>

      {noticiasCards.length > 0 && (
        <div className="mt-16">
          <h2 className="font-display font-semibold text-2xl mb-1.5">
            {t.home.noticiasImportantesTitulo}
          </h2>
          <p className="text-foreground-muted text-[15px] mb-6">
            {t.home.noticiasImportantesSub}
          </p>
          <div className="grid md:grid-cols-3 gap-4">
            {noticiasCards.map((n, i) => {
              const colorAcento = n.esCripto
                ? "var(--brand-secondary)"
                : "var(--brand-primary)";
              return (
                <a
                  key={`${n.url}-${i}`}
                  href={n.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group relative border-l-4 bg-surface p-5 overflow-hidden flex flex-col gap-3 transition-transform hover:-translate-y-0.5"
                  style={{
                    borderColor: colorAcento,
                    background: `radial-gradient(120% 100% at 100% 0%, color-mix(in srgb, ${colorAcento} 10%, var(--surface)) 0%, var(--surface) 60%)`,
                  }}
                >
                  <div className="flex items-center justify-between">
                    <div
                      className="w-9 h-9 rounded-[4px] flex items-center justify-center text-white shrink-0"
                      style={{ background: colorAcento }}
                    >
                      <IconoTendenciaSubida className="w-4 h-4" />
                    </div>
                    <span
                      className={`text-[10px] font-bold uppercase tracking-wide px-2 py-0.5 ${
                        n.esCripto
                          ? "bg-brand-secondary/15 text-brand-secondary"
                          : "bg-brand-primary/15 text-brand-primary"
                      }`}
                    >
                      {n.esCripto
                        ? t.home.noticiasCriptoEtiqueta
                        : t.home.noticiasStocksEtiqueta}
                    </span>
                  </div>
                  <p className="text-[15px] font-semibold leading-snug group-hover:text-brand-primary transition-colors">
                    {n.titulo}
                  </p>
                  <div className="flex items-center justify-between mt-auto pt-1">
                    <span className="text-[12px] text-foreground-muted">
                      {n.fuente}
                    </span>
                    <span className="text-sm font-bold text-brand-primary opacity-0 -translate-x-1 group-hover:opacity-100 group-hover:translate-x-0 transition-all">
                      →
                    </span>
                  </div>
                </a>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
