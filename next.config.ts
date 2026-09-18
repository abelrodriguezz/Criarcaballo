import type { NextConfig } from "next";

// Next.js carga las variables de .env.local antes de evaluar este archivo,
// así que esto sí ve la URL real de Supabase en build/arranque.
const supabaseOrigin = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").replace(
  /\/$/,
  ""
);
const supabaseWsOrigin = supabaseOrigin.replace(/^http/, "ws");

// CSP deliberadamente permisiva en scripts/estilos: el script inline de
// detección de tema oscuro (layout.tsx) y el widget de Cloudflare Turnstile
// necesitan 'unsafe-inline' / el origen de Cloudflare. Aun así bloquea
// carga de recursos de orígenes arbitrarios, que es el riesgo principal.
const csp = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' https://challenges.cloudflare.com",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self' data:",
  `connect-src 'self' https://api.binance.com https://api.twelvedata.com ${supabaseOrigin} ${supabaseWsOrigin}`,
  "frame-src https://challenges.cloudflare.com",
  "frame-ancestors 'self'",
]
  .filter(Boolean)
  .join("; ");

const nextConfig: NextConfig = {
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Frame-Options", value: "SAMEORIGIN" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          {
            key: "Referrer-Policy",
            value: "strict-origin-when-cross-origin",
          },
          {
            key: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()",
          },
          { key: "Content-Security-Policy", value: csp },
        ],
      },
    ];
  },
};

export default nextConfig;
