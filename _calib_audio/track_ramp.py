"""Track the fundamental swept harmonic across the launch ramp.

Observation from the spectrogram : a cluster of tonal lines sweeps
from ~100 Hz (idle) up to ~400-500 Hz during the 0:46 -> 1:40
acceleration, then holds during cruise, then descends at the end.

Strategy :
1. Restrict to 60-550 Hz band (kills fixed blower / fan tonals
   above 800 Hz).
2. Use harmonic-product-spectrum to collapse the harmonics into
   their fundamental, which is more robust than peak-picking.
3. Median-smooth with a 0.5 s kernel.
4. Calibrate : idle value = minimum observed ; cruise value = 99th
   percentile. Map (idle -> 0.5 m/s creep post-release, cruise ->
   10.1 m/s speed_cmd 84 %). Actually creep at release is ~0.5 m/s
   but the motor isn't driving yet — the pure idle whine is closer
   to blower only, so we take IDLE -> v = 0, CRUISE -> v = 10.1.
5. Differentiate -> acceleration profile. Report key metrics :
   a_peak, t_0.9*vcruise, S-curve fit parameters.
"""
import numpy as np
import librosa
import scipy.signal
import matplotlib.pyplot as plt
import json

y, sr = librosa.load("machinerie_full.wav", sr=22050, mono=True)
n_fft, hop = 8192, 1024
F0_LO, F0_HI = 60.0, 600.0      # fundamental search band
HPS_HARM = 4                     # harmonics to multiply in HPS
V_CRUISE = 10.1                  # m/s
SEG_LO, SEG_HI = 46.0, 100.0     # user segment

# Spectrogram
S = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
times = librosa.frames_to_time(np.arange(S.shape[1]), sr=sr, hop_length=hop)
bin_hz = freqs[1] - freqs[0]

# Harmonic product spectrum in the fundamental band ------------------
# For each frame, build HPS by downsampling S and multiplying
f0_min_bin = int(round(F0_LO / bin_hz))
f0_max_bin = int(round(F0_HI / bin_hz))
hps_band = np.zeros_like(S[f0_min_bin:f0_max_bin+1, :])

for h in range(1, HPS_HARM + 1):
    # For each candidate fundamental bin k, read S at k*h
    for k in range(f0_min_bin, f0_max_bin + 1):
        kh = k * h
        if kh < S.shape[0]:
            if h == 1:
                hps_band[k - f0_min_bin, :] += np.log(S[kh, :] + 1e-12)
            else:
                hps_band[k - f0_min_bin, :] += np.log(S[kh, :] + 1e-12)

f0_bins = np.arange(f0_min_bin, f0_max_bin + 1)
f0_freqs = freqs[f0_bins]

# Pick fundamental per frame with parabolic refinement
f0_track = []
for i in range(hps_band.shape[1]):
    col = hps_band[:, i]
    k = int(np.argmax(col))
    if 0 < k < len(col) - 1:
        a, b, c = col[k-1], col[k], col[k+1]
        denom = (a - 2*b + c)
        delta = 0.5 * (a - c) / denom if abs(denom) > 1e-12 else 0.0
    else:
        delta = 0.0
    f0_track.append(f0_freqs[k] + delta * bin_hz)
f0_track = np.array(f0_track)

# 0.5 s median smoothing
dt = hop / sr
kernel = max(3, int(round(0.5 / dt)))
if kernel % 2 == 0:
    kernel += 1
f0_s = scipy.signal.medfilt(f0_track, kernel_size=kernel)

# Idle (true background) — use first 5 s of clip (before any motion)
mask_idle = (times >= 1.0) & (times <= 5.0)
f0_idle = float(np.percentile(f0_s[mask_idle], 20))
# Cruise — highest sustained plateau. 99th percentile over mid-video.
mask_cruise = (times >= 150.0) & (times <= 250.0)
f0_cruise = float(np.percentile(f0_s[mask_cruise], 90))
print(f"Bandwidth idle -> cruise : {f0_idle:.1f} -> {f0_cruise:.1f} Hz")

