// Supabase simulado: sirve la web y responde /rest/v1/rpc/* con la base local.
// v107: imita también el login de Supabase (/auth/v1: entrar, renovar, salir,
// quién soy y cambiar la contraseña) con auth.users de la base local; una
// llamada con «Authorization: Bearer <sesión>» va como «authenticated» con su
// sub, como en Supabase (auth.uid()); sin sesión, como «anon».
// Base: PGDATABASE (por defecto «prueba»; la del login es «login»).
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path'; import crypto from 'node:crypto'; import pg from 'pg';
const RAIZ = process.argv[2], PUERTO = 8091;
let ultimoEnlace = null;
const pool = new pg.Pool({ host: process.env.PGHOST, port: 5445, user: 'postgres', database: process.env.PGDATABASE || 'prueba' }); pool.on('error', e => console.error('pool', e.message));
const tipos = { '.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.png':'image/png', '.mp4':'video/mp4', '.css':'text/css', '.woff2':'font/woff2' };

// Sesiones de Supabase imitadas (JWT HS256 con un secreto local).
const SECRETO = 'secreto-local-de-pruebas';
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const firmar = datos => { const c = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64(datos); return c + '.' + crypto.createHmac('sha256', SECRETO).update(c).digest('base64url'); };
function leerJwt(t){
  const [a, b, f] = String(t || '').split('.');
  if (!f || crypto.createHmac('sha256', SECRETO).update(a + '.' + b).digest('base64url') !== f) return null;
  const d = JSON.parse(Buffer.from(b, 'base64url').toString());
  return d.exp > Date.now() / 1000 ? d : null;
}
const renovaciones = new Map(); // refresh_token -> id de la cuenta
const DURACION = Number(process.env.SESION_SEGUNDOS || 3600);
function sesion(u){
  const ahora = Math.floor(Date.now() / 1000), refresh = crypto.randomBytes(16).toString('hex');
  renovaciones.set(refresh, u.id);
  return { access_token: firmar({ sub: u.id, role: 'authenticated', aud: 'authenticated', email: u.email, exp: ahora + DURACION }),
           token_type: 'bearer', expires_in: DURACION, expires_at: ahora + DURACION, refresh_token: refresh, user: usuario(u) };
}
const usuario = u => ({ id: u.id, aud: 'authenticated', role: 'authenticated', email: u.email, app_metadata: { provider: 'email' }, user_metadata: {}, created_at: u.created_at });
const json = (res, st, o) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(o === undefined ? '' : JSON.stringify(o)); };
const malAuth = (res, st, code, msg) => json(res, st, { code: st, error_code: code, msg });

