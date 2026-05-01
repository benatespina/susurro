import atexit
import json
import logging
import os
import secrets
import signal
import socket
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import susurro_backend.config as config

logger = logging.getLogger(__name__)

_cleanup_registered = False


class AlreadyRunning(Exception):
    def __init__(self, pid: int) -> None:
        self.pid = pid
        super().__init__(f"Susurro backend already running (pid={pid})")


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def generate_token() -> str:
    return secrets.token_urlsafe(32)


def write_lockfile(port: int, token: str) -> Path:
    path = config.LOCKFILE_PATH
    path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "port": port,
        "pid": os.getpid(),
        "token": token,
        "started_at": datetime.now(timezone.utc).isoformat(),
    }

    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload))
    os.chmod(tmp, 0o600)
    # atomic rename — avoids partial reads by the Swift side
    os.rename(tmp, path)

    return path


def read_lockfile() -> Optional[dict]:
    try:
        return json.loads(config.LOCKFILE_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def is_pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except ProcessLookupError:
        return False


def acquire_or_fail() -> tuple[int, str]:
    existing = read_lockfile()
    if existing is not None:
        pid = existing.get("pid")
        if pid is not None and is_pid_alive(pid):
            raise AlreadyRunning(pid)
        logger.warning("stale lockfile, overwriting")

    port = pick_free_port()
    token = generate_token()
    write_lockfile(port, token)
    return port, token


def release() -> None:
    try:
        config.LOCKFILE_PATH.unlink()
    except FileNotFoundError:
        pass


def register_cleanup() -> None:
    global _cleanup_registered
    if _cleanup_registered:
        return
    _cleanup_registered = True

    atexit.register(release)
    signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))
    signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))
