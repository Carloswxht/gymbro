// Prueba del aspecto de cada gimnasio (v102; v103: War300 ya va siempre con ?g=) contra el Supabase simulado.
// Necesita: War300 (Carlos, clave-prueba-1) con el SQL de aspecto aplicado;
// gym-luna (registro libre; dueña luna@ejemplo.test, clave-luna-1, admin) y
// gym-sin (sin aspecto) recién creados; y la cuenta de plataforma de replica-local.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const OUT = process.argv[2];
const B = 'http://127.0.0.1:8091';
let sinRed = false;
async function contexto(browser){
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
    if (sinRed) return r.abort();
    const u = new URL(r.request().url());
    const resp = await fetch(B + u.pathname, { method: 'POST', body: r.request().postData() || '{}' });
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
  const cap = n => page.screenshot({ path: `${OUT}/${n}.png`, fullPage: false });
  const ink = () => page.evaluate(() => getComputedStyle(document.body).getPropertyValue('--ink').trim().toUpperCase());
  const kicker = () => page.textContent('#authGate .marca-nombre');
  const entrar = async (email, clave) => {
    await page.fill('#authEmail', email); await page.fill('#authPass', clave); await page.click('#authSubmit'); await page.waitForTimeout(2500);
  };
  const salir = async () => { await page.evaluate(() => document.getElementById('logoutBtn').click()); await page.waitForTimeout(2000); };

  // Logo de prueba: un PNG de 800x600 (se recorta al centro).
  const logoPrueba = `${OUT}/logo-prueba.png`;
  await page.goto('about:blank');
  const datosLogo = await page.evaluate(() => {
    const c = document.createElement('canvas'); c.width = 800; c.height = 600; const x = c.getContext('2d');
    x.fillStyle = '#1E1B4B'; x.fillRect(0, 0, 800, 600); x.fillStyle = '#FACC15'; x.beginPath(); x.arc(400, 300, 220, 0, 7); x.fill();
    x.fillStyle = '#1E1B4B'; x.beginPath(); x.arc(470, 250, 200, 0, 7); x.fill(); return c.toDataURL('image/png');
  });
  fs.writeFileSync(logoPrueba, Buffer.from(datosLogo.split(',')[1], 'base64'));

  await paso('1 War300: nombre, frase, tema Original, su icono y su manifiesto', async () => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(1500); await cap('a1-war300-entrar');
    if ((await kicker()) !== 'War300') throw new Error('kicker ' + await kicker());
    if ((await page.title()) !== 'War300') throw new Error('título ' + await page.title());
    if ((await ink()) !== '#0E1013') throw new Error('tema ' + await ink());
    if (!(await page.getAttribute('link[rel=manifest]', 'href')).startsWith('blob:')) throw new Error('manifest fijo');
    if (await page.getAttribute('link[rel=apple-touch-icon]', 'href') !== '/icons/icon-512.png') throw new Error('icono ' + await page.getAttribute('link[rel=apple-touch-icon]', 'href'));
    if (await page.getAttribute('#authLogo', 'src') !== '/icons/icon-512.png') throw new Error('logo ' + await page.getAttribute('#authLogo', 'src'));
  });
  await paso('2 Carlos entra en War300: cabecera War300 y mismo tema', async () => {
    await entrar('carloswxht+war300@gmail.com', 'clave-prueba-1'); await cap('a2-war300-dentro');
    if ((await page.textContent('#masthead .marca-nombre')) !== 'War300') throw new Error('cabecera');
    if ((await ink()) !== '#0E1013') throw new Error('tema ' + await ink());
    await salir();
  });
  await paso('3 gimnasio sin aspecto: su nombre, sin logo, tema Original e icono de Gymbro', async () => {
    await page.goto(B + '/?g=gym-sin'); await page.waitForTimeout(1500); await cap('a3-sin-aspecto');
    if ((await kicker()) !== 'Gym Sin Aspecto') throw new Error('kicker ' + await kicker());
    if (!(await page.isHidden('#authLogo'))) throw new Error('enseña logo');
    if (await page.getAttribute('link[rel=apple-touch-icon]', 'href') !== '/icons/gymbro-512.png') throw new Error('icono');
    if ((await ink()) !== '#0E1013') throw new Error('tema');
  });
  await paso('4 plataforma: aspecto de Gym Luna (nombre, frase, colores propios, logo) con vista previa', async () => {
    await page.goto(B + '/plataforma/'); await page.waitForTimeout(600);
    await page.fill('#eEmail', 'plataforma@ejemplo.test'); await page.fill('#ePass', 'clave-plataforma'); await page.click('#fEntrar button[type=submit]'); await page.waitForTimeout(1000);
    await page.click('.tarjeta:has-text("Gym Luna")'); await page.waitForTimeout(1000);
    await page.locator('#xForm').scrollIntoViewIfNeeded(); await cap('a4-plataforma-antes');
    await page.fill('#xNombre', 'Luna Fitness'); await page.fill('#xLema', 'Cada día un poco más.');
    await page.click('[data-tema="propio"]');
    for (const [k, v] of [['#xInk', '#14123a'], ['#xDay1', '#facc15'], ['#xDay2', '#22d3ee'], ['#xDay3', '#f472b6']]) await page.fill(k, v);
    await page.setInputFiles('#xLogoArchivo', logoPrueba); await page.waitForTimeout(800);
    if (!(await page.getAttribute('#xPrevia img', 'src')).startsWith('data:image/png')) throw new Error('sin logo en la vista previa');
    await page.locator('#xForm').screenshot({ path: `${OUT}/a5-plataforma-aspecto.png` });
    await page.click('#xGuardar'); await page.waitForTimeout(1000);
    if (!(await page.textContent('#toast')).includes('guardado')) throw new Error('no guardó: ' + await page.textContent('#xError'));
    await page.reload(); await page.waitForTimeout(1200);
    if ((await page.inputValue('#xNombre')) !== 'Luna Fitness') throw new Error('nombre no guardado');
    if (!(await page.getAttribute('[data-tema="propio"]', 'class')).includes('activo')) throw new Error('tema no guardado');
  });
  await paso('5 plataforma: elegir un tema de la app (Neón) y volver a propios', async () => {
    await page.click('[data-tema="theme-neon"]'); await page.waitForTimeout(200);
    if (!(await page.isHidden('#xColores'))) throw new Error('enseña colores');
    await page.click('[data-tema="propio"]'); await page.click('#xGuardar'); await page.waitForTimeout(800);
  });
  await paso('6 app de Gym Luna: nombre, logo, colores, título, icono y manifest propios', async () => {
    await page.goto(B + '/?g=gym-luna'); await page.waitForTimeout(1800); await cap('a6-luna-entrar');
    if ((await kicker()) !== 'Luna Fitness') throw new Error('kicker ' + await kicker());
    if ((await page.title()) !== 'Luna Fitness') throw new Error('título');
    if ((await ink()) !== '#14123A') throw new Error('tema ' + await ink());
    if (!(await page.getAttribute('#authLogo', 'src')).startsWith('data:image/png')) throw new Error('logo');
    if (!(await page.getAttribute('link[rel=apple-touch-icon]', 'href')).startsWith('data:image/png')) throw new Error('icono');
    const cdp = await ctx.newCDPSession(page);
    const m = await cdp.send('Page.getAppManifest');
    const j = JSON.parse(m.data || '{}');
    if (m.errors.length) throw new Error('manifest con errores: ' + JSON.stringify(m.errors));
    if (j.name !== 'Luna Fitness' || !j.start_url.endsWith('/?g=gym-luna') || !j.icons[0].src.startsWith('data:image/png') || j.description !== 'Cada día un poco más.')
      throw new Error('manifest ' + m.data.slice(0, 200));
    console.log('    manifest: ' + j.name + ' · ' + j.start_url + ' · icono ' + j.icons[0].src.length + ' letras');
  });
  await paso('7 socia nueva de Gym Luna: entra con los colores del gimnasio; en Ajustes salen primero', async () => {
    await page.click('#authSwitch'); await page.fill('#authEmail', 'socia-luna@ejemplo.test'); await page.fill('#authPass', 'clave-socia-1'); await page.fill('#authPass2', 'clave-socia-1');
    await page.click('#authSubmit'); await page.waitForTimeout(2500); await cap('a7-luna-dentro');
    if ((await page.textContent('#masthead .marca-nombre')) !== 'Luna Fitness') throw new Error('cabecera');
    if ((await ink()) !== '#14123A') throw new Error('tema ' + await ink());
    await page.evaluate(() => { renderThemeGrid(); document.getElementById('settingsOverlay').classList.add('open'); }); await page.waitForTimeout(400);
    await page.locator('#themeGrid').scrollIntoViewIfNeeded(); await cap('a8-luna-ajustes');
    const primero = await page.textContent('#themeGrid .theme-swatch:first-child .sw-name');
    if (primero !== 'Luna Fitness') throw new Error('primer tema ' + primero);
    if (!(await page.getAttribute('#themeGrid .theme-swatch:first-child', 'class')).includes('active')) throw new Error('no marcado');
  });
  await paso('8 la socia elige «Fuego»: se respeta al recargar; volver al del gimnasio también', async () => {
    await page.click('#themeGrid [data-theme="theme-fire"]'); await page.waitForTimeout(800);
    await page.reload(); await page.waitForTimeout(2500);
    if ((await ink()) !== '#1A0500') throw new Error('no respetó su tema: ' + await ink());
    await page.evaluate(() => { renderThemeGrid(); document.getElementById('settingsOverlay').classList.add('open'); }); await page.waitForTimeout(300);
    await page.click('#themeGrid [data-gimnasio]'); await page.waitForTimeout(800);
    await page.reload(); await page.waitForTimeout(2500);
    if ((await ink()) !== '#14123A') throw new Error('no volvió al del gimnasio: ' + await ink());
  });
  await paso('9 sin señal: abre con el nombre, logo y colores guardados en el móvil', async () => {
    sinRed = true; await page.reload(); await page.waitForTimeout(2500); sinRed = false;
    if ((await page.textContent('#masthead .marca-nombre')) !== 'Luna Fitness') throw new Error('cabecera');
    if ((await ink()) !== '#14123A') throw new Error('tema');
    await salir();
  });
  await paso('10 panel de la dueña de Gym Luna: su nombre y su logo', async () => {
    await page.goto(B + '/panel/?g=gym-luna'); await page.waitForTimeout(1200);
    await page.fill('#eCorreo', 'luna@ejemplo.test'); await page.fill('#eClave', 'clave-luna-1'); await page.click('#eEntrar'); await page.waitForTimeout(1500);
    await cap('a9-luna-panel');
    if ((await page.textContent('#pNegocio')) !== 'Luna Fitness') throw new Error('nombre');
    if (!(await page.getAttribute('#vPanel .logo-gym', 'src') || '').startsWith('data:image/png')) throw new Error('logo');
  });
  await paso('11 War300 sigue igual después de cambiar otro gimnasio', async () => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(1500);
    if ((await kicker()) !== 'War300' || (await ink()) !== '#0E1013') throw new Error('War300 cambió');
  });
  console.log(errores.length ? 'ERRORES DE PÁGINA: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
