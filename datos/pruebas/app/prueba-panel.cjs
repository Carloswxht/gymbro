// Prueba del panel del dueño (v99) contra el Supabase simulado.
// Necesita: Carlos (clave-prueba-1) con rol admin y usuarioswxht (clave-prueba-1) socio.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = process.argv[2];
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  const page = await ctx.newPage(); const errores = [];
  page.on('pageerror', e => errores.push(e.message));
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
    const u = new URL(r.request().url());
    const resp = await fetch('http://127.0.0.1:8091' + u.pathname, { method: 'POST', body: r.request().postData() || '{}' });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const cap = n => page.screenshot({ path: `${OUT}/${n}.png` });
  const B = 'http://127.0.0.1:8091';
  let inicial = 0;
  await paso('1 un socio no entra en el panel', async () => {
    await page.goto(B + '/panel/?g=war300'); await page.waitForTimeout(800);
    await page.fill('#eCorreo', 'usuarioswxht@gmail.com'); await page.fill('#eClave', 'clave-prueba-1'); await page.click('#eEntrar'); await page.waitForTimeout(1000);
    const m = await page.textContent('#eMsg'); if (!m.includes('no es de administración')) throw new Error(m); await cap('p1-socio');
  });
  await paso('2 el dueño entra y ve a sus socios', async () => {
    await page.evaluate(() => localStorage.clear()); await page.goto(B + '/panel/?g=war300'); await page.waitForTimeout(800);
    await page.fill('#eCorreo', 'carloswxht+war300@gmail.com'); await page.fill('#eClave', 'clave-prueba-1'); await page.click('#eEntrar'); await page.waitForTimeout(1200);
    if (await page.isHidden('#vPanel')) throw new Error(await page.textContent('#eMsg'));
    inicial = await page.locator('.socio').count(); if (inicial < 2) throw new Error('socios: ' + inicial);
    if ((await page.textContent('#pVersion')) !== 'Panel v99') throw new Error('versión'); await cap('p2-panel');
  });
  await paso('3 dar de alta a un socio (manda invitación)', async () => {
    await page.click('#bAlta'); await page.fill('#aNombre', 'Socia ejemplo'); await page.fill('#aCorreo', 'socia@ejemplo.test'); await cap('p3-alta');
    await page.click('#aGuardar'); await page.waitForTimeout(1500);
    const n = await page.locator('.socio').count(); if (n !== inicial + 1) throw new Error('socios: ' + n);
    const e = await (await fetch(B + '/__ultimo_enlace')).json(); if (!e || !e.bienvenida || e.email !== 'socia@ejemplo.test') throw new Error(JSON.stringify(e));
    await cap('p4-tras-alta');
  });
  await paso('4 alta repetida da error', async () => {
    await page.click('#bAlta'); await page.fill('#aNombre', 'Otra'); await page.fill('#aCorreo', 'socia@ejemplo.test'); await page.click('#aGuardar'); await page.waitForTimeout(800);
    if (!(await page.textContent('#aMsg')).includes('ya tiene')) throw new Error(await page.textContent('#aMsg')); await page.click('.cerrar');
  });
  await paso('5 la socia invitada elige su contraseña con el enlace y entra en la app', async () => {
    const e = await (await fetch(B + '/__ultimo_enlace')).json();
    // Otro móvil (otro navegador): si no, compartiría la sesión con el dueño.
    const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 }, serviceWorkers: 'block' });
    await ctx2.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
    await ctx2.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
      const u = new URL(r.request().url());
      const resp = await fetch('http://127.0.0.1:8091' + u.pathname, { method: 'POST', body: r.request().postData() || '{}' });
      r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
    });
    const p2 = await ctx2.newPage(); await p2.goto(B + '/?g=war300#recuperar=' + e.token); await p2.waitForTimeout(800);
    await p2.fill('#authPass', 'clave-socia-1'); await p2.fill('#authPass2', 'clave-socia-1'); await p2.click('#authSubmit'); await p2.waitForTimeout(800);
    await p2.fill('#authPass', 'clave-socia-1'); await p2.click('#authSubmit'); await p2.waitForTimeout(2500);
    if (await p2.evaluate(() => !document.getElementById('authGate').classList.contains('hidden'))) throw new Error('no entró');
    await ctx2.close();
  });
  await paso('6 dar de baja (con confirmación) y reactivar', async () => {
    await page.reload(); await page.waitForTimeout(1200);
    await page.locator('.socio', { hasText: 'usuarioswxht' }).click(); await page.waitForTimeout(300); await cap('p5-ficha');
    await page.click('[data-accion="baja"]'); await page.waitForTimeout(200); await cap('p6-confirmar');
    await page.click('#cSi'); await page.waitForTimeout(1200);
    if (!(await page.locator('.socio', { hasText: 'usuarioswxht' }).textContent()).includes('De baja')) throw new Error('no salió de baja');
    await cap('p7-baja');
    await page.locator('.socio', { hasText: 'usuarioswxht' }).click(); await page.click('[data-accion="reactivar"]'); await page.click('#cSi'); await page.waitForTimeout(1200);
    if ((await page.locator('.socio', { hasText: 'usuarioswxht' }).textContent()).includes('De baja')) throw new Error('no se reactivó');
  });
  await paso('7 hacer admin y quitarlo', async () => {
    await page.locator('.socio', { hasText: 'usuarioswxht' }).click(); await page.click('[data-accion="hacer-admin"]'); await page.click('#cSi'); await page.waitForTimeout(1200);
    if (!(await page.locator('.socio', { hasText: 'usuarioswxht' }).textContent()).includes('Admin')) throw new Error('no es admin');
    await page.locator('.socio', { hasText: 'usuarioswxht' }).click(); await page.click('[data-accion="quitar-admin"]'); await page.click('#cSi'); await page.waitForTimeout(1200);
  });
  await paso('8 la ficha propia no deja darse de baja', async () => {
    await page.locator('.socio', { hasText: 'carloswxht' }).click(); await page.waitForTimeout(300);
    if (await page.locator('[data-accion="baja"]').count()) throw new Error('sale «Dar de baja»'); await page.click('.cerrar');
  });
  await paso('9 cerrar el registro libre (y la app ya no deja crear cuenta)', async () => {
    await page.click('.interruptor'); await page.waitForTimeout(1000);
    if (!(await page.textContent('#dRegistro')).includes('Solo entra')) throw new Error('no cambió'); await cap('p8-registro-cerrado');
    const r = await page.evaluate(async () => (await fetch('https://dorunbacwnkwdatfscri.supabase.co/rest/v1/rpc/registrar_gymbro', { method: 'POST', body: JSON.stringify({ p_slug: 'war300', p_email: 'x@ejemplo.test', p_password: 'clave-xxx-1' }) })).json());
    if (r.message !== 'REGISTRO_CERRADO') throw new Error(JSON.stringify(r));
    await page.click('.interruptor'); await page.waitForTimeout(1000);
  });
  await paso('10 la app enseña «Panel del gimnasio» solo al admin', async () => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(2500);
    if (await page.evaluate(() => document.getElementById('panelLink').hidden)) throw new Error('el admin no ve el enlace');
    await page.evaluate(() => document.getElementById('settingsOverlay').classList.add('open')); await page.waitForTimeout(300);
    await page.evaluate(() => { const s = document.querySelector('#settingsOverlay .settings-sheet'); s.scrollTop = s.scrollHeight; }); await page.waitForTimeout(200); await cap('p9-ajustes-admin');
    await page.evaluate(() => localStorage.clear()); await page.reload(); await page.waitForTimeout(800);
    await page.fill('#authEmail', 'usuarioswxht@gmail.com'); await page.fill('#authPass', 'clave-prueba-1'); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    if (!await page.evaluate(() => document.getElementById('panelLink').hidden)) throw new Error('un socio ve el enlace');
  });
  console.log(errores.length ? 'ERRORES: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
