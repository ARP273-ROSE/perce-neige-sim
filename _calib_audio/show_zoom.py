"""Focused spectrogram 0-600 Hz to identify the sweeping harmonic visually."""
import numpy as np, librosa, matplotlib.pyplot as plt

y, sr = librosa.load("machinerie_full.wav", sr=22050, mono=True)
S = np.abs(librosa.stft(y, n_fft=16384, hop_length=512))
f = librosa.fft_frequencies(sr=sr, n_fft=16384)
t = librosa.frames_to_time(np.arange(S.shape[1]), sr=sr, hop_length=512)
Sdb = librosa.amplitude_to_db(S + 1e-9)

# Focus 0-600 Hz and zoom
kmax = int(round(600 / (f[1]-f[0])))

# Full spectrogram 0-600 Hz
fig, ax = plt.subplots(figsize=(16, 6))
im = ax.imshow(Sdb[:kmax, :], origin="lower", aspect="auto",
               extent=[t[0], t[-1], 0, 600], cmap="magma",
               vmin=Sdb.max()-55, vmax=Sdb.max()-5)
ax.axvline(46, color="cyan", lw=1, ls="--")
ax.axvline(100, color="cyan", lw=1, ls="--")
ax.set_ylabel("Hz")
ax.set_xlabel("s")
ax.set_title("Spectrogram 0-600 Hz (zoom)")
plt.colorbar(im, label="dB", ax=ax)
plt.tight_layout()
plt.savefig("zoom_0_600.png", dpi=130, facecolor="#0b0f1a")
print("wrote zoom_0_600.png")

# Zoom on the sweep segment only (40-110 s), 0-500 Hz
tmask = (t >= 40) & (t <= 120)
S_seg = S[:kmax, tmask]
Sdb_seg = librosa.amplitude_to_db(S_seg + 1e-9)
t_seg = t[tmask]

fig, ax = plt.subplots(figsize=(14, 7))
im = ax.imshow(Sdb_seg, origin="lower", aspect="auto",
               extent=[t_seg[0], t_seg[-1], 0, 600], cmap="magma",
               vmin=Sdb_seg.max()-40, vmax=Sdb_seg.max())
ax.axvline(46, color="cyan", lw=1, ls="--")
ax.axvline(100, color="cyan", lw=1, ls="--")
ax.set_ylabel("Hz")
ax.set_xlabel("s")
ax.set_title("Launch ramp detail, 40-120 s, 0-600 Hz")
plt.colorbar(im, label="dB", ax=ax)
plt.tight_layout()
plt.savefig("zoom_ramp.png", dpi=140, facecolor="#0b0f1a")
print("wrote zoom_ramp.png")
