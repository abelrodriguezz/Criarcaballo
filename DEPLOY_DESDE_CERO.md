# Despliegue desde cero (para ejecutar con un agente de código)

Esta guía está escrita para el agente que la va a ejecutar, no para un humano haciendo clicks. Si sos ese agente: ejecutá cada paso en orden, pedile al operador humano presente los datos que falten justo cuando hagan falta, y verificá cada paso antes de pasar al siguiente. No asumas ningún valor — todas las cuentas y secretos de este despliegue son nuevos, separados del entorno de desarrollo original.

## Contexto

App Next.js 16 + Supabase (mercado-app / Trade4U: señales, paper trading, depósitos/retiros, referidos). Se despliega desde cero a cuentas nuevas de GitHub + Supabase + un VPS privado (1984 Hosting, pagado con cripto), sin reusar nada del entorno de desarrollo.

**Por qué un VPS y no Vercel/Railway/Cloudflare**: el operador necesita privacidad (sin tarjeta, sin verificación de identidad) y pago en cripto. Investigado y descartado: Vercel/Cloudflare/Railway piden tarjeta; el plan gratis de Cloudflare Workers no aguanta esta app (límite de 10ms de CPU por pedido, la app mide 180-574ms reales); el plan gratis de Vercel sí aguantaría de capacidad pero prohíbe uso comercial en sus términos. Un VPS normal (acceso root, sin medir CPU por pedido) no tiene ninguno de los dos problemas.

**Arquitectura**: la app se compila LOCALMENTE (en la máquina del operador, donde se ejecuta este agente) y solo se transfiere el resultado ya compilado al VPS — el plan elegido ($9.66/mes, 1GB RAM) alcanza de sobra para CORRER la app (probado: 294MB de pico con 20 usuarios concurrentes) pero podría quedarse sin memoria si se intentara COMPILAR ahí mismo.

## Paso 0 — Confirmar con el operador

