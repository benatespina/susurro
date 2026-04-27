# susurro-backend

Local FastAPI server providing TTS via mlx-audio + Chatterbox-Multilingual-MLX-v2-Q8.

## Install

```
python3.12 -m venv .venv
.venv/bin/pip install -e '.[dev]'
```

## Run standalone

The Swift app spawns this automatically. To run by hand for testing:

```
.venv/bin/python -m susurro_backend
```

It picks a free port and writes `~/Library/Application Support/Susurro/backend.lock` with `{port, pid, token, started_at}`.

## API

- `GET /health` — `{"status":"ready"|"loading"}` — no auth
- `POST /tts` (auth: `Authorization: Bearer <token>`) — body `{text: str, language: "es"|"en"|null}` — returns WAV bytes
- `POST /stop` (auth) — best-effort cancel of in-flight generation, returns 204

## Tests

```
.venv/bin/pytest -v src/susurro_backend/
```

Slow tests (model load) are skipped by default. Run with `pytest -m slow` to include.

## Cache

First request downloads ~1.7 GB of model weights to `~/Library/Application Support/Susurro/models/` (set via `HF_HOME`).
