interface LogoProps {
  className?: string;
  mostrarWordmark?: boolean;
}

// Marca: barras ascendentes que se funden en una flecha — "entrar al mercado".
export function Logo({ className = "", mostrarWordmark = true }: LogoProps) {
  return (
    <div className={`flex items-center gap-2.5 ${className}`}>
      <svg
        width="32"
        height="32"
        viewBox="0 0 32 32"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden="true"
      >
        <rect x="3" y="20" width="5" height="9" rx="1.5" fill="var(--brand-primary)" />
        <rect x="10.5" y="14" width="5" height="15" rx="1.5" fill="var(--brand-primary)" />
        <rect x="18" y="8" width="5" height="21" rx="1.5" fill="var(--brand-secondary)" />
        <path
          d="M18 9L27 3M27 3H21M27 3V9"
          stroke="var(--brand-secondary)"
          strokeWidth="2.4"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
      {mostrarWordmark && (
        // Oculto por debajo de 380px: en un iPhone SE (320px) la fila del
        // header (logo + botón de login/perfil + selector de idioma + tema)
        // no cabe con el wordmark completo y desborda la página entera. El
        // ícono solo sigue siendo un link a "/" igual de reconocible.
        <span className="hidden min-[380px]:inline font-display font-bold text-xl tracking-tight">
          Trade<span style={{ color: "var(--brand-primary)" }}>4U</span>
        </span>
      )}
    </div>
  );
}
