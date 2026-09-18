import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "@/lib/supabase/env";

// Refresca el token de sesión de Supabase en cada request (patrón oficial
// de @supabase/ssr, adaptado a la convención "proxy" de Next.js 16 — el
// antiguo middleware.ts fue renombrado). Sin esto, la sesión solo se
// renueva en las rutas que de casualidad llaman a Supabase desde el
// servidor, así que un usuario podía quedar deslogueado de forma
// inconsistente tras un rato de inactividad en vez de mantenerse activo
// mientras navega.
export async function proxy(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) =>
          request.cookies.set(name, value)
        );
        supabaseResponse = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          supabaseResponse.cookies.set(name, value, options)
        );
      },
    },
  });

  // No agregar lógica entre createServerClient() y esta llamada — es lo
  // que efectivamente refresca el token si hace falta.
  await supabase.auth.getUser();

  return supabaseResponse;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
