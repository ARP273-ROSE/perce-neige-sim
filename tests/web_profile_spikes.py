"""Pile des images longues (> seuil ms) d'un profil de web_profile.py.
usage : web_profile_spikes.py profil.json [seuil_ms]"""
import json, sys, collections
d = json.load(open(sys.argv[1])); seuil = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
prof = d["profile"]
nodes = {n["id"]: n for n in prof["nodes"]}
parent = {}
for n in prof["nodes"]:
    for c in n.get("children", []):
        parent[c] = n["id"]
def name(nid):
    cf = nodes[nid]["callFrame"]; return cf["functionName"] or "(anon)"
def stack(nid):
    out = []
    while nid in nodes:
        out.append(name(nid)); nid = parent.get(nid, -1)
    return out
samples, deltas = prof["samples"], prof["timeDeltas"]
t = prof["startTime"]; seg = []; segs = []
for s, dt in zip(samples, deltas[1:] + [0]):
    nm = name(s)
    if nm == "(idle)":
        if seg: segs.append(seg); seg = []
    else:
        seg.append((t, s, dt))
    t += dt
if seg: segs.append(seg)
t0 = prof["startTime"]
longs = [sg for sg in segs if sum(x[2] for x in sg) / 1000 > seuil]
print(f"{len(segs)} segments actifs, {len(longs)} > {seuil} ms")
for sg in longs[:12]:
    dur = sum(x[2] for x in sg) / 1000
    c = collections.Counter(); j = collections.Counter()
    for (tt, s, dt) in sg:
        st = stack(s); c[st[0]] += dt / 1000
        for f in set(st):
            if not f.startswith("wasm-function") and f not in ("(root)", "(anon)", "MainLoop_runner", "runIter", "callUserCallback", "js-to-wasm::", "wasm-to-js"):
                j[f] += dt / 1000
    print(f"\n t = {(sg[0][0]-t0)/1e6:6.2f} s  durée {dur:5.1f} ms ; propre : " + ", ".join(f"{k} {v:.1f}" for k, v in c.most_common(5)))
    print("   JS inclusif : " + ", ".join(f"{k} {v:.1f}" for k, v in j.most_common(8)))
