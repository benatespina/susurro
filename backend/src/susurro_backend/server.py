import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Optional, Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

import susurro_backend.lang as lang

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
        logger.info(
            "tts/stream language=%s len=%d text=%.60s",
            resolved_language,
            len(request.text),
            request.text,
        )

        async def gen():
            first_chunk_logged = False
            try:
                async for piece in tts.synthesize_chunked(request.text, resolved_language):
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

    @app.post("/stop", status_code=204)
    def stop(_: None = Depends(verify_token)):
        tts.request_cancel()

    return app
