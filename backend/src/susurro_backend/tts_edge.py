import asyncio
import threading
from typing import AsyncIterator, Literal

import edge_tts

from susurro_backend.chunking import chunk_text as _chunk_text

VOICE_BY_LANG: dict[str, str] = {
    "es": "es-ES-AlvaroNeural",
    "en": "en-US-AriaNeural",
}

_loaded = False
_cancel_flag = threading.Event()


class GenerationCancelled(Exception):
    pass


async def _warmup() -> None:
    voice = VOICE_BY_LANG["es"]
    communicate = edge_tts.Communicate(" ", voice)
    async for _ in communicate.stream():
        pass


def load_model() -> None:
    global _loaded
    if _loaded:
        return
    try:
        asyncio.run(_warmup())
    except Exception:
        pass
    _loaded = True


def is_loaded() -> bool:
    return _loaded


async def synthesize_stream(text: str, language: Literal["es", "en"]) -> AsyncIterator[bytes]:
    if not _loaded:
        raise RuntimeError("Provider not initialized — call load_model() first")

    _cancel_flag.clear()
    voice = VOICE_BY_LANG[language]

    for chunk_text in _chunk_text(text):
        if _cancel_flag.is_set():
            _cancel_flag.clear()
            raise GenerationCancelled()
        communicate = edge_tts.Communicate(chunk_text, voice)
        async for chunk in communicate.stream():
            if _cancel_flag.is_set():
                _cancel_flag.clear()
                raise GenerationCancelled()
            if chunk["type"] == "audio":
                yield chunk["data"]


async def synthesize_chunked(text: str, language: Literal["es", "en"]) -> AsyncIterator[bytes]:
    """
    Yields one self-contained MP3 per text chunk. Each yield is a complete
    edge-tts response for one sentence-group, framed for incremental playback.
    """
    if not _loaded:
        raise RuntimeError("Provider not initialized — call load_model() first")

    _cancel_flag.clear()
    voice = VOICE_BY_LANG[language]

    for chunk_text in _chunk_text(text):
        if _cancel_flag.is_set():
            _cancel_flag.clear()
            raise GenerationCancelled()
        communicate = edge_tts.Communicate(chunk_text, voice)
        buf = bytearray()
        async for chunk in communicate.stream():
            if _cancel_flag.is_set():
                _cancel_flag.clear()
                raise GenerationCancelled()
            if chunk["type"] == "audio":
                buf.extend(chunk["data"])
        if buf:
            yield bytes(buf)


def synthesize(text: str, language: Literal["es", "en"]) -> bytes:
    async def _collect() -> bytes:
        chunks: list[bytes] = []
        async for chunk in synthesize_stream(text, language):
            chunks.append(chunk)
        return b"".join(chunks)

    return asyncio.run(_collect())


def request_cancel() -> None:
    _cancel_flag.set()
