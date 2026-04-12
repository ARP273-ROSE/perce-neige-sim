"""GitHub-based auto-update for Perce-Neige Simulator.

Checks the repository's Releases API, compares the latest tag with the
running VERSION, downloads the zipball into a temp dir, validates size
+ members, and copies a whitelist of files into the project directory.
After a successful update it relaunches the app.

Security checks performed on the downloaded zip
-----------------------------------------------
- Max download size : 80 MB (protects against zip bombs)
- Member path validation : reject '..', '\\', null bytes and any path
  that escapes the temp extraction root
- Reject symlinks
- Only a whitelist of filenames is copied into the project directory so
  user-managed data (venv, CLAUDE.md, .git, local assets) is never
  touched

Network : uses urllib from stdlib to avoid adding a dependency.
"""
from __future__ import annotations

import json
import os
import shutil
import ssl
import sys
import tempfile
import threading
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional


GITHUB_API = "https://api.github.com/repos/{owner}/{repo}/releases/latest"
MAX_DOWNLOAD_BYTES = 80 * 1024 * 1024  # 80 MB
NETWORK_TIMEOUT = 10.0

# Files that auto-update is allowed to overwrite in the project dir.
# Everything else (venv, CLAUDE.md, user data, .git) is left untouched.
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


@dataclass
class ReleaseInfo:
    tag: str            # e.g. "v1.2.0"
    version: str        # normalized "1.2.0"
    name: str           # release title
    body: str           # changelog / markdown
    zipball_url: str    # GitHub zip archive
    html_url: str       # web page of the release


def _parse_version(s: str) -> tuple[int, ...]:
    """Parse '1.2.3' or 'v1.2.3' into a comparable tuple."""
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
    """Query the Releases API.  Returns None on any error (network / API)."""
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
    return ReleaseInfo(
        tag=tag,
        version=".".join(str(x) for x in _parse_version(tag)),
        name=str(data.get("name", tag)),
        body=str(data.get("body", "")),
        zipball_url=zipball,
        html_url=str(data.get("html_url", "")),
    )


def is_newer(remote_version: str, local_version: str) -> bool:
    return _parse_version(remote_version) > _parse_version(local_version)


def _safe_extract(zf: zipfile.ZipFile, dest: Path) -> Path:
    """Safely extract a zip into dest. Returns the single top-level dir.

    Rejects any member whose normalized path would escape dest, contains
    '..', backslashes, null bytes or is a symlink.
    """
    dest_resolved = dest.resolve()
    top_dirs: set[str] = set()
    for info in zf.infolist():
        name = info.filename
        if (not name or "\x00" in name or name.startswith("/")
                or ".." in name.split("/") or "\\" in name):
            raise ValueError(f"zip: unsafe member name {name!r}")
        # Symlinks in zip have high mode bits — refuse them.
        if (info.external_attr >> 16) & 0o170000 == 0o120000:
            raise ValueError(f"zip: symlink refused {name!r}")
        target = (dest_resolved / name).resolve()
        if dest_resolved not in target.parents and target != dest_resolved:
            raise ValueError(f"zip: path escape {name!r}")
        # Track top-level directory
        first = name.split("/", 1)[0]
        if first:
            top_dirs.add(first)
    zf.extractall(dest)
    if len(top_dirs) != 1:
        raise ValueError("zip: expected exactly one top-level directory")
    return dest / next(iter(top_dirs))


def download_and_install(
    release: ReleaseInfo,
    project_dir: Path,
    progress: Optional[Callable[[int, int], None]] = None,
) -> Path:
    """Download zipball, validate, copy whitelisted files over project_dir.

    Returns the path to the temp extraction dir (kept for debugging).
    Raises on any error — caller is responsible for showing a message.
    """
    tmp = Path(tempfile.mkdtemp(prefix="pn_update_"))
    zip_path = tmp / "release.zip"

    req = urllib.request.Request(
        release.zipball_url,
        headers={"User-Agent": "perce-neige-sim-auto-update"},
    )
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=NETWORK_TIMEOUT,
                                context=ctx) as resp:
        total = int(resp.headers.get("Content-Length", "0") or 0)
        if total and total > MAX_DOWNLOAD_BYTES:
            raise ValueError(f"download too large: {total} bytes")
        downloaded = 0
        with open(zip_path, "wb") as out:
            while True:
                chunk = resp.read(64 * 1024)
                if not chunk:
                    break
                downloaded += len(chunk)
                if downloaded > MAX_DOWNLOAD_BYTES:
                    raise ValueError("download exceeded max size")
                out.write(chunk)
                if progress is not None:
                    progress(downloaded, total)

    extract_root = tmp / "extract"
    extract_root.mkdir()
    with zipfile.ZipFile(zip_path) as zf:
        top = _safe_extract(zf, extract_root)

    # Copy whitelisted files into project_dir
    project_dir = Path(project_dir).resolve()
    for rel in sorted(UPDATE_WHITELIST):
        src = top / rel
        if not src.exists():
            continue
        if src.is_dir():
            continue  # whitelist is flat files only
        dst = project_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    return tmp


def relaunch_app() -> None:
    """Relaunch the current Python executable with the same argv, then exit."""
    try:
        python = sys.executable
        os.execv(python, [python] + sys.argv)
    except Exception:
        # Fallback — caller should exit and let the launcher restart us.
        sys.exit(0)


class UpdateCheckThread(threading.Thread):
    """Background thread that calls check_latest_release() once."""

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
