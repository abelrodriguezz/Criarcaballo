import type { Metadata } from "next";
import Script from "next/script";
import { Inter, Space_Grotesk, JetBrains_Mono } from "next/font/google";
import "./globals.css";
import { NavBar } from "@/components/layout/NavBar";
import { MobileTabBar } from "@/components/layout/MobileTabBar";
import { Footer } from "@/components/layout/Footer";
import { BotonFlotanteSoporte } from "@/components/layout/BotonFlotanteSoporte";
import { ContadorSoporteProvider } from "@/components/layout/ContadorSoporte";
import { BarridoTransition } from "@/components/layout/BarridoTransition";
import { CierreInactividad } from "@/components/auth/CierreInactividad";
import { esAdmin, obtenerUsuarioActual } from "@/lib/auth/sesion";
import { crearClienteSupabaseServidor } from "@/lib/supabase/server";
import { obtenerLocale, obtenerDiccionario } from "@/lib/i18n/servidor";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
  weight: ["500", "700"],
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
  weight: ["500", "600"],
});

// Título/descripción según el idioma elegido (cookie), igual que el resto
// de la interfaz — antes quedaban fijos en español aun con la app en inglés.
export async function generateMetadata(): Promise<Metadata> {
  const t = await obtenerDiccionario();
  return { title: t.home.metaTitulo, description: t.home.metaDescripcion };
}

// Se ejecuta antes de que React hidrate y antes del primer pintado, para
// que la página no "parpadee" en claro un instante cuando el usuario
// prefiere el modo oscuro (clásico problema de FOUC en dark mode).
const SCRIPT_TEMA_INICIAL = `
(function () {
  try {
    var guardado = localStorage.getItem('trade4u-theme');
    // Claro por defecto (pedido del dueño del proyecto, 2026-10-01) salvo
    // que la persona ya haya elegido oscuro explícitamente antes.
    var oscuro = guardado ? guardado === 'dark' : false;
    document.documentElement.setAttribute('data-theme', oscuro ? 'dark' : 'light');
  } catch (e) {}
})();
`;

export default async function RootLayout({ children }: LayoutProps<"/">) {
  const [usuario, locale, t] = await Promise.all([
    obtenerUsuarioActual(),
    obtenerLocale(),
    obtenerDiccionario(),
  ]);

  // Contador de mensajes de soporte sin leer, para la campanita del nav —
  // mismo query que ya usaba /perfil para el badge de "Bandeja de soporte".
  // Es solo el valor inicial: ContadorSoporteProvider lo vuelve a consultar
  // en cada cambio de ruta, porque este layout raíz no se re-renderiza en
  // una navegación suave y el número quedaba congelado.
  let mensajesSinLeer = 0;
  if (usuario) {
    const supabase = await crearClienteSupabaseServidor();
    const { count } = esAdmin(usuario)
      ? await supabase
          .from("mensajes_soporte")
          .select("id", { count: "exact", head: true })
          .eq("leido_admin", false)
      : await supabase
          .from("mensajes_soporte")
          .select("id", { count: "exact", head: true })
          .eq("usuario_id", usuario.id)
          .eq("leido_usuario", false);
    mensajesSinLeer = count ?? 0;
  }

  return (
    <html
      lang={locale}
      className={`${inter.variable} ${spaceGrotesk.variable} ${jetbrainsMono.variable} h-full antialiased`}
      suppressHydrationWarning
    >
      <head>
        <Script id="tema-inicial" strategy="beforeInteractive">
          {SCRIPT_TEMA_INICIAL}
        </Script>
      </head>
      <body className="min-h-full flex flex-col bg-background text-foreground overflow-x-hidden">
        {usuario && <CierreInactividad />}
        <ContadorSoporteProvider
          inicial={mensajesSinLeer}
          usuarioId={usuario?.id ?? null}
          esAdmin={esAdmin(usuario)}
        >
          <NavBar usuario={usuario} locale={locale} t={t} />
          {/* NavBar es fixed/flotante (ya no ocupa espacio en el flujo normal),
              así que este padding-top es lo que evita que el contenido quede
              tapado debajo — mismo motivo que el pb-24 de abajo para la
              barra flotante de mobile. */}
          <main className="flex-1 max-w-[1080px] mx-auto w-full px-6 pt-24 sm:pt-28 pb-24 md:pb-16">
            <BarridoTransition>{children}</BarridoTransition>
          </main>
          <Footer />
          <BotonFlotanteSoporte logueado={!!usuario} label={t.perfil.contactarSoporte} />
          <MobileTabBar t={t} />
        </ContadorSoporteProvider>
      </body>
    </html>
  );
}
