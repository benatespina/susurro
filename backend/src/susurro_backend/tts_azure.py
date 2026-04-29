import os
import re
import threading
from typing import AsyncIterator, Literal

import httpx

import susurro_backend.pronunciations as pronunciations

VOICE_BY_LANG: dict[str, str] = {
    "es": "es-ES-AlvaroNeural",
    "en": "en-US-AriaNeural",
}

_loaded = False
_cancel_flag = threading.Event()
_key: str | None = None
_region: str | None = None


class GenerationCancelled(Exception):
    pass


class AzureNotConfigured(Exception):
    pass


def load_model() -> None:
    global _loaded, _key, _region
    _key = os.environ.get("AZURE_SPEECH_KEY")
    _region = os.environ.get("AZURE_SPEECH_REGION")
    if not _key or not _region:
        raise AzureNotConfigured(
            "Azure provider requires AZURE_SPEECH_KEY and AZURE_SPEECH_REGION env vars"
        )
    _loaded = True


def is_loaded() -> bool:
    return _loaded


_PARAGRAPH_BREAK = '<break time="700ms"/>'
_LINE_BREAK = '<break time="300ms"/>'


def _inject_breaks(ssml_body: str) -> str:
    body = re.sub(r"￼+", _PARAGRAPH_BREAK, ssml_body)
    body = re.sub(r"(\r?\n[ \t]*){2,}", _PARAGRAPH_BREAK, body)
    body = re.sub(r"\r?\n", _LINE_BREAK, body)
    body = re.sub(r"([.!?])([A-ZÁÉÍÓÚÑ])", r"\1" + _PARAGRAPH_BREAK + r" \2", body)
    return body


def _build_ssml(text: str, voice: str, lang_code: str, language: str) -> str:
    body = pronunciations.apply(text, language)
    body = _inject_breaks(body)
    return (
        f"<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='{lang_code}'>"
        f"<voice xml:lang='{lang_code}' name='{voice}'>"
        f"{body}"
        "</voice>"
        "</speak>"
    )


def _lang_code(language: str) -> str:
    return {"es": "es-ES", "en": "en-US"}[language]


async def synthesize_stream(text: str, language: Literal["es", "en"]) -> AsyncIterator[bytes]:
    if not _loaded:
        raise RuntimeError("Provider not initialized — call load_model() first")
    assert _key and _region

    _cancel_flag.clear()
    voice = VOICE_BY_LANG[language]
    ssml = _build_ssml(text, voice, _lang_code(language), language)

    url = f"https://{_region}.tts.speech.microsoft.com/cognitiveservices/v1"
    headers = {
        "Ocp-Apim-Subscription-Key": _key,
        "Content-Type": "application/ssml+xml",
        "X-Microsoft-OutputFormat": "audio-24khz-48kbitrate-mono-mp3",
        "User-Agent": "susurro",
    }

    async with httpx.AsyncClient(timeout=httpx.Timeout(30.0)) as client:
        async with client.stream("POST", url, headers=headers, content=ssml.encode("utf-8")) as response:
            response.raise_for_status()
            async for chunk in response.aiter_bytes():
                if _cancel_flag.is_set():
                    _cancel_flag.clear()
                    raise GenerationCancelled()
                if chunk:
                    yield chunk


def synthesize(text: str, language: Literal["es", "en"]) -> bytes:
    import asyncio

    async def _collect() -> bytes:
        chunks: list[bytes] = []
        async for chunk in synthesize_stream(text, language):
            chunks.append(chunk)
        return b"".join(chunks)

    return asyncio.run(_collect())


def request_cancel() -> None:
    _cancel_flag.set()
