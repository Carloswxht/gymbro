// Supabase simulado: sirve la web y responde /rest/v1/rpc/* con la base local como «anon».
import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path'; import pg from 'pg';
const RAIZ = process.argv[2], PUERTO = 8091;
let ultimoEnlace = null;
const pool = new pg.Pool({ host: process.env.PGHOST, port: 5445, user: 'postgres', database: 'prueba' }); pool.on('error', e => console.error('pool', e.message));
const tipos = { '.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.png':'image/png', '.mp4':'video/mp4' };
http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const m = url.pathname.match(/^\/rest\/v1\/rpc\/([a-z_]+)$/);
  if (m && req.method === 'POST') {
    let body = ''; for await (const c of req) body += c;
    const args = body ? JSON.parse(body) : {};
    const ks = Object.keys(args);
    const vals = ks.map(k => args[k] !== null && typeof args[k] === 'object' ? JSON.stringify(args[k]) : args[k]);
    const cli = await pool.connect();
    try {
      await cli.query('set role anon');
      const r = await cli.query(`select to_jsonb(public.${m[1]}(${ks.map((k, i) => `${k} => $${i + 1}`).join(',')})) as r`, vals);
      res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(r.rows[0].r));
    } catch (e) {
      res.writeHead(400, { 'content-type': 'application/json' }); res.end(JSON.stringify({ message: e.message }));
    } finally { await cli.query('reset role').catch(()=>{}); cli.release(); }
    return;
  }
  // Imita la Edge Function de recuperar contraseña: crea el enlace como el servidor
  // (service_role) y en vez de mandar el correo lo guarda para la prueba.
  if (url.pathname === '/functions/v1/recuperar-contrasena-gymbro' && req.method === 'POST') {
    let body = ''; for await (const c of req) body += c;
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
