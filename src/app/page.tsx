import Link from "next/link";
import { IconoMercado, IconoSenales, IconoReto } from "@/components/ui/Iconos";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { obtenerConfigPortada } from "@/lib/config-portada";
import { AdminPortadaForm } from "@/components/admin/AdminPortadaForm";

export default async function PaginaInicio() {
  const [usuario, { hero, estadisticas }] = await Promise.all([
    obtenerUsuarioActual(),
    obtenerConfigPortada(),
  ]);
  const usuarioEsAdmin = esAdmin(usuario);

  return (
    <div className="pt-10 pb-20">
      {usuarioEsAdmin && (
        <AdminPortadaForm heroActual={hero} estadisticasActuales={estadisticas} />
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
              Crear cuenta gratis
            </Link>
            <Link
              href="/senales"
              className="border border-[var(--border)] font-semibold text-[15px] px-6 py-3.5 rounded-xl hover:bg-surface-hover transition-colors text-center"
            >
              Ver señales de hoy
            </Link>
          </div>
          <div className="flex flex-wrap gap-x-7 gap-y-3">
            {estadisticas.map((stat, i) => (
              <div key={i}>
                <div className="font-display font-bold text-2xl">
                  {stat.num}
                </div>
                <div className="text-[13px] text-foreground-muted">
                  {stat.label}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="relative">
          <div className="bg-surface border border-[var(--border)] rounded-[20px] p-6 relative">
            <div className="absolute -top-3.5 right-6 bg-gain text-white text-xs font-bold px-3.5 py-1.5 rounded-full">
              ▲ +2.4% hoy
            </div>
            <div className="mb-4">
              <div className="font-display font-semibold text-[15px]">
                BTC / USDT
              </div>
              <div className="font-display font-bold text-[28px] tabular">
                $62,410
              </div>
            </div>
            <svg viewBox="0 0 320 120" className="w-full h-[120px]">
              <polyline
                points="0,90 30,95 60,70 90,80 120,55 150,60 180,35 210,45 240,20 270,30 300,10 320,15"
                fill="none"
                stroke="var(--gain)"
                strokeWidth="3"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </div>
        </div>
      </div>

      <div className="bg-foreground text-background dark:bg-surface rounded-3xl p-6 sm:p-10 md:p-12 mt-16 grid md:grid-cols-3 gap-8">
        <div>
          <div className="w-10 h-10 rounded-[10px] bg-brand-secondary flex items-center justify-center text-white mb-4">
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
          <div className="w-10 h-10 rounded-[10px] bg-brand-secondary flex items-center justify-center text-white mb-4">
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
          <div className="w-10 h-10 rounded-[10px] bg-brand-secondary flex items-center justify-center text-white mb-4">
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
