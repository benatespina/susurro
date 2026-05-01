import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Optional, Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

import susurro_backend.lang as lang
import susurro_backend.pronunciations as pronunciations
from susurro_backend.chunking import chunk_text
from susurro_backend.extract import ExtractError, extract_article

_PROVIDER = os.environ.get("SUSURRO_TTS_PROVIDER", "edge").lower()

if _PROVIDER == "azure":
    import susurro_backend.tts_azure as tts
    from susurro_backend.tts_azure import GenerationCancelled
else:
    import susurro_backend.tts_edge as tts
    from susurro_backend.tts_edge import GenerationCancelled

_MEDIA_TYPE = "audio/mpeg"
_STREAM_MEDIA_TYPE = "application/octet-stream"

_PROFILE = os.environ.get("SUSURRO_PROFILE") == "1"

logger = logging.getLogger(__name__)

_expected_token: Optional[str] = None


class TTSRequest(BaseModel):
    text: str
    language: Optional[Literal["es", "en"]] = None
    start_chunk: Optional[int] = None


class PronunciationUpsert(BaseModel):
    language: Literal["es", "en"]
    word: str
    replacement: str


class CandidatesRequest(BaseModel):
    word: str
    language: Literal["es", "en"]


class PreviewSSMLRequest(BaseModel):
    ssml: str
    language: Literal["es", "en"]


class ExtractRequest(BaseModel):
    url: str


def verify_token(authorization: Optional[str] = Header(None)) -> None:
    expected = f"Bearer {_expected_token}"
    if authorization != expected:
        raise HTTPException(status_code=401)


def create_app(token: str) -> FastAPI:
    global _expected_token
    _expected_token = token

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        import asyncio
        # schedule model load in the MLX worker thread without blocking uvicorn
        asyncio.get_event_loop().run_in_executor(None, tts.load_model)
        yield

    app = FastAPI(title="Susurro Backend", lifespan=lifespan)

    @app.get("/health")
    def health():
        if tts.is_loaded():
            return {"status": "ready"}
        return Response(
            content='{"status": "loading"}',
            status_code=503,
            media_type="application/json",
        )

    @app.post("/tts")
    def synthesize(request: TTSRequest, _: None = Depends(verify_token)):
        t0 = time.perf_counter()
        resolved_language = request.language or lang.detect(request.text)
        logger.info("tts language=%s text=%.60s", resolved_language, request.text)
        try:
            audio_bytes = tts.synthesize(request.text, resolved_language)
        except GenerationCancelled:
            return Response(
                content='{"error": "cancelled"}',
                status_code=499,
                media_type="application/json",
            )
        if _PROFILE:
            total_ms = (time.perf_counter() - t0) * 1000
            print(f"[PROFILE] /tts handler total={total_ms:.0f}ms", flush=True)
        return Response(content=audio_bytes, media_type=_MEDIA_TYPE)

    @app.post("/tts/stream")
    async def synthesize_stream_endpoint(
        request: TTSRequest, _: None = Depends(verify_token)
    ):
        t0 = time.perf_counter()
        resolved_language = request.language or lang.detect(request.text)
        all_chunks = list(chunk_text(request.text))
        start = max(0, request.start_chunk or 0)
        chunks_to_synthesize = all_chunks[start:]
        logger.info(
            "tts/stream language=%s len=%d total_chunks=%d start=%d text=%.60s",
            resolved_language,
            len(request.text),
            len(all_chunks),
            start,
            request.text,
        )

        async def gen():
            first_chunk_logged = False
            try:
                async for piece in tts.synthesize_chunks(chunks_to_synthesize, resolved_language):
                    if _PROFILE and not first_chunk_logged:
                        ttfb_ms = (time.perf_counter() - t0) * 1000
                        print(f"[PROFILE] /tts/stream ttfb={ttfb_ms:.0f}ms", flush=True)
                        first_chunk_logged = True
                    yield len(piece).to_bytes(4, "big") + piece
                yield (0).to_bytes(4, "big")
            except GenerationCancelled:
                return
            if _PROFILE:
                total_ms = (time.perf_counter() - t0) * 1000
                print(f"[PROFILE] /tts/stream total={total_ms:.0f}ms", flush=True)

        return StreamingResponse(gen(), media_type=_STREAM_MEDIA_TYPE)

    @app.post("/tts/chunks")
    def get_chunks(request: TTSRequest, _: None = Depends(verify_token)):
        resolved_language = request.language or lang.detect(request.text)
        chunks = list(chunk_text(request.text))
        return {"chunks": chunks, "language": resolved_language}

    @app.post("/stop", status_code=204)
    def stop(_: None = Depends(verify_token)):
        tts.request_cancel()

    @app.get("/pronunciations")
    def get_pronunciations(_: None = Depends(verify_token)):
        return pronunciations.list_all()

    @app.post("/pronunciations", status_code=204)
    def upsert_pronunciation(
        request: PronunciationUpsert, _: None = Depends(verify_token)
    ):
        try:
            pronunciations.upsert(
                request.language, request.word, request.replacement
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    @app.delete("/pronunciations/{language}/{word}", status_code=204)
    def delete_pronunciation(
        language: str, word: str, _: None = Depends(verify_token)
    ):
        if language not in pronunciations.SUPPORTED_LANGUAGES:
            raise HTTPException(status_code=400, detail="invalid language")
        pronunciations.remove(language, word)

    @app.post("/pronunciations/candidates")
    def pronunciation_candidates(
        request: CandidatesRequest, _: None = Depends(verify_token)
    ):
        return {"candidates": pronunciations.candidates(request.word, request.language)}

    @app.post("/tts/preview-ssml")
    async def preview_ssml(
        request: PreviewSSMLRequest, _: None = Depends(verify_token)
    ):
        if _PROVIDER != "azure":
            raise HTTPException(
                status_code=409,
                detail="preview requires the Azure TTS provider",
            )
        try:
            audio_bytes = await tts.synthesize_preview(
                request.ssml, request.language
            )
        except Exception as exc:
            logger.error("preview-ssml failed: %s", exc)
            raise HTTPException(status_code=502, detail=str(exc))
        return Response(content=audio_bytes, media_type=_MEDIA_TYPE)

    @app.post("/extract")
    async def extract_endpoint(
        request: ExtractRequest, _: None = Depends(verify_token)
    ):
        import asyncio
        url = request.url.strip()
        if not (url.startswith("http://") or url.startswith("https://")):
            raise HTTPException(status_code=400, detail="invalid url")
        try:
            article = await asyncio.get_event_loop().run_in_executor(
                None, extract_article, url
            )
        except ExtractError as exc:
            logger.warning("extract failed url=%s: %s", url, exc)
            raise HTTPException(status_code=422, detail=str(exc))
        resolved_language = lang.detect(article.text)
        logger.info(
            "extract url=%s len=%d language=%s",
            url, len(article.text), resolved_language,
        )
        return {
            "text": article.text,
            "title": article.title,
            "url": article.url,
            "language": resolved_language,
        }

    return app
