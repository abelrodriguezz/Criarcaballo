import { RestablecerForm } from "@/components/auth/RestablecerForm";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";

export default async function PaginaRestablecerContrasena() {
  const [t, locale] = await Promise.all([obtenerDiccionario(), obtenerLocale()]);
  return (
    <div className="py-16">
      <RestablecerForm t={t} locale={locale} />
    </div>
  );
}