async function auth(req, res, url, body){
  const cli = await pool.connect();
  try {
    const q = (s, v) => cli.query(s, v).then(r => r.rows);
    const bearer = (req.headers.authorization || '').replace(/^Bearer /i, '');
    if (url.pathname === '/auth/v1/token') {
      const tipo = url.searchParams.get('grant_type') || (body.password ? 'password' : 'refresh_token');
      let u;
      if (tipo === 'password') {
        [u] = await q(`select id, email, encrypted_password, banned_until, created_at from auth.users where lower(email) = lower($1)`, [String(body.email || '').trim()]);
        if (!u || !u.encrypted_password || (await q('select extensions.crypt($1, $2) = $2 as ok', [body.password || '', u.encrypted_password]))[0].ok !== true)
          return malAuth(res, 400, 'invalid_credentials', 'Invalid login credentials');
      } else {
        const id = renovaciones.get(body.refresh_token);
        if (!id) return malAuth(res, 400, 'refresh_token_not_found', 'Invalid Refresh Token: Refresh Token Not Found');
        renovaciones.delete(body.refresh_token);
        [u] = await q('select id, email, banned_until, created_at from auth.users where id = $1', [id]);
      }
      if (u.banned_until && new Date(u.banned_until) > new Date()) return malAuth(res, 400, 'user_banned', 'User is banned');
      await q('update auth.users set last_sign_in_at = now() where id = $1', [u.id]);
      return json(res, 200, sesion(u));
    }
    const d = leerJwt(bearer);
    if (url.pathname === '/auth/v1/logout') return json(res, 204);
    if (!d) return malAuth(res, 401, 'bad_jwt', 'invalid JWT');
    if (url.pathname === '/auth/v1/user' && req.method === 'GET') {
      const [u] = await q('select id, email, created_at from auth.users where id = $1', [d.sub]);
      return json(res, 200, usuario(u));
    }
    if (url.pathname === '/auth/v1/user' && req.method === 'PUT') {
      if (body.password) await q(`update auth.users set encrypted_password = extensions.crypt($1, extensions.gen_salt('bf', 4)), updated_at = now() where id = $2`, [body.password, d.sub]);
      const [u] = await q('select id, email, created_at from auth.users where id = $1', [d.sub]);
      return json(res, 200, usuario(u));
    }
    return malAuth(res, 404, 'not_found', 'no imitado');
  } catch (e) { console.error(e.message); return malAuth(res, 500, 'error', e.message); } finally { cli.release(); }
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  let body = ''; for await (const c of req) body += c;
  if (url.pathname.startsWith('/auth/v1/')) return auth(req, res, url, body ? JSON.parse(body) : {});
  const m = url.pathname.match(/^\/rest\/v1\/rpc\/([a-z_]+)$/);
  if (m && req.method === 'POST') {
    const args = body ? JSON.parse(body) : {};
    const ks = Object.keys(args);
    const vals = ks.map(k => args[k] !== null && typeof args[k] === 'object' ? JSON.stringify(args[k]) : args[k]);
    const jwt = leerJwt((req.headers.authorization || '').replace(/^Bearer /i, ''));
    const cli = await pool.connect();
    try {
      await cli.query('begin');
      if (jwt) {
        await cli.query('set local role authenticated');
        await cli.query(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify({ sub: jwt.sub, role: 'authenticated' })]);
      } else await cli.query('set local role anon');
      const r = await cli.query(`select to_jsonb(public.${m[1]}(${ks.map((k, i) => `${k} => $${i + 1}`).join(',')})) as r`, vals);
      await cli.query('commit');
      res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(r.rows[0].r));
    } catch (e) {
      await cli.query('rollback').catch(()=>{});
      res.writeHead(400, { 'content-type': 'application/json' }); res.end(JSON.stringify({ message: e.message }));
    } finally { cli.release(); }
    return;
  }
  // Imita la Edge Function de recuperar contraseña: crea el enlace como el servidor
  // (service_role) y en vez de mandar el correo lo guarda para la prueba.
  if (url.pathname === '/functions/v1/recuperar-contrasena-gymbro' && req.method === 'POST') {
    const cli = await pool.connect();
    try {
      await cli.query('set role service_role');
      const b = JSON.parse(body);
      let r = await cli.query(`select public.${b.bienvenida ? 'bienvenida_crear_gymbro' : 'recuperar_crear_gymbro'}($1) as e`, [b.email]);
      if (!r.rows[0].e && b.bienvenida) r = await cli.query('select public.recuperar_crear_gymbro($1) as e', [b.email]);
      ultimoEnlace = r.rows[0].e;
    } catch (e) { console.error(e.message); } finally { await cli.query('reset role').catch(()=>{}); cli.release(); }
    res.writeHead(200, { 'content-type': 'application/json' }); res.end('{"ok":true}'); return;
  }
  if (url.pathname === '/__ultimo_enlace') { res.writeHead(200); res.end(JSON.stringify(ultimoEnlace)); return; }
  let f = path.join(RAIZ, url.pathname.endsWith('/') ? url.pathname + 'index.html' : url.pathname);
  if (!f.startsWith(RAIZ) || !fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': tipos[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
}).listen(PUERTO, () => console.log('listo ' + PUERTO));