# Linear map : f0 = f0_idle -> v = 0,  f0 = f0_cruise -> v = V_CRUISE
def f_to_v(f):
    return V_CRUISE * (f - f0_idle) / max(f0_cruise - f0_idle, 1.0)

v_track = f_to_v(f0_s)
# Clip at 0 (negative means below idle = noise)
v_track = np.maximum(v_track, 0.0)

# Focus on the user segment for the calibration deliverable ---------
seg_mask = (times >= SEG_LO) & (times <= SEG_HI)
t_seg = times[seg_mask]
v_seg = v_track[seg_mask]
f_seg = f0_s[seg_mask]

# Find launch (v rises above 0.5 m/s for the first time in segment)
launch_idx = np.where(v_seg >= 0.5)[0]
if len(launch_idx) == 0:
    t_launch_abs = SEG_LO
else:
    t_launch_abs = float(t_seg[launch_idx[0]])
print(f"Launch at t={t_launch_abs:.2f} s (absolute) = t-clip {t_launch_abs-SEG_LO:.2f} s")

# Acceleration : diff then 1-s Hann smooth
a_track = np.gradient(v_track, dt)
win_len = int(round(1.0 / dt))
if win_len % 2 == 0:
    win_len += 1
win = np.hanning(win_len); win /= win.sum()
a_track = np.convolve(a_track, win, mode="same")

# Plateau detection (cruise) — first time v >= 0.95*V_CRUISE after launch
mask_after = (times >= t_launch_abs)
over = np.where((times >= t_launch_abs) & (v_track >= 0.95 * V_CRUISE))[0]
t_to_95 = float(times[over[0]] - t_launch_abs) if len(over) else float("nan")
over90 = np.where((times >= t_launch_abs) & (v_track >= 0.90 * V_CRUISE))[0]
t_to_90 = float(times[over90[0]] - t_launch_abs) if len(over90) else float("nan")

# Peak acceleration during launch (first 30 s after launch)
lmask = (times >= t_launch_abs) & (times <= t_launch_abs + 30.0)
a_peak = float(np.nanmax(a_track[lmask]))
# Initial acceleration at v~0
init_mask = (times >= t_launch_abs) & (v_track < 2.0)
a_init = float(np.nanmedian(a_track[init_mask])) if init_mask.any() else float("nan")
# Mean accel over 2 <= v <= 8 m/s (cruise ramp)
mid_mask = (v_track > 2.0) & (v_track < 8.0) & (times >= t_launch_abs) & (times <= t_launch_abs + 30)
a_mid = float(np.nanmean(a_track[mid_mask])) if mid_mask.any() else float("nan")

# Fit S-curve : a(v) = A_START + (A_TARGET - A_START) * min(1, v / V_SOFT)
# via least squares on (v, a) points during launch
from scipy.optimize import curve_fit
def s_curve(v, A_start, A_target, V_soft):
    return A_start + (A_target - A_start) * np.minimum(1.0, v / V_soft)
fit_mask = (times >= t_launch_abs) & (times <= t_launch_abs + 40) & (v_track > 0.2) & (v_track < 10.5)
try:
    popt, _ = curve_fit(s_curve, v_track[fit_mask], a_track[fit_mask],
                        p0=[0.10, 0.30, 3.0],
                        bounds=([0.01, 0.05, 0.5], [0.5, 1.0, 8.0]))
    A_start_fit, A_target_fit, V_soft_fit = popt
except Exception as e:
    A_start_fit = A_target_fit = V_soft_fit = float("nan")
    print("fit failed :", e)

print(f"Fit : A_start={A_start_fit:.3f}  A_target={A_target_fit:.3f}  "
      f"V_soft={V_soft_fit:.2f}")
print(f"Peak a = {a_peak:.3f} m/s² ; a_init(v<2) = {a_init:.3f} ; "
      f"a_mid(2<v<8) = {a_mid:.3f}")
