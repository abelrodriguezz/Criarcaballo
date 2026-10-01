// Pie de página global — vive en el layout raíz, así que aparece en todas
// las páginas sin que cada una lo repita. pb-24 en mobile para que la barra
// flotante inferior (fixed, MobileTabBar) no tape el texto al hacer scroll
// hasta el final.
export function Footer() {
  return (
    <footer className="border-t border-[var(--border)] py-6 px-6 text-center text-[12px] text-foreground-muted pb-24 md:pb-6">
      © {new Date().getFullYear()} Trade4U. All rights reserved.
    </footer>
  );
}
