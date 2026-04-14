"""Track the lowest visible sweeping harmonic with a Viterbi-like
continuity-constrained peak tracker.

From zoom_ramp.png, the lowest sweep starts at t=46s around 50 Hz
and climbs linearly to ~220 Hz by t=90s. We anchor the tracker at
(t=46, f in [40,80]) and for each subsequent frame we look for the
peak within +- 15 Hz of the previous estimate, enforcing a maximum
slew rate of ~6 Hz/s (corresponding to a_peak ~ 0.35 m/s^2 if
f_cruise/v_cruise ~ 20 Hz per m/s).

After the ramp completes, we hold the peak at a stable plateau and
then track the descent at the end of the video (symmetric).
"""
import numpy as np
import librosa
import scipy.signal
import matplotlib.pyplot as plt
import json

y, sr = librosa.load("machinerie_full.wav", sr=22050, mono=True)
n_fft, hop = 16384, 512
V_CRUISE = 12.0   # full V_MAX cruise (this video runs at 100 % throttle)

S = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
times = librosa.frames_to_time(np.arange(S.shape[1]), sr=sr, hop_length=hop)
bin_hz = freqs[1] - freqs[0]
dt = hop / sr
print(f"STFT : {S.shape[1]} frames, bin={bin_hz:.3f} Hz, dt={dt*1000:.1f} ms")

# Detrend : subtract rolling-median spectrum over 30 s windows so
# stationary tones cancel but slow structural changes survive.
win_frames = int(round(30.0 / dt))
# scipy medfilt is slow over 2D. Use simple moving median approximation :
# subtract the overall time-median, then further subtract blocks.
med_global = np.median(S, axis=1, keepdims=True)
S_d = np.clip(S - med_global, 0, None)

# Anchor point --------------------------------------------------------
t_anchor = 46.0
k_anchor = int(round((t_anchor - times[0]) / dt))
# Search anchor peak in 40-90 Hz
lo, hi = 40.0, 90.0
bin_lo = int(round(lo / bin_hz))
bin_hi = int(round(hi / bin_hz))
col = S_d[bin_lo:bin_hi+1, k_anchor]
k0 = int(np.argmax(col))
f_anchor = float(freqs[bin_lo + k0])
print(f"Anchor at t={t_anchor} s, f={f_anchor:.1f} Hz")

# Forward tracking ---------------------------------------------------
N = S.shape[1]
track = np.full(N, np.nan)
track[k_anchor] = f_anchor
SLEW_HZ_S = 8.0     # max frequency change per second
WIN_HZ = 12.0       # +- search window around prediction

for i in range(k_anchor + 1, N):
    prev = track[i-1]
    # Predict : constant velocity (use last 2 frames)
    if i >= 2 and not np.isnan(track[i-2]):
        vel = (track[i-1] - track[i-2]) / dt
        vel = max(-SLEW_HZ_S, min(SLEW_HZ_S, vel))
    else:
        vel = 0.0
    pred = prev + vel * dt
    # Search band
    lo_f = max(20.0, pred - WIN_HZ)
    hi_f = min(1500.0, pred + WIN_HZ)
    bl = int(round(lo_f / bin_hz))
    bh = int(round(hi_f / bin_hz))
    col = S_d[bl:bh+1, i]
    if col.size == 0:
        track[i] = pred
        continue
    k = int(np.argmax(col))
    if 0 < k < len(col) - 1:
        a, b, c = col[k-1], col[k], col[k+1]
        denom = (a - 2*b + c)
        delta = 0.5 * (a - c) / denom if abs(denom) > 1e-12 else 0.0
    else:
        delta = 0.0
    cand = freqs[bl + k] + delta * bin_hz
    # Limit slew to +/- SLEW_HZ_S
    if cand - prev > SLEW_HZ_S * dt:
        cand = prev + SLEW_HZ_S * dt
    elif prev - cand > SLEW_HZ_S * dt:
        cand = prev - SLEW_HZ_S * dt
    track[i] = cand

