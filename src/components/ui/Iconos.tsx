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

export function IconoInfo({ className = "w-3.5 h-3.5" }: IconoProps) {
  return (
    <svg {...baseProps} className={className}>
      <circle cx="12" cy="12" r="9" />
      <line x1="12" y1="11" x2="12" y2="16" />
      <line x1="12" y1="8" x2="12" y2="8.01" />
    </svg>
  );
}
