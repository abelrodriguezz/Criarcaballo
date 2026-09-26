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
  IconoCampana,
} from "@/components/ui/Iconos";
import type { SesionUsuario } from "@/lib/auth/sesion";
import type { Diccionario, Locale } from "@/lib/i18n";

export function NavBar({
  usuario,
  locale,
  t,
  mensajesSinLeer = 0,
}: {
  usuario: SesionUsuario | null;
  locale: Locale;
  t: Diccionario;
  mensajesSinLeer?: number;
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
    <header className="fixed top-3 inset-x-3 sm:inset-x-4 z-30 max-w-[1080px] mx-auto bg-surface/90 backdrop-blur-md border border-[var(--border)] rounded-2xl shadow-[0_8px_24px_rgba(0,0,0,0.25)] px-3 sm:px-6 py-3 sm:py-4 flex items-center justify-between gap-2">
      <Link href="/" className="shrink-0">
        <Logo />
      </Link>

      {/* Entre md (768) y xl (1280) no caben las 6 etiquetas + campana,
          perfil, idioma y tema: el header (fixed, ancho del viewport)
          cortaba Perfil/ES-EN/tema fuera de la pantalla, sin forma de
          llegar a ellos (la barra de abajo solo existe por debajo de md).
          En ese rango se muestran solo los íconos. */}
      <nav className="hidden md:flex items-center gap-1 min-w-0">
        {ENLACES.map(({ href, label, Icono }) => {
          const activo = pathname === href;
          return (
            <Link
              key={href}
              href={href}
              aria-label={label}
              title={label}
              className={`flex items-center gap-1.5 px-2.5 xl:px-3.5 py-2 rounded-xl text-sm font-semibold whitespace-nowrap transition-colors ${
                activo
                  ? "bg-brand-primary/10 text-brand-primary"
                  : "text-foreground-muted hover:text-foreground hover:bg-surface-hover"
              }`}
            >
              <Icono className="w-[18px] h-[18px] shrink-0" />
              <span className="hidden xl:inline">{label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="flex items-center gap-2 sm:gap-3 shrink-0">
        {usuario ? (
          <>
            <Link
              href="/soporte"
              aria-label="Mensajes de soporte"
              className="hidden md:flex relative items-center justify-center w-9 h-9 rounded-full border border-[var(--border)] text-foreground-muted hover:text-foreground hover:bg-surface-hover transition-colors"
            >
              <IconoCampana />
              {mensajesSinLeer > 0 && (
                <span className="absolute -top-1 -right-1 min-w-[16px] h-4 px-1 flex items-center justify-center bg-brand-secondary text-white text-[10px] font-bold rounded-full">
                  {mensajesSinLeer > 9 ? "9+" : mensajesSinLeer}
                </span>
              )}
            </Link>
            <Link
              href="/perfil"
              aria-label="Perfil"
              className={`hidden md:flex items-center justify-center w-9 h-9 rounded-full border transition-colors ${
                pathname === "/perfil"
                  ? "border-brand-primary/40 bg-brand-primary/15 text-brand-primary"
                  : "border-[var(--border)] text-foreground-muted hover:text-foreground hover:bg-surface-hover"
              }`}
            >
              <IconoPerfil />
            </Link>
          </>
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
