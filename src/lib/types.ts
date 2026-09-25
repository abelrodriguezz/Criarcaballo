// Tipos que reflejan las tablas de supabase/migrations/001_esquema_inicial.sql

export type RolUsuario = "user" | "admin";

export interface Usuario {
  id: string;
  email: string;
  role: RolUsuario;
  activo: boolean;
  codigo_invitacion: string | null;
  invitado_por: string | null;
  wallet_usdt_erc20: string | null;
  id_corto: number | null;
  trading_habilitado: boolean;
  created_at: string;
  nombre: string | null;
  telefono: string | null;
  es_principal: boolean;
}

export interface Senal {
  id: string;
  par: string;
  tipo: "compra" | "venta";
  entrada: number;
  stop_loss: number | null;
  take_profit: number | null;
  razon: string | null;
  razon_en: string | null;
  estado: "activa" | "cerrada" | "cancelada";
  resultado: "tp" | "sl" | null;
  precio_cierre: number | null;
  porcentaje_resultado: number | null;
  cerrado_en: string | null;
  creado_por: string | null;
  created_at: string;
}

export interface Noticia {
  id: string;
  titulo: string;
  titulo_en: string | null;
  resumen: string | null;
  resumen_en: string | null;
  url_fuente: string | null;
  destacada: boolean;
  created_at: string;
}

export interface SaldoVirtual {
  usuario_id: string;
  saldo_usd: number;
  actualizado_en: string;
}

export interface OperacionSimulada {
  id: string;
  usuario_id: string;
  activo: string;
  tipo: "compra" | "venta";
  precio_entrada: number;
  cantidad: number;
  monto_usado: number;
  precio_salida: number | null;
  ganancia_perdida: number | null;
  estado: "abierta" | "cerrada";
  created_at: string;
  cerrado_en: string | null;
}

export interface PickDelDia {
  id: string;
  activo: string;
  fecha: string;
  nota_admin: string | null;
  created_at: string;
}

export interface GananciaConcurso {
  id: string;
  usuario_id: string;
  monto: number;
  concepto: string | null;
  creado_por: string | null;
  created_at: string;
  pagado: boolean;
  pagado_en: string | null;
  pagado_por: string | null;
  origen: "concurso" | "trade" | "referido";
  operacion_id: string | null;
  invitado_id: string | null;
}

export interface DepositoSimulado {
  id: string;
  usuario_id: string;
  monto: number;
  wallet_mostrada: string | null;
  created_at: string;
}

export interface SolicitudRetiro {
  id: string;
  usuario_id: string;
  monto: number;
  wallet_destino: string;
  estado: "pendiente" | "pagado" | "rechazado";
  nota_admin: string | null;
  created_at: string;
  procesado_en: string | null;
  procesado_por: string | null;
}

export interface MensajeSoporte {
  id: string;
  usuario_id: string;
  remitente_id: string;
  contenido: string;
  leido_admin: boolean;
  leido_usuario: boolean;
  created_at: string;
}
