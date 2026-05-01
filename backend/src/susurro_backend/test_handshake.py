import json
import os
import stat

import pytest

import susurro_backend.config as config
import susurro_backend.handshake as handshake
from susurro_backend.handshake import (
    AlreadyRunning,
    acquire_or_fail,
    generate_token,
    is_pid_alive,
    pick_free_port,
    read_lockfile,
    release,
    write_lockfile,
)


@pytest.fixture(autouse=True)
def isolate_lockfile(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "LOCKFILE_PATH", tmp_path / "backend.lock")
    handshake._cleanup_registered = False
    yield


def test_pick_free_port_returns_valid_port():
    port = pick_free_port()
    assert 1024 <= port <= 65535


def test_generate_token_returns_sufficient_length():
    token = generate_token()
    assert isinstance(token, str)
    assert len(token) >= 32


def test_write_and_read_lockfile_roundtrip():
    port = 12345
    token = "test-token-abc"

    write_lockfile(port, token)
    data = read_lockfile()

    assert data is not None
    assert data["port"] == port
    assert data["token"] == token
    assert data["pid"] == os.getpid()
    assert "started_at" in data


def test_write_lockfile_sets_mode_0o600(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "LOCKFILE_PATH", tmp_path / "backend.lock")
    write_lockfile(9999, "secret-token")
    mode = stat.S_IMODE(os.stat(config.LOCKFILE_PATH).st_mode)
    assert mode == 0o600


def test_read_lockfile_returns_none_when_missing():
    assert read_lockfile() is None


def test_read_lockfile_returns_none_when_malformed(tmp_path, monkeypatch):
    lockfile = tmp_path / "backend.lock"
    lockfile.write_text("not-valid-json")
    monkeypatch.setattr(config, "LOCKFILE_PATH", lockfile)
    assert read_lockfile() is None


def test_is_pid_alive_dead_pid():
    # PID 2**22 is virtually guaranteed not to exist
    assert is_pid_alive(2**22 - 1) is False


def test_is_pid_alive_current_process():
    assert is_pid_alive(os.getpid()) is True


def test_acquire_or_fail_raises_already_running_when_alive(monkeypatch):
    port, token = acquire_or_fail()
    # override is_pid_alive so it reports our own PID as alive
    monkeypatch.setattr(handshake, "is_pid_alive", lambda pid: True)
    with pytest.raises(AlreadyRunning) as exc_info:
        acquire_or_fail()
    assert exc_info.value.pid == os.getpid()


def test_acquire_or_fail_overwrites_stale_lockfile(tmp_path, monkeypatch):
    lockfile = tmp_path / "backend.lock"
    monkeypatch.setattr(config, "LOCKFILE_PATH", lockfile)
    stale = {"port": 1111, "pid": 2**22 - 1, "token": "old", "started_at": "x"}
    lockfile.write_text(json.dumps(stale))
    os.chmod(lockfile, 0o600)

    port, token = acquire_or_fail()

    data = read_lockfile()
    assert data is not None
    assert data["port"] == port
    assert data["token"] == token
    assert data["pid"] == os.getpid()


def test_release_is_idempotent():
    write_lockfile(1234, "tok")
    release()
    release()  # second call must not raise
    assert read_lockfile() is None
