"use client";

import { useLayoutEffect, useReducer, useRef, useState, type ChangeEvent, type FormEvent } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { crearClienteSupabase } from "@/lib/supabase/client";
import { mensajeErrorAuth } from "@/lib/auth/mensajesError";
import { Turnstile } from "@/components/auth/Turnstile";
import { PAISES, PAIS_POR_DEFECTO } from "@/lib/paises";
import type { Diccionario, Locale } from "@/lib/i18n";

// Ver nota en LoginForm.tsx: sin site key configurada, el captcha se omite
// en vez de dejar el formulario deshabilitado para siempre.
const TURNSTILE_CONFIGURADO = !!process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;

// Duplicado a propósito de DatosContactoForm.tsx: es un regex autocontenido,
// sin dependencias, y así este formulario no gana un import extra.
const TELEFONO_VALIDO = /^[0-9+\-\s()]{6,30}$/;

// Cédula dominicana: 3 dígitos, guion, 7 dígitos, guion, 1 dígito
// (001-1234567-8). El mismo formato se exige en la base de datos
// (migración 084, constraint usuarios_cedula_formato).
const CEDULA_VALIDA = /^[0-9]{3}-[0-9]{7}-[0-9]$/;

/** Inserta los guiones automáticamente mientras se escribe, sin que la
 * persona tenga que teclearlos ella misma. */
function formatearCedula(valor: string): string {
  const digitos = valor.replace(/\D/g, "").slice(0, 11);
  const p1 = digitos.slice(0, 3);
  const p2 = digitos.slice(3, 10);
  const p3 = digitos.slice(10, 11);
  if (digitos.length <= 3) return p1;
  if (digitos.length <= 10) return `${p1}-${p2}`;
  return `${p1}-${p2}-${p3}`;
}

/** Posición en el texto formateado justo después del dígito número
 * `cantDigitos` (contando desde 1). Sirve para devolver el cursor a donde
 * estaba después de reformatear, en vez de mandarlo siempre al final. */
function posicionTrasDigitos(formateado: string, cantDigitos: number): number {
  if (cantDigitos <= 0) return 0;
  let vistos = 0;
  for (let i = 0; i < formateado.length; i++) {
    if (/\d/.test(formateado[i]) && ++vistos === cantDigitos) return i + 1;
  }
  return formateado.length;
}

