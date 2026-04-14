"""Pitch-based acceleration calibration for Perce-Neige simulator.

Reads funiculaire_machinerie_1080p.mp4 segment [0:46, 1:40]
(extracted to machinerie_46s_100s.wav, mono 22050 Hz).

Approach
--------
The drive hall has 3 x 800 kW DC motors driving a bull wheel of
Ø 4.160 m through a reducer. When cable speed is v (m/s), the bull
wheel turns at n = v / (pi * 4.160) rev/s, and the motor turns at
n_mot = n * gear_ratio.

The audible whine in the machinery room is dominated by :
  - DC motor fan / armature slot harmonics : proportional to n_mot
  - Gear mesh frequency                    : proportional to n_mot * teeth
  - Bull-wheel bearing tone                : proportional to n

All three scale LINEARLY with cable speed. So the instantaneous
dominant pitch f(t) is proportional to v(t) up to a scale factor K
that we calibrate against a single known operating point.

Calibration point : at the end of the cruise plateau (just before
the driver starts taking the throttle down), the machinery stabilises
at f_max and we know the train is cruising at v_cruise. The real
Perce-Neige cruise is typically 10-12 m/s — the sim uses speed_cmd
=~ 84 % of 12 m/s = 10.1 m/s as the reference (matches the cockpit
video trip time 7 min 54 s for Val Claret -> Grande Motte).

Method
------
1. Compute short-time Fourier transform, sr=22050, n_fft=4096,
   hop=512 (~23 ms).
2. For each frame take the spectral centroid in 200-2000 Hz band
   (ignores low rumble and HF hiss).
3. Median-filter the centroid track (5-frame kernel) to kill
   transients.
4. Pick a reference : the plateau between 35-45 s of the clip
   (motor fully up-to-speed, constant pitch). Call this f_ref.
5. Scale : v(t) = v_cruise * f(t) / f_ref,  with v_cruise = 10.1 m/s.
6. Differentiate v(t) to get a(t). Smooth with 1-s window.
7. Fit the S-curve launch profile : a(v) = A_START + (A_TARGET -
   A_START) * min(1, v / V_SOFT_RAMP), matching sim lines 838-846.
"""
from __future__ import annotations
import numpy as np
import librosa
import scipy.signal
import matplotlib.pyplot as plt
import json

WAV = "machinerie_46s_100s.wav"
SR_TARGET = 22050
N_FFT = 4096
HOP = 512
BAND_LO = 200.0
BAND_HI = 2000.0
V_CRUISE = 10.1             # m/s : sim cruise (speed_cmd 84% of 12)
REF_WIN = (35.0, 45.0)      # s   : plateau window for f_ref

y, sr = librosa.load(WAV, sr=SR_TARGET, mono=True)
print(f"Loaded {len(y)/sr:.2f} s at {sr} Hz")

# STFT magnitude (log) --------------------------------------------------
S = np.abs(librosa.stft(y, n_fft=N_FFT, hop_length=HOP))
freqs = librosa.fft_frequencies(sr=sr, n_fft=N_FFT)
times = librosa.frames_to_time(np.arange(S.shape[1]), sr=sr, hop_length=HOP)

band = (freqs >= BAND_LO) & (freqs <= BAND_HI)
Sb = S[band, :]
fb = freqs[band]

# Spectral centroid in band --------------------------------------------
centroid = (Sb * fb[:, None]).sum(axis=0) / (Sb.sum(axis=0) + 1e-9)

# Median-filter to remove transients (5 frames ~= 120 ms)
centroid_f = scipy.signal.medfilt(centroid, kernel_size=5)

# Also get a robust "dominant peak" estimator as cross-check
peak_f = fb[Sb.argmax(axis=0)]
peak_f = scipy.signal.medfilt(peak_f, kernel_size=9)

# Reference window -----------------------------------------------------
mask_ref = (times >= REF_WIN[0]) & (times <= REF_WIN[1])
f_ref = np.median(centroid_f[mask_ref])
print(f"f_ref (plateau centroid) = {f_ref:.1f} Hz over t=[{REF_WIN[0]},{REF_WIN[1]}] s")

# Convert pitch -> speed ----------------------------------------------
v_est = V_CRUISE * centroid_f / f_ref

# Differentiate -> acceleration, smooth over 1 s
dt = HOP / sr
a_raw = np.gradient(v_est, dt)
# 1-s Hann smoothing window
win_len = int(round(1.0 / dt))
if win_len % 2 == 0:
    win_len += 1
win = np.hanning(win_len)
win /= win.sum()
a_smooth = np.convolve(a_raw, win, mode="same")

# Report launch profile : take first 25 s after motor first audible
# launch. We detect "launch start" as the first t after 1.0 s where
# centroid_f rises above 1.25 * its initial median (idle whine).
idle = np.median(centroid_f[(times >= 0) & (times <= 0.8)])
launch_mask = (times >= 1.0) & (centroid_f > 1.25 * idle)
if launch_mask.any():
    t_launch = times[launch_mask.argmax()]
