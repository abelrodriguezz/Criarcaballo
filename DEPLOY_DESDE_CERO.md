# Despliegue desde cero (para ejecutar con un agente de código)

Esta guía está escrita para el agente que la va a ejecutar, no para un humano haciendo clicks. Si sos ese agente: ejecutá cada paso en orden, pedile al operador humano presente los datos que falten justo cuando hagan falta, y verificá cada paso antes de pasar al siguiente. No asumas ningún valor — todas las cuentas y secretos de este despliegue son nuevos, separados del entorno de desarrollo original.

## Contexto

App Next.js 16 + Supabase (mercado-app / Trade4U: señales, paper trading, depósitos/retiros, referidos). Se despliega desde cero a cuentas nuevas de GitHub + Supabase + Cloudflare Workers, sin reusar nada del entorno de desarrollo. Objetivo final: base de datos vacía, 2 cuentas admin reales, app corriendo en Cloudflare.

## Paso 0 — Confirmar con el operador

Preguntale si ya tiene creadas las cuentas de GitHub, Supabase y Cloudflare de la empresa (si no, el operador tiene que crearlas él mismo — signup con email y verificación no lo podés hacer vos). También si ya existen:
- Un repositorio nuevo y PRIVADO en GitHub (si no: github.com → New repository → Private, sin README).
- Un proyecto nuevo en Supabase (si no: supabase.com → New project → cualquier región sirve, no afecta los precios de cripto porque se usa MEXC → anotar la contraseña de la base que pida).

## Paso 1 — Subir el código al repo nuevo

Si no estás corriendo ya dentro de un clon de este repo, clonalo primero desde el origen (preguntale la URL al operador si no la tenés).

```
git remote remove origin
git remote add origin <URL-DEL-REPO-NUEVO-DE-LA-EMPRESA>
git push -u origin master
```

Esto va a pedir login de GitHub — dejá que el operador lo resuelva (navegador o token), es su cuenta, no la completes vos por él.

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

En vez de pedirle al operador que pegue el SQL a mano, conectate vos directo y corré el bundle entero:

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

La migración 080 (cron de señales) trae hardcodeada la URL vieja de desarrollo — no pasa nada si se aplica tal cual, se corrige en el paso 6.

## Paso 4 — Generar el TRADING_SERVER_SECRET nuevo

```
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Guardá el valor (lo vas a necesitar también en el paso 5). Con la misma conexión del paso 3:

```sql
update public.config_servidor
set valor = '<EL VALOR GENERADO>', actualizado_en = now()
where clave = 'trading_server_secret';
```

## Paso 5 — Desplegar a Cloudflare Workers

```
npm install
```

Creá `.env.local` en la raíz del proyecto:

```
NEXT_PUBLIC_SUPABASE_URL=<del paso 2>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<del paso 2>
```

Login de Cloudflare (dejá que el operador complete el login en el navegador que se abre, es su cuenta):

```
npx wrangler login
```

Desplegar:

```
npm run cf:deploy
```

Anotá la URL que devuelve (tipo `https://mercado-app.<cuenta>.workers.dev`).

**Cargar el secreto — método obligatorio, no uses tuberías.** `echo valor | npx wrangler secret put ...` (o cualquier `|`) coló un salto de línea de más en una prueba real y rompió el secreto EN SILENCIO, sin ningún error visible al desplegar. Usá esto en su lugar:

```js
// guardar como poner_secreto.js y correr: node poner_secreto.js
const { spawn } = require("child_process");
const secreto = "<EL VALOR DEL PASO 4>";
const p = spawn("npx.cmd", ["wrangler", "secret", "put", "TRADING_SERVER_SECRET"], {
  stdio: ["pipe", "inherit", "inherit"],
  shell: true, // en Mac/Linux: quitar shell:true y usar "npx" en vez de "npx.cmd"
});
p.stdin.write(secreto);
p.stdin.end();
p.on("close", (code) => process.exit(code));
```

Verificá que quedó bien:

```
curl -X POST https://<TU-WORKER>.workers.dev/api/cron/senales -H "Authorization: Bearer <EL SECRETO DEL PASO 4>"
```

Tiene que devolver `{"ok":true}`. Si da 401, repetí el paso del secreto — no sigas sin esto en verde.

## Paso 6 — Apuntar el cron de señales a la URL nueva

Con la conexión del paso 2/3, reemplazando `TU-WORKER.workers.dev` por la URL real del paso 5:

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
    url := 'https://TU-WORKER.workers.dev/api/cron/senales',
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

Probá con el mismo curl del paso 5 — si da `{"ok":true}`, el cron ya apunta bien.

## Paso 7 — Crear los 2 admins

Pedile al operador los 2 correos reales de admin. En vez de hacerlos registrarse manualmente por la UI, creálos directo con la service_role key del paso 2:

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

Esto crea el usuario de auth; el trigger `handle_new_user()` crea la fila en `public.usuarios` con nombre/apellido/cédula/teléfono en `NULL` (se completan después desde `/perfil`, no son obligatorios en esta primera creación — a propósito, para no bloquear cuentas creadas así).

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

## Lo que el operador SÍ tiene que hacer a mano (no se puede scriptear)

- **SMTP (Resend)**: crear cuenta en resend.com, verificar el dominio (necesita el dominio del punto siguiente ya conectado a Cloudflare), generar una API key. Con esos 3 datos, vos configurás Supabase: Project Settings → Authentication → SMTP Settings → Enable Custom SMTP → Host `smtp.resend.com`, Port `465`, Username `resend`, Password la API key, Sender email del dominio verificado.
- **Dominio propio**: el operador lo compra. Si no está ya en Cloudflare: Cloudflare → Add a site → el dominio → cambiar los nameservers en el registrador por los que da Cloudflare. Después vos conectás: Workers & Pages → el Worker → Settings → Domains & Routes → Add → Custom Domain. Actualizá el paso 6 con la URL del dominio nuevo.
- **Cloudflare Turnstile**: el operador entra a dash.cloudflare.com/turnstile → Add widget → te pasa Site Key y Secret Key. Vos agregás `NEXT_PUBLIC_TURNSTILE_SITE_KEY` a `.env.local` y volvés a desplegar (`npm run cf:deploy`), y pegás el Secret Key en Supabase → Authentication → Attack Protection → Enable Captcha protection.
- **Twelve Data (opcional)**: el operador crea cuenta en twelvedata.com y te pasa la API key. Vos la agregás a `.env.local` como `MARKET_API_KEY` y volvés a desplegar.

## Al terminar

Resumen para el operador: URL final del sitio, qué quedó pendiente de la lista de arriba, y qué verificaste vos mismo (curl del cron, login de los 2 admins, alguna página clave cargando bien).
