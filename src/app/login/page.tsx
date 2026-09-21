import { LoginForm } from "@/components/auth/LoginForm";
import { obtenerDiccionario, obtenerLocale } from "@/lib/i18n/servidor";

export default async function PaginaLogin() {
  const [t, locale] = await Promise.all([obtenerDiccionario(), obtenerLocale()]);
  return (
    <div className="py-16">
      <LoginForm t={t} locale={locale} />
    </div>
  );
}
