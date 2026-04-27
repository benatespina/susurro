import pytest

import susurro_backend.tts as tts_module


@pytest.fixture(scope="session", autouse=True)
def loaded_model():
    tts_module.load_model()


@pytest.mark.slow
def test_synthesize_spanish_returns_wav_bytes():
    result = tts_module.synthesize("hola", "es")
    assert isinstance(result, bytes)
    assert result[:4] == b"RIFF"
    assert len(result) > 1024


@pytest.mark.slow
def test_synthesize_english_returns_wav_bytes():
    result = tts_module.synthesize("hello", "en")
    assert isinstance(result, bytes)
    assert result[:4] == b"RIFF"
    assert len(result) > 1024


@pytest.mark.slow
def test_synthesize_longer_spanish_text():
    text = "Buenas tardes. Esto es una prueba de síntesis de voz. Tercera oración para mayor cobertura."
    result = tts_module.synthesize(text, "es")
    assert isinstance(result, bytes)
    assert result[:4] == b"RIFF"
    assert len(result) > 4096


@pytest.mark.slow
def test_cancel_before_synthesize_raises():
    tts_module.request_cancel()
    with pytest.raises(tts_module.GenerationCancelled):
        tts_module.synthesize("this should be cancelled", "en")


@pytest.mark.slow
def test_synthesize_works_after_cancel():
    result = tts_module.synthesize("hello after cancel", "en")
    assert isinstance(result, bytes)
    assert result[:4] == b"RIFF"


@pytest.mark.slow
def test_is_loaded_true_after_load():
    assert tts_module.is_loaded() is True
