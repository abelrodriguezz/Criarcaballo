"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "@/components/ui/Logo";
import { ThemeToggle } from "@/components/ui/ThemeToggle";
import {
  IconoMercado,
  IconoSenales,
  IconoComunidad,
  IconoReto,
  IconoPerfil,
} from "@/components/ui/Iconos";
import type { SesionUsuario } from "@/lib/auth/sesion";

const ENLACES = [
  { href: "/mercado", label: "Mercado", Icono: IconoMercado },
  { href: "/senales", label: "Señales", Icono: IconoSenales },
  { href: "/comunidad", label: "Comunidad", Icono: IconoComunidad },
  { href: "/trade-del-dia", label: "Trade del día", Icono: IconoReto },
];

export function NavBar({ usuario }: { usuario: SesionUsuario | null }) {
  const pathname = usePathname();

  return (
    <header className="max-w-[1080px] mx-auto w-full px-6 py-6 flex items-center justify-between">
      <Link href="/">
        <Logo />
      </Link>

      <nav className="hidden md:flex items-center gap-1.5 bg-surface rounded-2xl p-1.5">
        {ENLACES.map(({ href, label, Icono }) => {
          const activo = pathname === href;
          return (
            <Link
              key={href}
              href={href}
              className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${
                activo
                  ? "bg-background text-brand-primary shadow-[0_1px_0_var(--border)]"
                  : "text-foreground-muted hover:text-foreground"
              }`}
            >
              <Icono />
              {label}
            </Link>
          );
        })}
      </nav>

      <div className="flex items-center gap-3">
        {usuario ? (
          <Link
            href="/perfil"
            aria-label="Perfil"
            className={`hidden md:flex items-center justify-center w-9 h-9 rounded-full transition-colors ${
              pathname === "/perfil"
                ? "bg-brand-primary/15 text-brand-primary"
                : "bg-surface text-foreground-muted hover:text-foreground"
            }`}
          >
            <IconoPerfil />
          </Link>
        ) : (
          // En móvil este botón estaba oculto (hidden md:inline-flex) y la
          // MobileTabBar no tiene entrada de login: quien llegaba a la
          // portada desde un teléfono sin sesión no veía ninguna forma
          // obvia de entrar (había que tocar "Perfil" y esperar el
          // redirect). Se muestra siempre, más compacto en pantalla chica.
          <Link
            href="/login"
            className="inline-flex items-center px-3 md:px-4 py-2 rounded-xl text-[13px] md:text-sm font-semibold bg-brand-primary text-white hover:bg-brand-primary-hover transition-colors whitespace-nowrap"
          >
            Iniciar sesión
          </Link>
        )}
        <ThemeToggle />
      </div>
    </header>
  );
}