# Backward tracking for t < anchor ---------------------------------
# Before anchor, motor is idling — pitch should be flat around f_anchor_idle
for i in range(k_anchor - 1, -1, -1):
    # Before motor engagement we expect the tracker to stick on its
    # initial value. Just copy anchor.
    track[i] = f_anchor

# Smooth lightly
track_s = scipy.signal.medfilt(track, kernel_size=7)
ha = int(round(0.3/dt))
if ha % 2 == 0: ha += 1
win = np.hanning(ha); win /= win.sum()
track_ss = np.convolve(track_s, win, mode="same")

# Calibration : at anchor t=46 s, cable is at rest -> v=0
# At cruise plateau (find plateau automatically)
# Plateau = first 60 s with d(track)/dt < 0.3 Hz/s starting after t=80 s
def find_plateau(track, times, start_t=80.0, max_slope=1.0, length_s=30.0):
    dtr = np.gradient(track, dt)
    # 1-s smoothed slope
    k = max(3, int(round(1.0/dt)))
    if k%2==0: k+=1
    w = np.hanning(k); w /= w.sum()
    dtr_s = np.convolve(dtr, w, mode="same")
    for i, ti in enumerate(times):
        if ti < start_t: continue
        j = i + int(round(length_s/dt))
        if j >= len(times): break
        if np.all(np.abs(dtr_s[i:j]) < max_slope):
            return float(np.median(track[i:j])), float(ti), float(times[j])
    return float(np.percentile(track[times>start_t], 90)), start_t, times[-1]

f_plateau, tp_lo, tp_hi = find_plateau(track_ss, times)
f_idle = f_anchor
print(f"Idle pitch (anchor t=46s) = {f_idle:.1f} Hz")
print(f"Cruise plateau = {f_plateau:.1f} Hz, stable from "
      f"[{tp_lo:.1f}, {tp_hi:.1f}] s")
print(f"Ratio cruise/idle = {f_plateau/f_idle:.2f}x")

def f_to_v(f):
    return V_CRUISE * (f - f_idle) / max(f_plateau - f_idle, 1.0)

v = f_to_v(track_ss)
v = np.clip(v, -0.5, V_CRUISE * 1.3)

# Acceleration, 1-s Hann smooth
a = np.gradient(v, dt)
kal = int(round(1.0/dt));
if kal % 2 == 0: kal += 1
wa = np.hanning(kal); wa /= wa.sum()
a = np.convolve(a, wa, mode="same")

# Launch time (v reaches 0.5 m/s in segment)
SEG_LO, SEG_HI = 46.0, 100.0
seg_mask = (times >= SEG_LO) & (times <= SEG_HI)
seg_idx = np.where(seg_mask)[0]
lnc = np.where(v[seg_mask] >= 0.5)[0]
t_launch = float(times[seg_idx[lnc[0]]]) if len(lnc) else SEG_LO

# Metrics
over90 = np.where((times >= t_launch) & (v >= 0.90 * V_CRUISE))[0]
over95 = np.where((times >= t_launch) & (v >= 0.95 * V_CRUISE))[0]
t90 = float(times[over90[0]] - t_launch) if len(over90) else float("nan")
t95 = float(times[over95[0]] - t_launch) if len(over95) else float("nan")
lmask = (times >= t_launch) & (times <= t_launch + 60)
a_peak = float(np.nanmax(a[lmask]))
init_mask = (times >= t_launch) & (v < 1.5)
a_init = float(np.nanmedian(a[init_mask])) if init_mask.any() else float("nan")
mid_mask = (times >= t_launch) & (times <= t_launch + 60) & (v > 2) & (v < 8)
a_mid = float(np.nanmean(a[mid_mask])) if mid_mask.any() else float("nan")

