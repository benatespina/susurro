import json
import re
from pathlib import Path
from typing import Iterable
from xml.sax.saxutils import escape, quoteattr

from susurro_backend import pronunciations_dict, pronunciations_rules

PRONUNCIATIONS_PATH = (
    Path.home() / "Library/Application Support/Susurro/pronunciations.json"
)

DEFAULT_TEMPLATE = {
    "es": {
        "dónde": '<emphasis level="moderate">dónde</emphasis>'
    },
    "en": {},
}

SUPPORTED_LANGUAGES = ("es", "en")


def _ensure_file() -> None:
    if PRONUNCIATIONS_PATH.exists():
        return
    PRONUNCIATIONS_PATH.parent.mkdir(parents=True, exist_ok=True)
    PRONUNCIATIONS_PATH.write_text(
        json.dumps(DEFAULT_TEMPLATE, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _read_data() -> dict:
    _ensure_file()
    try:
        data = json.loads(PRONUNCIATIONS_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {"es": {}, "en": {}}
    if not isinstance(data, dict):
        return {"es": {}, "en": {}}
    return data


def _write_data(data: dict) -> None:
    PRONUNCIATIONS_PATH.parent.mkdir(parents=True, exist_ok=True)
    PRONUNCIATIONS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _load(language: str) -> dict[str, str]:
    data = _read_data()
    section = data.get(language, {})
    if not isinstance(section, dict):
        return {}
    return {str(k): str(v) for k, v in section.items() if k}


def list_all() -> dict[str, dict[str, str]]:
    data = _read_data()
    result: dict[str, dict[str, str]] = {}
    for lang in SUPPORTED_LANGUAGES:
        section = data.get(lang, {})
        if isinstance(section, dict):
            result[lang] = {str(k): str(v) for k, v in section.items() if k}
        else:
            result[lang] = {}
    return result


def upsert(language: str, word: str, replacement: str) -> None:
    if language not in SUPPORTED_LANGUAGES:
        raise ValueError(f"language must be one of {SUPPORTED_LANGUAGES}")
    word = word.strip()
    if not word:
        raise ValueError("word required")
    if not replacement:
        raise ValueError("replacement required")
    data = _read_data()
    section = data.get(language)
    if not isinstance(section, dict):
        section = {}
        data[language] = section
    section[word] = replacement
    _write_data(data)


def remove(language: str, word: str) -> bool:
    if language not in SUPPORTED_LANGUAGES:
        return False
    data = _read_data()
    section = data.get(language)
    if not isinstance(section, dict) or word not in section:
        return False
    del section[word]
    _write_data(data)
    return True


def _compile_pattern(words: Iterable[str]) -> re.Pattern[str] | None:
    keys = [w for w in words if w]
    if not keys:
        return None
    keys.sort(key=len, reverse=True)
    alternation = "|".join(re.escape(k) for k in keys)
    return re.compile(rf"(?<!\w)({alternation})(?!\w)", re.UNICODE | re.IGNORECASE)


def apply(text: str, language: str) -> str:
    """
    Returns an XML/SSML-safe inner-fragment for the given text.

    Words present in the user's pronunciations.json for `language` are
    replaced by their raw SSML value (not escaped). Matching is
    case-insensitive: a stored entry "Playbook" still matches "playbook"
    in the input text. Everything else is XML-escaped so it's safe to
    embed inside a <voice> element.
    """
    replacements = _load(language)
    pattern = _compile_pattern(replacements.keys())
    if pattern is None:
        return escape(text)

    ci_map = {k.lower(): v for k, v in replacements.items()}

    parts: list[str] = []
    last = 0
    for match in pattern.finditer(text):
        parts.append(escape(text[last : match.start()]))
        parts.append(ci_map[match.group(1).lower()])
        last = match.end()
    parts.append(escape(text[last:]))
    return "".join(parts)


def candidates(word: str, language: str) -> list[dict]:
    """
    Generate up to ~5 SSML candidate replacements for a word.

    Each candidate is a dict: {"kind": str, "label": str, "ssml": str}.
    The order is roughly best-first: dictionary > derived IPA > sub alias > lang switch.
    """
    word = word.strip()
    if not word:
        return []

    out: list[dict] = []
    safe_word = escape(word)

    if pronunciations_dict.is_acronym(word):
        out.append({
            "kind": "say-as",
            "label": "Read letter by letter",
            "ssml": f'<say-as interpret-as="characters">{safe_word}</say-as>',
        })

    entry = pronunciations_dict.lookup(word, language)
    seen_ipas: set[str] = set()
    if entry and entry.get("ipa"):
        ipa = entry["ipa"]
        seen_ipas.add(ipa)
        out.append({
            "kind": "phoneme",
            "label": f"IPA (curated): {ipa}",
            "ssml": f'<phoneme alphabet="ipa" ph={quoteattr(ipa)}>{safe_word}</phoneme>',
        })

    if language == "es":
        derived_ipa = pronunciations_rules.en_to_ipa_es(word)
        if derived_ipa and derived_ipa not in seen_ipas:
            seen_ipas.add(derived_ipa)
            out.append({
                "kind": "phoneme",
                "label": f"IPA (derived): {derived_ipa}",
                "ssml": f'<phoneme alphabet="ipa" ph={quoteattr(derived_ipa)}>{safe_word}</phoneme>',
            })

        translit = pronunciations_rules.transliterate_to_es(word)
        if translit and translit != word.lower():
            out.append({
                "kind": "sub",
                "label": f"Read as “{translit}”",
                "ssml": f'<sub alias={quoteattr(translit)}>{safe_word}</sub>',
            })

        out.append({
            "kind": "lang",
            "label": "Read in English",
            "ssml": f'<lang xml:lang="en-US">{safe_word}</lang>',
        })

    if language == "en":
        out.append({
            "kind": "raw",
            "label": "Keep as-is",
            "ssml": safe_word,
        })

    return out
