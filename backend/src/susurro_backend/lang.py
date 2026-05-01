from typing import Literal

from lingua import Language, LanguageDetectorBuilder

_detector = None


def _get_detector():
    global _detector
    if _detector is None:
        _detector = (
            LanguageDetectorBuilder.from_languages(Language.ENGLISH, Language.SPANISH)
            .with_minimum_relative_distance(0.1)
            .build()
        )
    return _detector


def detect(text: str) -> Literal["es", "en"]:
    if len(text) < 10:
        return "en"

    detector = _get_detector()
    result = detector.detect_language_of(text)

    if result == Language.SPANISH:
        return "es"
    return "en"
