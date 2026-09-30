"""Statistiques des rappels requestAnimationFrame relevés par web_perf.py."""
import json, statistics as st, sys
for f in sys.argv[1:]:
    d = json.load(open(f))
    dur, ts = d["d"], d["t"]
    iv = [ts[i+1] - ts[i] for i in range(len(ts) - 1)]
    n = len(dur)
    print(f"{f}: {n} images")
    # dernier tiers = rame lancée
    for a, b in ((n // 3, 2 * n // 3), (2 * n // 3, n)):
        x = sorted(dur[a:b]); y = sorted(iv[a:b - 1])
        late = sum(1 for v in y if v > 20)
        print(f"  images {a}-{b}: rappel méd {st.median(x):5.2f} p90 {x[int(.9*len(x))]:5.2f} p99 {x[int(.99*len(x))]:5.2f} max {x[-1]:6.1f} ms"
              f" | intervalle méd {st.median(y):5.2f} p99 {y[int(.99*len(y))]:5.2f} ; >20 ms : {late}")
