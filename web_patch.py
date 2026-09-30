#!/usr/bin/env python3
"""Retouche de l'export Web après `godot --export-release "Web"`.

Présentation directe dans le canvas (retour du 30/09/2026 : « ça saccade
toujours le défilement du tunnel ») : Godot crée son contexte WebGL avec
`explicitSwapControl`, ce qui oblige Emscripten à dessiner dans un tampon
HORS ÉCRAN puis à le recopier dans le canvas à chaque image
(`blitOffscreenFramebuffer`), avec `preserveDrawingBuffer` forcé. Cette
recopie plein écran (2752 × 2064 sur l'iPad) commence par deux
`gl.getParameter` qui attendent le processeur graphique : dans Chromium sur
GPU réel, 13 % du temps du fil principal y passait et le coût d'une image
tombe de 6,6 à 3,4-4,0 ms sans elle (banc tests/web_perf.py). Godot dessine
chaque image en entier dans le rappel requestAnimationFrame : la
présentation implicite du navigateur suffit, le rendu est identique.

usage : web_patch.py build/web/index.js
"""
import sys

ANCIEN = ("if(contextAttributes.explicitSwapControl&&!contextAttributes.renderViaOffscreenBackBuffer)"
          "{contextAttributes.renderViaOffscreenBackBuffer=true}")
NOUVEAU = ("contextAttributes.explicitSwapControl=0;"
           "contextAttributes.renderViaOffscreenBackBuffer=0;")

p = sys.argv[1]
t = open(p, encoding="utf-8").read()
if NOUVEAU in t:
    print("web_patch : déjà appliqué")
elif t.count(ANCIEN) == 1:
    open(p, "w", encoding="utf-8").write(t.replace(ANCIEN, NOUVEAU))
    print("web_patch : présentation directe (sans tampon hors écran)")
else:
    sys.exit("web_patch : motif Emscripten introuvable — gabarit Web changé, "
             "vérifier _emscripten_webgl_do_create_context dans index.js")
