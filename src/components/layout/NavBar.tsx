"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "@/components/ui/Logo";
import { ThemeToggle } from "@/components/ui/ThemeToggle";
import { LanguageToggle } from "@/components/ui/LanguageToggle";
import {
  IconoInicio,
  IconoMercado,
  IconoSenales,
  IconoComunidad,
  IconoReto,
  IconoPerfil,
  IconoInfo,
} from "@/components/ui/Iconos";
import type { SesionUsuario } from "@/lib/auth/sesion";
import type { Diccionario, Locale } from "@/lib/i18n";

export function NavBar({
  usuario,
  locale,
  t,
}: {
  usuario: SesionUsuario | null;
  locale: Locale;
  t: Diccionario;
}) {
  const pathname = usePathname();

  const ENLACES = [
    { href: "/", label: t.nav.inicio, Icono: IconoInicio },
    { href: "/mercado", label: t.nav.mercado, Icono: IconoMercado },
    { href: "/senales", label: t.nav.senales, Icono: IconoSenales },
    { href: "/comunidad", label: t.nav.comunidad, Icono: IconoComunidad },
    { href: "/trade-del-dia", label: t.nav.tradeDelDia, Icono: IconoReto },
    { href: "/nosotros", label: t.nav.nosotros, Icono: IconoInfo },
  ];

  return (
    <header className="max-w-[1080px] mx-auto w-full px-4 sm:px-6 py-6 flex items-center justify-between">
      <Link href="/" className="shrink-0">
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
              <Icono className="w-[18px] h-[18px]" />
              {label}
            </Link>
          );
        })}
      </nav>

      <div className="flex items-center gap-1.5 sm:gap-3 shrink-0">
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
            className="inline-flex items-center px-2.5 md:px-4 py-2 rounded-xl text-[13px] md:text-sm font-semibold bg-brand-primary text-white hover:bg-brand-primary-hover transition-colors whitespace-nowrap"
          >
            {t.nav.iniciarSesion}
          </Link>
        )}
        <LanguageToggle locale={locale} />
        <ThemeToggle />
      </div>
    </header>
  );
}
