"""Dry run PC avec lecteur d'annonces SIMULÉ aux vraies durées : exploitation
automatique 24/7, arrivée en haut puis départ ; journal des portes et des sons."""
import os, sys, wave
os.environ["QT_QPA_PLATFORM"] = "offscreen"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from pathlib import Path
from PyQt6.QtWidgets import QApplication
from PyQt6.QtGui import QKeyEvent
from PyQt6.QtCore import Qt, QEvent
from PyQt6.QtMultimedia import QMediaPlayer
app = QApplication(sys.argv)
import perce_neige_sim as pn
os.makedirs("/tmp/pn", exist_ok=True)
pn._persistent_data_dir = lambda: Path("/tmp/pn"); pn._writable_dir = lambda: Path("/tmp/pn")
clock = [1000.0]
pn.time.monotonic = lambda: clock[0]
win = pn.MainWindow(); g = win.game; st = g.state
print("sons.enabled =", g.sounds.enabled, "| player réel :", g.sounds._player is not None)
T0 = clock[0]
sound_log = []

def duration(path):
    p = str(path)
    if p.lower().endswith(".wav"):
        try:
            with wave.open(p) as w: return w.getnframes() / w.getframerate()
        except Exception: return 3.0
    return 7.43   # mp3 (annonce 01 = 7,43 s mesurés)

class FakePlayer:
    def __init__(self, sounds): self.s = sounds; self.src = None; self.end = None; self.playing = False
    def setSource(self, url): self.src = url.toLocalFile() if hasattr(url, "toLocalFile") else str(url)
    def play(self):
        d = duration(self.src); self.end = clock[0] + d; self.playing = True
        sound_log.append((clock[0] - T0, os.path.basename(self.src or "?"), d))
    def stop(self): self.playing = False; self.end = None
    def playbackState(self):
        return QMediaPlayer.PlaybackState.PlayingState if self.playing else QMediaPlayer.PlaybackState.StoppedState
    def tick(self):
        if self.playing and clock[0] >= self.end:
            self.playing = False; self.end = None
            self.s._on_status(QMediaPlayer.MediaStatus.EndOfMedia)

fake = FakePlayer(g.sounds); g.sounds._player = fake; g.sounds.enabled = True
def key(k, mod=Qt.KeyboardModifier.NoModifier): g.keyPressEvent(QKeyEvent(QEvent.Type.KeyPress, k, mod))
g.new_trip(); st.mode = pn.MODE_RUN
tr = st.train
tr.s = pn.STOP_S - 300.0; tr.v = 12.0; tr.doors_open = False; tr.doors_cmd = False; tr.doors_visual_open = False
tr.maint_brake = False; st.trip_started = True; tr.trip_started = True; tr.speed_cmd = 1.0
key(Qt.Key.Key_X, Qt.KeyboardModifier.ShiftModifier)
if not g.auto_ops.enabled: key(Qt.Key.Key_X)
prev = None; t = 0.0
for i in range(int(420 * 60)):
    clock[0] += 1/60; t += 1/60
    fake.tick(); g._tick()
    cur = (tr.doors_open, tr.doors_visual_open, tr.doors_cmd, st.trip_started, st.finished, getattr(g.auto_ops, "phase", "?"), tr.ready, st.ghost_ready, g.sounds._close_seq_active)
    if cur != prev:
        print(f"t={t:6.1f}s s={tr.s:6.1f} v={tr.v:5.2f} | open={cur[0]} visuel={cur[1]} cmd={cur[2]} trip={cur[3]} fin={cur[4]} phase={cur[5]} ready={cur[6]} ghost={cur[7]} seq={cur[8]}")
        prev = cur
    if st.trip_started and t > 120 and tr.s < pn.STOP_S - 100:
        print("… reparti en descente, fin du dry run"); break
print("\n--- sons joués (t, fichier, durée) ---")
for e in sound_log: print(f"  t={e[0]:6.1f}s  {e[1][:42]:42s} {e[2]:5.1f} s")
