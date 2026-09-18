import type { Metadata } from "next";
import Script from "next/script";
import { Inter, Space_Grotesk } from "next/font/google";
import "./globals.css";
import { NavBar } from "@/components/layout/NavBar";
import { MobileTabBar } from "@/components/layout/MobileTabBar";
import { BarridoTransition } from "@/components/layout/BarridoTransition";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
  weight: ["500", "700"],
});

export const metadata: Metadata = {
  title: "TradeIN — Mercado, señales y práctica de trading",
  description:
    "Datos de mercado en tiempo real, análisis y un modo de práctica sin riesgo.",
};

// Se ejecuta antes de que React hidrate y antes del primer pintado, para
// que la página no "parpadee" en claro un instante cuando el usuario
// prefiere el modo oscuro (clásico problema de FOUC en dark mode).
const SCRIPT_TEMA_INICIAL = `
(function () {
  try {
    var guardado = localStorage.getItem('tradein-theme');
    var oscuro = guardado
      ? guardado === 'dark'
      : window.matchMedia('(prefers-color-scheme: dark)').matches;
    document.documentElement.setAttribute('data-theme', oscuro ? 'dark' : 'light');
  } catch (e) {}
})();
`;

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="es"
      className={`${inter.variable} ${spaceGrotesk.variable} h-full antialiased`}
    >
      <head>
        <Script id="tema-inicial" strategy="beforeInteractive">
          {SCRIPT_TEMA_INICIAL}
        </Script>
      </head>
      <body className="min-h-full flex flex-col bg-background text-foreground overflow-x-hidden">
        <NavBar />
        <main className="flex-1 max-w-[1080px] mx-auto w-full px-6 pb-24 md:pb-16">
          <BarridoTransition>{children}</BarridoTransition>
        </main>
        <MobileTabBar />
      </body>
    </html>
  );
}
