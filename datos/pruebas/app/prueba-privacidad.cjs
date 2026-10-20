// Prueba de la privacidad y el aviso legal (v104) contra el Supabase simulado.
// Necesita: War300 con registro libre, Carlos (clave-prueba-1) admin y
// usuarioswxht (clave-prueba-1) socio, los dos sin consentimiento aún; sin
// datos legales en War300; la cuenta de plataforma de replica-local.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = process.argv[2];
const B = 'http://127.0.0.1:8091';
let cortarLegal = false;
async function contexto(browser){
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
    const u = new URL(r.request().url());
    if (cortarLegal && u.pathname.endsWith('/legal_estado_gymbro')) return r.abort();
    const resp = await fetch(B + u.pathname, { method: 'POST', body: r.request().postData() || '{}' });
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
  const cap = n => page.screenshot({ path: `${OUT}/${n}.png` });
  const gate = () => page.isVisible('#legalGate');
  const nuevo = async () => { await ctx.close(); ctx = await contexto(browser); page = await ctx.newPage(); vigilar(page); };
  const entrar = async (email, clave) => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(1200);
    await page.fill('#authEmail', email); await page.fill('#authPass', clave); await page.click('#authSubmit'); await page.waitForTimeout(2500);
  };

  await paso('1 la página de Gymbro enlaza su texto general', async () => {
    await page.goto(B + '/'); await page.waitForTimeout(1000);
    await page.click('text=Privacidad y aviso legal'); await page.waitForTimeout(800);
    if (new URL(page.url()).pathname !== '/legal/') throw new Error(page.url());
    if (!(await page.textContent('main')).includes('no te pide datos')) throw new Error('texto');
  });
  await paso('2 privacidad de War300 sin datos legales: avisa de que faltan', async () => {
    await page.goto(B + '/legal/?g=war300'); await page.waitForTimeout(1000); await cap('l1-legal-incompleta');
    if (!(await page.isVisible('.aviso'))) throw new Error('sin aviso');
    if (!(await page.textContent('h1')).includes('Privacidad')) throw new Error('título');
    if ((await page.locator('.pendiente').count()) < 3) throw new Error('pendientes');
  });
  await paso('3 crear cuenta pide la casilla; con ella entra sin más preguntas', async () => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(1200);
    await page.click('#authSwitch');
    if (!(await page.isVisible('#authAcepto'))) throw new Error('sin casilla');
    if (!(await page.getAttribute('#authAcepto a', 'href')).endsWith('/legal/?g=war300')) throw new Error('enlace');
    await page.fill('#authEmail', 'socia-priv@ejemplo.test'); await page.fill('#authPass', 'clave-socia-1'); await page.fill('#authPass2', 'clave-socia-1');
    await page.click('#authSubmit'); await page.waitForTimeout(600);
    if (!(await page.textContent('#authMsg')).includes('aceptar')) throw new Error('sin aviso: ' + await page.textContent('#authMsg'));
    await cap('l2-crear-cuenta');
    await page.check('#authAceptoCheck'); await page.click('#authSubmit'); await page.waitForTimeout(3000);
    if (!(await page.isHidden('#authGate'))) throw new Error('no entró');
    if (await gate()) throw new Error('le vuelve a pedir aceptar');
  });
  await paso('4 Carlos (sin aceptar): le pide aceptar antes de seguir; sin casilla no pasa', async () => {
    await nuevo(); await entrar('carloswxht+war300@gmail.com', 'clave-prueba-1');
    if (!(await gate())) throw new Error('no lo pide');
    await cap('l3-antes-de-seguir');
    await page.click('#legalAceptar'); await page.waitForTimeout(300);
    if (!(await page.textContent('#legalMsg')).includes('Marca')) throw new Error('pasó sin casilla');
    await page.check('#legalCheck'); await page.click('#legalAceptar'); await page.waitForTimeout(1200);
    if (await gate()) throw new Error('no se quitó');
    await page.reload(); await page.waitForTimeout(2500);
    if (await gate()) throw new Error('lo pide otra vez al recargar');
  });
  await paso('5 Ajustes tiene «Privacidad y aviso legal» de su gimnasio', async () => {
    const href = await page.getAttribute('#settingsOverlay .legal-link', 'href');
    if (!href.endsWith('/legal/?g=war300')) throw new Error(href);
    await page.evaluate(() => document.getElementById('settingsOverlay').classList.add('open')); await page.waitForTimeout(300);
    await page.evaluate(() => { const s = document.querySelector('#settingsOverlay .settings-sheet'); s.scrollTop = s.scrollHeight; }); await page.waitForTimeout(300);
    await cap('l4-ajustes');
  });
  await paso('6 sin señal para comprobarlo, no bloquea el entreno', async () => {
    await nuevo(); cortarLegal = true; await entrar('usuarioswxht@gmail.com', 'clave-prueba-1'); cortarLegal = false;
    if (await gate()) throw new Error('bloqueó sin señal');
    if (!(await page.isHidden('#authGate'))) throw new Error('no entró');
  });
  await paso('7 «Salir» desde la pantalla de aceptar cierra la sesión', async () => {
    await page.reload(); await page.waitForTimeout(2500);
    if (!(await gate())) throw new Error('no lo pide');
    await page.click('#legalSalir'); await page.waitForTimeout(2500);
    if (!(await page.isVisible('#authGate'))) throw new Error('no salió');
  });
  await paso('8 plataforma: aviso de datos legales que faltan; rellenarlos (NIF con puntos)', async () => {
    await page.goto(B + '/plataforma/'); await page.waitForTimeout(600);
    await page.fill('#eEmail', 'plataforma@ejemplo.test'); await page.fill('#ePass', 'clave-plataforma'); await page.click('#fEntrar button[type=submit]'); await page.waitForTimeout(1000);
    await page.click('.tarjeta:has-text("War300")'); await page.waitForTimeout(1000);
    if (!(await page.isVisible('.f-cabeza .error'))) throw new Error('sin aviso');
    await page.fill('#lNif', 'xx'); await page.click('#lGuardar'); await page.waitForTimeout(600);
    if (await page.isHidden('#lError')) throw new Error('aceptó un NIF malo');
    await page.fill('#lTitular', 'Carlos Ejemplo'); await page.fill('#lNif', '12.345.678-z'); await page.fill('#lDomicilio', 'Calle Mayor 1, 28001 Madrid');
    await page.fill('#lCorreo', 'Hola@War300.test.'); await page.click('#lGuardar'); await page.waitForTimeout(800);
    if (!(await page.textContent('#toast')).includes('guardados')) throw new Error(await page.textContent('#toast'));
    if ((await page.inputValue('#lNif')) !== '12345678Z') throw new Error('nif ' + await page.inputValue('#lNif'));
    if (!(await page.isHidden('.f-cabeza .error'))) throw new Error('sigue el aviso');
    await page.locator('#lForm').scrollIntoViewIfNeeded(); await cap('l5-plataforma-legal');
  });
  await paso('9 la privacidad de War300 ya sale completa con sus datos', async () => {
    await page.goto(B + '/legal/?g=war300'); await page.waitForTimeout(1000); await cap('l6-legal-completa');
    if (await page.isVisible('.aviso')) throw new Error('sigue el aviso');
    const t = await page.textContent('main');
    if (!t.includes('Carlos Ejemplo') || !t.includes('12345678Z') || !t.includes('hola@war300.test')) throw new Error('faltan datos');
    await page.screenshot({ path: `${OUT}/l7-legal-entera.png`, fullPage: true });
  });
  await paso('10 el panel del dueño enlaza la privacidad de su gimnasio', async () => {
    await page.goto(B + '/panel/?g=war300'); await page.waitForTimeout(800);
    if (!(await page.getAttribute('#pLegal', 'href')).endsWith('/legal/?g=war300')) throw new Error('enlace');
  });
  console.log(errores.length ? 'ERRORES DE PÁGINA: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
