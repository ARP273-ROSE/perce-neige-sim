// Essai de la perte du contexte WebGL : relance allégée, niveau gardé, rapport.
const pw = require('/qnh/node_modules/playwright');
(async () => {
  const b = await pw.webkit.launch();
  const ctx = await b.newContext({ viewport: { width: 1194, height: 834 }, deviceScaleFactor: 2 });
  const p = await ctx.newPage();
  const rapports = [];
  await ctx.route('**/collecte.php', r => { rapports.push(r.request().postData()); r.fulfill({ status: 200, body: '{}' }); });
  await p.addInitScript(() => { const o = HTMLCanvasElement.prototype.getContext; HTMLCanvasElement.prototype.getContext = function (...a) { const c = o.apply(this, a); if (c && /webgl/.test(a[0])) window.__gl = c; return c; }; });
  const log = [];
  p.on('console', m => { if (/\[Perf\] cran/.test(m.text())) log.push(m.text().slice(0, 120)); });
  await p.goto(process.argv[2], { waitUntil: 'load', timeout: 180000 });
  for (let tour = 0; tour < 3; tour++) {
    await p.waitForTimeout(35000);
    const avant = await p.evaluate(() => ({ s: window.__pn_secours, etat: window.__pn_etat }));
    console.log('tour', tour, JSON.stringify(avant), '| journal:', log.slice(-1)[0]);
    await p.evaluate(() => window.__gl.getExtension('WEBGL_lose_context').loseContext());
    await p.waitForTimeout(800);
    console.log('  écran:', await p.evaluate(() => { const d = document.body.lastChild; return d && d.textContent; }));
    await p.screenshot({ path: `/out/perte${tour}.png` });
    await p.waitForTimeout(1500);
  }
  console.log('rapports:', rapports.map(r => { const j = JSON.parse(r); return j.resume + ' :: ' + j.traceback; }).join('\n'));
  await b.close();
})().catch(e => { console.error(e); process.exit(1); });
