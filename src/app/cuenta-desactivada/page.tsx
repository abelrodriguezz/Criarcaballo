import { CerrarSesionBoton } from "@/components/auth/CerrarSesionBoton";

export default function PaginaCuentaDesactivada() {
  return (
    <div className="py-16">
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          Cuenta desactivada
        </h1>
        <p className="text-sm text-foreground-muted mb-5">
          Tu cuenta fue desactivada. Si crees que esto es un error, contacta
          al equipo de soporte.
        </p>
        <CerrarSesionBoton />
      </div>
    </div>
  );
}
