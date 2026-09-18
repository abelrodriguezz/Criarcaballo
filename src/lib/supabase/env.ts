// Falla claro y de inmediato si faltan las variables de Supabase, en vez de
// dejar que createBrowserClient/createServerClient reciban `undefined` y
// fallen más tarde, a mitad de una request, con un error críptico.

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    "Faltan NEXT_PUBLIC_SUPABASE_URL y/o NEXT_PUBLIC_SUPABASE_ANON_KEY. " +
      "Copia .env.local.example como .env.local y complétalo con los datos " +
      "de tu proyecto de Supabase (Project Settings → API)."
  );
}

export const SUPABASE_URL = url;
export const SUPABASE_ANON_KEY = anonKey;
