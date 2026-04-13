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
- Zip member validation : reject '..', '\\', null bytes and any path
  that escapes the extraction root
- Reject symlinks in zipballs
- Whitelist of filenames allowed to be written in source mode so
  user data (venv, CLAUDE.md, .git, local assets) is never touched

Network : uses urllib from stdlib to avoid adding a dependency.
"""
from __future__ import annotations

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


def _pick_binary_asset(release: ReleaseInfo) -> Optional[ReleaseAsset]:
    suffix = _platform_suffix()
    if not suffix:
        return None
    for a in release.assets:
        if a.name.endswith(suffix):
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


def _swap_windows_exe(new_exe: Path) -> None:
    """Schedule replacement of the currently-running .exe on Windows.

    You cannot overwrite a running .exe directly.  We drop a small
    batch script next to the new file that waits for our PID to exit,
    swaps the binaries, deletes itself and relaunches the app.
    """
    current = Path(sys.executable).resolve()
    pid = os.getpid()
    swap_bat = new_exe.parent / "_pn_update_swap.bat"
    # Use CRLF line endings, no UTF-8 BOM -- cmd.exe friendly.
    script = (
        "@echo off\r\n"
        "setlocal\r\n"
        f'set "PID={pid}"\r\n'
        f'set "TARGET={current}"\r\n'
        f'set "NEW={new_exe}"\r\n'
        ":waitloop\r\n"
        'tasklist /FI "PID eq %PID%" 2>nul | find "%PID%" >nul\r\n'
        "if %errorlevel%==0 (\r\n"
        "  timeout /t 1 /nobreak >nul\r\n"
        "  goto waitloop\r\n"
        ")\r\n"
        'del /Q "%TARGET%" >nul 2>&1\r\n'
        'move /Y "%NEW%" "%TARGET%" >nul\r\n'
        'start "" "%TARGET%"\r\n'
        '(goto) 2>nul & del "%~f0"\r\n'
    )
    swap_bat.write_bytes(script.encode("cp1252", errors="replace"))

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
    current = Path(sys.executable).resolve()
    tmp = Path(tempfile.mkdtemp(prefix="pn_update_"))
    new_bin = tmp / asset.name
    _stream_download(asset.url, new_bin, progress=progress)
    if new_bin.stat().st_size < 1024:
        raise RuntimeError("downloaded asset is suspiciously small")

    if sys.platform == "win32":
        # Move into the target directory first so move /Y is atomic
        staged = current.parent / (current.stem + ".new.exe")
        shutil.move(str(new_bin), str(staged))
        _swap_windows_exe(staged)
        # Parent continues; caller will sys.exit() via relaunch_app()
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
    """Relaunch the app.  In frozen/Windows mode the swap .bat handles
    the restart, so we just exit cleanly."""
    if is_frozen() and sys.platform == "win32":
        # swap .bat will start the new .exe once our PID dies
        sys.exit(0)
    try:
        python = sys.executable
        os.execv(python, [python] + sys.argv)
    except Exception:
        sys.exit(0)


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
