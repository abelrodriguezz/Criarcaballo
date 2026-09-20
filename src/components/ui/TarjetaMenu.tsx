import Link from "next/link";
import type { ReactNode } from "react";

/**
 * Tarjeta tipo "botón de menú" — icono + título/subtítulo + flecha — para
 * distinguir visualmente los accesos de navegación (Wallet, Gestión de
 * usuarios, Soporte, Reportes) de las tarjetas de solo-datos (Ganancias,
 * Favoritos, Saldo).
 */
export function TarjetaMenu({
  href,
  icono,
  titulo,
  subtitulo,
  badge,
}: {
  href: string;
  icono: ReactNode;
  titulo: string;
  subtitulo: string;
  badge?: number;
}) {
  return (
    <Link
      href={href}
      className="border border-[var(--border)] rounded-2xl p-4 mb-3 flex items-center gap-3.5 hover:bg-surface-hover hover:border-brand-primary/40 transition-colors"
    >
      <div className="shrink-0 w-10 h-10 rounded-[4px] bg-brand-primary/10 text-brand-primary flex items-center justify-center">
        {icono}
      </div>
      <div className="min-w-0 flex-1">
        <div className="font-medium text-sm">{titulo}</div>
        <div className="text-[13px] text-foreground-muted truncate">
          {subtitulo}
        </div>
      </div>
      {!!badge && (
        <span className="shrink-0 bg-brand-secondary text-white text-xs font-bold px-2.5 py-1 rounded-full">
          {badge}
        </span>
      )}
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
        className="w-4 h-4 shrink-0 text-foreground-muted"
      >
        <polyline points="9 18 15 12 9 6" />
      </svg>
    </Link>
  );
}
