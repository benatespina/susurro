import io
import queue
import threading
from typing import Optional

import numpy as np

from susurro_backend.config import MODEL_ID, SAMPLE_RATE

# MLX requires that the GPU stream is created and used on the same OS thread.
# We dedicate one background thread for all model load and generate calls.
# Requests are posted as (fn, Future) pairs; the worker thread executes fn and
# resolves the Future.

_model: Optional[object] = None
_cancel_flag = threading.Event()
_task_queue: queue.Queue = queue.Queue()
_worker_thread: Optional[threading.Thread] = None
_model_loaded_event = threading.Event()


class GenerationCancelled(Exception):
    pass


class _Future:
    def __init__(self):
        self._event = threading.Event()
        self._result = None
        self._exc = None

    def set_result(self, value):
        self._result = value
        self._event.set()

    def set_exception(self, exc):
        self._exc = exc
        self._event.set()

    def result(self, timeout=None):
        self._event.wait(timeout=timeout)
        if self._exc is not None:
            raise self._exc
        return self._result


def _worker_loop():
    global _model
    while True:
        fn, future = _task_queue.get()
        if fn is None:
            break
        try:
            future.set_result(fn())
        except Exception as exc:
            future.set_exception(exc)


def _ensure_worker_started():
    global _worker_thread
    if _worker_thread is not None:
        return
    _worker_thread = threading.Thread(target=_worker_loop, daemon=True, name="mlx-worker")
    _worker_thread.start()


def _dispatch(fn) -> _Future:
    _ensure_worker_started()
    future = _Future()
    _task_queue.put((fn, future))
    return future


def load_model() -> None:
    global _model
    if _model is not None:
        return

    def _load():
        global _model
        from mlx_audio.tts.utils import load_model as mlx_load_model
        _model = mlx_load_model(MODEL_ID)

    _dispatch(_load).result()


def synthesize(text: str, language: str) -> bytes:
    if _model is None:
        raise RuntimeError("Model not loaded — call load_model() first")

    _cancel_flag.clear()

    def _generate():
        audio_chunks = []

        # mlx-audio has no native cancellation hook — the flag is checked between
        # generator iterations (segment boundaries), which is best-effort.
        for result in _model.generate(
            text=text,
            lang_code=language,
            verbose=False,
            stream=False,
        ):
            if _cancel_flag.is_set():
                _cancel_flag.clear()
                raise GenerationCancelled()
            audio_chunks.append(np.array(result.audio))

        if not audio_chunks:
            raise RuntimeError("Model returned no audio")

        combined = (
            np.concatenate(audio_chunks, axis=0)
            if len(audio_chunks) > 1
            else audio_chunks[0]
        )

        buffer = io.BytesIO()
        import soundfile as sf
        sf.write(buffer, combined, SAMPLE_RATE, format="WAV")
        buffer.seek(0)
        return buffer.read()

    return _dispatch(_generate).result()


def request_cancel() -> None:
    _cancel_flag.set()


def get_model() -> Optional[object]:
    return _model
