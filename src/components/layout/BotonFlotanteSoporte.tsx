import Link from "next/link";
import { IconoSoporte } from "@/components/ui/Iconos";

interface BotonFlotanteSoporteProps {
  logueado: boolean;
  label: string;
}

const CLASES_BASE =
  "fixed z-30 right-4 md:right-6 bottom-[calc(5.75rem+env(safe-area-inset-bottom))] md:bottom-6 flex items-center justify-center w-12 h-12 rounded-full shadow-[0_8px_20px_rgba(0,0,0,0.35)] transition-colors";

// A pedido del dueño del proyecto: el ícono se ve en TODAS las páginas,
// pero solo lleva al chat de soporte si hay sesión iniciada. Un visitante
// sin cuenta lo ve igual (para que sepa que existe soporte), pero tocarlo
// no hace nada -- a propósito, no se le manda a /login.
export function BotonFlotanteSoporte({ logueado, label }: BotonFlotanteSoporteProps) {
  if (!logueado) {
    return (
      <button
        type="button"
        disabled
        aria-label={label}
        className={`${CLASES_BASE} bg-surface border border-[var(--border)] text-foreground-muted opacity-70 cursor-default`}
      >
        <IconoSoporte className="w-5 h-5" />
      </button>
    );
  }

  return (
    <Link
      href="/soporte"
      aria-label={label}
      className={`${CLASES_BASE} bg-brand-primary hover:bg-brand-primary-hover text-white`}
    >
      <IconoSoporte className="w-5 h-5" />
    </Link>
  );
}
