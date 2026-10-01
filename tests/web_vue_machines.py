"""Conduite d'essai : capture et chronométrage en vue cabine puis en vue
salle des machines (touche V deux fois). usage : URL sortie_prefixe"""
import sys, time, json, statistics as st
from playwright.sync_api import sync_playwright
URL, OUT = sys.argv[1], sys.argv[2]
SAFARI = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/18.0 Safari/605.1.15")
with sync_playwright() as p:
    b = p.chromium.launch(headless=True, ignore_default_args=["--mute-audio"], args=[
        "--autoplay-policy=no-user-gesture-required", "--use-angle=vulkan",
        "--enable-features=Vulkan", "--ignore-gpu-blocklist", "--enable-gpu"])
    ctx = b.new_context(viewport={"width": 1376, "height": 1032}, device_scale_factor=2, user_agent=SAFARI)
    pg = ctx.new_page()
    pg.goto(URL); time.sleep(60)
    pg.screenshot(path=f"{OUT}_cabine.png")
    i0 = pg.evaluate("window.__pn.d.length"); time.sleep(20)
    i1 = pg.evaluate("window.__pn.d.length")
    pg.keyboard.press("v"); time.sleep(1); pg.keyboard.press("v"); time.sleep(3)
    i2 = pg.evaluate("window.__pn.d.length"); time.sleep(20)
    i3 = pg.evaluate("window.__pn.d.length")
    pg.screenshot(path=f"{OUT}_machines.png")
    d = pg.evaluate("window.__pn")
    b.close()
for nom, a, z in (("cabine", i0, i1), ("salle des machines", i2, i3)):
    x = sorted(d["d"][a:z]); ts = d["t"][a:z]
    iv = sorted(ts[k+1] - ts[k] for k in range(len(ts) - 1))
    print(f"{nom:20s} {len(x)} images : rappel méd {st.median(x):.2f} p99 {x[int(.99*len(x))]:.2f} max {x[-1]:.1f} ms ; intervalle p99 {iv[int(.99*len(iv))]:.1f}, > 20 ms : {sum(1 for v in iv if v > 20)}")
