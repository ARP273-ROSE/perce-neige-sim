"""Track the swept harmonic after subtracting the stationary spectrum.

The machinery noise is dominated by stationary blower/fan/hum tones
(constant frequency). The sweeping harmonic we want is buried under
them. Trick : subtract the MEDIAN spectrum across time from every
frame — stationary tones cancel, only time-varying tones remain.
Then peak-pick in a narrow band.
"""
import numpy as np
import librosa
import scipy.signal
import matplotlib.pyplot as plt
import json

y, sr = librosa.load("machinerie_full.wav", sr=22050, mono=True)
n_fft, hop = 8192, 1024
V_CRUISE = 10.1

S = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
times = librosa.frames_to_time(np.arange(S.shape[1]), sr=sr, hop_length=hop)
bin_hz = freqs[1] - freqs[0]

# Subtract median spectrum along time axis (robust stationary removal)
median_spec = np.median(S, axis=1, keepdims=True)
S_detrend = np.clip(S - median_spec, 0, None)
S_det_db = 20 * np.log10(S_detrend + 1e-9)

# Restrict to 80-600 Hz (the sweep range we see in the spectrogram)
LO, HI = 80.0, 600.0
band_mask = (freqs >= LO) & (freqs <= HI)
Sb = S_detrend[band_mask, :]
fb = freqs[band_mask]

# Per-frame peak with parabolic refinement
peak_f = []
for i in range(Sb.shape[1]):
    col = Sb[:, i]
    k = int(np.argmax(col))
    if 0 < k < len(col) - 1:
        a, b, c = col[k-1], col[k], col[k+1]
        denom = (a - 2*b + c)
        delta = 0.5 * (a - c) / denom if abs(denom) > 1e-12 else 0.0
    else:
        delta = 0.0
    peak_f.append(fb[k] + delta * bin_hz)
peak_f = np.array(peak_f)
peak_f_s = scipy.signal.medfilt(peak_f, kernel_size=15)

# Smooth further via rolling mean 0.5 s
dt = hop / sr
win_len = max(3, int(round(0.5 / dt)))
if win_len % 2 == 0:
    win_len += 1
win = np.hanning(win_len); win /= win.sum()
peak_f_smooth = np.convolve(peak_f_s, win, mode="same")

# Idle — minimum sustained level, taken from first 5 s
mask_idle = (times >= 1.0) & (times <= 5.0)
f_idle = float(np.percentile(peak_f_smooth[mask_idle], 20))
# Cruise — plateau. Look for longest stable high-pitch plateau.
mask_cruise = (times >= 120.0) & (times <= 280.0)
f_cruise = float(np.percentile(peak_f_smooth[mask_cruise], 80))
print(f"Pitch idle={f_idle:.1f} Hz ; cruise={f_cruise:.1f} Hz ; "
      f"ratio {f_cruise/f_idle:.2f}")

def f_to_v(f):
    return V_CRUISE * (f - f_idle) / max(f_cruise - f_idle, 1.0)

v = f_to_v(peak_f_smooth)
v = np.clip(v, -1.0, V_CRUISE * 1.3)
a = np.gradient(v, dt)
win_len_a = int(round(1.5 / dt))
if win_len_a % 2 == 0:
    win_len_a += 1
wa = np.hanning(win_len_a); wa /= wa.sum()
a = np.convolve(a, wa, mode="same")

SEG_LO, SEG_HI = 46.0, 100.0
seg_mask = (times >= SEG_LO) & (times <= SEG_HI)
# Launch = first time v>0.5 after SEG_LO
seg_indices = np.where(seg_mask)[0]
launch_candidates = np.where(v[seg_mask] >= 0.5)[0]
t_launch_abs = float(times[seg_indices[launch_candidates[0]]]) \
    if len(launch_candidates) else SEG_LO
print(f"Launch @ t={t_launch_abs:.2f} s abs")

# Metrics
over90 = np.where((times >= t_launch_abs) & (v >= 0.90 * V_CRUISE))[0]
over95 = np.where((times >= t_launch_abs) & (v >= 0.95 * V_CRUISE))[0]
t90 = float(times[over90[0]] - t_launch_abs) if len(over90) else float("nan")
t95 = float(times[over95[0]] - t_launch_abs) if len(over95) else float("nan")