print(f"t_launch={t_launch:.2f}s  a_init={a_init:.3f}  a_mid={a_mid:.3f}  "
      f"a_peak={a_peak:.3f}")
print(f"t 0.9 Vc = {t90:.2f}s   t 0.95 Vc = {t95:.2f}s")

# S-curve fit
from scipy.optimize import curve_fit
def s_curve(vv, A_s, A_t, V_s):
    return A_s + (A_t - A_s) * np.minimum(1.0, vv / V_s)
fmask = (times >= t_launch) & (times <= t_launch + 50) & (v > 0.3) & (v < 10.3)
try:
    popt, _ = curve_fit(s_curve, v[fmask], a[fmask],
                        p0=[0.12, 0.30, 3.0],
                        bounds=([0.03, 0.1, 0.5], [0.4, 0.7, 7.0]))
    A_s_fit, A_t_fit, V_s_fit = popt
    print(f"S-curve fit : A_start={A_s_fit:.3f}  A_target={A_t_fit:.3f}  "
          f"V_soft={V_s_fit:.2f}")
except Exception as e:
    A_s_fit = A_t_fit = V_s_fit = float("nan")
    print("fit failed:", e)

samples = []
for tt in np.arange(t_launch, t_launch + 50, 2.0):
    if tt > times[-1]:
        break
    idx = int(round((tt - times[0]) / dt))
    if 0 <= idx < len(v):
        samples.append({
            "t_since_launch_s": round(float(times[idx] - t_launch), 2),
            "pitch_Hz":         round(float(track_ss[idx]), 2),
            "v_m_s":            round(float(v[idx]), 2),
            "a_m_s2":           round(float(a[idx]), 3),
        })

summary = {
    "method": ("Viterbi-like peak tracker on median-detrended "
               "spectrogram. Anchor at t=46 s in band 40-90 Hz "
               "(motor idle pitch). Forward tracking with max slew "
               "8 Hz/s and +/-12 Hz search window. Idle -> v=0, "
               "cruise plateau (auto-detected) -> v=10.1 m/s."),
    "video":          "sons/videos/funiculaire_machinerie_1080p.mp4",
    "segment":        [SEG_LO, SEG_HI],
    "anchor_t_s":     t_anchor,
    "pitch_idle_Hz":  round(f_idle, 2),
    "pitch_cruise_Hz": round(f_plateau, 2),
    "pitch_ratio":    round(f_plateau / f_idle, 2),
    "v_cruise_ref_m_s": V_CRUISE,
    "t_launch_abs_s": round(t_launch, 2),
    "a_init_m_s2":    round(a_init, 3),
    "a_mid_m_s2":     round(a_mid, 3),
    "a_peak_m_s2":    round(a_peak, 3),
    "t_to_0p9_vc_s":  round(t90, 2) if not np.isnan(t90) else None,
    "t_to_0p95_vc_s": round(t95, 2) if not np.isnan(t95) else None,
    "s_curve_fit": {
        "A_start_m_s2":    round(float(A_s_fit), 3),
        "A_target_m_s2":   round(float(A_t_fit), 3),
        "V_soft_ramp_m_s": round(float(V_s_fit), 2),
    },
    "sim_reference": {"A_START": 0.12, "A_TARGET": 0.30,
                      "V_SOFT_RAMP": 3.0},
    "samples_2s_steps": samples,
}
with open("calibration_v3.json", "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)
print("wrote calibration_v3.json")

# Plots
Sdb = librosa.amplitude_to_db(S + 1e-9)
kmax = int(round(300 / bin_hz))
fig, axes = plt.subplots(3, 1, figsize=(12, 10), sharex=True)
ax = axes[0]
im = ax.imshow(Sdb[:kmax, :], origin="lower", aspect="auto",
               extent=[times[0], times[-1], 0, 300], cmap="magma",
               vmin=Sdb.max()-50, vmax=Sdb.max()-5)
ax.plot(times, track_ss, color="#4ec9ff", lw=1.0, label="Tracked peak")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.08)
ax.axhline(f_idle, color="orange", ls=":", lw=1,
           label=f"Idle {f_idle:.1f} Hz -> v=0")
