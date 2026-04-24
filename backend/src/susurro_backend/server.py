from typing import Optional, Literal

from fastapi import FastAPI, Response
from pydantic import BaseModel

import susurro_backend.lang as lang
import susurro_backend.tts as tts
from susurro_backend.tts import GenerationCancelled


class TTSRequest(BaseModel):
    text: str
    language: Optional[Literal["es", "en"]] = None


def create_app() -> FastAPI:
    app = FastAPI(title="Susurro Backend")

    @app.get("/health")
    def health():
        if tts.get_model() is not None:
            return {"status": "ready"}
        return Response(
            content='{"status": "loading"}',
            status_code=503,
            media_type="application/json",
        )

    @app.post("/tts")
    def synthesize(request: TTSRequest):
        resolved_language = request.language or lang.detect(request.text)
        print(f"TTS language={resolved_language!r} text={request.text[:60]!r}", flush=True)
        try:
            wav_bytes = tts.synthesize(request.text, resolved_language)
        except GenerationCancelled:
            return Response(
                content='{"error": "cancelled"}',
                status_code=499,
                media_type="application/json",
            )
        return Response(content=wav_bytes, media_type="audio/wav")

    @app.post("/stop", status_code=204)
    def stop():
        tts.request_cancel()

    return app


app = create_app()