lmask = (times >= t_launch_abs) & (times <= t_launch_abs + 40)
a_peak = float(np.nanmax(a[lmask]))
a_init_mask = (times >= t_launch_abs) & (v < 1.5)
a_init = float(np.nanmedian(a[a_init_mask])) if a_init_mask.any() else float("nan")
a_mid_mask = (times >= t_launch_abs) & (times <= t_launch_abs + 40) & (v > 2) & (v < 8)
a_mid = float(np.nanmean(a[a_mid_mask])) if a_mid_mask.any() else float("nan")

# S-curve fit
from scipy.optimize import curve_fit
def s_curve(vv, A_s, A_t, V_s):
    return A_s + (A_t - A_s) * np.minimum(1.0, vv / V_s)
fmask = (times >= t_launch_abs) & (times <= t_launch_abs + 40) & (v > 0.3) & (v < 10.5)
try:
    popt, _ = curve_fit(s_curve, v[fmask], a[fmask],
                        p0=[0.1, 0.3, 3.0],
                        bounds=([0.02, 0.08, 0.5], [0.4, 0.8, 7.0]))
    A_s_fit, A_t_fit, V_s_fit = popt
    print(f"S-curve fit : A_start={A_s_fit:.3f} A_target={A_t_fit:.3f} "
          f"V_soft={V_s_fit:.2f}")
except Exception as e:
    A_s_fit = A_t_fit = V_s_fit = float("nan")
    print("fit failed:", e)

print(f"a_init(v<1.5)={a_init:.3f}  a_mid(2<v<8)={a_mid:.3f}  "
      f"a_peak={a_peak:.3f}")
print(f"t→0.9 v_c = {t90:.2f} s ; t→0.95 v_c = {t95:.2f} s")

# Sample table
samples = []
for tt in np.arange(t_launch_abs, t_launch_abs + 40, 2.0):
    if tt > times[-1]:
        break
    idx = int(round((tt - times[0]) / dt))
    if 0 <= idx < len(v):
        samples.append({
            "t_since_launch_s": round(float(times[idx] - t_launch_abs), 2),
            "pitch_Hz":         round(float(peak_f_smooth[idx]), 2),
            "v_m_s":            round(float(v[idx]), 2),
            "a_m_s2":           round(float(a[idx]), 3),
        })

summary = {
    "method": ("Dominant peak in 80-600 Hz band of the time-median-"
               "subtracted spectrogram (stationary tones removed). "
               "15-frame median + 0.5 s Hann smoothed. Linear map : "
               "f_idle (20th pctile, t=1-5 s) -> v=0 ; f_cruise (80th "
               "pctile, t=120-280 s plateau) -> v=v_cruise=10.1 m/s."),
    "video":            "sons/videos/funiculaire_machinerie_1080p.mp4",
    "segment_studied":  [SEG_LO, SEG_HI],
    "pitch_idle_Hz":    round(f_idle, 2),
    "pitch_cruise_Hz":  round(f_cruise, 2),
    "pitch_ratio":      round(f_cruise / f_idle, 2),
    "v_cruise_ref_m_s": V_CRUISE,
    "t_launch_absolute_s": round(t_launch_abs, 2),
    "a_init_v_lt_1p5_m_s2": round(a_init, 3),
    "a_mid_2_8_m_s2":       round(a_mid, 3),
    "a_peak_m_s2":          round(a_peak, 3),
    "t_to_0p9_vcruise_s":   round(t90, 2) if not np.isnan(t90) else None,
    "t_to_0p95_vcruise_s":  round(t95, 2) if not np.isnan(t95) else None,
    "s_curve_fit": {
        "A_start_m_s2":    round(float(A_s_fit), 3),
        "A_target_m_s2":   round(float(A_t_fit), 3),
        "V_soft_ramp_m_s": round(float(V_s_fit), 2),
    },
    "sim_reference": {"A_START": 0.12, "A_TARGET": 0.30,
                      "V_SOFT_RAMP": 3.0},
    "samples_2s_steps": samples,
}
with open("calibration_v2.json", "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)
print("Wrote calibration_v2.json")

# ------ plots ------
fig, axes = plt.subplots(3, 1, figsize=(12, 9), sharex=True)
ax = axes[0]
S_disp_max = int(round(800 / bin_hz))
ax.imshow(S_det_db[:S_disp_max, :], origin="lower", aspect="auto",
          extent=[times[0], times[-1], 0, 800], cmap="magma",
          vmin=S_det_db.max()-50, vmax=S_det_db.max())
ax.plot(times, peak_f_smooth, color="#4ec9ff", lw=0.8,
        label="Tracked peak (detrended)")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.10)
