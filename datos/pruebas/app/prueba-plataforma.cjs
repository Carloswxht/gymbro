// Prueba del panel de plataforma de Gymbro (v101) contra el Supabase simulado.
// Necesita la cuenta de plataforma de replica-local (plataforma@ejemplo.test).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = process.argv[2];
const B = 'http://127.0.0.1:8091';
async function contexto(browser){
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
    const u = new URL(r.request().url());
    const resp = await fetch('http://127.0.0.1:8091' + u.pathname, { method: 'POST', body: r.request().postData() || '{}' });
    r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
  });
  return ctx;
}
(async () => {
  const browser = await chromium.launch();
  const ctx = await contexto(browser);
  const page = await ctx.newPage(); const errores = [];
  page.on('pageerror', e => errores.push(e.message));
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const cap = n => page.screenshot({ path: `${OUT}/${n}.png`, fullPage: true });
  const n = Date.now() % 100000, slug = 'gym-prueba-' + n, correo = `dueno${n}@ejemplo.test`;
  let ctx2, p2;
  await paso('1 entrada; contraseña mala y cuenta de un gimnasio no entran', async () => {
    await page.goto(B + '/plataforma/'); await page.waitForTimeout(600); await cap('q1-entrar');
    await page.fill('#eEmail', 'plataforma@ejemplo.test'); await page.fill('#ePass', 'mala'); await page.click('#fEntrar button[type=submit]'); await page.waitForTimeout(600);
    if (!(await page.textContent('#eError')).includes('incorrectos')) throw new Error('sin error');
    await page.fill('#eEmail', 'carloswxht+war300@gmail.com'); await page.fill('#ePass', 'clave-prueba-1'); await page.click('#fEntrar button[type=submit]'); await page.waitForTimeout(600);
    if (await page.isVisible('#vLista')) throw new Error('entró un admin de gimnasio');
  });
  await paso('2 entra (con punto final del dictado) y ve War300 en la lista', async () => {
    await page.fill('#eEmail', 'plataforma@ejemplo.test.'); await page.fill('#ePass', 'clave-plataforma'); await page.click('#fEntrar button[type=submit]'); await page.waitForTimeout(1200);
    if (!(await page.textContent('#lLista')).includes('war300')) throw new Error('no sale war300');
    await cap('q2-lista');
  });
  await paso('3 ficha de War300 y registro libre que se queda al recargar', async () => {
    await page.locator('.tarjeta', { hasText: 'war300' }).click(); await page.waitForTimeout(1000); await cap('q3-ficha');
    await page.click('#fRegistro'); await page.waitForTimeout(800);
    await page.reload(); await page.waitForTimeout(1200);
    if (await page.isChecked('#fRegistro')) throw new Error('no se apagó');
    await page.click('#fRegistro'); await page.waitForTimeout(800);
    await page.reload(); await page.waitForTimeout(1200);
    if (!(await page.isChecked('#fRegistro'))) throw new Error('no se encendió');
  });
  await paso('4 alta de gimnasio (dirección corta automática; correo con punto final)', async () => {
    await page.goto(B + '/plataforma/#'); await page.waitForTimeout(800);
    await page.click('[data-ir="alta"]'); await page.waitForTimeout(300);
    await page.fill('#aNombre', 'Gym Prueba ' + n);
    if (await page.inputValue('#aSlug') !== slug) throw new Error('slug ' + await page.inputValue('#aSlug'));
    await page.fill('#aEmail', correo + '.'); await page.fill('#aDueno', 'Dueña prueba'); await cap('q4-alta');
    await page.click('#aGuardar'); await page.waitForTimeout(1500);
    if (!(await page.isVisible('#vHecho'))) throw new Error('no se dio de alta: ' + await page.textContent('#aError'));
    if (!(await page.textContent('#hLista')).includes('le ha llegado')) throw new Error('sin correo');
    await cap('q5-hecho');
  });
  await paso('5 dirección repetida: SLUG_EN_USO', async () => {
    await page.goto(B + '/plataforma/#alta'); await page.waitForTimeout(600);
    await page.fill('#aNombre', 'Gym Prueba ' + n); await page.fill('#aEmail', 'otro' + n + '@ejemplo.test'); await page.click('#aGuardar'); await page.waitForTimeout(1000);
    if (!(await page.textContent('#aError')).includes('ya la usa')) throw new Error(await page.textContent('#aError'));
  });
  await paso('6 el dueño elige contraseña con el correo, entra y abre su panel', async () => {
    const e = await (await fetch(B + '/__ultimo_enlace')).json();
    if (e.negocio_slug !== slug) throw new Error('enlace de ' + e.negocio_slug);
    ctx2 = await contexto(browser); p2 = await ctx2.newPage();
    await p2.goto(B + '/?g=' + slug + '#recuperar=' + e.token); await p2.waitForTimeout(800);
    await p2.fill('#authPass', 'clave-duena-1'); await p2.fill('#authPass2', 'clave-duena-1'); await p2.click('#authSubmit'); await p2.waitForTimeout(800);
    await p2.fill('#authPass', 'clave-duena-1'); await p2.click('#authSubmit'); await p2.waitForTimeout(2500);
    await p2.goto(B + '/panel/?g=' + slug); await p2.waitForTimeout(1500);
    if (!(await p2.textContent('body')).includes('Dueña prueba')) throw new Error('no ve su panel');
  });
  await paso('7 ficha del nuevo: dueño ya admin (sin «Invitación enviada»)', async () => {
    await page.goto(B + '/plataforma/#'); await page.waitForTimeout(1000);
    await page.locator('.tarjeta', { hasText: slug }).click(); await page.waitForTimeout(1000);
    const t = await page.textContent('#fContenido');
    if (!t.includes(correo) || t.includes('Invitación enviada')) throw new Error('admin mal');
  });
  await paso('8 dar de baja (con confirmación): el dueño queda fuera; reactivar', async () => {
    await page.click('#fEstado'); await page.waitForTimeout(300); await cap('q6-confirmar');
    await page.click('#dSi'); await page.waitForTimeout(1200);
    if (!(await page.textContent('#fContenido')).includes('De baja')) throw new Error('no salió de baja');
    await cap('q7-baja');
    await p2.reload(); await p2.waitForTimeout(1500);
    if (!(await p2.isVisible('#eCorreo'))) throw new Error('el dueño sigue dentro');
    await page.click('#fEstado'); await page.click('#dSi'); await page.waitForTimeout(1200);
    if ((await page.textContent('#fContenido')).includes('De baja desde')) throw new Error('no se reactivó');
  });
  await paso('9 salir', async () => {
    await page.click('#bSalir'); await page.waitForTimeout(800);
    if (!(await page.isVisible('#vEntrar'))) throw new Error('no salió');
    await page.goto(B + '/plataforma/#'); await page.waitForTimeout(800);
    if (!(await page.isVisible('#vEntrar'))) throw new Error('sigue la sesión');
  });
  console.log('errores de página:', errores.length ? errores : 'ninguno');
  await browser.close();
})();
