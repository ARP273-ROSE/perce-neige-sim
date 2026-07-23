"""GitHub-based auto-update for Perce-Neige Simulator.

Two modes
---------
1. **Frozen mode** (PyInstaller .exe) --- the end-user experience.
   Downloads the platform-specific binary asset from the latest
   release (``PerceNeigeSimulator-windows.exe`` on Windows,
   ``PerceNeigeSimulator-linux.AppImage`` on Linux, etc.), validates
   its size, then swaps the running executable via a small helper
   script so the user never has to do anything manual.

2. **Source mode** (``python perce_neige_sim.py``) --- for developers.
   Downloads the repository zipball and copies whitelisted source
   files into the project directory.

Security
--------
- Max download size : 200 MB (protects against zip bombs / oversized
  binaries)
- Binary integrity : frozen-mode assets are verified against the
  ``SHA256SUMS`` file published in the same release (mandatory --- a
  release without checksums is refused). Size must also match the
  size announced by the GitHub API.
- Zip member validation : reject '..', '\\', null bytes and any path
  that escapes the extraction root
- Reject symlinks in zipballs
- Whitelist of filenames allowed to be written in source mode so
  user data (venv, CLAUDE.md, .git, local assets) is never touched

Network : uses urllib from stdlib to avoid adding a dependency.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional


GITHUB_API = "https://api.github.com/repos/{owner}/{repo}/releases/latest"
MAX_DOWNLOAD_BYTES = 200 * 1024 * 1024  # 200 MB
NETWORK_TIMEOUT = 15.0


def _log(msg: str) -> None:
    """Trace l'auto-update dans %TEMP%/perce_neige_update.log. Le sim
    frozen tourne sans console → sans ce journal, un échec de swap est
    totalement muet (« la MAJ marche pas » sans le moindre indice)."""
    try:
        import tempfile
        from datetime import datetime
        logf = Path(tempfile.gettempdir()) / "perce_neige_update.log"
        with open(logf, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().isoformat(timespec='seconds')}] {msg}\n")
    except Exception:
        pass

# Files that auto-update is allowed to overwrite in source mode.
UPDATE_WHITELIST = {
    "perce_neige_sim.py",
    "autoupdate.py",
    "bugreport.py",
    "make_logo.py",
    "launch.bat",
    "launch.sh",
    "requirements.txt",
    "README.md",
    "logo.png",
    "logo.ico",
    "logo_64.png",
    "manuel_perce_neige.pdf",
}

# Platform → expected asset name suffix (matches our GitHub Actions build)
PLATFORM_ASSET_SUFFIX = {
    "win32":  "-windows.exe",
    "darwin": "-macos.dmg",
    "linux":  "-linux.AppImage",
}

# Viewer Godot 3D standalone publié en asset de release (gitignoré dans le
# repo car ~125 Mo). asset name → nom de fichier local dans bundled_godot/.
VIEWER_ASSETS = {
    "win32":  ("perce_neige_3d-windows.exe",   "perce_neige_3d.exe"),
    "linux":  ("perce_neige_3d-linux.x86_64",  "perce_neige_3d.x86_64"),
}


@dataclass
class ReleaseAsset:
    name: str
    url: str          # browser_download_url
    size: int


@dataclass
class ReleaseInfo:
    tag: str
    version: str
    name: str
    body: str
    zipball_url: str
    html_url: str
    assets: list = field(default_factory=list)


def _parse_version(s: str) -> tuple[int, ...]:
    clean = s.strip().lstrip("vV ")
    parts: list[int] = []
    for chunk in clean.split("."):
        digits = "".join(c for c in chunk if c.isdigit())
        parts.append(int(digits) if digits else 0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def _http_get_json(url: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "perce-neige-sim-auto-update",
            "Accept": "application/vnd.github+json",
        },
    )
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=NETWORK_TIMEOUT,
                                context=ctx) as resp:
        payload = resp.read(2 * 1024 * 1024)
    return json.loads(payload.decode("utf-8"))


def check_latest_release(owner: str, repo: str) -> Optional[ReleaseInfo]:
    try:
        data = _http_get_json(GITHUB_API.format(owner=owner, repo=repo))
    except Exception:
        return None
    tag = str(data.get("tag_name", ""))
    if not tag:
        return None
    zipball = str(data.get("zipball_url", ""))
    if not zipball.startswith("https://"):
        return None
    assets = []
    for a in data.get("assets") or []:
        url = str(a.get("browser_download_url", ""))
        if url.startswith("https://"):
            assets.append(ReleaseAsset(
                name=str(a.get("name", "")),
                url=url,
                size=int(a.get("size", 0) or 0),
            ))
    return ReleaseInfo(
        tag=tag,
        version=".".join(str(x) for x in _parse_version(tag)),
        name=str(data.get("name", tag)),
        body=str(data.get("body", "")),
        zipball_url=zipball,
        html_url=str(data.get("html_url", "")),
        assets=assets,
    )


def is_newer(remote_version: str, local_version: str) -> bool:
    return _parse_version(remote_version) > _parse_version(local_version)


# ---------------------------------------------------------------------------
# Mode detection
# ---------------------------------------------------------------------------

def is_frozen() -> bool:
    return bool(getattr(sys, "frozen", False))


def _platform_suffix() -> str:
    return PLATFORM_ASSET_SUFFIX.get(sys.platform, "")


# Nom de l'application principale (préfixe de l'asset à installer). Le
# viewer 3D (perce_neige_3d-windows.exe) porte AUSSI le suffixe
# "-windows.exe" → sans ce filtre par préfixe, l'updater pouvait
# remplacer le simulateur par le viewer selon l'ordre (non garanti) des
# assets renvoyés par l'API GitHub.
APP_ASSET_PREFIX = "PerceNeigeSimulator"


def _pick_binary_asset(release: ReleaseInfo) -> Optional[ReleaseAsset]:
    suffix = _platform_suffix()
    if not suffix:
        return None
    # 1. Match exact : l'exe du simulateur (préfixe app + suffixe plateforme).
    for a in release.assets:
        if a.name.startswith(APP_ASSET_PREFIX) and a.name.endswith(suffix):
            return a
    # 2. Repli : un asset au bon suffixe qui n'est PAS le viewer 3D.
    for a in release.assets:
        if a.name.endswith(suffix) and "perce_neige_3d" not in a.name:
            return a
    return None


# ---------------------------------------------------------------------------
# Frozen mode — swap the running executable
# ---------------------------------------------------------------------------

def _stream_download(url: str, dest: Path,
                     progress: Optional[Callable[[int, int], None]] = None,
                     max_bytes: int = MAX_DOWNLOAD_BYTES) -> None:
    req = urllib.request.Request(
        url, headers={"User-Agent": "perce-neige-sim-auto-update"})
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=NETWORK_TIMEOUT,
                                context=ctx) as resp:
        total = int(resp.headers.get("Content-Length", "0") or 0)
        if total and total > max_bytes:
            raise ValueError(f"download too large: {total} bytes")
        downloaded = 0
        with open(dest, "wb") as out:
            while True:
                chunk = resp.read(64 * 1024)
                if not chunk:
                    break
                downloaded += len(chunk)
                if downloaded > max_bytes:
                    raise ValueError("download exceeded max size")
                out.write(chunk)
                if progress is not None:
                    progress(downloaded, total)


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _verify_asset_sha256(release: ReleaseInfo, asset: ReleaseAsset,
                         downloaded: Path) -> None:
    """Verify ``downloaded`` against the SHA256SUMS asset of the release.

    Raises RuntimeError on any mismatch or if the release ships no
    SHA256SUMS --- we refuse to swap the running executable for an
    unverifiable binary (defense against a tampered release asset).
    """
    sums_asset = next(
        (a for a in release.assets if a.name == "SHA256SUMS"), None)
    if sums_asset is None:
        raise RuntimeError(
            f"release {release.tag} has no SHA256SUMS asset — refusing "
            f"to install an unverified binary")
    tmp = Path(tempfile.mkdtemp(prefix="pn_sums_")) / "SHA256SUMS"
    _stream_download(sums_asset.url, tmp, max_bytes=64 * 1024)
    expected = None
    for line in tmp.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-1].lstrip("*") == asset.name:
            expected = parts[0].lower()
            break
    if expected is None or len(expected) != 64:
        raise RuntimeError(
            f"SHA256SUMS has no valid entry for {asset.name!r}")
    actual = _sha256_file(downloaded)
    if actual != expected:
        raise RuntimeError(
            f"SHA-256 mismatch for {asset.name}: expected {expected}, "
            f"got {actual} — download corrupted or tampered")


def _swap_windows_exe(new_exe: Path) -> None:
    """Schedule replacement of the currently-running .exe on Windows.

    You cannot overwrite a running .exe directly.  We drop a small
    batch script next to the new file that waits for our PID to exit,
    swaps the binaries, deletes itself and relaunches the app.
    """
    import tempfile
    current = Path(sys.executable).resolve()
    pid = os.getpid()
    swap_bat = new_exe.parent / "_pn_update_swap.bat"
    bat_log = Path(tempfile.gettempdir()) / "perce_neige_update_swap.log"
    # Robustesse (retours terrain « la MAJ marche pas ») :
    #  - attente du PID bornée (~60 s) puis on force le swap : si la
    #    détection tasklist déraille, on ne reste pas bloqué à l'infini ;
    #  - `move` réessayé 10 × (le fichier .exe reste parfois verrouillé
    #    une poignée de secondes après la sortie du process) ;
    #  - tout est journalisé dans %TEMP%/perce_neige_update_swap.log ;
    #  - l'appli est RELANCÉE même si le swap échoue (l'ancienne version
    #    plutôt que rien), pour ne jamais laisser l'utilisateur sans app.
    backup = current.with_name(current.stem + ".old.exe")
    # Séquence SÛRE (retour d'essai 2026-07-24 « à la fin du téléchargement
    # ça bug ») : l'ancien batch faisait `del TARGET` PUIS `move NEW
    # TARGET`. Si le move échouait (antivirus verrouillant le .exe
    # fraîchement téléchargé, dossier non inscriptible…), l'exe était
    # supprimé SANS remplaçant → l'appli disparaissait, jamais relancée.
    # Nouvelle logique atomique-ish, sans jamais laisser l'utilisateur
    # sans exe :
    #   1. renommer TARGET → TARGET.old (libère le nom cible)
    #   2. move NEW → TARGET (réessayé : NEW peut rester verrouillé qq s)
    #   3. si TARGET recréé → OK : supprimer TARGET.old, relancer
    #   4. si échec → RESTAURER TARGET.old → TARGET, relancer l'ancienne
    script = (
        "@echo off\r\n"
        "setlocal enableextensions\r\n"
        f'set "PID={pid}"\r\n'
        f'set "TARGET={current}"\r\n'
        f'set "NEW={new_exe}"\r\n'
        f'set "BACKUP={backup}"\r\n'
        f'set "LOG={bat_log}"\r\n'
        'echo [swap] start pid=%PID% > "%LOG%"\r\n'
        "set /a WAIT=0\r\n"
        ":waitloop\r\n"
        'tasklist /FI "PID eq %PID%" 2>nul | find "%PID%" >nul\r\n'
        "if %errorlevel%==0 (\r\n"
        "  set /a WAIT+=1\r\n"
        "  if %WAIT% geq 60 goto doswap\r\n"
        "  timeout /t 1 /nobreak >nul\r\n"
        "  goto waitloop\r\n"
        ")\r\n"
        ":doswap\r\n"
        'echo [swap] pid gone, swapping >> "%LOG%"\r\n'
        'del /Q "%BACKUP%" >nul 2>&1\r\n'
        # 1. écarte l'ancien exe (réessayé : il peut rester verrouillé un
        #    court instant après la sortie du process).
        "set /a TRY=0\r\n"
        ":renloop\r\n"
        'move /Y "%TARGET%" "%BACKUP%" >nul 2>&1\r\n'
        'if exist "%TARGET%" (\r\n'
        "  set /a TRY+=1\r\n"
        '  echo [swap] rename retry %TRY% >> "%LOG%"\r\n'
        "  if %TRY% geq 15 goto relaunch\r\n"
        "  timeout /t 1 /nobreak >nul\r\n"
        "  goto renloop\r\n"
        ")\r\n"
        # 2. installe le nouveau à la place.
        "set /a TRY=0\r\n"
        ":moveloop\r\n"
        'move /Y "%NEW%" "%TARGET%" >nul 2>&1\r\n'
        'if not exist "%TARGET%" (\r\n'
        "  set /a TRY+=1\r\n"
        '  echo [swap] move retry %TRY% >> "%LOG%"\r\n'
        "  if %TRY% geq 15 goto restore\r\n"
        "  timeout /t 1 /nobreak >nul\r\n"
        "  goto moveloop\r\n"
        ")\r\n"
        # 3. succès → supprime la sauvegarde et relance la NOUVELLE.
        'echo [swap] ok, new installed >> "%LOG%"\r\n'
        'del /Q "%BACKUP%" >nul 2>&1\r\n'
        "goto relaunch\r\n"
        # 4. échec d'installation → restaure l'ANCIENNE (ne jamais
        #    laisser l'utilisateur sans exe).
        ":restore\r\n"
        'echo [swap] move failed, restoring backup >> "%LOG%"\r\n'
        'if exist "%BACKUP%" move /Y "%BACKUP%" "%TARGET%" >nul 2>&1\r\n'
        ":relaunch\r\n"
        'echo [swap] relaunch %TARGET% >> "%LOG%"\r\n'
        'if exist "%TARGET%" start "" "%TARGET%"\r\n'
        '(goto) 2>nul & del "%~f0"\r\n'
    )
    swap_bat.write_bytes(script.encode("cp1252", errors="replace"))
    _log(f"[swap] batch écrit : {swap_bat} (pid={pid}, target={current})")

    DETACHED_PROCESS = 0x00000008
    CREATE_NEW_PROCESS_GROUP = 0x00000200
    subprocess.Popen(
        ["cmd.exe", "/c", str(swap_bat)],
        creationflags=DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP,
        close_fds=True,
    )


def _swap_unix_binary(new_bin: Path) -> None:
    """Replace the current binary on Linux/macOS and exec it."""
    current = Path(sys.executable).resolve()
    new_bin.chmod(0o755)
    os.replace(str(new_bin), str(current))
    os.execv(str(current), [str(current)] + sys.argv[1:])


def _install_frozen(release: ReleaseInfo,
                    progress: Optional[Callable[[int, int], None]]) -> None:
    asset = _pick_binary_asset(release)
    if asset is None:
        raise RuntimeError(
            f"No binary asset for platform {sys.platform!r} in release "
            f"{release.tag}")
    _log(f"[install] release {release.tag}, asset choisi : {asset.name} "
         f"({asset.size} o)")
    current = Path(sys.executable).resolve()
    tmp = Path(tempfile.mkdtemp(prefix="pn_update_"))
    new_bin = tmp / asset.name
    _stream_download(asset.url, new_bin, progress=progress)
    if new_bin.stat().st_size < 1024:
        raise RuntimeError("downloaded asset is suspiciously small")
    if asset.size and new_bin.stat().st_size != asset.size:
        raise RuntimeError(
            f"downloaded size {new_bin.stat().st_size} != announced "
            f"size {asset.size}")
    _verify_asset_sha256(release, asset, new_bin)
    _log(f"[install] téléchargé + SHA-256 vérifié → {new_bin}")

    if sys.platform == "win32":
        # Move into the target directory first so move /Y is atomic
        staged = current.parent / (current.stem + ".new.exe")
        try:
            if staged.exists():
                staged.unlink()
        except OSError:
            pass
        shutil.move(str(new_bin), str(staged))
        _swap_windows_exe(staged)
        # Parent continues; caller will hard-exit via relaunch_app()
    else:
        _swap_unix_binary(new_bin)


# ---------------------------------------------------------------------------
# Source mode — zipball + whitelist copy
# ---------------------------------------------------------------------------

def _safe_extract(zf: zipfile.ZipFile, dest: Path) -> Path:
    dest_resolved = dest.resolve()
    top_dirs: set[str] = set()
    for info in zf.infolist():
        name = info.filename
        if (not name or "\x00" in name or name.startswith("/")
                or ".." in name.split("/") or "\\" in name):
            raise ValueError(f"zip: unsafe member name {name!r}")
        if (info.external_attr >> 16) & 0o170000 == 0o120000:
            raise ValueError(f"zip: symlink refused {name!r}")
        target = (dest_resolved / name).resolve()
        if dest_resolved not in target.parents and target != dest_resolved:
            raise ValueError(f"zip: path escape {name!r}")
        first = name.split("/", 1)[0]
        if first:
            top_dirs.add(first)
    zf.extractall(dest)
    if len(top_dirs) != 1:
        raise ValueError("zip: expected exactly one top-level directory")
    return dest / next(iter(top_dirs))


def _install_source(release: ReleaseInfo, project_dir: Path,
                    progress: Optional[Callable[[int, int], None]]) -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="pn_update_"))
    zip_path = tmp / "release.zip"
    _stream_download(release.zipball_url, zip_path, progress=progress)
    extract_root = tmp / "extract"
    extract_root.mkdir()
    with zipfile.ZipFile(zip_path) as zf:
        top = _safe_extract(zf, extract_root)
    project_dir = Path(project_dir).resolve()
    for rel in sorted(UPDATE_WHITELIST):
        src = top / rel
        if not src.exists() or src.is_dir():
            continue
        dst = project_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    return tmp


# ---------------------------------------------------------------------------
# Viewer 3D — téléchargement du binaire Godot standalone depuis la release
# ---------------------------------------------------------------------------

def download_viewer(owner: str, repo: str, dest_dir: Path,
                    progress: Optional[Callable[[int, int], None]] = None,
                    ) -> Path:
    """Télécharge le viewer 3D standalone depuis la dernière release et
    l'installe dans ``dest_dir`` (bundled_godot/). Intégrité vérifiée via
    le SHA256SUMS de la release (obligatoire). Lève RuntimeError sur tout
    échec. Utilisé en mode source quand bundled_godot/ est vide (le binaire
    est gitignoré) et que Godot n'est pas installé sur la machine.
    """
    entry = VIEWER_ASSETS.get(sys.platform)
    if entry is None:
        raise RuntimeError(f"pas de viewer 3D publié pour {sys.platform!r}")
    asset_name, local_name = entry
    release = check_latest_release(owner, repo)
    if release is None:
        raise RuntimeError("release GitHub injoignable")
    asset = next((a for a in release.assets if a.name == asset_name), None)
    if asset is None:
        raise RuntimeError(
            f"la release {release.tag} ne publie pas {asset_name!r} "
            f"(release antérieure à la publication du viewer ?)")
    tmp = Path(tempfile.mkdtemp(prefix="pn_viewer_"))
    tmp_bin = tmp / asset_name
    _stream_download(asset.url, tmp_bin, progress=progress)
    if asset.size and tmp_bin.stat().st_size != asset.size:
        raise RuntimeError("taille téléchargée != taille annoncée")
    _verify_asset_sha256(release, asset, tmp_bin)
    dest_dir = Path(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / local_name
    shutil.move(str(tmp_bin), str(dest))
    if sys.platform != "win32":
        dest.chmod(0o755)
    return dest


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def download_and_install(
    release: ReleaseInfo,
    project_dir: Path,
    progress: Optional[Callable[[int, int], None]] = None,
) -> Optional[Path]:
    """Install the update appropriate to the current runtime mode.

    In frozen mode, returns None (the swap script will relaunch the
    app).  In source mode, returns the temp directory used for
    extraction.
    """
    if is_frozen():
        _install_frozen(release, progress)
        return None
    return _install_source(release, project_dir, progress)


def relaunch_app() -> None:
    """Termine le process pour laisser le batch de swap remplacer l'exe
    puis relancer la nouvelle version.

    IMPORTANT : en frozen/Windows on utilise ``os._exit(0)`` — une sortie
    DURE — et pas ``sys.exit(0)``. sys.exit() lève SystemExit, qui est
    avalé par la boucle d'événements Qt quand relaunch_app est appelé
    depuis un slot/QTimer : le process ne mourait pas, le batch attendait
    la mort du PID indéfiniment et le swap n'avait jamais lieu (cause n°1
    du « la MAJ marche pas »). os._exit tue le process immédiatement."""
    _log("[relaunch] fin du process pour laisser le swap opérer")
    if is_frozen() and sys.platform == "win32":
        # Laisse le temps aux tampons du log de partir, puis exit dur.
        sys.stdout.flush() if sys.stdout else None
        os._exit(0)
    try:
        python = sys.executable
        os.execv(python, [python] + sys.argv)
    except Exception:
        os._exit(0)


class UpdateCheckThread(threading.Thread):
    def __init__(self, owner: str, repo: str,
                 on_result: Callable[[Optional[ReleaseInfo]], None]) -> None:
        super().__init__(daemon=True, name="pn-update-check")
        self.owner = owner
        self.repo = repo
        self._cb = on_result

    def run(self) -> None:
        try:
            info = check_latest_release(self.owner, self.repo)
        except Exception:
            info = None
        try:
            self._cb(info)
        except Exception:
            pass