ax.axhline(f_plateau, color="lime", ls=":", lw=1,
           label=f"Cruise {f_plateau:.1f} Hz -> v={V_CRUISE}")
ax.set_ylabel("Hz")
ax.legend(loc="upper right", fontsize=8)
ax.set_title("Spectrogram 0-300 Hz + Viterbi-tracked peak")

ax = axes[1]
ax.plot(times, v, color="#4ec9ff", lw=1.2)
ax.axhline(V_CRUISE, color="lime", ls=":", alpha=0.6,
           label=f"v_cruise={V_CRUISE} m/s")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.10)
ax.axvline(t_launch, color="w", ls="--", alpha=0.4,
           label=f"Launch {t_launch:.1f} s")
ax.set_ylabel("v (m/s)")
ax.set_ylim(-1, V_CRUISE*1.2)
ax.grid(alpha=0.3)
ax.legend(loc="lower right", fontsize=8)

ax = axes[2]
ax.plot(times, a, color="#ffd34d", lw=1.2)
ax.axhline(0.30, color="lime", ls="--", alpha=0.5, label="Sim A_TARGET")
ax.axhline(0.12, color="orange", ls="--", alpha=0.5, label="Sim A_START")
ax.axhline(-0.25, color="#ff8888", ls="--", alpha=0.4,
           label="Sim A_NATURAL_UP (coast decel)")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.10)
ax.axvline(t_launch, color="w", ls="--", alpha=0.4)
ax.set_ylim(-0.5, 0.5)
ax.set_ylabel("a (m/s2)")
ax.set_xlabel("Time (s)")
ax.grid(alpha=0.3)
ax.legend(loc="upper right", fontsize=8, ncol=2)

plt.tight_layout()
plt.savefig("calibration_v3.png", dpi=130, facecolor="#0b0f1a")
print("wrote calibration_v3.png")

# Focused launch plot
fig, axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True)
ax = axes[0]
ax.plot(times - t_launch, v, color="#4ec9ff", lw=1.3)
ax.axhline(V_CRUISE, color="lime", ls=":", alpha=0.5,
           label=f"v_cruise={V_CRUISE} m/s")
ax.set_ylabel("v (m/s)")
ax.set_xlim(-3, 55)
ax.set_ylim(-0.5, V_CRUISE * 1.2)
ax.grid(alpha=0.3)
ax.legend(loc="lower right")
ax.set_title(f"Launch ramp derived from pitch tracking (video 0:46)")
ax = axes[1]
ax.plot(times - t_launch, a, color="#ffd34d", lw=1.3,
        label="Measured a(t)")
if not np.isnan(A_s_fit):
    a_model = s_curve(v, A_s_fit, A_t_fit, V_s_fit)
    ax.plot(times - t_launch, a_model, color="#66ff66", lw=1.3, ls="--",
            label=f"S-curve fit : A_s={A_s_fit:.2f}  A_t={A_t_fit:.2f}  "
                  f"V_s={V_s_fit:.1f} m/s")
ax.axhline(0.30, color="lime", ls=":", alpha=0.5, label="Sim A_TARGET=0.30")
ax.axhline(0.12, color="orange", ls=":", alpha=0.5, label="Sim A_START=0.12")
ax.set_xlabel("Time since launch (s)")
ax.set_ylabel("a (m/s2)")
ax.set_xlim(-3, 55)
ax.set_ylim(-0.3, 0.55)
ax.grid(alpha=0.3)
ax.legend(loc="upper right", fontsize=8)
plt.tight_layout()
plt.savefig("launch_profile_v3.png", dpi=130, facecolor="#0b0f1a")
print("wrote launch_profile_v3.png")
