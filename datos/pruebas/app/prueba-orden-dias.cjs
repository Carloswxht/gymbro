// Prueba de la v106: sin los datos del socio cargados, la app no guarda nada,
// y la «Ver pantalla de bienvenida» de Ajustes es solo una vista previa
// (antes, con mala señal, el orden de días volvía al de fábrica y «Hoy toca»
// se equivocaba). Necesita: Carlos (clave-prueba-1) con orden {1:2,2:1,3:3},
// entrenos de los días 2, 1 y 3 (el último, Tirón) y la privacidad aceptada;
// usuarioswxht (clave-prueba-1) sin orden de días guardado.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const OUT = process.argv[2];
const B = 'http://127.0.0.1:8091';
const sql = q => execSync(`psql -h /var/tmp/gympg -p 5445 -U postgres -d prueba -Atc "${q}"`).toString().trim();
const orden = email => sql(`select p.reps from gymbro.progreso_gymbro p join comun.usuarios u on u.id = p.usuario_id where u.email = '${email}' and p.work_key = '__day_slots__'`);
let cortarDatos = 0;
(async () => {
  const browser = await chromium.launch();
  const nuevo = async () => {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block' });
    await ctx.route('https://dorunbacwnkwdatfscri.supabase.co/**', async r => {
      const u = new URL(r.request().url());
      if (u.pathname.endsWith('/mis_datos_gymbro') && cortarDatos > 0){ cortarDatos--; return r.abort(); }
      const resp = await fetch(B + u.pathname, { method: 'POST', body: r.request().postData() || '{}' });
      r.fulfill({ status: resp.status, contentType: 'application/json', body: await resp.text() });
    });
    const page = await ctx.newPage(); page.on('pageerror', e => errores.push(e.message));
    return page;
  };
  const errores = [];
  const paso = async (n, f) => { try { await f(); console.log('OK  ' + n); } catch (e) { console.log('MAL ' + n + ': ' + e.message.split('\n')[0]); } };
  const entrar = async (page, email) => {
    await page.goto(B + '/?g=war300'); await page.waitForTimeout(1200);
    await page.fill('#authEmail', email); await page.fill('#authPass', 'clave-prueba-1'); await page.click('#authSubmit'); await page.waitForTimeout(3000);
  };
  const hoy = page => page.textContent('.tc-title');
  let page;

  await paso('1 con señal: «Hoy toca: Pierna y core» (tras Tirón, en su orden)', async () => {
    page = await nuevo(); await entrar(page, 'carloswxht+war300@gmail.com');
    const t = await hoy(page); if (!t.includes('Pierna y core')) throw new Error(t);
    await page.screenshot({ path: `${OUT}/o1-hoy.png` });
    await page.context().close();
  });
  await paso('2 sin señal al cargar sus datos: abrir «Orden de tus días» y guardar no pisan su orden', async () => {
    page = await nuevo(); cortarDatos = 100; await entrar(page, 'carloswxht+war300@gmail.com');
    await page.evaluate(() => { goToDayOrder(); persistState(true); persistDaySlots(); saveThemePref(); });
    await page.waitForTimeout(1500);
    const o = orden('carloswxht+war300@gmail.com'); if (o !== '{"1":2,"2":1,"3":3}') throw new Error('orden pisado: ' + o);
    const n = sql("select count(*) from gymbro.progreso_gymbro p join comun.usuarios u on u.id = p.usuario_id where u.email = 'carloswxht+war300@gmail.com' and p.updated_at > now() - interval '30 seconds'");
    if (n !== '0') throw new Error(n + ' filas guardadas sin datos');
  });
  await paso('3 vuelve la señal: carga sola y «Hoy toca» es Pierna y core; su orden sigue igual', async () => {
    cortarDatos = 0; await page.evaluate(() => goHome()); await page.waitForTimeout(7000);
    const t = await hoy(page); if (!t.includes('Pierna y core')) throw new Error(t);
    const o = orden('carloswxht+war300@gmail.com'); if (o !== '{"1":2,"2":1,"3":3}') throw new Error('orden: ' + o);
    await page.screenshot({ path: `${OUT}/o2-tras-reintento.png` });
    await page.context().close();
  });
  await paso('4 primera vez de verdad (datos cargados, sin orden): sale y se guarda el de fábrica', async () => {
    page = await nuevo(); await entrar(page, 'usuarioswxht@gmail.com');
    if (await page.isVisible('#legalGate')) { await page.check('#legalCheck'); await page.click('#legalAceptar'); await page.waitForTimeout(800); }
    await page.evaluate(() => goToDayOrder()); await page.waitForTimeout(1500);
    const o = orden('usuarioswxht@gmail.com'); if (o !== '{"1":1,"2":2,"3":3}') throw new Error('orden: ' + o);
    await page.context().close();
  });
  await paso('5 vista previa de bienvenida (Ajustes): mover el orden y salir no guarda nada', async () => {
    page = await nuevo(); await entrar(page, 'carloswxht+war300@gmail.com');
    await page.evaluate(() => document.getElementById('viewOnboardingBtn').click()); await page.waitForTimeout(300);
    await page.click('#onbCreateBtn'); await page.waitForTimeout(300);
    await page.click('#splitPPLBtn'); await page.waitForTimeout(500);
    if (!(await page.textContent('#dayOrderHint')).includes('Vista previa')) throw new Error('sin aviso de vista previa');
    if ((await page.textContent('#continueBtn')).trim() !== 'Guardar este orden') throw new Error('botón: ' + await page.textContent('#continueBtn'));
    await page.evaluate(() => { assignDaySlot(1, 1); unassignDaySlot(3); }); await page.waitForTimeout(1200);
    await page.screenshot({ path: `${OUT}/o3-vista-previa.png` });
    if (orden('carloswxht+war300@gmail.com') !== '{"1":2,"2":1,"3":3}') throw new Error('guardó al mover: ' + orden('carloswxht+war300@gmail.com'));
    await page.evaluate(() => goHome()); await page.waitForTimeout(1500);
    if (orden('carloswxht+war300@gmail.com') !== '{"1":2,"2":1,"3":3}') throw new Error('guardó al salir');
    const mem = await page.evaluate(() => JSON.stringify(dayAssignment));
    if (mem !== '{"1":2,"2":1,"3":3}') throw new Error('en memoria quedó ' + mem);
    const t = await hoy(page); if (!t.includes('Pierna y core')) throw new Error(t);
  });
  await paso('6 vista previa: «Guardar este orden» guarda y dice qué toca hoy', async () => {
    await page.evaluate(() => document.getElementById('viewOnboardingBtn').click()); await page.waitForTimeout(300);
    await page.click('#onbCreateBtn'); await page.waitForTimeout(300);
    await page.click('#splitPPLBtn'); await page.waitForTimeout(500);
    await page.evaluate(() => assignDaySlot(1, 1)); await page.waitForTimeout(300);
    await page.click('#continueBtn'); await page.waitForTimeout(1500);
    if (orden('carloswxht+war300@gmail.com') !== '{"1":1,"2":2,"3":3}') throw new Error('no guardó: ' + orden('carloswxht+war300@gmail.com'));
    const toast = await page.textContent('#status'); if (!toast.includes('Orden guardado') || !toast.includes('Empuje superior')) throw new Error(toast);
    const t = await hoy(page); if (!t.includes('Empuje superior')) throw new Error(t);
    await page.screenshot({ path: `${OUT}/o4-guardado.png` });
  });
  await paso('7 fuera de la vista previa, «Orden de tus días» sigue guardando al momento', async () => {
    await page.evaluate(() => goToDayOrder()); await page.waitForTimeout(300);
    if ((await page.textContent('#dayOrderHint')).includes('Vista previa')) throw new Error('aviso de vista previa fuera de ella');
    await page.evaluate(() => assignDaySlot(1, 2)); await page.waitForTimeout(1200);
    if (orden('carloswxht+war300@gmail.com') !== '{"1":2,"2":1,"3":3}') throw new Error('orden: ' + orden('carloswxht+war300@gmail.com'));
    await page.context().close();
  });
  console.log(errores.length ? 'ERRORES DE PÁGINA: ' + errores.join(' | ') : 'sin errores de página');
  await browser.close();
})();