ax.axhline(f_idle, color="orange", ls=":", alpha=0.7,
           label=f"Idle {f_idle:.0f} Hz")
ax.axhline(f_cruise, color="lime", ls=":", alpha=0.7,
           label=f"Cruise {f_cruise:.0f} Hz")
ax.set_ylabel("Frequency (Hz)")
ax.legend(loc="upper right", fontsize=8)
ax.set_title("Detrended spectrogram 0-800 Hz + tracked peak")

ax = axes[1]
ax.plot(times, v, color="#4ec9ff", lw=1.0)
ax.axhline(V_CRUISE, color="lime", ls=":", alpha=0.6,
           label=f"v_cruise = {V_CRUISE} m/s")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.10)
ax.axvline(t_launch_abs, color="w", ls="--", alpha=0.4,
           label=f"Launch {t_launch_abs:.1f} s")
ax.set_ylabel("v (m/s)")
ax.set_ylim(-1, V_CRUISE*1.3)
ax.grid(alpha=0.3)
ax.legend(loc="lower right", fontsize=8)
ax.set_title("Inferred cable speed")

ax = axes[2]
ax.plot(times, a, color="#ffd34d", lw=1.0)
ax.axhline(0.30, color="lime", ls="--", alpha=0.6,
           label="Sim A_TARGET = 0.30 m/s²")
ax.axhline(0.12, color="orange", ls="--", alpha=0.6,
           label="Sim A_START = 0.12 m/s²")
ax.axhline(-0.25, color="#ff8888", ls="--", alpha=0.5,
           label="Sim A_NATURAL_UP = 0.25 m/s² (coast decel)")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.10)
ax.axvline(t_launch_abs, color="w", ls="--", alpha=0.4)
ax.set_ylabel("a (m/s²)")
ax.set_xlabel("Time in video (s)")
ax.set_ylim(-0.6, 0.6)
ax.grid(alpha=0.3)
ax.legend(loc="upper right", fontsize=7, ncol=2)
ax.set_title("Acceleration (1.5-s smoothed)")

plt.tight_layout()
plt.savefig("calibration_v2.png", dpi=120, facecolor="#0b0f1a")

# Focused on the launch segment
fig, axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True)
ax = axes[0]
ax.plot(times - t_launch_abs, v, color="#4ec9ff", lw=1.3,
        label="Pitch-derived v(t)")
ax.axhline(V_CRUISE, color="lime", ls=":", alpha=0.6,
           label=f"v_cruise = {V_CRUISE} m/s")
ax.set_ylabel("v (m/s)")
ax.set_xlim(-2, 45)
ax.set_ylim(-0.5, V_CRUISE * 1.2)
ax.grid(alpha=0.3)
ax.legend(loc="lower right", fontsize=9)
ax.set_title(f"Launch ramp derived from pitch tracking "
             f"(launch @ {t_launch_abs:.1f} s video time)")
ax = axes[1]
ax.plot(times - t_launch_abs, a, color="#ffd34d", lw=1.2,
        label="Measured a(t)")
# Overlay S-curve fit
if not np.isnan(A_s_fit):
    a_model = s_curve(v, A_s_fit, A_t_fit, V_s_fit)
    ax.plot(times - t_launch_abs, a_model, color="#66ff66", lw=1.3, ls="--",
            label=f"S-curve fit : A_s={A_s_fit:.2f}  A_t={A_t_fit:.2f}  "
                  f"V_s={V_s_fit:.1f}")
ax.axhline(0.30, color="lime", ls=":", alpha=0.5,
           label="Sim A_TARGET = 0.30")
ax.axhline(0.12, color="orange", ls=":", alpha=0.5,
           label="Sim A_START = 0.12")
ax.set_xlabel("Time since launch (s)")
ax.set_ylabel("a (m/s²)")
ax.set_xlim(-2, 45)
ax.set_ylim(-0.3, 0.6)
ax.grid(alpha=0.3)
ax.legend(loc="upper right", fontsize=8)

plt.tight_layout()
plt.savefig("launch_profile_v2.png", dpi=120, facecolor="#0b0f1a")
print("Wrote launch_profile_v2.png")
