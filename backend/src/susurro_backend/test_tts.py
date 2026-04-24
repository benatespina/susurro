import pytest

import susurro_backend.tts as tts_module


@pytest.fixture(scope="session", autouse=True)
def loaded_model():
    tts_module.load_model()


@pytest.mark.slow
def test_synthesize_english_returns_wav_bytes():
    result = tts_module.synthesize("hello world", "en")
    assert isinstance(result, bytes)
    assert result[:4] == b"RIFF"
    assert len(result) > 1024
