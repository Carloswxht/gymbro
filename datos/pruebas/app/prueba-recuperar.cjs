// Prueba de «¿Has olvidado tu contraseña?» (v108: correo de Supabase, con la
// imagen de cada gimnasio) contra el Supabase simulado, en la app y en /plataforma/.
// Base «login» recién montada (datos/pruebas/montar-base-login.sh).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const OUT = process.argv[2], B = 'http://127.0.0.1:8091';
(async () => {
  const browser = await chromium.launch();
  let ctx, page; const errores = [];
  const otroMovil = async () => {
    if (ctx) await ctx.close();
    ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
    await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
      const u = new URL(r.request().url());
      const resp = await fetch(B + u.pathname + u.search, { method: r.request().method(), headers: (h => ({ 'content-type': 'application/json', ...(h.authorization ? { authorization: h.authorization } : {}) }))(r.request().headers()), body: r.request().method() === 'GET' ? undefined : (r.request().postData() || '{}') });
      r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
    });
    page = await ctx.newPage(); page.on('pageerror', e => errores.push(e.message));
  };
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const msg = () => page.textContent('#authMsg');
  const vis = s => page.isVisible(s);
  const dentro = () => page.evaluate(() => document.getElementById('authGate').classList.contains('hidden'));
  const enlace = async () => (await (await fetch(B + '/__ultimo_enlace')).json());
  const pedir = async (slug, email) => {
    await page.goto(B + '/?g=' + slug); await page.waitForTimeout(1000);
    await page.click('#authForgot span'); await page.fill('#authEmail', email); await page.click('#authSubmit'); await page.waitForTimeout(1000);
  };
  const entrar = async (email, clave) => {
    await otroMovil(); await page.goto(B + '/?g=war300'); await page.waitForTimeout(1000);
    await page.fill('#authEmail', email); await page.fill('#authPass', clave); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    return dentro();
  };

  await otroMovil();
  let e1;
  await paso('1 pedir el enlace en War300: el correo lleva a la app de War300 con su imagen', async () => {
    await pedir('war300', 'usuarioswxht@gmail.com.');   // con el punto del dictado
    if (!(await msg()).includes('te llegará')) throw new Error(await msg());
    await page.screenshot({ path: `${OUT}/s1-mandado.png` });
    e1 = await enlace();
    if (!e1.enlace.startsWith(B + '/?g=war300&token_hash=') || !e1.enlace.endsWith('&type=recovery')) throw new Error(e1.enlace);
    const m = e1.marca;
    if (m.nombre !== 'War300' || m.fondo !== '#0E1013' || m.acento !== '#FF8A3D' || m.logo !== 'https://gymbro.autonomialab.es/icons/icon-512.png') throw new Error(JSON.stringify(m));
  });
  await paso('2 el enlace abre «Contraseña nueva» y limpia la dirección', async () => {
    await otroMovil(); await page.goto(e1.enlace); await page.waitForTimeout(1500);
    if ((await page.textContent('#authTitle')) !== 'Contraseña nueva' || await vis('#authEmail') || !await vis('#authPass2')) throw new Error('pantalla mal: ' + await msg());
    if (page.url() !== B + '/?g=war300') throw new Error(page.url());
    await page.screenshot({ path: `${OUT}/s2-nueva.png` });
  });
  await paso('3 no coinciden, corta y la misma de ahora', async () => {
    await page.fill('#authPass', 'nueva-clave-9'); await page.fill('#authPass2', 'otra'); await page.click('#authSubmit'); await page.waitForTimeout(300);
    if (!(await msg()).includes('no coinciden')) throw new Error(await msg());
    await page.fill('#authPass', 'corta'); await page.fill('#authPass2', 'corta'); await page.click('#authSubmit'); await page.waitForTimeout(300);
    if (!(await msg()).includes('8 caracteres')) throw new Error(await msg());
    await page.fill('#authPass', 'clave-prueba-1'); await page.fill('#authPass2', 'clave-prueba-1'); await page.click('#authSubmit'); await page.waitForTimeout(800);
    if (!(await msg()).includes('contraseña de ahora')) throw new Error(await msg());
  });
  await paso('4 guarda y entra directo en la app', async () => {
    await page.fill('#authPass', 'nueva-clave-9'); await page.fill('#authPass2', 'nueva-clave-9'); await page.click('#authSubmit'); await page.waitForTimeout(2500);
    if (!await dentro()) throw new Error('no entró: ' + await msg());
    await page.screenshot({ path: `${OUT}/s3-dentro.png` });
  });
  await paso('5 en otro móvil: la vieja ya no vale y la nueva sí', async () => {
    if (await entrar('usuarioswxht@gmail.com', 'clave-prueba-1')) throw new Error('entró con la vieja');
    if (!await entrar('usuarioswxht@gmail.com', 'nueva-clave-9')) throw new Error('no entró con la nueva: ' + await msg());
  });
  await paso('6 el mismo enlace ya no vale: pide el correo para mandar otro', async () => {
    await otroMovil(); await page.goto(e1.enlace); await page.waitForTimeout(1500);
    if (!(await msg()).includes('caducado') || (await page.textContent('#authTitle')) !== 'Recuperar contraseña' || !await vis('#authEmail')) throw new Error(await msg());
    if (await dentro()) throw new Error('entró');
    await page.screenshot({ path: `${OUT}/s4-caducado.png` });
  });
  let e2;
  await paso('7 otro gimnasio: el enlace lleva a su app y con su imagen (no la de War300)', async () => {
    await otroMovil(); await pedir('gym-luna', 'luna@ejemplo.test');
    e2 = await enlace();
    if (!e2.enlace.startsWith(B + '/?g=gym-luna&token_hash=')) throw new Error(e2.enlace);
    if (e2.marca.nombre === 'War300' || e2.marca.logo !== 'https://gymbro.autonomialab.es/icons/gymbro-512.png') throw new Error(JSON.stringify(e2.marca));
  });
  await paso('8 el enlace de Luna abierto en War300: no entra ni cambia nada', async () => {
    await otroMovil(); await page.goto(e2.enlace.replace('g=gym-luna', 'g=war300')); await page.waitForTimeout(1800);
    if (!(await msg()).includes('no es de una cuenta de este gimnasio') || await dentro()) throw new Error(await msg());
    const s = await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('gymbro.sb.') && localStorage.getItem(k) && localStorage.getItem(k) !== 'null'));
    if (s.length) throw new Error('quedó sesión: ' + s);
    await page.screenshot({ path: `${OUT}/s5-otro-gimnasio.png` });
  });
  await paso('9 plataforma: pedir el enlace, vuelve a /plataforma/ con la imagen de autonomIA Lab', async () => {
    await otroMovil(); await page.goto(B + '/plataforma/'); await page.waitForTimeout(1000);
    await page.click('#bOlvido'); await page.fill('#oEmail', 'plataforma@ejemplo.test'); await page.click('#fOlvido button[type=submit]'); await page.waitForTimeout(1000);
    if (!await vis('#oOk')) throw new Error('sin aviso');
    const e = await enlace();
    if (!e.enlace.startsWith(B + '/plataforma/?token_hash=') || e.marca.marca !== 'autonomialab') throw new Error(JSON.stringify(e));
    await otroMovil(); await page.goto(e.enlace); await page.waitForTimeout(1500);
    if (!await vis('#vNueva') || await vis('#bSalir')) throw new Error('no se ve la contraseña nueva');
    if (page.url() !== B + '/plataforma/') throw new Error(page.url());
    await page.screenshot({ path: `${OUT}/s6-plataforma-nueva.png` });
    await page.fill('#nPass', 'plataforma-nueva-1'); await page.fill('#nPass2', 'plataforma-nueva-1'); await page.click('#fNueva button'); await page.waitForTimeout(1800);
    if (!await vis('#vLista') || !(await page.textContent('#lLista')).includes('War300')) throw new Error('no entró a la lista');
    await page.screenshot({ path: `${OUT}/s7-plataforma-dentro.png` });
  });
  await paso('10 plataforma: el enlace de un socio no sirve allí', async () => {
    await otroMovil(); await pedir('war300', 'carloswxht+war300@gmail.com');
    const e = await enlace();
    await otroMovil(); await page.goto(e.enlace.replace('/?g=war300&', '/plataforma/?')); await page.waitForTimeout(1500);
    if (!await vis('#vEntrar') || !(await page.textContent('#eError')).includes('no es de la cuenta de plataforma')) throw new Error('mal');
  });
  console.log(errores.length ? 'ERRORES: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
