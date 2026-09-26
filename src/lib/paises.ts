// Lista curada de países con su código de marcación, para el selector de
// teléfono en el registro. Latinoamérica primero (audiencia principal de
// la app), luego el resto en orden alfabético. No es exhaustiva a
// propósito — cubre los países donde es razonable esperar usuarios.
export interface Pais {
  nombre: string;
  bandera: string;
  dial: string;
}

export const PAISES: Pais[] = [
  { nombre: "República Dominicana", bandera: "🇩🇴", dial: "+1" },
  { nombre: "México", bandera: "🇲🇽", dial: "+52" },
  { nombre: "Colombia", bandera: "🇨🇴", dial: "+57" },
  { nombre: "Venezuela", bandera: "🇻🇪", dial: "+58" },
  { nombre: "Argentina", bandera: "🇦🇷", dial: "+54" },
  { nombre: "Chile", bandera: "🇨🇱", dial: "+56" },
  { nombre: "Perú", bandera: "🇵🇪", dial: "+51" },
  { nombre: "Ecuador", bandera: "🇪🇨", dial: "+593" },
  { nombre: "Bolivia", bandera: "🇧🇴", dial: "+591" },
  { nombre: "Paraguay", bandera: "🇵🇾", dial: "+595" },
  { nombre: "Uruguay", bandera: "🇺🇾", dial: "+598" },
  { nombre: "Panamá", bandera: "🇵🇦", dial: "+507" },
  { nombre: "Costa Rica", bandera: "🇨🇷", dial: "+506" },
  { nombre: "Guatemala", bandera: "🇬🇹", dial: "+502" },
  { nombre: "Honduras", bandera: "🇭🇳", dial: "+504" },
  { nombre: "El Salvador", bandera: "🇸🇻", dial: "+503" },
  { nombre: "Nicaragua", bandera: "🇳🇮", dial: "+505" },
  { nombre: "Cuba", bandera: "🇨🇺", dial: "+53" },
  { nombre: "Puerto Rico", bandera: "🇵🇷", dial: "+1" },
  { nombre: "Estados Unidos", bandera: "🇺🇸", dial: "+1" },
  { nombre: "Canadá", bandera: "🇨🇦", dial: "+1" },
  { nombre: "España", bandera: "🇪🇸", dial: "+34" },
  { nombre: "Brasil", bandera: "🇧🇷", dial: "+55" },
  { nombre: "Portugal", bandera: "🇵🇹", dial: "+351" },
  { nombre: "Francia", bandera: "🇫🇷", dial: "+33" },
  { nombre: "Alemania", bandera: "🇩🇪", dial: "+49" },
  { nombre: "Italia", bandera: "🇮🇹", dial: "+39" },
  { nombre: "Reino Unido", bandera: "🇬🇧", dial: "+44" },
  { nombre: "China", bandera: "🇨🇳", dial: "+86" },
  { nombre: "India", bandera: "🇮🇳", dial: "+91" },
  { nombre: "Otro", bandera: "🌐", dial: "+" },
];

export const PAIS_POR_DEFECTO = PAISES[0];
