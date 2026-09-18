"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  IconoMercado,
  IconoSenales,
  IconoComunidad,
  IconoReto,
  IconoPerfil,
} from "@/components/ui/Iconos";

const ENLACES = [
  { href: "/mercado", label: "Mercado", Icono: IconoMercado },
  { href: "/senales", label: "Señales", Icono: IconoSenales },
  { href: "/comunidad", label: "Comunidad", Icono: IconoComunidad },
  { href: "/reto-del-dia", label: "Reto", Icono: IconoReto },
  { href: "/perfil", label: "Perfil", Icono: IconoPerfil },
];

/**
 * En pantallas md+ la navegación vive en NavBar (arriba). Por debajo de md,
 * NavBar oculta esos enlaces, así que esta barra inferior es la única forma
 * de moverse entre módulos en mobile — sin ella, la app queda sin navegación
 * utilizable en un teléfono.
 */
export function MobileTabBar() {
  const pathname = usePathname();

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
