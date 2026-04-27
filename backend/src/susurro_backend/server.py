import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Optional, Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Response
from pydantic import BaseModel

import susurro_backend.lang as lang
import susurro_backend.tts as tts
from susurro_backend.tts import GenerationCancelled

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
            wav_bytes = tts.synthesize(request.text, resolved_language)
        except GenerationCancelled:
            return Response(
                content='{"error": "cancelled"}',
                status_code=499,
                media_type="application/json",
            )
        if _PROFILE:
            total_ms = (time.perf_counter() - t0) * 1000
            print(f"[PROFILE] /tts handler total={total_ms:.0f}ms", flush=True)
        return Response(content=wav_bytes, media_type="audio/wav")

    @app.post("/stop", status_code=204)
    def stop(_: None = Depends(verify_token)):
        tts.request_cancel()

    return app
