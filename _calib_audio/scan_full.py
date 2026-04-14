"""Scan the full 414 s machinery video to find the real launch / cruise
segment. Look for a tonal component that actually tracks cable speed.

The whine we want is a gear-mesh / armature-slot harmonic : linear in
RPM, narrowband, and swept during acceleration. A stationary blower
or commutator hum will stay at a fixed frequency — useless for
calibration. We spot swept tones by computing, in each time frame,
the TOP few spectral peaks and checking whether their frequencies
change over time.
"""
import numpy as np
import librosa
import scipy.signal
import matplotlib.pyplot as plt

y, sr = librosa.load("machinerie_full.wav", sr=22050, mono=True)
print(f"Loaded {len(y)/sr:.1f} s at {sr} Hz")

# Spectrogram (log magnitude) -----------------------------------------
n_fft, hop = 8192, 1024
S = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
S_db = librosa.amplitude_to_db(S + 1e-9)
freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
times = librosa.frames_to_time(np.arange(S.shape[1]), sr=sr, hop_length=hop)
print(f"STFT : {S.shape[1]} frames, {freqs[-1]:.0f} Hz max, bin = {freqs[1]:.2f} Hz")

# For a quick overview, compute mean energy in several bands ----------
bands = [(20, 100), (100, 300), (300, 800), (800, 2000), (2000, 5000)]
for lo, hi in bands:
    mask = (freqs >= lo) & (freqs < hi)
    e = 20*np.log10(S[mask,:].mean(axis=0) + 1e-9)
    print(f"  band {lo:>5}-{hi:<5} Hz : mean dB range "
          f"[{e.min():.1f}, {e.max():.1f}], std {e.std():.2f} dB")

# Plot a full-range spectrogram to spot swept tones -------------------
fig, ax = plt.subplots(figsize=(14, 5))
ax.imshow(S_db[:int(n_fft/2*2000/sr),:], origin="lower", aspect="auto",
          extent=[times[0], times[-1], 0, 2000], cmap="magma",
          vmin=S_db.max()-60, vmax=S_db.max())
ax.set_ylabel("Frequency (Hz)")
ax.set_xlabel("Time (s)")
ax.set_title("Machinery video — full spectrogram 0-2000 Hz")
ax.axvspan(46, 100, alpha=0.0, edgecolor="cyan", lw=1.5,
           facecolor="none", ls="--")
ax.axvline(46, color="cyan", lw=0.8, ls="--")
ax.axvline(100, color="cyan", lw=0.8, ls="--")
ax.text(73, 1900, "segment 0:46–1:40", color="cyan", ha="center", fontsize=9)
plt.tight_layout()
plt.savefig("full_spectrogram.png", dpi=110, facecolor="#0b0f1a")
print("Wrote full_spectrogram.png")

# Track the DOMINANT narrowband peak in 80-500 Hz (likely gear mesh
# or bull-wheel tonal) over the whole clip --------------------------
lo, hi = 80, 500
mask = (freqs >= lo) & (freqs <= hi)
Sb = S[mask, :]
fb = freqs[mask]
# Parabolic-interpolated peak per frame
peak_f = []
peak_db = []
for i in range(Sb.shape[1]):
    col = Sb[:, i]
    k = int(np.argmax(col))
    # Parabolic interp (quadratic fit to 3 bins)
    if 0 < k < len(col) - 1:
        a, b, c = col[k-1], col[k], col[k+1]
        denom = (a - 2*b + c)
        delta = 0.5 * (a - c) / denom if abs(denom) > 1e-12 else 0.0
    else:
        delta = 0.0
    peak_f.append(fb[k] + delta * (fb[1] - fb[0]))
    peak_db.append(20*np.log10(col[k] + 1e-9))

peak_f = np.array(peak_f)
peak_db = np.array(peak_db)
peak_f_s = scipy.signal.medfilt(peak_f, kernel_size=7)

fig, ax = plt.subplots(2, 1, figsize=(14, 6), sharex=True)
ax[0].plot(times, peak_f_s, color="#4ec9ff", lw=0.8)
ax[0].axvline(46, color="cyan", lw=0.8, ls="--")
ax[0].axvline(100, color="cyan", lw=0.8, ls="--")
ax[0].set_ylabel("Peak (Hz) in 80-500 Hz")
ax[0].set_ylim(lo, hi)
ax[0].grid(alpha=0.3)
ax[0].set_title("Dominant narrowband tone track 80-500 Hz")
ax[1].plot(times, peak_db, color="#ffd34d", lw=0.6)
ax[1].set_ylabel("Peak dB")
ax[1].set_xlabel("Time (s)")
ax[1].grid(alpha=0.3)
plt.tight_layout()
plt.savefig("peak_track.png", dpi=110, facecolor="#0b0f1a")
print("Wrote peak_track.png")

# Print some key windows -----------------------------------------------
for (lo_t, hi_t, label) in [(0, 30, "opening"), (30, 46, "pre-segment"),
                            (46, 100, "USER SEGMENT"),
                            (100, 160, "post-segment"),
                            (160, 260, "mid"),
                            (260, 360, "late"),
                            (360, 414, "ending")]:
    m = (times >= lo_t) & (times <= hi_t)
    if m.any():
        f = peak_f_s[m]
        print(f"  [{lo_t:>3}-{hi_t:<3}] {label:<14} : "
              f"peak Hz median {np.median(f):>6.1f}, "
              f"range [{f.min():>6.1f}, {f.max():>6.1f}], "
              f"sweep {f.max()-f.min():>5.1f} Hz")
