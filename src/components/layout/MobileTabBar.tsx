"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  IconoInicio,
  IconoMercado,
  IconoSenales,
  IconoComunidad,
  IconoReto,
  IconoPerfil,
  IconoInfo,
} from "@/components/ui/Iconos";
import type { Diccionario } from "@/lib/i18n";

/**
 * En pantallas md+ la navegación vive en NavBar (arriba). Por debajo de md,
 * NavBar oculta esos enlaces, así que esta barra inferior es la única forma
 * de moverse entre módulos en mobile — sin ella, la app queda sin navegación
 * utilizable en un teléfono.
 */
export function MobileTabBar({
  t,
  mensajesSinLeer = 0,
}: {
  t: Diccionario;
  mensajesSinLeer?: number;
}) {
  const pathname = usePathname();

  const ENLACES = [
    { href: "/", label: t.nav.inicio, Icono: IconoInicio },
    { href: "/mercado", label: t.nav.mercado, Icono: IconoMercado },
    { href: "/senales", label: t.nav.senales, Icono: IconoSenales },
    { href: "/comunidad", label: t.nav.comunidadCorta, Icono: IconoComunidad },
    { href: "/trade-del-dia", label: t.nav.tradeCorto, Icono: IconoReto },
    { href: "/perfil", label: t.nav.perfil, Icono: IconoPerfil },
    { href: "/nosotros", label: t.nav.nosotrosCorto, Icono: IconoInfo },
  ];

  return (
    <nav
      className="md:hidden fixed left-3 right-3 z-20 bg-surface/90 backdrop-blur-md border border-[var(--border)] rounded-2xl shadow-[0_8px_24px_rgba(0,0,0,0.35)] flex items-stretch py-1.5"
      style={{ bottom: "calc(0.75rem + env(safe-area-inset-bottom))" }}
    >
      {ENLACES.map(({ href, label, Icono }) => {
        const activo = pathname === href;
        return (
          <Link
            key={href}
            href={href}
            className={`relative flex-1 min-w-0 flex flex-col items-center gap-0.5 px-0.5 py-1 rounded-xl text-[10px] font-medium transition-colors ${
              activo ? "text-brand-primary bg-brand-primary/10" : "text-foreground-muted"
            }`}
          >
            <span className="relative">
              <Icono className="w-5 h-5 shrink-0" />
              {href === "/perfil" && mensajesSinLeer > 0 && (
                <span className="absolute -top-1 -right-1.5 w-2.5 h-2.5 rounded-full bg-brand-secondary border-2 border-[var(--surface)]" />
              )}
            </span>
            <span className="truncate max-w-full">{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