print(f"Time to 90% V_cruise = {t_to_90:.2f} s ; to 95 % = {t_to_95:.2f} s")

# Sim reference constants --------------------------------------------
SIM = {"A_START": 0.12, "A_TARGET": 0.30, "V_SOFT_RAMP": 3.0}
print(f"Sim reference : A_START={SIM['A_START']}, A_TARGET={SIM['A_TARGET']}, "
      f"V_SOFT_RAMP={SIM['V_SOFT_RAMP']}")

# Dump calibration summary ------------------------------------------
calib_samples = []
for target_t in np.arange(t_launch_abs, t_launch_abs + 40, 2.0):
    if target_t > times[-1]:
        break
    idx = int(round((target_t - times[0]) / dt))
    if 0 <= idx < len(v_track):
        calib_samples.append({
            "t_since_launch_s": round(float(times[idx] - t_launch_abs), 2),
            "pitch_Hz":         round(float(f0_s[idx]), 2),
            "v_m_s":            round(float(v_track[idx]), 2),
            "a_m_s2":           round(float(a_track[idx]), 3),
        })

summary = {
    "method": "Harmonic-product-spectrum fundamental tracking, 60-600 Hz band, 0.5 s median-smoothed. Scaled linearly : idle pitch (first 5 s of video) -> 0 m/s ; cruise pitch (90th pctile of t=150-250 s plateau) -> 10.1 m/s.",
    "video": "sons/videos/funiculaire_machinerie_1080p.mp4",
    "segment_studied": [SEG_LO, SEG_HI],
    "pitch_idle_Hz":    round(f0_idle, 2),
    "pitch_cruise_Hz":  round(f0_cruise, 2),
    "v_cruise_ref_m_s": V_CRUISE,
    "t_launch_absolute_s": round(t_launch_abs, 2),
    "a_init_v_lt_2_m_s2": round(a_init, 3),
    "a_mid_2_8_m_s2":     round(a_mid, 3),
    "a_peak_m_s2":        round(a_peak, 3),
    "t_to_0p9_vcruise_s": round(t_to_90, 2) if not np.isnan(t_to_90) else None,
    "t_to_0p95_vcruise_s": round(t_to_95, 2) if not np.isnan(t_to_95) else None,
    "s_curve_fit": {
        "A_start_m_s2":   round(float(A_start_fit), 3),
        "A_target_m_s2":  round(float(A_target_fit), 3),
        "V_soft_ramp_m_s": round(float(V_soft_fit), 2),
    },
    "sim_reference":     SIM,
    "samples_2s_steps":  calib_samples,
}
with open("calibration_final.json", "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)
print("Wrote calibration_final.json")

# ---------- figures -------------------------------------------------
fig, axes = plt.subplots(3, 1, figsize=(11, 9), sharex=True)

# 1 : pitch track over full video
ax = axes[0]
ax.plot(times, f0_s, color="#4ec9ff", lw=0.9)
ax.axhline(f0_idle, color="orange", ls=":", alpha=0.7,
           label=f"Idle  {f0_idle:.1f} Hz → 0 m/s")
ax.axhline(f0_cruise, color="lime", ls=":", alpha=0.7,
           label=f"Cruise {f0_cruise:.1f} Hz → {V_CRUISE} m/s")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.12,
           label="Segment 0:46–1:40")
ax.axvline(t_launch_abs, color="w", ls="--", alpha=0.4)
ax.set_ylabel("Fundamental (Hz)")
ax.set_title("Harmonic-product-spectrum pitch track, full video")
ax.legend(loc="upper right", fontsize=8)
ax.grid(alpha=0.3)

# 2 : cable speed
ax = axes[1]
ax.plot(times, v_track, color="#4ec9ff", lw=1.0)
ax.axhline(V_CRUISE, color="lime", ls=":", alpha=0.6,
           label=f"v_cruise = {V_CRUISE} m/s")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.12)
