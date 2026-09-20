import type { NextConfig } from "next";

// Next.js carga las variables de .env.local antes de evaluar este archivo,
// así que esto sí ve la URL real de Supabase en build/arranque.
const supabaseOrigin = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").replace(
  /\/$/,
  ""
);
const supabaseWsOrigin = supabaseOrigin.replace(/^http/, "ws");

// En dev, Next/React usan eval() para Fast Refresh y para reconstruir
// stack traces (nunca en producción) — sin 'unsafe-eval' ahí, Turbopack
// rompe con "eval() is not supported" apenas abres cualquier página.
const esDev = process.env.NODE_ENV !== "production";

// CSP deliberadamente permisiva en scripts/estilos: el script inline de
// detección de tema oscuro (layout.tsx) y el widget de Cloudflare Turnstile
// necesitan 'unsafe-inline' / el origen de Cloudflare. Aun así bloquea
// carga de recursos de orígenes arbitrarios, que es el riesgo principal.
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline' ${esDev ? "'unsafe-eval' " : ""}https://challenges.cloudflare.com`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self' data:",
  // challenges.cloudflare.com también en connect-src: el widget de
  // Turnstile hace sus propias peticiones a ese origen, y sin esto el
  // captcha no llega a resolverse cuando la site key está configurada.
  `connect-src 'self' https://api.binance.com https://api.twelvedata.com https://challenges.cloudflare.com ${supabaseOrigin} ${supabaseWsOrigin}`,
  "frame-src https://challenges.cloudflare.com",
  "frame-ancestors 'self'",
  // Con 'unsafe-inline' en script-src, una inyección de HTML que consiga
  // colar un <base href="//evil.com"> reapunta TODOS los scripts de ruta
  // relativa de la página. base-uri es lo único que lo frena y no tiene
  // contrapartida: esta app nunca usa <base>.
  "base-uri 'self'",
  // No hay <object>/<embed>/<applet> en el proyecto; cerrarlos elimina una
  // vía clásica de ejecución que default-src no cubre en navegadores viejos.
  "object-src 'none'",
  // Impide que un formulario inyectado envíe credenciales a un tercero.
  "form-action 'self'",
  // Solo en producción: en dev el servidor es http://localhost y no hace
  // falta (los navegadores tratan localhost como origen seguro igual).
  esDev ? null : "upgrade-insecure-requests",
]
  .filter(Boolean)
  .join("; ");

const nextConfig: NextConfig = {
  // No anunciar "X-Powered-By: Next.js" en cada respuesta: no aporta nada
  // al usuario y le regala a quien escanee el sitio la pila exacta que
  // está corriendo.
  poweredByHeader: false,

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
