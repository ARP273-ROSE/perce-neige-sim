"""Anonymous crash + manual bug reporting for Perce-Neige Simulator.

Design goals
------------
- **No telemetry** : we never send anything over the network automatically.
  The user always explicitly chooses to open a pre-filled GitHub Issue
  in their browser.
- **Fully anonymous** : every path is stripped of the user's home
  directory (replaced by ``~``), never any username, host name or
  absolute local path. No IP address, no account info, no email.
- **Crash capture** : ``install_crash_handler()`` hooks ``sys.excepthook``
  and writes a JSON crash report next to the project so the next launch
  can offer to send it.
- **Manual report** : the Help menu entry lets the user write a free-form
  description and opens a pre-filled GitHub Issue URL.

Storage
-------
Reports live in ``<project_dir>/crash_reports/`` as individual JSON files.
Delete them freely — the next launch simply won't find anything to offer.
"""
from __future__ import annotations

import json
import locale
import os
import platform
import re
import sys
import traceback
import urllib.parse
from datetime import datetime
from pathlib import Path
from typing import Optional


REPO_OWNER = "ARP273-ROSE"
REPO_NAME = "perce-neige-sim"
ISSUES_URL = f"https://github.com/{REPO_OWNER}/{REPO_NAME}/issues/new"

# Max body length accepted by GitHub's URL-encoded "new issue" endpoint
MAX_ISSUE_BODY = 6000


def _anonymize(text: str) -> str:
    """Strip any absolute user path, username or home directory.

    - C:/Users/<name>/...  → ~/...
    - /home/<name>/...     → ~/...
    - /Users/<name>/...    → ~/...
    - Any remaining reference to the current username → ~user
    """
    if not text:
        return text
    home = str(Path.home()).replace("\\", "/")
    text_norm = text.replace("\\", "/")
    # Replace the exact home dir with ~
    if home:
        text_norm = text_norm.replace(home, "~")
    # Generic Windows / Linux / macOS user paths
    text_norm = re.sub(r"(?i)C:/Users/[^/\"'<>]+", "~", text_norm)
    text_norm = re.sub(r"/home/[^/\"'<>]+", "~", text_norm)
    text_norm = re.sub(r"/Users/[^/\"'<>]+", "~", text_norm)
    # Remove any lingering occurrence of the current OS username
    user = os.environ.get("USER") or os.environ.get("USERNAME") or ""
    if user and len(user) > 2:
        text_norm = re.sub(re.escape(user), "~user", text_norm,
                           flags=re.IGNORECASE)
    return text_norm


def _system_info(version: str) -> dict:
    return {
        "app_version": version,
        "python": sys.version.split()[0],
        "platform": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "arch": platform.architecture()[0],
        # locale is read from Python (not env var) to avoid leaking
        # user-set LANG values that may contain personal/region info.
        "locale": (locale.getlocale()[0] or "")[:5] if locale else "",
    }


def _reports_dir(project_dir: Path) -> Path:
    d = Path(project_dir) / "crash_reports"
    d.mkdir(exist_ok=True)
    return d


def save_crash_report(
    project_dir: Path,
    version: str,
    exc_type: type,
    exc_value: BaseException,
    exc_tb,
) -> Optional[Path]:
    """Write an anonymized crash report JSON.  Returns path, or None."""
    try:
        tb_text = "".join(traceback.format_exception(exc_type, exc_value, exc_tb))
        report = {
            "kind": "crash",
            "timestamp": datetime.now().isoformat(timespec="seconds"),
            "system": _system_info(version),
            "exception_type": getattr(exc_type, "__name__", str(exc_type)),
            "exception_message": _anonymize(str(exc_value))[:2000],
            "traceback": _anonymize(tb_text)[:8000],
        }
        d = _reports_dir(project_dir)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = d / f"crash_{ts}.json"
        path.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return path
    except Exception:
        return None


def install_crash_handler(project_dir: Path, version: str) -> None:
    """Hook sys.excepthook so any unhandled exception is saved."""
    previous = sys.excepthook

    def _hook(exc_type, exc_value, exc_tb):
        try:
            save_crash_report(project_dir, version, exc_type, exc_value, exc_tb)
        except Exception:
            pass
        previous(exc_type, exc_value, exc_tb)

    sys.excepthook = _hook


def list_pending_reports(project_dir: Path) -> list[Path]:
    d = _reports_dir(project_dir)
    return sorted(d.glob("crash_*.json"))


def load_report(path: Path) -> Optional[dict]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def format_crash_body(report: dict) -> str:
    sysinfo = report.get("system", {})
    body = [
        "**Automatic crash report (anonymized)**",
        "",
        f"- Time : {report.get('timestamp', '')}",
        f"- Version : {sysinfo.get('app_version', '')}",
        f"- Python : {sysinfo.get('python', '')}",
        f"- OS : {sysinfo.get('platform', '')} {sysinfo.get('release', '')}"
        f" ({sysinfo.get('arch', '')})",
        "",
        "## Exception",
        "```",
        f"{report.get('exception_type', '')}:"
        f" {report.get('exception_message', '')}",
        "```",
        "",
        "## Traceback",
        "```",
        report.get("traceback", "")[:4500],
        "```",
    ]
    return "\n".join(body)


def format_manual_body(
    description: str,
    steps: str,
    version: str,
) -> str:
    info = _system_info(version)
    body = [
        "**Manual bug report (anonymized)**",
        "",
        "## Description",
        _anonymize(description.strip() or "(not provided)"),
        "",
        "## Steps to reproduce",
        _anonymize(steps.strip() or "(not provided)"),
        "",
        "## System",
        f"- Version : {info['app_version']}",
        f"- Python  : {info['python']}",
        f"- OS      : {info['platform']} {info['release']} ({info['arch']})",
    ]
    return "\n".join(body)


def make_issue_url(title: str, body: str) -> str:
    safe_title = _anonymize(title.strip() or "Bug report")
    safe_body = body[:MAX_ISSUE_BODY]
    params = urllib.parse.urlencode({
        "title": safe_title,
        "body": safe_body,
    })
    return f"{ISSUES_URL}?{params}"


def delete_report(path: Path) -> bool:
    try:
        Path(path).unlink(missing_ok=True)
        return True
    except Exception:
        return False
