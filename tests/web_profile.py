"""Profil CPU (CDP) de la PWA en conduite d'essai : temps propre par
fonction JS/wasm, et pile des images les plus longues.
usage : web_profile.py URL t_debut t_fin sortie.json"""
import sys, time, json
from playwright.sync_api import sync_playwright
URL, T0, T1, OUT = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
SAFARI = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/18.0 Safari/605.1.15")
with sync_playwright() as p:
    b = p.chromium.launch(headless=True, ignore_default_args=["--mute-audio"], args=[
        "--autoplay-policy=no-user-gesture-required", "--use-angle=vulkan",
        "--enable-features=Vulkan", "--ignore-gpu-blocklist", "--enable-gpu"])
    ctx = b.new_context(viewport={"width": 1376, "height": 1032}, device_scale_factor=2,
        # UA de l'iPad (Safari se présente en Mac) → lecture audio STREAM,
        # mixée en wasm sur le fil principal comme sur l'iPad
        user_agent=SAFARI)
    pg = ctx.new_page()
    cdp = ctx.new_cdp_session(pg)
    cdp.send("Profiler.enable")
    cdp.send("Profiler.setSamplingInterval", {"interval": 200})
    pg.goto(URL)
    t0 = time.time()
    while time.time() - t0 < T0:
        time.sleep(0.5)
    cdp.send("Profiler.start")
    pstart = pg.evaluate("performance.now()")
    while time.time() - t0 < T1:
        time.sleep(0.5)
    prof = cdp.send("Profiler.stop")["profile"]
    d = pg.evaluate("window.__pn")
    json.dump({"profile": prof, "d": d["d"], "t": d["t"], "pstart": pstart}, open(OUT, "w"))
    b.close()