Preguntale si ya tiene:
- Cuenta de GitHub de la empresa + un repositorio nuevo y PRIVADO creado.
- Proyecto nuevo en Supabase (región: cualquiera, ya no importa — tanto `/mercado` como el cierre de señales usan MEXC, que no bloquea por región).
- Cuenta en 1984 Hosting (1984.hosting) y el VPS **ya pagado** (plan VPS #1, 1GB RAM/1 CPU, $9.66/mes, pagado con Bitcoin o Monero). Si todavía no lo pagó, decile que lo haga ahora — vos no podés pagar en cripto por él.
- La **IP del VPS** y la contraseña de **root** (se la dan por email o en el panel de 1984 al terminar de pagar).
- Cuenta de Cloudflare con un widget de **Turnstile** creado (ver paso 6 — si no la tiene todavía, no hace falta pararse ahí hasta llegar a ese paso).

Si el VPS no está listo, esperá a que el operador lo tenga antes de seguir del paso 5 en adelante — los pasos 1-4 (GitHub/Supabase) se pueden hacer mientras tanto.

## Paso 1 — Subir el código al repo nuevo

El código llega a esta máquina como un archivo `mercado-app-export.zip` (sin historial de git, por privacidad) — no un clon del repo de desarrollo original. Extraelo a una carpeta nueva y armá el repo desde cero ahí:

```
git init
git add -A
git commit -m "Version inicial"
git branch -M master
git remote add origin <URL-DEL-REPO-NUEVO-DE-LA-EMPRESA>
git push -u origin master
```

Esto va a pedir login de GitHub — dejá que el operador lo resuelva (navegador o token), es su cuenta nueva de la empresa, no la completes vos por él.

## Paso 2 — Datos de Supabase

Pedile al operador, del proyecto NUEVO de Supabase:
- Project Settings → API → "Project URL" y "anon public" key.
- Project Settings → API → "service_role" key (secreta, para crear los admins sin pasar por el registro manual).
- Project Settings → Database → Connection string, modo "Transaction pooler", con la contraseña real ya puesta.

Instalá la librería que vas a necesitar para hablar con Postgres directo (no se commitea al repo, es solo para este despliegue):

```
npm install pg --no-save
```

## Paso 3 — Correr las migraciones

Conectate directo y corré el bundle entero:

```js
// guardar como migrar.js y correr: node migrar.js
const { Client } = require("pg");
const fs = require("fs");
const client = new Client({ connectionString: "<CONNECTION STRING DEL PASO 2>", ssl: { rejectUnauthorized: false } });
(async () => {
  await client.connect();
  const sql = fs.readFileSync("supabase/bundle_todas_las_migraciones.sql", "utf8");
  await client.query(sql);
  console.log("Migraciones aplicadas.");
  await client.end();
})().catch((e) => { console.error(e); process.exit(1); });
```

Si da un error que NO sea "ya existe"/"already exists", DETENTE ahí y mostrale al operador el mensaje completo y la sección `=== MIGRACION NNN ===` más cercana arriba del error antes de seguir — esto nunca se corrió de punta a punta contra un proyecto realmente vacío antes de ahora.

La migración 080 (cron de señales) trae hardcodeada la URL vieja de desarrollo — no pasa nada si se aplica tal cual, se corrige en el paso 11.

## Paso 4 — Generar el TRADING_SERVER_SECRET nuevo

```
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Guardá el valor (lo vas a necesitar también en el paso 9). Con la misma conexión del paso 3:

```sql
update public.config_servidor
set valor = '<EL VALOR GENERADO>', actualizado_en = now()
where clave = 'trading_server_secret';
```

## Paso 5 — Preparar el VPS (primera conexión)

Conectate por SSH con los datos que te dio el operador (reemplazando la IP real):

```
ssh root@IP_DEL_VPS
```

La primera vez te va a pedir aceptar la huella del servidor (escribí `yes`) y la contraseña de root que dio 1984. Una vez adentro, actualizá el sistema e instalá lo necesario (asumiendo Ubuntu/Debian, que es lo más común en 1984 Hosting — si el VPS corre otra distro, avisale al operador y ajustá los comandos de instalación de paquetes, el resto es igual):

```bash
apt update && apt upgrade -y

# Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# PM2: mantiene la app corriendo y la reinicia sola si se cae o si el VPS reinicia
npm install -g pm2

# Caddy: servidor web con HTTPS automatico (certificado real, se renueva solo)
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# Firewall basico: solo SSH, HTTP y HTTPS
apt install -y ufw
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# Usuario sin privilegios para correr la app (root nunca deberia correr la app en si)
adduser --disabled-password --gecos "" mercadoapp
mkdir -p /home/mercadoapp/app
chown -R mercadoapp:mercadoapp /home/mercadoapp/app
```

Confirmá que `node -v` da `v20.x.x` y que `systemctl status caddy` dice "active (running)" antes de seguir.

## Paso 6 — Cloudflare Turnstile (captcha de login y registro)

**PARATE ACÁ y esperá los datos del operador antes de seguir.** El código ya está listo y conectado en login, registro y recuperar contraseña — solo falta la cuenta real.

Pedile al operador:
1. Que entre a <https://dash.cloudflare.com/?to=/:account/turnstile> (cuenta de Cloudflare de la empresa, separada del VPS — Turnstile es gratis y no tiene nada que ver con dónde corre la app).
2. Add widget → nombre cualquiera → en "Domain" pone el dominio que va a usar la app (o lo deja en blanco/localhost si todavía no lo tiene, lo puede agregar después desde el mismo panel) → Widget Mode: Managed → Create.
3. Que te pase el **Site Key** y el **Secret Key** que le muestra.

Con esos dos valores:
- Guardá el Site Key — lo vas a necesitar en el paso 7 (`NEXT_PUBLIC_TURNSTILE_SITE_KEY`, va al `.env.local` antes de compilar).
- El Secret Key configuralo ahora mismo en Supabase: Authentication → Attack Protection → activá "Enable Captcha protection" → elegí Turnstile → pegá el Secret Key → Save.

Si el operador todavía no tiene la cuenta de Cloudflare lista, podés seguir con el resto del despliegue sin el captcha activado (login/registro funcionan igual, solo sin esa capa extra) y volver a este paso después — en ese caso, cuando lo tenga, hay que agregar el Site Key al `.env.local`, volver a compilar (paso 7) y transferir (paso 8) de nuevo.

## Paso 7 — Compilar la app LOCALMENTE

En tu máquina (NO en el VPS), dentro de la carpeta del proyecto:

```
npm install
```

Creá `.env.local` en la raíz con los datos reales de los pasos anteriores (estas variables se necesitan en el momento de compilar, quedan "horneadas" en el resultado):

```
NEXT_PUBLIC_SUPABASE_URL=<del paso 2>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<del paso 2>
NEXT_PUBLIC_TURNSTILE_SITE_KEY=<del paso 6>
```

Compilá:

```
npm run build
```

Si termina sin errores, seguís al paso 8. El resultado queda en `.next/` — eso es lo que se transfiere, no hace falta volver a compilar en el VPS.

## Paso 8 — Transferir la app al VPS

Desde tu máquina, reemplazando IP_DEL_VPS:

```
rsync -avz --exclude ".git" --exclude ".env.local" ./ mercadoapp@IP_DEL_VPS:/home/mercadoapp/app/
```

(Si no tenés `rsync` disponible — por ejemplo en Windows sin WSL — usá `scp -r . mercadoapp@IP_DEL_VPS:/home/mercadoapp/app/` en su lugar; es más lento pero funciona igual. Puede pedir la contraseña del usuario `mercadoapp` — si no tiene, poné temporalmente `ssh root@IP_DEL_VPS "passwd mercadoapp"` para asignarle una antes de este paso.)

Esto copia TODO el proyecto, incluido `node_modules` (así el VPS no necesita correr `npm install`, que es justo lo que queríamos evitar con 1GB de RAM) y `.next` ya compilado. **No copia `.env.local`** a propósito (está excluido arriba) — el del VPS se arma aparte en el paso 9, porque necesita una variable que el de acá NO tiene (el secreto).

## Paso 9 — Variables de entorno en el VPS y arranque con PM2

Por SSH, como el usuario `mercadoapp` (no root):

```
ssh mercadoapp@IP_DEL_VPS
cd /home/mercadoapp/app
```

Creá el archivo de entorno de producción con las variables (las del paso 7 + el secreto del paso 4 — Next.js lee `.env.production.local` automáticamente al arrancar con `next start`):

```
cat > .env.production.local << 'EOF'
NEXT_PUBLIC_SUPABASE_URL=<del paso 2>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<del paso 2>
NEXT_PUBLIC_TURNSTILE_SITE_KEY=<del paso 6>
TRADING_SERVER_SECRET=<del paso 4>
EOF
```

Arrancá la app con PM2, apuntando al puerto interno 3000 (Caddy lo va a exponer afuera en el paso 10):

```
pm2 start npm --name mercado-app -- start -- -p 3000
pm2 save
```

Para que arranque solo si el VPS se reinicia, como root:

```
exit
pm2 startup systemd -u mercadoapp --hp /home/mercadoapp
```

(ese comando imprime una línea que empieza con `sudo env PATH=...` — copiala y correla tal cual, es la que registra el arranque automático).

Verificá que responde:

```
curl -I http://localhost:3000
```

Tiene que dar `HTTP/1.1 200 OK`. Si no, revisá `pm2 logs mercado-app` para ver el error.

## Paso 10 — Caddy: HTTPS automático con el dominio

Esto requiere que el operador ya haya comprado un dominio y apuntado su registro DNS tipo **A** a la IP del VPS (decile que lo haga si todavía no — puede tardar unos minutos en propagar). Como root en el VPS:

```
cat > /etc/caddy/Caddyfile << 'EOF'
TU-DOMINIO.com {
  reverse_proxy localhost:3000
}
EOF
systemctl reload caddy
```

Caddy consigue el certificado HTTPS real solo (Let's Encrypt) en cuanto detecta que el dominio ya apunta a esta IP — puede tardar uno o dos minutos la primera vez. Confirmá entrando a `https://TU-DOMINIO.com` desde un navegador o con `curl -I https://TU-DOMINIO.com`.

Si el operador todavía no tiene dominio, se puede probar por ahora con `curl -I http://IP_DEL_VPS:3000` directo (sin HTTPS) mientras tanto, y hacer este paso después.

Si en el paso 6 el widget de Turnstile se creó sin dominio (o con otro), volvé al dashboard de Cloudflare y agregá este dominio a la lista de dominios del widget — si no, el captcha no va a validar en producción.

## Paso 11 — Apuntar el cron de señales a la URL nueva

Con la conexión del paso 2/3, reemplazando `TU-DOMINIO.com` por el dominio real (o la IP:3000 si todavía no hay dominio — pero el cron necesita que ese puerto sea alcanzable desde internet, así que lo ideal es esperar a tener el dominio):

```sql
select cron.unschedule('cerrar-senales-automatico');

create or replace function public.disparar_cron_senales()
returns void as $$
declare
  v_secreto text;
begin
  select valor into v_secreto
  from public.config_servidor
  where clave = 'trading_server_secret';

  if v_secreto is null or v_secreto = 'FALTA-ROTAR-ESTE-SECRETO' then
    raise notice 'trading_server_secret sin configurar todavia';
    return;
  end if;

  perform net.http_post(
    url := 'https://TU-DOMINIO.com/api/cron/senales',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secreto,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  );
end;
$$ language plpgsql security definer
   set search_path = pg_catalog, public, pg_temp, net;

select cron.schedule(
  'cerrar-senales-automatico',
  '* * * * *',
  $$select public.disparar_cron_senales()$$
);
```

Probá con curl (reemplazando dominio y secreto):

```
curl -X POST https://TU-DOMINIO.com/api/cron/senales -H "Authorization: Bearer TU-SECRETO-DEL-PASO-4"
```

Tiene que devolver `{"ok":true}`.

## Paso 12 — Crear los 2 admins

Pedile al operador los 2 correos reales de admin. Creálos directo con la service_role key del paso 2 (evita el registro manual por la UI):

```js
// guardar como crear_admins.js y correr: node crear_admins.js
const { createClient } = require("@supabase/supabase-js");
const admin = createClient("<PROJECT URL DEL PASO 2>", "<SERVICE ROLE KEY DEL PASO 2>");
const CORREOS = ["<correo-admin-1>", "<correo-admin-2>"];
const PASSWORD_TEMPORAL = "<una contraseña temporal segura>";

(async () => {
  for (const email of CORREOS) {
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password: PASSWORD_TEMPORAL,
      email_confirm: true,
    });
    if (error) { console.error(email, error.message); continue; }
    console.log(email, "creado:", data.user.id);
  }
})();
```

Esto crea el usuario de auth; el trigger `handle_new_user()` crea la fila en `public.usuarios` con nombre/apellido/cédula/teléfono en `NULL` (se completan después desde `/perfil`, no son obligatorios en esta primera creación).

Con la conexión SQL, marcá los roles (reemplazando los correos reales, y eligiendo cuál de las dos es la principal):

```sql
update public.usuarios
set role = 'admin'
where email in ('<correo-admin-1>', '<correo-admin-2>');

-- Solo UNA cuenta puede ser la principal (protegida: ni el otro admin puede tocarla):
update public.usuarios
set es_principal = true
where email = '<correo-admin-1>';
```

Pedile al operador que entre con cualquiera de las 2 (contraseña temporal del script), confirme que ve el panel de admin completo en `/perfil`, y que cambie esa contraseña temporal por una real ahí mismo.

## Cómo actualizar la app más adelante (una vez que ya está desplegada)

Para subir cambios de código después de este primer despliegue, repetí los pasos 7 y 8 (compilar local, `rsync` al VPS), y reiniciá el proceso:

```
ssh mercadoapp@IP_DEL_VPS "pm2 restart mercado-app"
```

No hace falta tocar Caddy, PM2 ni las variables de entorno de nuevo salvo que cambien.

## Lo que el operador SÍ tiene que hacer a mano (no se puede scriptear)

- **SMTP (Resend)**: crear cuenta en resend.com, verificar el dominio (necesita el dominio del paso 10 ya apuntado), generar una API key. Con esos 3 datos, vos configurás Supabase: Project Settings → Authentication → SMTP Settings → Enable Custom SMTP → Host `smtp.resend.com`, Port `465`, Username `resend`, Password la API key, Sender email del dominio verificado.
- **Dominio propio**: el operador lo compra y apunta el registro DNS tipo A a la IP del VPS (ver paso 10).
- **Twelve Data (opcional)**: el operador crea cuenta en twelvedata.com y te pasa la API key. Vos la agregás a `.env.local` como `MARKET_API_KEY` antes de compilar y repetís 7-8.

(Cloudflare Turnstile ya tiene su propio paso numerado, el 6 — no quedó en esta lista porque no es opcional, el formulario de login/registro ya lo espera.)

## Al terminar

Resumen para el operador: URL final del sitio, qué quedó pendiente de la lista de arriba, y qué verificaste vos mismo (curl del cron, `pm2 status` mostrando la app "online", login de los 2 admins, captcha visible en login/registro, alguna página clave cargando bien con HTTPS).
