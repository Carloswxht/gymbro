// Prueba del login de Supabase (v107) en la app, el panel del dueño y la
// plataforma, contra el Supabase simulado sobre la base «login»
// (datos/pruebas/montar-base-login.sh; servidor con PGDATABASE=login).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const OUT = process.argv[2];
const B = 'http://127.0.0.1:8091';
const sql = q => execSync(`psql -h /var/tmp/gympg -p 5445 -U postgres -d login -Atc "${q.replace(/"/g, '\\"')}"`).toString().trim();
const errores = [];
async function contexto(browser){
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
    const u = new URL(r.request().url()), h = r.request().headers();
    const resp = await fetch(B + u.pathname + u.search, { method: r.request().method(),
      headers: { 'content-type': 'application/json', ...(h.authorization ? { authorization: h.authorization } : {}) },
      body: r.request().method() === 'GET' ? undefined : (r.request().postData() || '{}') });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  return ctx;
}
(async () => {
  const browser = await chromium.launch();
  let ctx = await contexto(browser), page;
  const nueva = async () => { page = await ctx.newPage(); page.on('pageerror', e => errores.push(e.message)); return page; };
  const otroMovil = async () => { await ctx.close(); ctx = await contexto(browser); return nueva(); };
  await nueva();
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const cap = n => page.screenshot({ path: `${OUT}/${n}.png` });
  const entrar = async (email, clave, g = 'war300') => {
    await page.goto(B + '/?g=' + g); await page.waitForTimeout(1200);
    await page.fill('#authEmail', email); await page.fill('#authPass', clave); await page.click('#authSubmit'); await page.waitForTimeout(2800);
  };
  const dentro = () => page.isHidden('#authGate');
  const msg = () => page.textContent('#authMsg');
  const claves = () => page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('gymbro.')).sort().join(' '));
  const antes = sql("select count(*) || '/' || (select count(*) from gymbro.progreso_gymbro where usuario_id = u.id) from gymbro.entrenos_gymbro e join comun.usuarios u on u.id = e.usuario_id where u.email = 'carloswxht+war300@gmail.com' group by u.id");

  await paso('1 contraseña mala: «Correo o contraseña incorrectos.»; buena (con punto del dictado): entra con su historial', async () => {
    await entrar('carloswxht+war300@gmail.com', 'mala');
    if (await dentro() || !(await msg()).includes('incorrectos')) throw new Error(await msg());
    await entrar('carloswxht+war300@gmail.com.', 'clave-prueba-1');
    if (!(await dentro())) throw new Error('no entró: ' + await msg());
    const t = await page.textContent('.tc-title'); if (!t.includes('Pierna y core')) throw new Error(t);
    const k = await claves(); if (!k.includes('gymbro.sb.war300') || k.includes('gymbro.sesion.war300 ')) throw new Error(k);
    await cap('l1-dentro');
  });
  await paso('2 al recargar sigue dentro (la sesión la guarda Supabase) y guarda pesos con su cuenta', async () => {
    await page.reload(); await page.waitForTimeout(2800);
    if (!(await dentro())) throw new Error('pidió entrar');
    await page.evaluate(async () => { const k = Object.keys(workData)[0]; workData[k] = { ...workData[k], peso: 82.5 }; await persistState(true); });
    await page.waitForTimeout(800);
    const n = sql("select count(*) from gymbro.progreso_gymbro p join comun.usuarios u on u.id = p.usuario_id where u.email = 'carloswxht+war300@gmail.com' and p.peso = 82.5");
    if (n !== '1') throw new Error('peso no guardado: ' + n);
  });
  await paso('3 la sesión caducada se renueva sola (sigue dentro y guardando)', async () => {
    await page.evaluate(() => { const k = 'gymbro.sb.war300'; const s = JSON.parse(localStorage.getItem(k)); s.expires_at = Math.floor(Date.now() / 1000) - 60; localStorage.setItem(k, JSON.stringify(s)); });
    await page.reload(); await page.waitForTimeout(2800);
    if (!(await dentro())) throw new Error('pidió entrar');
    const r = await page.evaluate(async () => (await api('yo_gymbro', {})).email);
    if (r !== 'carloswxht+war300@gmail.com') throw new Error(r);
  });
  await paso('4 salir: borra la sesión del móvil y vuelve a pedir entrar', async () => {
    await page.evaluate(() => document.getElementById('logoutBtn').click()); await page.waitForTimeout(2500);
    if (await dentro()) throw new Error('sigue dentro');
    if ((await claves()).includes('gymbro.sb.war300')) throw new Error('quedó la sesión: ' + await claves());
    await page.reload(); await page.waitForTimeout(1500); if (await dentro()) throw new Error('dentro tras recargar');
  });
  await paso('5 cuenta de otro gimnasio y cuenta de un bar: no entran en War300 (mismo aviso) ni dejan sesión', async () => {
    for (const [e, c] of [['luna@ejemplo.test', 'clave-luna-1'], ['camarero@ejemplo.test', 'clave-camarero']]) {
      await entrar(e, c);
      if (await dentro()) throw new Error(e + ' entró');
      if (!(await msg()).includes('incorrectos')) throw new Error(e + ': ' + await msg());
      const s = await page.evaluate(() => localStorage.getItem('gymbro.sb.war300'));
      if (s) throw new Error(e + ' dejó sesión');
    }
  });
  await paso('6 quien venía de la v106 (sesión propia guardada) entra una vez más y la vieja se borra', async () => {
    await otroMovil();
    const tk = sql("select public.entrar_gymbro('war300','usuarioswxht@gmail.com','clave-prueba-1')->>'token'");
    await page.goto(B + '/inicio/'); await page.evaluate(t => localStorage.setItem('gymbro.sesion.war300', t), tk);
    await page.goto(B + '/'); await page.waitForTimeout(1500);
    if (new URL(page.url()).search !== '?g=war300') throw new Error('no fue a su gimnasio: ' + page.url());
    if (await dentro()) throw new Error('entró con la sesión vieja');
    if ((await claves()).includes('gymbro.sesion.war300 ') || (await page.evaluate(() => localStorage.getItem('gymbro.sesion.war300')))) throw new Error('no borró la vieja');
    await cap('l2-entrar-otra-vez');
  });
  await paso('7 crear cuenta en Gym Luna (registro libre): entra directa, con su cuenta de Supabase y la privacidad aceptada', async () => {
    await page.goto(B + '/?g=gym-luna'); await page.waitForTimeout(1200);
    await page.click('#authSwitch');
    await page.fill('#authEmail', 'Nueva-Socia@Ejemplo.test. '); await page.fill('#authPass', 'clave-nueva-1'); await page.fill('#authPass2', 'clave-nueva-1');
    await page.check('#authAceptoCheck'); await page.click('#authSubmit'); await page.waitForTimeout(3500);
    if (!(await dentro())) throw new Error('no entró: ' + await msg());
    if (await page.isVisible('#legalGate')) throw new Error('le pide aceptar otra vez');
    const r = sql("select (u.auth_id is not null)::text || '/' || (select count(*) from gymbro.consentimientos_gymbro c where c.usuario_id = u.id) from comun.usuarios u where u.email = 'nueva-socia@ejemplo.test'");
    if (r !== 'true/1') throw new Error(r);
  });
  await paso('8 crear cuenta con un correo que ya existe: «Ese correo ya tiene una cuenta»', async () => {
    await otroMovil(); await page.goto(B + '/?g=gym-luna'); await page.waitForTimeout(1200);
    await page.click('#authSwitch');
    await page.fill('#authEmail', 'camarero@ejemplo.test'); await page.fill('#authPass', 'clave-nueva-1'); await page.fill('#authPass2', 'clave-nueva-1');
    await page.check('#authAceptoCheck'); await page.click('#authSubmit'); await page.waitForTimeout(1500);
    if (!(await msg()).includes('ya tiene una cuenta')) throw new Error(await msg());
  });
  await paso('9 recuperar la contraseña (v108: correo de Supabase): la nueva vale para entrar con Supabase', async () => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(1200);
    await page.click('#authForgot'); await page.fill('#authEmail', 'usuarioswxht@gmail.com'); await page.click('#authSubmit'); await page.waitForTimeout(1200);
    const e = await (await fetch(B + '/__ultimo_enlace')).json();
    await page.goto('about:blank'); await page.goto(e.enlace); await page.waitForTimeout(1500);
    await page.fill('#authPass', 'clave-cambiada-9'); await page.fill('#authPass2', 'clave-cambiada-9'); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    if (!(await dentro())) throw new Error('no entró al guardar: ' + await msg());
    await otroMovil(); await page.goto(B + '/?g=war300'); await page.waitForTimeout(1200);
    await page.fill('#authEmail', 'usuarioswxht@gmail.com'); await page.fill('#authPass', 'clave-prueba-1'); await page.click('#authSubmit'); await page.waitForTimeout(1500);
    if (await dentro()) throw new Error('entró con la vieja');
    await page.fill('#authPass', 'clave-cambiada-9'); await page.click('#authSubmit'); await page.waitForTimeout(2800);
    if (!(await dentro())) throw new Error('no entró con la nueva: ' + await msg());
  });
  await paso('10 panel del dueño: con la sesión de la app entra directo; un socio no (SIN_PERMISO); otra dueña ve solo lo suyo', async () => {
    await otroMovil(); await entrar('carloswxht+war300@gmail.com', 'clave-prueba-1');
    await page.goto(B + '/panel/?g=war300'); await page.waitForTimeout(1800);
    if (!(await page.isVisible('#vPanel'))) throw new Error('no entró directo');
    await cap('l3-panel');
    await otroMovil(); await page.goto(B + '/panel/?g=war300'); await page.waitForTimeout(1200);
    await page.fill('#eCorreo', 'usuarioswxht@gmail.com'); await page.fill('#eClave', 'clave-cambiada-9'); await page.click('#eEntrar'); await page.waitForTimeout(1800);
    if (await page.isVisible('#vPanel') || !(await page.textContent('#eMsg')).includes('administración')) throw new Error('socio: ' + await page.textContent('#eMsg'));
    await otroMovil(); await page.goto(B + '/panel/?g=gym-luna'); await page.waitForTimeout(1200);
    await page.fill('#eCorreo', 'luna@ejemplo.test'); await page.fill('#eClave', 'clave-luna-1'); await page.click('#eEntrar'); await page.waitForTimeout(1800);
    const t = await page.textContent('#vPanel'); if (!t.includes('nueva-socia@ejemplo.test') || t.includes('usuarioswxht')) throw new Error('lista de socios');
    await page.goto(B + '/panel/?g=war300'); await page.waitForTimeout(1500);
    if (await page.isVisible('#vPanel')) throw new Error('la dueña de Luna entró en el panel de War300');
  });
  await paso('11 plataforma: entra la cuenta de plataforma; la de un gimnasio no; su sesión va aparte de la app', async () => {
    await otroMovil(); await entrar('carloswxht+war300@gmail.com', 'clave-prueba-1');
    await page.goto(B + '/plataforma/'); await page.waitForTimeout(1000);
    await page.fill('#eEmail', 'carloswxht+war300@gmail.com'); await page.fill('#ePass', 'clave-prueba-1'); await page.click('#fEntrar button[type=submit]'); await page.waitForTimeout(1500);
    if (await page.isVisible('#vLista')) throw new Error('entró una cuenta de gimnasio');
    await page.fill('#eEmail', 'plataforma@ejemplo.test'); await page.fill('#ePass', 'clave-plataforma'); await page.click('#fEntrar button[type=submit]'); await page.waitForTimeout(1800);
    if (!(await page.isVisible('#vLista'))) throw new Error('no entró: ' + await page.textContent('#eError'));
    const t = await page.textContent('#lLista'); if (!t.includes('War300') || !t.includes('Gym Luna')) throw new Error(t);
    await cap('l4-plataforma');
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(2500);
    if (!(await dentro())) throw new Error('la app perdió su sesión');
    await page.goto(B + '/plataforma/'); await page.waitForTimeout(1500);
    if (!(await page.isVisible('#vLista'))) throw new Error('la plataforma perdió su sesión');
    await page.click('#bSalir'); await page.waitForTimeout(800);
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(2500);
    if (!(await dentro())) throw new Error('salir de la plataforma sacó de la app');
  });
  await paso('12 historial de Carlos intacto (entrenos y filas: los de antes; el peso de la prueba 2 es una fila que ya existía)', async () => {
    const despues = sql("select count(*) || '/' || (select count(*) from gymbro.progreso_gymbro where usuario_id = u.id) from gymbro.entrenos_gymbro e join comun.usuarios u on u.id = e.usuario_id where u.email = 'carloswxht+war300@gmail.com' group by u.id");
    console.log('    antes ' + antes + ' · después ' + despues);
    if (antes.split('/')[0] !== despues.split('/')[0]) throw new Error('entrenos cambiaron');
  });
  console.log(errores.length ? 'ERRORES DE PÁGINA: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
