import { RecuperarForm } from "@/components/auth/RecuperarForm";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";

export default async function PaginaRecuperarContrasena() {
  const [t, locale] = await Promise.all([obtenerDiccionario(), obtenerLocale()]);
  return (
    <div className="py-16">
      <RecuperarForm t={t} locale={locale} />
    </div>
  );
}