// Mismo criterio laxo que usa el navegador para type="email": algo@algo.algo.
// Se valida aquí porque el formulario va con noValidate (ver más abajo).
const CORREO_VALIDO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function RegistroForm({ t, locale }: { t: Diccionario; locale: Locale }) {
  const searchParams = useSearchParams();
  const codigoRefUrl = searchParams.get("ref");

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmar, setConfirmar] = useState("");
  const [nombre, setNombre] = useState("");
  const [apellido, setApellido] = useState("");
  const [cedula, setCedula] = useState("");
  const inputCedula = useRef<HTMLInputElement>(null);
  const cursorCedula = useRef<number | null>(null);
  const [renderCedula, forzarRenderCedula] = useReducer((n: number) => n + 1, 0);
  // Se guarda el NOMBRE del país, no el dial: varios países comparten el
  // mismo código (+1 es República Dominicana, Puerto Rico, EE.UU. y
  // Canadá a la vez) — un <select> con value=dial no puede distinguir
  // entre opciones con el mismo value y termina mostrando cualquiera de
  // ellas como si fuera la seleccionada.
  const [nombrePais, setNombrePais] = useState(PAIS_POR_DEFECTO.nombre);
  const [telefono, setTelefono] = useState("");
  const [codigoInvitacion, setCodigoInvitacion] = useState(codigoRefUrl ?? "");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [exito, setExito] = useState(false);
  const [cargando, setCargando] = useState(false);

  // Reformatear en cada tecla sin más mandaba el cursor al final (editar un
  // dígito del medio obligaba a reescribir todo lo que seguía) y hacía
  // imposible borrar "a través" de un guion: Backspace justo después de un
  // guion lo quitaba, se volvía a insertar al reformatear y no pasaba nada.
  function alCambiarCedula(e: ChangeEvent<HTMLInputElement>) {
    const input = e.target;
    const crudo = input.value;
    const cursor = input.selectionStart ?? crudo.length;
    let digitos = crudo.replace(/\D/g, "");
    let digitosAntesDelCursor = crudo.slice(0, cursor).replace(/\D/g, "").length;

    const soloSeBorroUnGuion =
      crudo.length < cedula.length && digitos === cedula.replace(/\D/g, "");
    if (soloSeBorroUnGuion) {
      const tipo = (e.nativeEvent as InputEvent).inputType;
      if (tipo === "deleteContentBackward" && digitosAntesDelCursor > 0) {
        digitos =
          digitos.slice(0, digitosAntesDelCursor - 1) + digitos.slice(digitosAntesDelCursor);
        digitosAntesDelCursor -= 1;
      } else if (tipo === "deleteContentForward") {
        digitos =
          digitos.slice(0, digitosAntesDelCursor) + digitos.slice(digitosAntesDelCursor + 1);
      }
    }

    const formateado = formatearCedula(digitos);
    const nuevoCursor = posicionTrasDigitos(formateado, Math.min(digitosAntesDelCursor, 11));
    // El cursor se aplica en el useLayoutEffect de abajo, en el mismo commit
    // en que React escribe el valor (un requestAnimationFrame llegaba tarde
    // si se tecleaba rápido y mandaba los dígitos siguientes a otro lado).
    // Si el valor no cambia (ej. tecleó una letra) igual se fuerza un render
    // para que el efecto corra y el cursor no salte al final.
    cursorCedula.current = nuevoCursor;
    setCedula(formateado);
    if (formateado === cedula) forzarRenderCedula();
  }

  useLayoutEffect(() => {
    const pos = cursorCedula.current;
    const el = inputCedula.current;
    cursorCedula.current = null;
    if (pos !== null && el && document.activeElement === el) el.setSelectionRange(pos, pos);
  }, [cedula, renderCedula]);

  async function manejarEnvio(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const emailLimpio = email.trim();
    if (!CORREO_VALIDO.test(emailLimpio)) {
      setError(t.errores.correoInvalido);
      return;
    }
    const nombreLimpio = nombre.trim();
    if (!nombreLimpio) {
      setError(t.auth.nombreRequerido);
      return;
    }
    const apellidoLimpio = apellido.trim();
    if (!apellidoLimpio) {
      setError(t.auth.apellidoRequerido);
      return;
    }
    const cedulaLimpia = cedula.trim();
    if (!cedulaLimpia) {
      setError(t.auth.cedulaRequerido);
      return;
    }
    if (!CEDULA_VALIDA.test(cedulaLimpia)) {
      setError(t.auth.cedulaFormatoInvalido);
      return;
    }
    const telefonoLimpio = telefono.trim();
    if (!telefonoLimpio) {
      setError(t.auth.telefonoRequerido);
      return;
    }
    if (!TELEFONO_VALIDO.test(telefonoLimpio)) {
      setError(t.datosContacto.formatoInvalido);
      return;
    }
    // El código de país se antepone aquí, no lo escribe la persona — evita
    // que alguien meta un "+" propio y quede duplicado (ej. "+52 +8091234").
    const dialPais =
      PAISES.find((p) => p.nombre === nombrePais)?.dial ?? PAIS_POR_DEFECTO.dial;
    const telefonoConPais = `${dialPais} ${telefonoLimpio}`;
    if (password !== confirmar) {
      setError(t.auth.contrasenasNoCoinciden);
      return;
    }
    if (password.length < 8) {
      setError(t.auth.contrasenaCorta);
      return;
    }
    if (TURNSTILE_CONFIGURADO && !captchaToken) {
      setError(t.auth.completaVerificacion);
      return;
    }

    // El código se guarda en mayúsculas (así se generan en la base de
    // datos) para que el trigger handle_new_user() lo encuentre sin
    // importar cómo lo haya escrito la persona.
    const codigoLimpio = codigoInvitacion.trim().toUpperCase();

    setCargando(true);
    const supabase = crearClienteSupabase();

    // invitado_por es inmutable una vez creada la cuenta (no se puede
    // corregir después), así que si escribieron algo, confirmamos que
    // exista ANTES de registrar — no después, cuando ya sería tarde.
    if (codigoLimpio) {
      const { data: codigoValido, error: errorCodigo } = await supabase.rpc(
        "codigo_invitacion_valido",
        { p_codigo: codigoLimpio }
      );
      if (errorCodigo) {
        setCargando(false);
        setError(t.auth.errorRegistroGenerico);
        return;
      }
      if (!codigoValido) {
        setCargando(false);
        setError(t.auth.codigoInvitacionInvalido);
        return;
      }
    }

    const { data, error } = await supabase.auth.signUp({
      email: emailLimpio,
      password,
      options: {
        ...(captchaToken ? { captchaToken } : {}),
        data: {
          ...(codigoLimpio ? { ref: codigoLimpio } : {}),
          nombre: nombreLimpio,
          apellido: apellidoLimpio,
          cedula: cedulaLimpia,
          telefono: telefonoConPais,
        },
      },
    });
    setCargando(false);

    if (error) {
      setError(mensajeErrorAuth(error, t.auth.errorRegistroGenerico, locale));
      setCaptchaToken(null); // el token de Turnstile es de un solo uso
      return;
    }

    // Con "Confirm email" activo, Supabase no devuelve un error cuando el
    // correo ya tiene cuenta (para no confirmarle a un atacante que ese
    // correo existe) — en vez de eso responde igual que un registro nuevo
    // pero con `identities: []`. Sin este chequeo, alguien que ya tiene
    // cuenta y se re-registra por error veía "revisa tu correo" como si se
    // hubiera creado algo, sin que llegara ningún email de verdad.
    if (data.user && data.user.identities && data.user.identities.length === 0) {
      setError(t.errores.correoYaRegistrado);
      setCaptchaToken(null);
      return;
    }

    setExito(true);
  }

  if (exito) {
    return (
      <div className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto text-center">
        <h1 className="font-display font-semibold text-lg mb-2">
          {t.auth.revisaTuCorreoTitulo}
        </h1>
        <p className="text-sm text-foreground-muted">
          {locale === "en" ? (
            <>
              We sent a confirmation link to <strong>{email}</strong>.{" "}
              {t.auth.revisaTuCorreoRegistro}
            </>
          ) : (
            <>
              Te enviamos un enlace de confirmación a <strong>{email}</strong>.{" "}
              {t.auth.revisaTuCorreoRegistro}
            </>
          )}
        </p>
      </div>
    );
  }

  return (
    // noValidate: sin esto, el `required` nativo frena el envío ANTES de
    // manejarEnvio y muestra la burbuja del navegador ("Please fill out this
    // field.", en el idioma del navegador y no en el elegido en la app), y
    // además deja a la vista el error anterior de la app, que ya no
    // corresponde. Toda la validación (incluido el correo) se hace en
    // manejarEnvio con los mensajes traducidos; `required` se queda por
    // accesibilidad (aria-required).
    <form
      onSubmit={manejarEnvio}
      noValidate
      className="bg-surface border border-[var(--border)] rounded-2xl p-6 max-w-[400px] w-full mx-auto"
    >
      <h1 className="font-display font-semibold text-lg mb-5">
        {t.auth.crearCuentaTitulo}
      </h1>

      <label htmlFor="registro-email" className="block text-[13px] font-medium mb-1.5">
        {t.auth.correo}
      </label>
      <input
        id="registro-email"
        type="email"
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.correoPlaceholder}
      />

      <div className="grid grid-cols-2 gap-2.5 mb-3">
        <div>
          <label htmlFor="registro-nombre" className="block text-[13px] font-medium mb-1.5">
            {t.auth.nombreLabel}
          </label>
          <input
            id="registro-nombre"
            required
            value={nombre}
            onChange={(e) => setNombre(e.target.value)}
            maxLength={100}
            className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
            placeholder={t.auth.nombrePlaceholder}
          />
        </div>
        <div>
          <label htmlFor="registro-apellido" className="block text-[13px] font-medium mb-1.5">
            {t.auth.apellidoLabel}
          </label>
          <input
            id="registro-apellido"
            required
            value={apellido}
            onChange={(e) => setApellido(e.target.value)}
            maxLength={100}
            className="w-full px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
            placeholder={t.auth.apellidoPlaceholder}
          />
        </div>
      </div>

      <label htmlFor="registro-cedula" className="block text-[13px] font-medium mb-1.5">
        {t.auth.cedulaLabel}
      </label>
      <input
        id="registro-cedula"
        ref={inputCedula}
        required
        inputMode="numeric"
        value={cedula}
        onChange={alCambiarCedula}
        maxLength={13}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.cedulaPlaceholder}
      />

      <label htmlFor="registro-telefono" className="block text-[13px] font-medium mb-1.5">
        {t.auth.telefonoLabel}
      </label>
      <div className="flex gap-2 mb-3">
        <select
          aria-label={t.auth.paisLabel}
          value={nombrePais}
          onChange={(e) => setNombrePais(e.target.value)}
          className="shrink-0 w-[92px] px-2 py-2.5 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        >
          {PAISES.map((p) => (
            <option key={p.nombre} value={p.nombre}>
              {p.bandera} {p.dial}
            </option>
          ))}
        </select>
        <input
          id="registro-telefono"
          type="tel"
          inputMode="tel"
          required
          value={telefono}
          onChange={(e) => setTelefono(e.target.value)}
          maxLength={20}
          className="flex-1 min-w-0 px-3.5 py-2.5 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
          placeholder={t.auth.telefonoPlaceholder}
        />
      </div>

      <label htmlFor="registro-password" className="block text-[13px] font-medium mb-1.5">
        {t.auth.contrasena}
      </label>
      <input
        id="registro-password"
        type="password"
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.contrasenaMinima}
      />

      <label htmlFor="registro-confirmar" className="block text-[13px] font-medium mb-1.5">
        {t.auth.confirmarContrasena}
      </label>
      <input
        id="registro-confirmar"
        type="password"
        required
        value={confirmar}
        onChange={(e) => setConfirmar(e.target.value)}
        className="w-full px-3.5 py-2.5 mb-3 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder="••••••••"
      />

      <label htmlFor="registro-codigo" className="block text-[13px] font-medium mb-1.5">
        {t.auth.codigoInvitacionLabel}
      </label>
      <input
        id="registro-codigo"
        value={codigoInvitacion}
        onChange={(e) => setCodigoInvitacion(e.target.value)}
        maxLength={20}
        className="w-full px-3.5 py-2.5 mb-4 rounded-lg border border-[var(--border)] bg-background text-base md:text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary"
        placeholder={t.auth.codigoInvitacionPlaceholder}
      />

      {error && (
        <p className="text-loss text-[13px] mb-3" role="alert">
          {error}
        </p>
      )}

      <div className="mb-4">
        <Turnstile onVerify={setCaptchaToken} onExpire={() => setCaptchaToken(null)} />
      </div>

      <button
        type="submit"
        disabled={cargando || (TURNSTILE_CONFIGURADO && !captchaToken)}
        className="w-full bg-brand-primary hover:bg-brand-primary-hover disabled:opacity-60 text-white font-semibold text-sm py-3 rounded-xl transition-colors"
      >
        {cargando ? t.auth.creandoCuenta : t.auth.crearCuenta}
      </button>

      <p className="text-center text-[13px] text-foreground-muted mt-4">
        {t.auth.yaTienesCuenta}{" "}
        <Link href="/login" className="text-brand-primary font-semibold">
          {t.auth.iniciaSesion}
        </Link>
      </p>
    </form>
  );
}
