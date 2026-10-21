// Prueba de la página de Gymbro (v103): sin ?g= y sin gimnasio en el móvil se
// abre /inicio/; si el móvil ya conoce un gimnasio, va directo a él.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = process.argv[2];
const B = 'http://127.0.0.1:8091';
async function contexto(browser){
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
    const u = new URL(r.request().url());
    const resp = await fetch(B + u.pathname + u.search, { method: r.request().method(), headers: (h => ({ 'content-type': 'application/json', ...(h.authorization ? { authorization: h.authorization } : {}) }))(r.request().headers()), body: r.request().method() === 'GET' ? undefined : (r.request().postData() || '{}') });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  return ctx;
}
(async () => {
  const browser = await chromium.launch();
  let ctx = await contexto(browser);
  let page = await ctx.newPage(); const errores = [];
  const vigilar = p => p.on('pageerror', e => errores.push(e.message));
  vigilar(page);
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const ruta = () => { const u = new URL(page.url()); return u.pathname + u.search; };
  await paso('1 móvil nuevo: la dirección sola abre la página de Gymbro (estilo autonomIA Lab)', async () => {
    await page.goto(B + '/'); await page.waitForTimeout(1200);
    if (ruta() !== '/inicio/') throw new Error(ruta());
    await page.screenshot({ path: `${OUT}/i1-inicio.png`, fullPage: true });
    if (!(await page.textContent('h1')).includes('rutinas')) throw new Error('título');
    if (await page.getAttribute('.pie a', 'href') !== 'https://www.autonomialab.es') throw new Error('enlace');
  });
  await paso('2 el panel sin ?g= en un móvil nuevo también va a la página de Gymbro', async () => {
    await page.goto(B + '/panel/'); await page.waitForTimeout(1200);
    if (ruta() !== '/inicio/') throw new Error(ruta());
  });
  await paso('3 nombre corto mal escrito o que no existe: aviso; un bar tampoco vale', async () => {
    for (const [v, txt] of [['Mi Gym!', 'tal como'], ['no-existe', 'No encontramos'], ['bar-ejemplo', 'No encontramos']]) {
      await page.fill('#gSlug', v); await page.click('#gIr'); await page.waitForTimeout(700);
      if (!(await page.textContent('#gError')).includes(txt)) throw new Error(v + ': ' + await page.textContent('#gError'));
    }
    await page.screenshot({ path: `${OUT}/i2-inicio-error.png` });
  });
  await paso('4 nombre corto bueno (con mayúsculas y punto del dictado): abre su gimnasio', async () => {
    await page.fill('#gSlug', 'War300.'); await page.click('#gIr'); await page.waitForTimeout(1800);
    if (ruta() !== '/?g=war300') throw new Error(ruta());
    if ((await page.textContent('#authGate .marca-nombre')) !== 'War300') throw new Error('no es War300');
  });
  await paso('5 ya lo conoce: la dirección sola (o la app instalada) vuelve a War300, y el panel también', async () => {
    await page.goto(B + '/'); await page.waitForTimeout(1500);
    if (ruta() !== '/?g=war300') throw new Error(ruta());
    await page.goto(B + '/panel/'); await page.waitForTimeout(1200);
    if (ruta() !== '/panel/?g=war300') throw new Error(ruta());
  });
  await paso('6 con sesión abierta pero sin «último» guardado: va a su gimnasio y entra', async () => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(1200);
    await page.fill('#authEmail', 'carloswxht+war300@gmail.com'); await page.fill('#authPass', 'clave-prueba-1'); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    await page.evaluate(() => localStorage.removeItem('gymbro.ultimo'));
    await page.goto(B + '/'); await page.waitForTimeout(2500);
    if (ruta() !== '/?g=war300') throw new Error(ruta());
    if (!(await page.isHidden('#authGate'))) throw new Error('pidió entrar');
  });
  await paso('7 un gimnasio que ya no existe no se vuelve a abrir solo', async () => {
    await ctx.close(); ctx = await contexto(browser); page = await ctx.newPage(); vigilar(page);
    await page.goto(B + '/?g=gym-borrado'); await page.waitForTimeout(1500);
    await page.goto(B + '/'); await page.waitForTimeout(1200);
    if (ruta() !== '/inicio/') throw new Error(ruta());
  });
  await paso('8 «Compartir» lleva siempre su gimnasio en el enlace', async () => {
    await page.goto(B + '/?g=gym-luna'); await page.waitForTimeout(1500);
    const url = await page.evaluate(async () => { let u = null; navigator.share = async d => { u = d.url; }; await shareWar300(); return u; });
    if (!url.endsWith('/?g=gym-luna')) throw new Error(url);
  });
  console.log(errores.length ? 'ERRORES DE PÁGINA: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
