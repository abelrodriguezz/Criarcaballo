# Trade4U

Plataforma de señales de trading, práctica con saldo simulado ("Trade del
día"), comunidad y soporte. Next.js 16 (App Router + Turbopack) sobre
Supabase (Postgres + Auth + Row Level Security).

## Qué incluye

| Módulo | Ruta | Resumen |
| --- | --- | --- |
| Portada | `/` | Hero editable por el admin, tarjeta del S&P 500 (Yahoo Finance) y cinta de noticias (RSS de Cointelegraph y MarketWatch + las noticias propias). |
| Mercado | `/mercado` | Precios en vivo de cripto (Binance, sin API key), índices/acciones (Twelve Data, opcional), mini-gráficos y favoritos. Cada tarjeta enlaza al gráfico en TradingView. |
| Señales | `/senales` | Señales publicadas por el admin con entrada, stop loss, take profit y razón. Se cierran solas cuando las velas de Binance tocan TP o SL. |
| Trade del día | `/trade-del-dia` | El admin define el "pick" y los usuarios abren una operación con saldo simulado, solo en horario de la bolsa de Nueva York. La sesión la liquida el admin en bloque con un precio de salida manual. |
| Comunidad | `/comunidad` | Enlace y código de invitación de cada usuario. |
| Soporte | `/soporte` | Chat en tiempo real usuario ↔ admin, con bandeja por orden de llegada. |
| Admin | `/usuarios`, `/usuarios/reportes` | Roles, activar/desactivar cuentas, bloquear trading, ajustar saldo, registrar y marcar como pagadas las ganancias de concursos, y reportes diarios exportables a CSV. |

## Puesta en marcha

### 1. Requisitos

- Node.js 20 o superior.
- Una cuenta de [Supabase](https://supabase.com) (el plan gratuito alcanza).

### 2. Instalar

```bash
npm install
```

### 3. Crear el proyecto de Supabase y correr las migraciones

1. Crea un proyecto nuevo en Supabase.
2. Abre el **SQL Editor** y ejecuta, **en orden**, todos los archivos de
   `supabase/migrations/` (`001_…` hasta el último). No te saltes ninguno
   ni cambies el orden: varias migraciones modifican lo que creó la
   anterior.
3. En **Database → Replication** (o **Realtime**), confirma que la tabla
   `public.mensajes_soporte` está publicada en `supabase_realtime`. Es lo
   que hace que el chat de soporte llegue al instante sin recargar.
4. En **Authentication → Providers → Email**, deja activada la
   confirmación por correo y sube la longitud mínima de contraseña a **8
   caracteres**, que es lo que valida la interfaz.

### 4. Variables de entorno

Copia `.env.local.example` a `.env.local` y complétalo. El archivo
documenta cada variable; en resumen:

| Variable | ¿Obligatoria? | Para qué |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Sí | Proyecto de Supabase. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Sí | Clave pública de Supabase. |
| `TRADING_SERVER_SECRET` | Sí | Secreto compartido servidor ↔ Postgres. Sin él, "Trade del día" y el cierre automático de señales fallan a propósito. |
| `MARKET_API_KEY` | No | Twelve Data, para índices y acciones. Sin ella, esa sección de `/mercado` no se muestra; la cripto sigue funcionando. |
| `NEXT_PUBLIC_TURNSTILE_SITE_KEY` | No | Captcha de Cloudflare en login/registro. Sin ella, no se muestra captcha. |

`TRADING_SERVER_SECRET` tiene que existir **en los dos lados**: en el
entorno de la app y en la tabla `config_servidor` de Postgres. Genera uno
y guárdalo en ambos:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

```sql
update public.config_servidor
   set valor = 'EL_SECRETO_QUE_GENERASTE'
 where clave = 'trading_server_secret';
```

### 5. Crear el primer administrador

Regístrate desde `/registro` con el correo que vaya a ser el del admin y
después, en el SQL Editor:

```sql
update public.usuarios set role = 'admin' where email = 'tu@correo.com';
```

### 6. Levantar la app

```bash
npm run dev       # desarrollo en http://localhost:3000
npm run build     # build de producción
npm run start     # servir el build
npm run lint      # ESLint
npm run typecheck # TypeScript sin emitir
```

## Desplegar en Vercel

1. Importa el repositorio en Vercel (detecta Next.js solo, no hace falta
   configurar el comando de build).
2. Carga las mismas variables de `.env.local` en **Settings → Environment
   Variables**. Ojo con `TRADING_SERVER_SECRET`: si el valor no coincide
   con el de `config_servidor`, abrir operaciones falla.
3. En Supabase, añade la URL de producción a **Authentication → URL
   Configuration** (Site URL y Redirect URLs), o los enlaces de
   confirmación y de recuperar contraseña apuntarán a `localhost`.
4. Para que los correos de confirmación y recuperación lleguen de verdad,
   configura un **SMTP propio** en **Authentication → Emails → SMTP
   Settings** (Resend, Postmark, SES...). Sin eso Supabase usa su
   servicio compartido, con un límite de envíos por hora muy bajo pensado
   solo para pruebas.

## Notas de arquitectura

- **Seguridad del dinero.** Ni el saldo ni el resultado de una operación
  se calculan en el navegador: viven en funciones `SECURITY DEFINER` de
  Postgres (`abrir_operacion`, `admin_cerrar_operacion`,
  `cerrar_senal_automatica`) que exigen `TRADING_SERVER_SECRET`. La clave
  anónima de Supabase está en el navegador por diseño, así que ese
  secreto es lo único que distingue "me llamó la app" de "me llamó
  alguien desde la consola".
- **RLS en todas las tablas.** Cada tabla de `public` tiene Row Level
  Security activada. `config_servidor` no tiene ninguna política a
  propósito: nadie la puede leer por la API.
- **Errores de las Server Actions.** Los fallos esperados se *devuelven*
  (`src/lib/actions/resultado.ts`), no se lanzan: en un build de
  producción Next.js borra el mensaje de cualquier `Error` que escape de
  una Server Action, así que lanzarlos convertiría cada aviso en español
  en un texto genérico en inglés.
- **Sesiones.** El refresco del token vive en `src/proxy.ts` (en Next.js
  16 el antiguo `middleware.ts` se llama así).
- **Horario de mercado.** Todo lo que dependa de "el día" usa el día de
  la bolsa de Nueva York, no UTC (`src/lib/horarioMercado.ts`), porque de
  eso dependen los reportes que deciden los premios.
