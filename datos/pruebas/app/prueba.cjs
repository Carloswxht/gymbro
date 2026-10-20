const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = process.argv[2];
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  const errores = [];
  page.on('pageerror', e => errores.push('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errores.push('console: ' + m.text()); });
  page.on('dialog', d => d.accept());
  await ctx.route('https://fonts.googleapis.com/**', r => r.abort());
  await ctx.route('https://fonts.gstatic.com/**', r => r.abort());
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/rest/v1/rpc/**', async r => {
    const u = new URL(r.request().url());
    const resp = await fetch('http://127.0.0.1:8091' + u.pathname, { method: 'POST', body: r.request().postData() || '{}' });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const cap = n => page.screenshot({ path: `${OUT}/${n}.png` });
  const gateVisible = () => page.evaluate(() => !document.getElementById('authGate').classList.contains('hidden'));

  await page.goto('http://127.0.0.1:8091/?g=war300');
  await page.waitForTimeout(800);
  await paso('1 sin sesión sale la entrada', async () => { if (!await gateVisible()) throw new Error('no'); await cap('01-entrar'); });
  await paso('2 contraseña mal', async () => {
    await page.fill('#authEmail', 'carloswxht+war300@gmail.com'); await page.fill('#authPass', 'mala-clave');
    await page.click('#authSubmit'); await page.waitForTimeout(800);
    const m = await page.textContent('#authMsg'); if (!m.includes('incorrectos')) throw new Error(m); await cap('02-error');
  });
  await paso('3 entra con su cuenta', async () => {
    await page.fill('#authPass', 'clave-prueba-1'); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    if (await gateVisible()) throw new Error('sigue en la entrada'); await cap('03-dentro');
  });
  await paso('4 datos cargados (16 entrenos, progreso, tema)', async () => {
    const r = await page.evaluate(async () => { const e = await selEntrenos(); return { n: e.data.length, user: currentUser.email, work: Object.keys(workData).length }; });
    if (r.n !== 16 || r.work < 50) throw new Error(JSON.stringify(r)); console.log('    ', JSON.stringify(r));
  });
  await paso('5 guardar un peso y releerlo', async () => {
    const r = await page.evaluate(async () => {
      const k = Object.keys(workData)[0]; workData[k] = { ...workData[k], peso: 77.5 }; await persistState(true);
      const d = await leerMisDatos(); return d.data.progreso.find(p => p.work_key === k);
    });
    if (!r || Number(r.peso) !== 77.5) throw new Error(JSON.stringify(r));
  });
  await paso('6 guardar un entreno', async () => {
    const r = await page.evaluate(async () => { const g = await guardarEntreno({ fecha: '2026-10-19', resumen: [{ exName: 'Prueba', peso: 1 }], dia: 1 }); const e = await selEntrenos({ orden: 'desc', limite: 1 }); return { g: g.error && g.error.message, top: e.data[0].fecha, n: (await selEntrenos()).data.length }; });
    if (r.g || r.n !== 17) throw new Error(JSON.stringify(r));
  });
  await paso('7 al recargar sigue dentro', async () => {
    await page.reload(); await page.waitForTimeout(2500); if (await gateVisible()) throw new Error('pidió entrar'); await cap('04-recargar');
  });
  await paso('8 ajustes con versión', async () => {
    const v = await page.textContent('#appVersion'); if (v !== 'Gymbro v103') throw new Error(v);
    await page.evaluate(() => document.getElementById('settingsOverlay').classList.add('open')); await page.waitForTimeout(400);
    await page.evaluate(() => { const s = document.querySelector('#settingsOverlay .settings-sheet'); s.scrollTop = s.scrollHeight; }); await page.waitForTimeout(300); await cap('05-ajustes');
    await page.evaluate(() => document.getElementById('settingsOverlay').classList.remove('open'));
  });
  await paso('9 salir', async () => {
    await page.evaluate(() => document.getElementById('logoutBtn').click()); await page.waitForTimeout(2000);
    if (!await gateVisible()) throw new Error('no salió');
    const t = await page.evaluate(() => localStorage.getItem('gymbro.sesion.war300')); if (t) throw new Error('token sigue');
  });
  await paso('10 crear cuenta nueva', async () => {
    await page.click('#authSwitch'); await page.fill('#authEmail', 'nueva@ejemplo.test'); await page.fill('#authPass', 'clave-nueva-1'); await page.fill('#authPass2', 'clave-nueva-1');
    await cap('06-crear'); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    if (await gateVisible()) throw new Error(await page.textContent('#authMsg')); await cap('07-nueva-dentro');
    const n = await page.evaluate(async () => ({ e: (await selEntrenos()).data.length, w: Object.keys(workData).filter(k => workData[k].peso != null).length }));
    if (n.e !== 0 || n.w !== 0) throw new Error('ve datos de otra cuenta: ' + JSON.stringify(n));
    const nav = await page.evaluate(() => Object.keys(localStorage)); console.log('     localStorage:', nav.join(', '));
  });
  await paso('11 ejercicio propio con enlace', async () => {
    const r = await page.evaluate(async () => { const sub = Object.keys(SUB_INDEX)[0]; openAddExerciseModal(sub); document.getElementById('addExName').value = 'Mi ejercicio ejemplo'; document.getElementById('addExVideo').value = 'youtu.be/abc'; await saveCustomExercise(); const d = await leerMisDatos(); return d.data.personalizados; });
    if (r.length !== 1 || r[0].video_url !== 'https://youtu.be/abc') throw new Error(JSON.stringify(r));
  });
  await paso('12 borrar cuenta (mal y bien)', async () => {
    await page.evaluate(() => document.getElementById('deleteConfirmOverlay').classList.add('open')); await page.waitForTimeout(300);
    await page.fill('#deletePass', 'otra'); await cap('08-borrar'); await page.click('#confirmDeleteDataBtn'); await page.waitForTimeout(800);
    if (await gateVisible()) throw new Error('borró con contraseña mala');
    await page.fill('#deletePass', 'clave-nueva-1'); await page.click('#confirmDeleteDataBtn'); await page.waitForTimeout(2500);
    if (!await gateVisible()) throw new Error('no volvió a la entrada');
    await page.fill('#authEmail', 'nueva@ejemplo.test'); await page.fill('#authPass', 'clave-nueva-1');
    if (await page.evaluate(() => authMode) !== 'signin') await page.click('#authSwitch');
    await page.click('#authSubmit'); await page.waitForTimeout(800);
    const m = await page.textContent('#authMsg'); if (!m.includes('incorrectos')) throw new Error('aún entra: ' + m);
  });
  console.log(errores.length ? 'ERRORES:\n' + errores.join('\n') : 'sin errores en consola');
  await browser.close();
})();
