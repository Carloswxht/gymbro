// Prueba de «¿Has olvidado tu contraseña?» (v98) contra el Supabase simulado.
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
    const resp = await fetch('http://127.0.0.1:8091' + u.pathname + u.search, { method: r.request().method(), headers: (h => ({ 'content-type': 'application/json', ...(h.authorization ? { authorization: h.authorization } : {}) }))(r.request().headers()), body: r.request().method() === 'GET' ? undefined : (r.request().postData() || '{}') });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const msg = () => page.textContent('#authMsg');
  const vis = s => page.isVisible(s);
  await page.goto('http://127.0.0.1:8091/?g=war300'); await page.waitForTimeout(800);
  await paso('1 se ve el enlace «¿Has olvidado…?»', async () => { if (!await vis('#authForgot')) throw new Error('no'); await page.screenshot({ path: `${OUT}/r1-entrar.png` }); });
  await paso('2 correo con espacio', async () => {
    await page.fill('#authEmail', 'carloswxht+war300@gmail.com y'); await page.fill('#authPass', 'x'); await page.click('#authSubmit'); await page.waitForTimeout(300);
    if (!(await msg()).includes('espacio')) throw new Error(await msg());
  });
  await paso('3 pantalla de recuperar', async () => {
    await page.click('#authForgot span'); await page.waitForTimeout(200);
    if (await vis('#authPass') || await vis('#authPass2') || await vis('#authForgot')) throw new Error('sobran campos');
    await page.fill('#authEmail', 'carloswxht+war300@gmail.com'); await page.screenshot({ path: `${OUT}/r2-recuperar.png` });
    await page.click('#authSubmit'); await page.waitForTimeout(800);
    if (!(await msg()).includes('te llegará')) throw new Error(await msg()); await page.screenshot({ path: `${OUT}/r3-mandado.png` });
  });
  let token;
  await paso('4 se creó el enlace', async () => { const e = await (await fetch('http://127.0.0.1:8091/__ultimo_enlace')).json(); token = e && e.token; if (!token) throw new Error(JSON.stringify(e)); });
  await paso('5 el enlace abre «Contraseña nueva»', async () => {
    await page.goto('about:blank'); await page.goto('http://127.0.0.1:8091/?g=war300#recuperar=' + token); await page.waitForTimeout(800);
    if ((await page.textContent('#authTitle')) !== 'Contraseña nueva' || await vis('#authEmail') || !await vis('#authPass2')) throw new Error('pantalla mal');
    if (page.url().includes('recuperar')) throw new Error('el código sigue en la dirección'); await page.screenshot({ path: `${OUT}/r4-nueva.png` });
  });
  await paso('6 no coinciden / corta', async () => {
    await page.fill('#authPass', 'nueva-clave-9'); await page.fill('#authPass2', 'otra'); await page.click('#authSubmit'); await page.waitForTimeout(200);
    if (!(await msg()).includes('no coinciden')) throw new Error(await msg());
    await page.fill('#authPass', 'corta'); await page.fill('#authPass2', 'corta'); await page.click('#authSubmit'); await page.waitForTimeout(200);
    if (!(await msg()).includes('8 caracteres')) throw new Error(await msg());
  });
  await paso('7 guarda y vuelve a entrar con la nueva', async () => {
    await page.fill('#authPass', 'nueva-clave-9'); await page.fill('#authPass2', 'nueva-clave-9'); await page.click('#authSubmit'); await page.waitForTimeout(1000);
    if (!(await msg()).includes('Contraseña cambiada') || (await page.inputValue('#authEmail')) !== 'carloswxht+war300@gmail.com') throw new Error(await msg());
    await page.screenshot({ path: `${OUT}/r5-cambiada.png` });
    await page.fill('#authPass', 'nueva-clave-9'); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    if (await page.evaluate(() => !document.getElementById('authGate').classList.contains('hidden'))) throw new Error('no entró');
  });
  await paso('8 el mismo enlace ya no vale', async () => {
    await page.evaluate(() => localStorage.clear()); await page.goto('about:blank');
    await page.goto('http://127.0.0.1:8091/?g=war300#recuperar=' + token); await page.waitForTimeout(800);
    await page.fill('#authPass', 'otra-clave-99'); await page.fill('#authPass2', 'otra-clave-99'); await page.click('#authSubmit'); await page.waitForTimeout(800);
    if (!(await msg()).includes('caducado')) throw new Error(await msg()); await page.screenshot({ path: `${OUT}/r6-caducado.png` });
  });
  console.log(errores.length ? 'ERRORES: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
