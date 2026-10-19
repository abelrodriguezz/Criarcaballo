// Configuración del adaptador de Cloudflare (@opennextjs/cloudflare).
// Sin caché incremental con R2 a propósito -- ver el comentario en
// wrangler.jsonc. Config por defecto, sin overrides, alcanza para esta app.
import { defineCloudflareConfig } from "@opennextjs/cloudflare";

export default defineCloudflareConfig({});
