// Mémoire réelle de la PWA dans WebKit : tas wasm, octets et objets envoyés à WebGL.
// usage : node memoire.js <url> <largeur> <hauteur> <secondes menu> <secondes skieur>
const pw = require('/qnh/node_modules/playwright');
const [url, W, H, T1, T2] = [process.argv[2], +process.argv[3] || 1194, +process.argv[4] || 834, +process.argv[5] || 40, +process.argv[6] || 120];
(async () => {
  const b = await pw.webkit.launch();
  const ctx = await b.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 2 });
  const p = await ctx.newPage();
  await p.addInitScript(() => {
    const S = window.__S = { prog: 0, progMort: 0, shad: 0, mem: null, perdu: 0, buf: new Map(), tex: new Map(), rb: new Map(), bufCrees: 0, bufTues: 0, texCrees: 0, texTues: 0, gros: [] };
    const garde = r => { try { const m = (r.instance || r).exports.memory; if (m) S.mem = m; } catch (e) {} return r; };
    for (const n of ['instantiate', 'instantiateStreaming']) { const o = WebAssembly[n]; if (o) WebAssembly[n] = function (...a) { return o.apply(this, a).then(garde); }; }
    const Mm = WebAssembly.Memory;
    WebAssembly.Memory = function (d) { const m = new Mm(d); S.mem = m; return m; };
    WebAssembly.Memory.prototype = Mm.prototype;
    const G = WebGL2RenderingContext.prototype;
    const w = (n, f) => { const o = G[n]; G[n] = function (...a) { const r = o.apply(this, a); f(a, r, this); return r; }; };
    const lie = new Map(), lieT = new Map(); let rbLie = null;
    w('createProgram', () => S.prog++);
    w('deleteProgram', () => S.progMort++);
    w('createShader', () => S.shad++);
    w('createBuffer', (a, r) => { S.bufCrees++; S.buf.set(r, 0); });
    w('deleteBuffer', a => { S.bufTues++; S.buf.delete(a[0]); });
    w('bindBuffer', a => lie.set(a[0], a[1]));
    w('bufferData', a => { const b = lie.get(a[0]); const n = a[4] !== undefined ? a[4] : (typeof a[1] === 'number' ? a[1] : (a[1] ? a[1].byteLength : 0)); if (b) S.buf.set(b, n); });
    w('createTexture', (a, r) => { S.texCrees++; S.tex.set(r, 0); });
    w('deleteTexture', a => { S.texTues++; S.tex.delete(a[0]); });
    w('activeTexture', a => { S.unit = a[0]; });
    w('bindTexture', a => lieT.set((S.unit || 0) + ':' + a[0], a[1]));
    const bpp = { 0x8058: 4, 0x1908: 4, 0x8051: 3, 0x1907: 3, 0x8229: 1, 0x1903: 1, 0x822B: 2, 0x881A: 8, 0x8814: 16, 0x8D62: 2, 0x8C3A: 4, 0x8C43: 4, 0x81A5: 2, 0x81A6: 3, 0x81A7: 4, 0x88F0: 4, 0x8CAC: 4 };
    w('texImage2D', a => { if (a.length < 8) return; const t = lieT.get((S.unit || 0) + ':' + a[0]); if (!t) return; const n = a[3] * a[4] * (bpp[a[2]] || 4); S.niv = S.niv || new Map(); const cle = S.niv.get(t) || {}; S.niv.set(t, cle); S.tex.set(t, (S.tex.get(t) || 0) - (cle[a[1]] || 0) + n); cle[a[1]] = n; if (!a[1]) (S.dim = S.dim || new Map()).set(t, a[3] + 'x' + a[4] + '/' + a[2].toString(16)); if (n > 4e6) S.gros.push(a[3] + 'x' + a[4] + '/' + a[2].toString(16) + ' niv' + a[1]); });
    w('texStorage2D', a => { const t = lieT.get((S.unit || 0) + ':' + a[0]); if (!t) return; const n = a[3] * a[4] * (bpp[a[2]] || 4) * (a[1] > 1 ? 1.33 : 1); S.tex.set(t, n); (S.dim = S.dim || new Map()).set(t, a[3] + 'x' + a[4] + '/' + a[2].toString(16) + 'S' + a[1]); if (n > 4e6) S.gros.push(a[3] + 'x' + a[4] + '/' + a[2].toString(16) + ' S' + a[1]); });
    w('compressedTexImage2D', a => { const t = lieT.get((S.unit || 0) + ':' + a[0]); if (!t) return; const n = a.length > 7 ? (a[8] || 0) : 0; S.tex.set(t, (S.tex.get(t) || 0) + n); });
    w('bindRenderbuffer', a => { rbLie = a[1]; });
    w('createRenderbuffer', (a, r) => S.rb.set(r, 0));
    w('deleteRenderbuffer', a => S.rb.delete(a[0]));
    w('renderbufferStorage', a => { if (rbLie) S.rb.set(rbLie, a[2] * a[3] * (bpp[a[1]] || 4)); });
    w('renderbufferStorageMultisample', a => { if (rbLie) { S.rb.set(rbLie, a[1] * a[3] * a[4] * (bpp[a[2]] || 4)); S.gros.push('RB ' + a[3] + 'x' + a[4] + ' x' + a[1]); } });
    document.addEventListener('webglcontextlost', () => S.perdu++, true);
  });
  const log = [];
  p.on('console', m => log.push(m.text()));
  p.on('pageerror', e => log.push('pageerror: ' + e.message.slice(0, 200)));
  const t0 = Date.now();
  const lire = async (etiq) => {
    const s = await p.evaluate(() => { const S = window.__S, c = document.querySelector('canvas'), so = m => { let t = 0; for (const v of m.values()) t += v; return t; }, gt = (m, k) => { let n = 0; for (const v of m.values()) if (v >= k) n++; return n; }; return { tas: S.mem ? S.mem.buffer.byteLength : 0, prog: S.prog, pm: S.progMort, bc: S.bufCrees, bt: S.bufTues, bv: S.buf.size, bo: so(S.buf), tc: S.texCrees, tt: S.texTues, tv: S.tex.size, to: so(S.tex), tvide: gt(S.tex, 1), rb: so(S.rb), perdu: S.perdu, cw: c && c.width, ch: c && c.height, gros: (() => { const h = {}; for (const [t, n] of S.tex) { const d = (S.dim && S.dim.get(t)) || '?'; h[d] = h[d] || [0, 0]; h[d][0]++; h[d][1] += n; } return Object.entries(h).sort((a, b) => b[1][1] - a[1][1]).slice(0, 25).map(([d, v]) => d + ' ×' + v[0] + ' = ' + (v[1] / 1048576).toFixed(1) + ' Mo'); })() }; });
    const M = x => (x / 1048576).toFixed(0);
    console.log(`${etiq.padEnd(7)} t=${String(Math.round((Date.now() - t0) / 1000)).padStart(4)}s tas=${M(s.tas)} | prog ${s.prog}-${s.pm} | tampons créés ${s.bc} tués ${s.bt} vivants ${s.bv} = ${M(s.bo)} Mo | textures créées ${s.tc} tuées ${s.tt} vivantes ${s.tv} (non vides ${s.tvide}) = ${M(s.to)} Mo | RB ${M(s.rb)} Mo | canvas ${s.cw}x${s.ch} perdu=${s.perdu}`);
    lire.gros = s.gros;
  };
  await p.goto(url, { waitUntil: 'load', timeout: 180000 });
  for (let i = 0; i < T1 / 10; i++) { await p.waitForTimeout(10000); await lire('menu'); }
  await p.mouse.click(W / 2, H / 2);
  await p.keyboard.press('k');
  for (let i = 0; i < T2 / 20; i++) { await p.waitForTimeout(20000); await lire('skieur'); }
  await p.screenshot({ path: '/out/memoire.png' });
  console.log(log.filter(l => /pageerror|SCRIPT ERROR|USER ERROR|\[Perf\] cran|Module/.test(l)).slice(0, 15).join('\n'));
  console.log('GROS: ' + (lire.gros||[]).join('\n  '));
  await b.close();
})().catch(e => { console.error(e); process.exit(1); });
