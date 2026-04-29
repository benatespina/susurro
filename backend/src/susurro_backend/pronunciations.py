import json
import re
from pathlib import Path
from typing import Iterable
from xml.sax.saxutils import escape

PRONUNCIATIONS_PATH = (
    Path.home() / "Library/Application Support/Susurro/pronunciations.json"
)

DEFAULT_TEMPLATE = {
    "es": {
        "dónde": '<emphasis level="moderate">dónde</emphasis>'
    },
    "en": {},
}


def _ensure_file() -> None:
    if PRONUNCIATIONS_PATH.exists():
        return
    PRONUNCIATIONS_PATH.parent.mkdir(parents=True, exist_ok=True)
    PRONUNCIATIONS_PATH.write_text(
        json.dumps(DEFAULT_TEMPLATE, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _load(language: str) -> dict[str, str]:
    _ensure_file()
    try:
        data = json.loads(PRONUNCIATIONS_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}
    section = data.get(language, {})
    if not isinstance(section, dict):
        return {}
    return {str(k): str(v) for k, v in section.items() if k}


def _compile_pattern(words: Iterable[str]) -> re.Pattern[str] | None:
    keys = [w for w in words if w]
    if not keys:
        return None
    keys.sort(key=len, reverse=True)
    alternation = "|".join(re.escape(k) for k in keys)
    return re.compile(rf"(?<!\w)({alternation})(?!\w)", re.UNICODE)


def apply(text: str, language: str) -> str:
    """
    Returns an XML/SSML-safe inner-fragment for the given text.

    Words present in the user's pronunciations.json for `language` are
    replaced by their raw SSML value (not escaped). Everything else is
    XML-escaped so it's safe to embed inside a <voice> element.
    """
    replacements = _load(language)
    pattern = _compile_pattern(replacements.keys())
    if pattern is None:
        return escape(text)

    parts: list[str] = []
    last = 0
    for match in pattern.finditer(text):
        parts.append(escape(text[last : match.start()]))
        parts.append(replacements[match.group(1)])
        last = match.end()
    parts.append(escape(text[last:]))
    return "".join(parts)
