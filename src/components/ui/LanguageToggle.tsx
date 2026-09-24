"use client";

import { useRouter } from "next/navigation";
import { COOKIE_IDIOMA, type Locale } from "@/lib/i18n";

export function LanguageToggle({ locale }: { locale: Locale }) {
  const router = useRouter();

  function cambiar(nuevo: Locale) {
    if (nuevo === locale) return;
    // Un año de duración, igual de simple que el toggle de tema — el
    // servidor la lee en la siguiente petición, por eso el refresh().
    document.cookie = `${COOKIE_IDIOMA}=${nuevo}; path=/; max-age=31536000`;
    router.refresh();
  }

  return (
    <div className="flex items-center border border-[var(--border)] p-0.5 text-[11px] font-bold">
      <button
        onClick={() => cambiar("es")}
        aria-label="Español"
        className={`px-1.5 sm:px-2 py-1 transition-colors ${
          locale === "es"
            ? "bg-brand-primary text-white"
            : "text-foreground-muted hover:text-foreground"
        }`}
      >
        ES
      </button>
      <button
        onClick={() => cambiar("en")}
        aria-label="English"
        className={`px-1.5 sm:px-2 py-1 transition-colors ${
          locale === "en"
            ? "bg-brand-primary text-white"
            : "text-foreground-muted hover:text-foreground"
        }`}
      >
        EN
      </button>
    </div>
  );
}
