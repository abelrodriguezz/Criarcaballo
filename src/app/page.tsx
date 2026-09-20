import Link from "next/link";
import { IconoMercado, IconoSenales, IconoReto } from "@/components/ui/Iconos";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { obtenerConfigPortada } from "@/lib/config-portada";
import { AdminPortadaForm } from "@/components/admin/AdminPortadaForm";
import { obtenerPrecioIndice } from "@/lib/market/yahoo";
import { obtenerNoticiasExternas } from "@/lib/noticias/feedExterno";
import { formatearPrecio } from "@/lib/format";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { TickerNoticias, type ItemTicker } from "@/components/ui/TickerNoticias";
import { SparklineChart } from "@/components/mercado/SparklineChart";
import type { Noticia } from "@/lib/types";

export default async function PaginaInicio() {
  const supabase = await crearClienteSupabaseServidor();
  const [usuario, { hero }, sp500, { data: noticiasPropias }, noticiasExternas] =
    await Promise.all([
      obtenerUsuarioActual(),
      obtenerConfigPortada(),
      obtenerPrecioIndice("^GSPC"),
      supabase
        .from("noticias")
        .select("*")
        .order("destacada", { ascending: false })
        .order("created_at", { ascending: false })
        .limit(6)
        .returns<Noticia[]>(),
      obtenerNoticiasExternas(4),
    ]);
  const usuarioEsAdmin = esAdmin(usuario);

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

  return (
    <div className="pt-10 pb-20">
      {usuarioEsAdmin && <AdminPortadaForm heroActual={hero} />}

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
              Crear cuenta gratis
            </Link>
            <Link
              href="/trade-del-dia"
              className="border-2 border-brand-primary text-brand-primary bg-brand-primary/10 font-semibold text-[15px] px-6 py-3.5 rounded-xl hover:bg-brand-primary/20 transition-colors text-center"
            >
              Trade del día
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
                  {sp500.cambioPorc.toFixed(2)}% hoy
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
                  Índices en vivo próximamente.
                </p>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="mt-8">
        <TickerNoticias items={itemsTicker} />
      </div>

      <div className="bg-foreground text-background dark:bg-surface dark:text-foreground rounded-3xl p-6 sm:p-10 md:p-12 mt-16 grid md:grid-cols-3 gap-8">
        <div>
          <div className="w-10 h-10 rounded-[4px] bg-brand-secondary flex items-center justify-center text-white mb-4">
            <IconoMercado />
          </div>
          <h3 className="font-display font-semibold text-lg mb-2">
            Datos reales, no decorativos
          </h3>
          <p className="text-sm opacity-70 leading-relaxed">
            Precios de cripto, índices y acciones en tiempo real, directo de
            la fuente.
          </p>
        </div>
        <div>
          <div className="w-10 h-10 rounded-[4px] bg-brand-secondary flex items-center justify-center text-white mb-4">
            <IconoSenales />
          </div>
          <h3 className="font-display font-semibold text-lg mb-2">
            Análisis publicado a diario
          </h3>
          <p className="text-sm opacity-70 leading-relaxed">
            Entradas, stop loss y take profit explicados, no solo números
            sueltos.
          </p>
        </div>
        <div>
          <div className="w-10 h-10 rounded-[4px] bg-brand-secondary flex items-center justify-center text-white mb-4">
            <IconoReto />
          </div>
          <h3 className="font-display font-semibold text-lg mb-2">
            Práctica con saldo virtual
          </h3>
          <p className="text-sm opacity-70 leading-relaxed">
            Opera el &quot;pick del día&quot; sin dinero real y mide tu
            progreso con el tiempo.
          </p>
        </div>
      </div>
    </div>
  );
}
