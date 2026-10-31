// Prueba de la v105: letras guardadas en la web (nada a Google) y pie con la
// versión y «Creado por autonomIA Lab», como en la carta de MultiBar.
// Necesita: War300 y Carlos (clave-prueba-1), sin haber aceptado la versión 2026-10-20.2.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = process.argv[2];
const B = 'http://127.0.0.1:8091';
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  const aGoogle = [];
  ctx.on('request', r => { if (/google/.test(new URL(r.url()).hostname)) aGoogle.push(r.url()); });
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
    const u = new URL(r.request().url());
    const resp = await fetch(B + u.pathname + u.search, { method: r.request().method(), headers: (h => ({ 'content-type': 'application/json', ...(h.authorization ? { authorization: h.authorization } : {}) }))(r.request().headers()), body: r.request().method() === 'GET' ? undefined : (r.request().postData() || '{}') });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  const page = await ctx.newPage(); const errores = [];
  page.on('pageerror', e => errores.push(e.message));
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const letras = () => page.evaluate(async () => { await document.fonts.ready;
    return [...document.fonts].filter(f => f.status === 'loaded').map(f => f.family.replace(/"/g, '') + ' ' + f.weight); });

  await paso('1 entrada: letras de la web y pie con versión y firma', async () => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(1500);
    const l = await letras();
    if (!l.some(x => x.startsWith('Archivo Black')) || !l.some(x => x.startsWith('Archivo 4'))) throw new Error('letras: ' + l.join(', '));
    const pie = await page.textContent('#authGate .pie-app');
    if (!pie.includes('Gymbro v109') || !pie.includes('Creado por autonomIA Lab')) throw new Error(pie);
    if (await page.getAttribute('#authGate .pie-firma a', 'href') !== 'https://www.autonomialab.es') throw new Error('enlace');
    await page.screenshot({ path: `${OUT}/v1-entrada.png` });
  });
  await paso('2 dentro: pide aceptar la privacidad nueva; el pie sale abajo del todo', async () => {
    await page.fill('#authEmail', 'carloswxht+war300@gmail.com'); await page.fill('#authPass', 'clave-prueba-1'); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    if (!(await page.isVisible('#legalGate'))) throw new Error('no pidió aceptar la versión nueva');
    await page.check('#legalCheck'); await page.click('#legalAceptar'); await page.waitForTimeout(1000);
    if (!(await page.isVisible('#pieApp'))) throw new Error('sin pie');
    if ((await page.textContent('#pieApp .pie-version')) !== 'Gymbro v109') throw new Error('versión');
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight)); await page.waitForTimeout(400);
    await page.screenshot({ path: `${OUT}/v2-abajo.png` });
  });
  await paso('3 privacidad: ya no nombra a Google; versión nueva', async () => {
    await page.goto(B + '/legal/?g=war300'); await page.waitForTimeout(1000);
    const t = await page.textContent('main');
    if (/Google/.test(t)) throw new Error('nombra a Google');
    if (!t.includes('20 de octubre de 2026')) throw new Error('fecha');
  });
  await paso('4 panel del dueño: letras de la web', async () => {
    await page.goto(B + '/panel/?g=war300'); await page.waitForTimeout(1500);
    const l = await letras(); if (!l.some(x => x.startsWith('Archivo Black'))) throw new Error('letras: ' + l.join(', '));
  });
  await paso('5 ninguna página ha pedido nada a Google', async () => {
    if (aGoogle.length) throw new Error(aGoogle.join(' '));
  });
  console.log(errores.length ? 'ERRORES DE PÁGINA: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
