from susurro_backend.lang import detect


def test_spanish_text_detected_as_es():
    result = detect("Hola, ¿cómo estás? Me gustaría revisar el pull request.")
    assert result == "es"


def test_english_text_detected_as_en():
    result = detect("Hello, could we review the pull request before merging?")
    assert result == "en"


def test_short_text_falls_back_to_en():
    result = detect("Hi")
    assert result == "en"


def test_mixed_code_text_returns_dominant_language():
    result = detect("Hola, I want to revisar el código and merge the pull request pronto.")
    assert result in ("es", "en")
