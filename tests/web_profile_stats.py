"""Temps propre et inclusif par fonction d'un profil de web_profile.py."""
import json, sys, collections
d = json.load(open(sys.argv[1]))
prof = d["profile"]
nodes = {n["id"]: n for n in prof["nodes"]}
parent = {}
for n in prof["nodes"]:
    for c in n.get("children", []):
        parent[c] = n["id"]
def name(nid):
    cf = nodes[nid]["callFrame"]
    fn = cf["functionName"] or "(anon)"
    return fn if not cf["url"] else fn + (" [wasm]" if cf["url"].startswith("wasm") else "")
self_t = collections.Counter()
incl_t = collections.Counter()
samples, deltas = prof["samples"], prof["timeDeltas"]
tot = 0.0
for s, dt in zip(samples, deltas[1:] + [0]):
    dt /= 1000.0
    tot += dt
    self_t[name(s)] += dt
    seen = set(); nid = s
    while nid in nodes:
        nm = name(nid)
        if nm not in seen:
            incl_t[nm] += dt; seen.add(nm)
        nid = parent.get(nid, -1)
dur = (prof["endTime"] - prof["startTime"]) / 1000.0
print(f"durée {dur:.0f} ms échantillonnée")
print("--- temps propre (hors idle) ---")
for k, v in self_t.most_common(30):
    print(f"  {v:8.0f} ms {100*v/dur:5.1f} %  {k}")
print("--- temps inclusif, fonctions JS nommées ---")
for k, v in incl_t.most_common(60):
    if "wasm-function" in k: continue
    print(f"  {v:8.0f} ms {100*v/dur:5.1f} %  {k}")