ax.axvline(t_launch_abs, color="w", ls="--", alpha=0.4,
           label=f"Launch t={t_launch_abs:.1f} s")
ax.set_ylabel("Cable speed v (m/s)")
ax.set_ylim(-0.5, 12)
ax.legend(loc="upper right", fontsize=8)
ax.grid(alpha=0.3)

# 3 : acceleration
ax = axes[2]
ax.plot(times, a_track, color="#ffd34d", lw=1.0)
ax.axhline(0.30, color="lime", ls="--", alpha=0.6,
           label="Sim A_TARGET = 0.30 m/s²")
ax.axhline(0.12, color="orange", ls="--", alpha=0.6,
           label="Sim A_START = 0.12 m/s²")
ax.axhline(-0.25, color="#ff7777", ls="--", alpha=0.6,
           label="Sim A_NATURAL_UP = 0.25 m/s² (decel)")
ax.axvspan(SEG_LO, SEG_HI, color="cyan", alpha=0.12)
ax.axvline(t_launch_abs, color="w", ls="--", alpha=0.4)
ax.set_ylabel("Acceleration (m/s²)")
ax.set_xlabel("Time in video (s)")
ax.set_ylim(-0.6, 0.8)
ax.legend(loc="upper right", fontsize=7, ncol=2)
ax.grid(alpha=0.3)
ax.set_xlim(0, times[-1])

plt.tight_layout()
plt.savefig("calibration_final.png", dpi=120, facecolor="#0b0f1a")
print("Wrote calibration_final.png")

# Segment-focused plot ----------------------------------------------
fig, axes = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
ax = axes[0]
ax.plot(times - t_launch_abs, v_track, color="#4ec9ff", lw=1.2)
ax.axhline(V_CRUISE, color="lime", ls=":", alpha=0.6,
           label=f"v_cruise = {V_CRUISE} m/s")
v_fit = s_curve(v_track, A_start_fit, A_target_fit, V_soft_fit)
ax.set_ylabel("v (m/s)")
ax.set_xlim(-2, 40)
ax.set_ylim(-0.5, 12)
ax.grid(alpha=0.3)
ax.legend(loc="lower right", fontsize=8)
ax.set_title(f"Launch profile — derived from pitch "
             f"(segment 0:46–1:40, launch @ {t_launch_abs:.1f} s)")
ax = axes[1]
ax.plot(times - t_launch_abs, a_track, color="#ffd34d", lw=1.2,
        label="Measured a(t)")
vv = np.linspace(0.0, V_CRUISE, 200)
ax.plot(v_track[mask_after][:len(vv)], a_track[mask_after][:len(vv)],
        alpha=0.0)  # alignment-only hack ; we really want a(v)
# a-vs-v scatter (small dots)
ax.scatter(times[fit_mask] - t_launch_abs, a_track[fit_mask], s=3,
           color="#888", alpha=0.4)
# Fitted S-curve on time axis : map t -> v(t) -> s_curve(v)
a_fit_t = s_curve(v_track, A_start_fit, A_target_fit, V_soft_fit)
ax.plot(times - t_launch_abs, a_fit_t, color="#66ff66", lw=1.2, ls="--",
        label=f"Fit : A_s={A_start_fit:.2f}  A_t={A_target_fit:.2f}  "
              f"V_s={V_soft_fit:.1f}")
ax.axhline(0.30, color="lime", ls=":", alpha=0.5)
ax.axhline(0.12, color="orange", ls=":", alpha=0.5)
ax.set_xlabel("Time since launch (s)")
ax.set_ylabel("a (m/s²)")
ax.set_xlim(-2, 40)
ax.set_ylim(-0.4, 0.6)
ax.grid(alpha=0.3)
ax.legend(loc="upper right", fontsize=8)

plt.tight_layout()
plt.savefig("launch_profile.png", dpi=120, facecolor="#0b0f1a")
print("Wrote launch_profile.png")
