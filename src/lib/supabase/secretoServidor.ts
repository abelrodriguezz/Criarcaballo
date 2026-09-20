/**
 * Secreto compartido entre este servidor y las funciones SECURITY DEFINER
 * de Postgres que mueven dinero (`abrir_operacion`) o cierran señales
 * automáticamente (`cerrar_senal_automatica`). Ver la migración 019.
 *
 * Por qué existe: el navegador tiene la anon key de Supabase (viaja en el
 * bundle, es pública por diseño), así que cualquier usuario logueado puede
 * llamar un RPC directo desde la consola, saltándose los server actions de
 * Next.js. Eso hacía inútil que el server action consultara el precio real
 * en Binance: bastaba con llamar `abrir_operacion` a mano con el precio de
 * entrada que uno quisiera. Este valor solo existe en el entorno del
 * servidor (sin prefijo NEXT_PUBLIC_), así que es lo único que la base de
 * datos puede usar para distinguir "me llamó la app" de "me llamó alguien
 * con la anon key".
 *
 * IMPORTANTE: este módulo solo se puede importar desde Server Components o
 * Server Actions. Si se importara desde un componente "use client", el
 * valor llegaría vacío (Next.js solo inyecta en el bundle las variables
 * con prefijo NEXT_PUBLIC_) y esto lanzaría — que es el comportamiento
 * deseado: fallar ruidosamente en vez de filtrar el secreto.
 */
export function obtenerSecretoServidor(): string {
  const secreto = process.env.TRADING_SERVER_SECRET;

  if (!secreto) {
    throw new Error(
      "Falta la variable de entorno TRADING_SERVER_SECRET. Es obligatoria " +
        "para abrir operaciones y para el cierre automático de señales. " +
        "Ver .env.local.example y la migración 019."
    );
  }

  return secreto;
}
