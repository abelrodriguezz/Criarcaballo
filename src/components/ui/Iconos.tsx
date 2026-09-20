interface IconoProps {
  className?: string;
}

const baseProps = {
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

export function IconoMercado({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <rect x="3" y="12" width="4" height="8" rx="1" />
      <rect x="10" y="7" width="4" height="13" rx="1" />
      <rect x="17" y="3" width="4" height="17" rx="1" />
    </svg>
  );
}

export function IconoSenales({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <path d="M8.5 8.5a5 5 0 0 0 0 7" />
      <path d="M15.5 8.5a5 5 0 0 1 0 7" />
      <path d="M5 5a9 9 0 0 0 0 14" />
      <path d="M19 5a9 9 0 0 1 0 14" />
      <circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function IconoComunidad({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <circle cx="9" cy="8" r="3" />
      <circle cx="17" cy="9" r="2.6" />
      <path d="M3.5 20c0-3 2.5-5.5 5.5-5.5s5.5 2.5 5.5 5.5" />
      <path d="M15 15c2.4.3 4.5 2.3 4.5 5" />
    </svg>
  );
}

export function IconoReto({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <circle cx="12" cy="12" r="8.5" />
      <circle cx="12" cy="12" r="4.5" />
      <circle cx="12" cy="12" r="1" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function IconoTendenciaSubida({ className = "w-4 h-4" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <polyline points="3 17 9 11 13 15 21 6" />
      <polyline points="14 6 21 6 21 13" />
    </svg>
  );
}

export function IconoEstrella({ className = "w-4 h-4" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <polygon points="12 2.5 15.1 8.9 22 9.9 17 14.8 18.2 21.7 12 18.4 5.8 21.7 7 14.8 2 9.9 8.9 8.9 12 2.5" />
    </svg>
  );
}

export function IconoPerfil({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <circle cx="12" cy="8" r="3.5" />
      <path d="M4.5 20c0-4.2 3.4-6.5 7.5-6.5s7.5 2.3 7.5 6.5" />
    </svg>
  );
}

export function IconoWallet({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <rect x="2.5" y="6" width="19" height="13" rx="2.5" />
      <path d="M2.5 9.5h19" />
      <circle cx="16.5" cy="14" r="1.2" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function IconoUsuarios({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <circle cx="9" cy="8" r="3" />
      <path d="M3.5 20c0-3.3 2.5-6 5.5-6s5.5 2.7 5.5 6" />
      <path d="M16 5.2c1.4.4 2.4 1.7 2.4 3.2 0 1.5-1 2.8-2.4 3.2" />
      <path d="M18 14.3c2 .6 3.4 2.5 3.4 4.7" />
    </svg>
  );
}

export function IconoSoporte({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <path d="M4 12a8 8 0 1 1 3.2 6.4L4 19l1.1-3.4A7.96 7.96 0 0 1 4 12Z" />
      <line x1="8.5" y1="11" x2="15.5" y2="11" />
      <line x1="8.5" y1="14" x2="13" y2="14" />
    </svg>
  );
}

export function IconoReportes({ className = "w-[18px] h-[18px]" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <path d="M6 2.5h9l4.5 4.5V21a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3.5a1 1 0 0 1 1-1Z" />
      <path d="M15 2.5V7h4.5" />
      <line x1="8" y1="12.5" x2="16" y2="12.5" />
      <line x1="8" y1="16" x2="16" y2="16" />
      <line x1="8" y1="9" x2="11" y2="9" />
    </svg>
  );
}

export function IconoInfo({ className = "w-3.5 h-3.5" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <circle cx="12" cy="12" r="9" />
      <line x1="12" y1="11" x2="12" y2="16" />
      <line x1="12" y1="8" x2="12" y2="8.01" />
    </svg>
  );
}