else:
    t_launch = 0.0
print(f"Launch detected at t={t_launch:.2f} s (idle pitch {idle:.1f} Hz)")

# Summary table (every 2 s after launch) ------------------------------
samples = []
for target_t in np.arange(t_launch, t_launch + 40.0, 2.0):
    if target_t > times[-1]:
        break
    idx = int(round((target_t - times[0]) / dt))
    if 0 <= idx < len(v_est):
        samples.append({
            "t_clip_s":  round(float(times[idx]), 2),
            "t_launch_s": round(float(times[idx] - t_launch), 2),
            "pitch_Hz":   round(float(centroid_f[idx]), 1),
            "v_m_s":      round(float(v_est[idx]), 2),
            "a_m_s2":     round(float(a_smooth[idx]), 3),
        })

# Peak acceleration during launch (first 20 s after t_launch)
launch_win = (times >= t_launch) & (times <= t_launch + 20.0)
a_peak = float(np.nanmax(a_smooth[launch_win]))
v_peak = float(np.nanmax(v_est[launch_win]))
# Time to reach 90 % of v_cruise
target_v = 0.90 * V_CRUISE
reached = np.where((times >= t_launch) & (v_est >= target_v))[0]
t_to_90 = float(times[reached[0]] - t_launch) if len(reached) else float("nan")

summary = {
    "segment":         [46.0, 100.0],
    "duration_s":      round(float(len(y) / sr), 2),
    "f_ref_Hz":        round(float(f_ref), 1),
    "v_cruise_ref_m_s": V_CRUISE,
    "t_launch_in_clip_s": round(float(t_launch), 2),
    "idle_pitch_Hz":   round(float(idle), 1),
    "peak_accel_m_s2": round(a_peak, 3),
    "peak_speed_m_s":  round(v_peak, 2),
    "t_to_0p9_vc_s":   round(t_to_90, 2) if not np.isnan(t_to_90) else None,
    "samples":         samples,
}
with open("calibration_result.json", "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)
print("Wrote calibration_result.json")

# Save figure ----------------------------------------------------------
fig, axes = plt.subplots(3, 1, figsize=(9, 9), sharex=True)

ax = axes[0]
# spectrogram (log) restricted to band
extent = [times[0], times[-1], BAND_LO, BAND_HI]
ax.imshow(20*np.log10(Sb + 1e-9), origin="lower", aspect="auto",
          extent=extent, cmap="magma")
ax.plot(times, centroid_f, color="#4ec9ff", lw=1.2, label="Spectral centroid (band)")
ax.plot(times, peak_f, color="#ffd34d", lw=0.8, ls=":", label="Dominant peak (cross-check)")
ax.axvline(t_launch, color="w", ls="--", alpha=0.6, label=f"Launch @ {t_launch:.2f}s")
ax.axvspan(REF_WIN[0], REF_WIN[1], color="lime", alpha=0.15, label="Ref plateau")
ax.set_ylabel("Pitch (Hz)")
ax.set_title("Machinery whine — pitch track (200-2000 Hz band)")
ax.legend(loc="upper left", fontsize=8)

ax = axes[1]
ax.plot(times - t_launch, v_est, color="#4ec9ff", lw=1.3)
ax.axhline(V_CRUISE, color="w", ls=":", alpha=0.5, label=f"v_cruise = {V_CRUISE} m/s")
ax.set_ylabel("Cable speed v (m/s)")
ax.set_title("Inferred cable speed (pitch scaled to known cruise)")
ax.set_xlim(-2, 40)
ax.grid(True, alpha=0.3)
ax.legend(loc="lower right", fontsize=8)

ax = axes[2]
ax.plot(times - t_launch, a_smooth, color="#ffd34d", lw=1.3)
ax.axhline(0.30, color="lime", ls="--", alpha=0.6, label="A_TARGET = 0.30 m/s²")
ax.axhline(0.12, color="orange", ls="--", alpha=0.6, label="A_START = 0.12 m/s²")
ax.set_ylabel("Acceleration a (m/s²)")
ax.set_xlabel("Time since launch (s)")
ax.set_title("Derived acceleration profile (1-s smoothed)")
ax.set_xlim(-2, 40)
ax.set_ylim(-0.2, 0.6)
ax.grid(True, alpha=0.3)
ax.legend(loc="upper right", fontsize=8)

plt.tight_layout()
plt.savefig("calibration_plot.png", dpi=120, facecolor="#0b0f1a")
print("Wrote calibration_plot.png")

# Also dump a CSV for the LaTeX guide table ---------------------------
with open("calibration_samples.csv", "w", encoding="utf-8") as f:
    f.write("t_since_launch_s,pitch_Hz,v_m_s,a_m_s2\n")
    for s in samples:
        f.write(f"{s['t_launch_s']},{s['pitch_Hz']},{s['v_m_s']},{s['a_m_s2']}\n")
print("Wrote calibration_samples.csv")
