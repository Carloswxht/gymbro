// Prueba de la v112: al pulsar «Finalizar» sale una ventana propia (no el
// confirm() del navegador) con letra grande y solo «Confirma si terminaste
// el entreno de hoy.». «No» o tocar fuera no guarda; «Sí, terminé» guarda.
// Base «login» recién montada; Carlos (clave-prueba-1) con la privacidad aceptada.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const OUT = process.argv[2], B = 'http://127.0.0.1:8091';
const sql = q => execSync(`psql -h /var/tmp/gympg -p 5445 -U postgres -d login -Atc "${q}"`).toString().trim();
const entrenos = () => Number(sql(`select count(*) from gymbro.entrenos_gymbro e join comun.usuarios u on u.id = e.usuario_id where u.email = 'carloswxht+war300@gmail.com'`));
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
    const u = new URL(r.request().url());
    const resp = await fetch(B + u.pathname + u.search, { method: r.request().method(), headers: (h => ({ 'content-type': 'application/json', ...(h.authorization ? { authorization: h.authorization } : {}) }))(r.request().headers()), body: r.request().method() === 'GET' ? undefined : (r.request().postData() || '{}') });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  const page = await ctx.newPage(); const errores = []; let dialogos = 0;
  page.on('pageerror', e => errores.push(e.message));
  page.on('dialog', d => { dialogos++; d.dismiss(); });
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const visible = () => page.isVisible('#finConfirm');

  await page.goto(B + '/?g=war300'); await page.waitForTimeout(1200);
  await page.fill('#authEmail', 'carloswxht+war300@gmail.com'); await page.fill('#authPass', 'clave-prueba-1'); await page.click('#authSubmit'); await page.waitForTimeout(3000);
  if (await page.isVisible('#legalGate')) { await page.check('#legalCheck'); await page.click('#legalAceptar'); await page.waitForTimeout(800); }
  await page.click('#tcStartBtn'); await page.waitForTimeout(1500);
  const antes = entrenos();

  await paso('1 sin nada marcado: avisa y no sale la ventana', async () => {
    await page.click('#continueBtn'); await page.waitForTimeout(500);
    if (await visible()) throw new Error('salió la ventana');
  });
  await paso('2 con un ejercicio hecho: ventana propia, solo la frase, letra grande', async () => {
    await page.click('.rt-check[data-done]'); await page.waitForTimeout(600);
    await page.click('#continueBtn'); await page.waitForTimeout(500);
    if (!await visible()) throw new Error('no salió');
    const t = (await page.textContent('#finTxt')).trim();
    if (t !== 'Confirma si terminaste el entreno de hoy.') throw new Error(t);
    const px = await page.evaluate(() => parseFloat(getComputedStyle(document.getElementById('finTxt')).fontSize));
    if (px < 22) throw new Error('letra ' + px);
    if (dialogos) throw new Error('salió el confirm() del navegador');
    await page.screenshot({ path: `${OUT}/fin1-ventana.png` });
  });
  await paso('3 «No»: se cierra, sigue en el entreno y no guarda', async () => {
    await page.click('#finNo'); await page.waitForTimeout(800);
    if (await visible() || entrenos() !== antes || !(await page.textContent('#continueBtn')).includes('Finalizar')) throw new Error('mal');
  });
  await paso('4 tocar fuera de la ventana cuenta como «No»', async () => {
    await page.click('#continueBtn'); await page.waitForTimeout(500);
    await page.mouse.click(195, 60); await page.waitForTimeout(800);
    if (await visible() || entrenos() !== antes) throw new Error('mal');
  });
  await paso('5 «Sí, terminé»: guarda el entreno y enseña el resumen', async () => {
    await page.click('#continueBtn'); await page.waitForTimeout(500);
    await page.click('#finSi'); await page.waitForTimeout(3000);
    if (await visible()) throw new Error('la ventana sigue');
    if (entrenos() !== antes + 1) throw new Error('entrenos ' + antes + ' → ' + entrenos());
    await page.screenshot({ path: `${OUT}/fin2-guardado.png` });
  });
  console.log(errores.length ? 'ERRORES: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
