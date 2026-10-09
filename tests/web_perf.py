"""Coût CPU par image de la PWA dans Chromium : durée de chaque rappel
requestAnimationFrame (la boucle Godot y tourne), en conduite d'essai.
usage : web_perf.py URL durée_s sortie.json [capture.png]

Chaîne complète (2026-09-30) :
  1. tests/web_perf_export.sh <travail>/pn_tests/web_x [--masquer=hud,…]
  2. conteneur à GPU (python-lab n'a pas /dev/dri) :
     docker run -d --name pn-gpu --device /dev/dri --group-add 44 --group-add 107 -u 0 \
       -v <travail>:/home/jovyan/work --entrypoint sleep \
       quay.io/jupyter/scipy-notebook:latest infinity
     + apt-get install des bibliothèques Playwright et de Mesa (libgl1-mesa-dri
       libegl1 mesa-vulkan-drivers libvulkan1), puis un http.server sur 8767
  3. PLAYWRIGHT_BROWSERS_PATH=/home/jovyan/work/venv/ms-playwright
     venv/bin/python web_perf.py http://localhost:8767/web_x/index.html 60 x.json
  4. web_perf_stats.py x.json (web_profile.py + web_profile_stats.py /
     web_profile_spikes.py pour le profil CPU et la pile des images lentes)"""
import sys, time, json
from playwright.sync_api import sync_playwright
URL, DUR, OUT = sys.argv[1], float(sys.argv[2]), sys.argv[3]
SAFARI = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/18.0 Safari/605.1.15")
with sync_playwright() as p:
    # GPU réel (Radeon 740M via ANGLE/Vulkan, conteneur pn-gpu avec /dev/dri)
    b = p.chromium.launch(headless=True, ignore_default_args=["--mute-audio"], args=[
        "--autoplay-policy=no-user-gesture-required", "--use-angle=vulkan",
        "--enable-features=Vulkan", "--ignore-gpu-blocklist", "--enable-gpu"])
    # iPad Pro 13" : 1376×1032 points, facteur 2
    ctx = b.new_context(viewport={"width": 1376, "height": 1032}, device_scale_factor=2,
        # UA de l'iPad (Safari se présente en Mac) → lecture audio STREAM,
        # mixée en wasm sur le fil principal comme sur l'iPad
        user_agent=SAFARI)
    pg = ctx.new_page()
    logs = []
    pg.on("console", lambda m: logs.append(m.text))
    pg.goto(URL)
    t0 = time.time()
    while time.time() - t0 < DUR:
        time.sleep(2)
    if len(sys.argv) > 4:
        pg.screenshot(path=sys.argv[4])
    d = pg.evaluate("window.__pn")
    json.dump({"d": d["d"], "t": d["t"], "logs": logs[-40:]}, open(OUT, "w"))
    b.close()
print("\n".join(l for l in logs if "DriveTest" in l or "rror" in l)[:3000])
