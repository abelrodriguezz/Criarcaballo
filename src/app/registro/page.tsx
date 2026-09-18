import { Suspense } from "react";
import { RegistroForm } from "@/components/auth/RegistroForm";

export default function PaginaRegistro() {
  return (
    <div className="py-16">
      <Suspense fallback={null}>
        <RegistroForm />
      </Suspense>
    </div>
  );
}
