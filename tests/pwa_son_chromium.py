"""Ouvre la PWA dans Chromium (sortie son PulseAudio), capture l'écran,
clique aux positions données, appuie sur des touches ; l'enregistrement
du son est fait à part (parec)."""
import sys, time, json
from playwright.sync_api import sync_playwright
URL = sys.argv[1]
ACTIONS = json.loads(sys.argv[2]) if len(sys.argv) > 2 else []
OUT = "/home/jovyan/work/pn_tests/_scratch/web_shot"
with sync_playwright() as p:
    b = p.chromium.launch(headless=True, ignore_default_args=["--mute-audio"],
        args=["--autoplay-policy=no-user-gesture-required", "--use-angle=swiftshader",
              "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    ctx = b.new_context(viewport={"width": 1280, "height": 800},
        user_agent="Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36")
    pg = ctx.new_page()
    logs = []
    pg.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
    pg.on("pageerror", lambda e: logs.append(f"[pageerror] {e}"))
    pg.goto(URL)
    t0 = time.time()
    for a in ACTIONS:
        kind = a[0]
        if kind == "wait":
            time.sleep(a[1])
        elif kind == "shot":
            pg.screenshot(path=f"{OUT}_{a[1]}.png")
        elif kind == "click":
            pg.mouse.click(a[1], a[2])
        elif kind == "key":
            pg.keyboard.press(a[1])
        print(f"{time.time()-t0:6.1f} s  {a}", flush=True)
    b.close()
    for l in logs[-60:]:
        print(l)
