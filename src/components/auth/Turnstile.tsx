"use client";

import { useEffect, useRef, useId, useState } from "react";
import Script from "next/script";

declare global {
  interface Window {
    turnstile?: {
      render: (
        container: string | HTMLElement,
        options: {
          sitekey: string;
          callback: (token: string) => void;
          "expired-callback"?: () => void;
          "error-callback"?: () => void;
          theme?: "light" | "dark" | "auto";
        }
      ) => string;
      reset: (widgetId?: string) => void;
      remove: (widgetId?: string) => void;
    };
  }
}

export function Turnstile({
  onVerify,
  onExpire,
}: {
  onVerify: (token: string) => void;
  onExpire?: () => void;
}) {
  const contenedorId = useId().replace(/:/g, "");
  const widgetIdRef = useRef<string | null>(null);
  const [noCargo, setNoCargo] = useState(false);

  const siteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

  useEffect(() => {
    if (!siteKey) return;

    function renderizar() {
      if (!window.turnstile || widgetIdRef.current) return;
      setNoCargo(false);
      widgetIdRef.current = window.turnstile.render(`#${contenedorId}`, {
        sitekey: siteKey!,
        callback: onVerify,
        "expired-callback": onExpire,
        theme: "auto",
      });
    }

    // El script puede ya estar cargado (navegación entre login/registro).
    if (window.turnstile) {
      renderizar();
    } else {
      window.addEventListener("turnstile-listo", renderizar);
    }

    // Si un bloqueador de anuncios/rastreadores impide que el script de
    // Cloudflare cargue, el widget nunca aparece y el formulario queda
    // inutilizable sin explicación — a los 8s avisamos qué pasó.
    const timeoutSinCargar = setTimeout(() => {
      if (!widgetIdRef.current) setNoCargo(true);
    }, 8000);

    return () => {
      window.removeEventListener("turnstile-listo", renderizar);
      clearTimeout(timeoutSinCargar);
      if (widgetIdRef.current && window.turnstile) {
        window.turnstile.remove(widgetIdRef.current);
        widgetIdRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [siteKey, contenedorId]);

  if (!siteKey) {
    // El aviso de configuración es para quien desarrolla/despliega, NO
    // para el visitante: en producción, un usuario que entra a iniciar
    // sesión veía un recuadro hablándole de una variable de entorno. Sin
    // site key simplemente no se muestra captcha (login y registro siguen
    // funcionando; ver la nota en LoginForm.tsx).
    if (process.env.NODE_ENV === "production") return null;

    return (
      <p className="text-[12px] text-foreground-muted border border-dashed border-[var(--border)] rounded-lg px-3 py-2">
        Falta configurar <code>NEXT_PUBLIC_TURNSTILE_SITE_KEY</code> para
        mostrar el captcha (aviso visible solo en desarrollo).
      </p>
    );
  }

  return (
    <>
      {/* challenges.cloudflare.com, en plural: el host en singular no es
          el de Turnstile y además no está en la CSP (next.config.ts), así
          que en producción el script no cargaba nunca, el widget no
          aparecía y el botón de enviar quedaba deshabilitado para
          siempre — login y registro inutilizables en cuanto se
          configurara la site key. */}
      <Script
        src="https://challenges.cloudflare.com/turnstile/v0/api.js"
        strategy="afterInteractive"
        onLoad={() =>
          window.dispatchEvent(new Event("turnstile-listo"))
        }
      />
      <div id={contenedorId} />
      {noCargo && (
        <p className="text-[12px] text-loss mt-1.5">
          No se pudo cargar la verificación. Si usas un bloqueador de
          anuncios o de rastreadores, desactívalo para este sitio y recarga
          la página.
        </p>
      )}
    </>
  );
}
