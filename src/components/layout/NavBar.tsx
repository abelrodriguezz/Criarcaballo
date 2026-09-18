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
} from "@/components/ui/Iconos";

const ENLACES = [
  { href: "/mercado", label: "Mercado", Icono: IconoMercado },
  { href: "/senales", label: "Señales", Icono: IconoSenales },
  { href: "/comunidad", label: "Comunidad", Icono: IconoComunidad },
  { href: "/reto-del-dia", label: "Reto del día", Icono: IconoReto },
];

export function NavBar() {
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

      <ThemeToggle />
    </header>
  );
}
