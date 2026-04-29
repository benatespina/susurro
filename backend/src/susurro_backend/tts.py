import io
import threading
import wave
from pathlib import Path
from typing import Literal

from piper import PiperVoice
from piper.download_voices import download_voice

VOICE_DIR = Path.home() / "Library/Application Support/Susurro/piper-voices"

VOICE_BY_LANG: dict[str, str] = {
    "es": "es_ES-davefx-medium",
    "en": "en_US-lessac-medium",
}

_voices: dict[str, PiperVoice] = {}
_loaded = False
_cancel_flag = threading.Event()


class GenerationCancelled(Exception):
    pass


def _ensure_voice_file(voice_name: str) -> Path:
    VOICE_DIR.mkdir(parents=True, exist_ok=True)
    model_path = VOICE_DIR / f"{voice_name}.onnx"
    if not model_path.exists() or model_path.stat().st_size == 0:
        download_voice(voice_name, VOICE_DIR)
    return model_path


def load_model() -> None:
    global _loaded
    if _loaded:
        return
    for lang, voice_name in VOICE_BY_LANG.items():
        model_path = _ensure_voice_file(voice_name)
        _voices[lang] = PiperVoice.load(model_path, use_cuda=False)
    _loaded = True


def is_loaded() -> bool:
    return _loaded


def synthesize(text: str, language: Literal["es", "en"]) -> bytes:
    if not _loaded:
        raise RuntimeError("Model not loaded — call load_model() first")

    _cancel_flag.clear()

    voice = _voices[language]

    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        voice.synthesize_wav(text, wav_file)

    if _cancel_flag.is_set():
        _cancel_flag.clear()
        raise GenerationCancelled()

    buffer.seek(0)
    return buffer.read()


def request_cancel() -> None:
    _cancel_flag.set()


async def synthesize_stream(text: str, language):
    import asyncio as _asyncio
    loop = _asyncio.get_event_loop()
    data = await loop.run_in_executor(None, synthesize, text, language)
    yield data
