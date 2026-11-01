// Qui crée des tampons à chaque image ? Tailles et usages sur 20 images.
const pw = require('/qnh/node_modules/playwright');
(async () => {
  const b = await pw.webkit.launch();
  const p = await (await b.newContext({ viewport: { width: 1194, height: 834 }, deviceScaleFactor: 2 })).newPage();
  await p.addInitScript(() => {
    const S = window.__S = { on: false, cr: 0, del: 0, h: {}, frames: 0, tex: 0, stacks: {} };
    const G = WebGL2RenderingContext.prototype;
    const cB = G.createBuffer, dB = G.deleteBuffer, bD = G.bufferData, bS = G.bufferSubData, cV = G.createVertexArray, dA = G.drawArrays, dE = G.drawElements;
    G.createBuffer = function () { if (S.on) { S.cr++; const st = new Error().stack.split('\n').slice(1, 7).map(l => (l.match(/wasm-function\[(\d+)\]/) || [, ''])[1]).join('<'); S.stacks[st] = (S.stacks[st] || 0) + 1; } return cB.call(this); };
    G.deleteBuffer = function (x) { if (S.on) S.del++; return dB.call(this, x); };
    G.bufferData = function (...a) { if (S.on) { const n = a[4] !== undefined ? a[4] : (typeof a[1] === 'number' ? a[1] : 0); const k = 'bufferData t' + a[0].toString(16) + ' u' + a[2].toString(16) + ' ' + n; S.h[k] = (S.h[k] || 0) + 1; } return bD.apply(this, a); };
    const r = window.requestAnimationFrame; window.requestAnimationFrame = function (f) { return r.call(window, t => { if (S.on) S.frames++; f(t); }); };
  });
  await p.goto(process.argv[2], { waitUntil: 'load', timeout: 180000 });
  await p.waitForTimeout(25000);
  const mesure = async (etq) => {
    await p.evaluate(() => { const S = window.__S; S.on = true; S.cr = S.del = S.frames = 0; S.h = {}; S.stacks = {}; });
    await p.waitForTimeout(10000);
    const s = await p.evaluate(() => { const S = window.__S; S.on = false; return { cr: S.cr, del: S.del, frames: S.frames, h: Object.entries(S.h).sort((a, b) => b[1] - a[1]).slice(0, 18), st: Object.entries(S.stacks).sort((a, b) => b[1] - a[1]).slice(0, 8) }; });
    console.log(`\n== ${etq} : ${s.frames} images, créés ${s.cr} (${(s.cr / Math.max(s.frames, 1)).toFixed(1)}/image), tués ${s.del}`);
    s.h.forEach(([k, v]) => console.log('  ', v, k));
    s.st.forEach(([k, v]) => console.log('   pile', v, k));
  };
  await mesure('menu');
  await p.mouse.click(597, 417);
  await p.keyboard.press('k');
  await p.waitForTimeout(40000);
  await mesure('après k');
  await b.close();
})().catch(e => { console.error(e); process.exit(1); });
