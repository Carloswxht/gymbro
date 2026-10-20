// =====================================================================
// Gymbro · Edge Function «recuperar-contrasena-gymbro» (v98; bienvenida desde la v99)
// ---------------------------------------------------------------------
// Corre en el servidor de Supabase (no en la web). La app le manda
// { email }; aquí, con la clave secreta que solo existe dentro de Supabase,
// se pide a la base un enlace (public.recuperar_crear_gymbro) y se manda
// por correo con Resend. Contesta SIEMPRE { ok: true } y tarda lo mismo,
// exista o no el correo: así nadie puede averiguar quién tiene cuenta. Los
// límites (3 enlaces por hora, 30 minutos, un solo uso) los pone la base.
// v99: con { email, bienvenida: true } (lo manda el panel del dueño al dar
// de alta a un socio) manda el correo de bienvenida: enlace de 3 días para
// elegir su primera contraseña (public.bienvenida_crear_gymbro: solo si aún
// no la ha elegido; si ya la eligió, se manda el de «contraseña nueva»).
//
// Secretos (Supabase → Edge Functions → Secrets; nunca en el repositorio):
//   RESEND_API_KEY  clave de Resend (ya está: la usa también MultiBar)
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los pone Supabase solo.
// Desplegar con verify_jwt = false (la web no tiene sesión de Supabase).
// =====================================================================

const WEB = 'https://gymbro.autonomialab.es';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-client-info',
  'Access-Control-Max-Age': '86400',
};

function respuesta(status: number, cuerpo: unknown) {
  return new Response(JSON.stringify(cuerpo), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function esc(t: string) {
  return String(t ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string));
}

type Enlace = { token: string; email: string; nombre: string; negocio_nombre: string; negocio_slug: string; bienvenida?: boolean };

async function crearEnlace(email: string, bienvenida: boolean): Promise<Enlace | null> {
  const url = Deno.env.get('SUPABASE_URL');
  const clave = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !clave) { console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY'); return null; }
  const r = await fetch(url + '/rest/v1/rpc/' + (bienvenida ? 'bienvenida_crear_gymbro' : 'recuperar_crear_gymbro'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: clave, Authorization: 'Bearer ' + clave },
    body: JSON.stringify({ p_email: email }),
  });
  if (!r.ok) { console.error('recuperar_crear_gymbro', r.status, await r.text()); return null; }
  return await r.json();
}

async function mandarCorreo(e: Enlace) {
  const clave = Deno.env.get('RESEND_API_KEY');
  if (!clave) { console.error('Falta el secreto RESEND_API_KEY'); return; }
  // El remitente lleva el nombre del gimnasio (sin caracteres que rompan la cabecera).
  const remitente = `${String(e.negocio_nombre).replace(/[<>"\r\n]/g, '').slice(0, 60) || 'Gymbro'} <avisos@autonomialab.com>`;
  const enlace = `${WEB}/?g=${encodeURIComponent(e.negocio_slug)}#recuperar=${e.token}`;
  const gym = esc(e.negocio_nombre), nombre = esc(e.nombre);
  const bv = !!e.bienvenida;
  const titulo = bv ? `Ya tienes cuenta en ${gym}` : 'Contraseña nueva';
  const intro = bv ? `Hola ${nombre}: ${gym} te ha dado de alta en su app de entrenamiento. Toca el botón para elegir tu contraseña y entrar.`
    : `Hola ${nombre}: alguien (seguramente tú) ha pedido cambiar tu contraseña. Toca el botón para elegir una nueva.`;
  const boton = bv ? 'Elegir mi contraseña' : 'Elegir contraseña nueva';
  const pie = bv ? `El botón vale <b>3 días</b> y una sola vez. Después entra siempre en <a href="${WEB}/?g=${encodeURIComponent(e.negocio_slug)}" style="color:#9AA0AA">${WEB.replace('https://', '')}</a> con este correo. Si se te pasa, usa «¿Has olvidado tu contraseña?».`
    : 'El enlace vale <b>30 minutos</b> y una sola vez. Si no lo has pedido tú, no hagas nada: tu contraseña sigue siendo la misma.';
  const html = `<!doctype html><html lang="es"><body style="margin:0;background:#0E1013;font-family:Arial,Helvetica,sans-serif;color:#F2F1EC">
<div style="max-width:480px;margin:0 auto;padding:24px 16px">
  <div style="background:#181B20;border-radius:14px;padding:24px;border:1px solid #2B3038">
    <p style="margin:0 0 4px;font-size:13px;letter-spacing:.06em;color:#9AA0AA;text-transform:uppercase">${gym}</p>
    <h1 style="margin:0 0 16px;font-size:22px">${titulo}</h1>
    <p style="margin:0 0 16px;font-size:15px;line-height:1.5">${intro}</p>
    <p style="margin:0 0 20px;text-align:center"><a href="${enlace}" style="display:inline-block;background:#F2F1EC;color:#0E1013;text-decoration:none;font-weight:bold;font-size:16px;padding:14px 24px;border-radius:10px">${boton}</a></p>
    <p style="margin:0;font-size:13px;line-height:1.5;color:#9AA0AA">${pie}</p>
  </div>
  <p style="margin:16px 0 0;text-align:center;font-size:11px;color:#6B6F76">Gymbro · autonomIA Lab</p>
</div></body></html>`;
  const texto = bv
    ? `${e.negocio_nombre}\n\nHola ${e.nombre}: ${e.negocio_nombre} te ha dado de alta en su app de entrenamiento.\n` +
      `Abre este enlace para elegir tu contraseña (vale 3 días y una sola vez):\n${enlace}\n\n` +
      `Después entra siempre en ${WEB}/?g=${encodeURIComponent(e.negocio_slug)} con este correo.\n\nGymbro · autonomIA Lab`
    : `${e.negocio_nombre}\n\nHola ${e.nombre}: alguien (seguramente tú) ha pedido cambiar tu contraseña.\n` +
      `Abre este enlace para elegir una nueva (vale 30 minutos y una sola vez):\n${enlace}\n\n` +
      `Si no lo has pedido tú, no hagas nada: tu contraseña sigue siendo la misma.\n\nGymbro · autonomIA Lab`;
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + clave },
    body: JSON.stringify({ from: remitente, to: [e.email], subject: bv ? `Ya tienes cuenta en ${e.negocio_nombre}` : `Contraseña nueva · ${e.negocio_nombre}`, html, text: texto }),
  });
  if (!r.ok) console.error('Resend', r.status, await r.text());
}

async function trabajo(email: string, bienvenida: boolean) {
  try {
    let e = await crearEnlace(email, bienvenida);
    // Si ya eligió su contraseña, la bienvenida no vale: se manda el de «contraseña nueva».
    if (!(e && e.token) && bienvenida) e = await crearEnlace(email, false);
    if (e && e.token) await mandarCorreo(e);
  } catch (err) { console.error('recuperar-contrasena-gymbro', err); }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return respuesta(405, { ok: false });
  let email = '', bienvenida = false;
  try {
    const cuerpo = await req.json();
    email = String(cuerpo?.email ?? '').trim().slice(0, 200);
    bienvenida = cuerpo?.bienvenida === true;
  } catch { /* cuerpo malo */ }
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    // Se trabaja después de contestar: la respuesta tarda lo mismo con o sin cuenta.
    const p = trabajo(email, bienvenida);
    // deno-lint-ignore no-explicit-any
    const rt = (globalThis as any).EdgeRuntime;
    if (rt && typeof rt.waitUntil === 'function') rt.waitUntil(p); else await p;
  }
  return respuesta(200, { ok: true });
});
