"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
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
export function MobileTabBar({ t }: { t: Diccionario }) {
  const pathname = usePathname();

  const ENLACES = [
    { href: "/mercado", label: t.nav.mercado, Icono: IconoMercado },
    { href: "/senales", label: t.nav.senales, Icono: IconoSenales },
    { href: "/comunidad", label: t.nav.comunidad, Icono: IconoComunidad },
    { href: "/trade-del-dia", label: t.nav.tradeCorto, Icono: IconoReto },
    { href: "/perfil", label: t.nav.perfil, Icono: IconoPerfil },
    { href: "/nosotros", label: t.nav.nosotros, Icono: IconoInfo },
  ];

  return (
    <nav className="md:hidden fixed bottom-0 left-0 right-0 z-20 bg-background border-t border-[var(--border)] flex items-stretch py-1.5 pb-[calc(0.375rem+env(safe-area-inset-bottom))]">
      {ENLACES.map(({ href, label, Icono }) => {
        const activo = pathname === href;
        return (
          <Link
            key={href}
            href={href}
            className={`flex-1 min-w-0 flex flex-col items-center gap-0.5 px-1 py-1 text-[10px] font-medium ${
              activo ? "text-brand-primary" : "text-foreground-muted"
            }`}
          >
            <Icono className="w-5 h-5 shrink-0" />
            <span className="truncate max-w-full">{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
