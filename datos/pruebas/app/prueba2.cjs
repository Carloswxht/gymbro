const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = process.argv[2];
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  const page = await ctx.newPage(); const errores = [];
  page.on('pageerror', e => errores.push(e.message));
  await ctx.route('https://fonts.*/**', r => r.abort());
  await ctx.route('https://fonts.gstatic.com/**', r => r.abort());
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/rest/v1/rpc/**', async r => {
    const u = new URL(r.request().url());
    const resp = await fetch('http://127.0.0.1:8091' + u.pathname + u.search, { method: r.request().method(), headers: (h => ({ 'content-type': 'application/json', ...(h.authorization ? { authorization: h.authorization } : {}) }))(r.request().headers()), body: r.request().method() === 'GET' ? undefined : (r.request().postData() || '{}') });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  await page.goto('http://127.0.0.1:8091/'); await page.waitForTimeout(800);
  await page.fill('#authEmail', 'carloswxht+war300@gmail.com'); await page.fill('#authPass', 'clave-prueba-1');
  await page.click('#authSubmit'); await page.waitForTimeout(2500);
  for (const [n, f] of [['09-historial', 'goToStatsDaily'], ['10-periodo', 'goToStatsPeriod'], ['11-ejercicio', 'goToStatsExercise']]) {
    await page.evaluate(f => window[f](), f); await page.waitForTimeout(1500); await page.screenshot({ path: `${OUT}/${n}.png` });
  }
  console.log(errores.length ? 'ERRORES: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
