"""
Heuristic English→Spanish transliteration helpers.

Two outputs:
- en_to_ipa_es: rough IPA approximation usable inside an SSML
  <phoneme alphabet="ipa"> tag for Azure es-ES voices.
- transliterate_to_es: plain-Spanish-spelling string usable inside an SSML
  <sub alias="..."> tag (the TTS will read it as if it were a Spanish word).

Both are best-effort. Users preview candidates and pick the best.
"""

import re

_IPA_RULES: list[tuple[str, str]] = [
    (r"sh", "ʃ"),
    (r"ch", "tʃ"),
    (r"th", "θ"),
    (r"ph", "f"),
    (r"ck", "k"),
    (r"qu", "kw"),
    (r"ee", "i"),
    (r"oo", "u"),
    (r"ea", "i"),
    (r"ai", "ej"),
    (r"ay", "ej"),
    (r"ou", "aw"),
    (r"ow", "aw"),
    (r"oa", "ow"),
    (r"oi", "oj"),
    (r"oy", "oj"),
    (r"ie", "aj"),
    (r"x", "ks"),
    (r"y([aeiou])", r"j\1"),
    (r"y$", "i"),
    (r"j", "ʃ"),
    (r"v", "b"),
    (r"z", "s"),
    (r"w", "w"),
    (r"er$", "eɾ"),
    (r"ing$", "iŋ"),
    (r"tion$", "ʃon"),
    (r"sion$", "ʃon"),
    (r"ll", "l"),
]


def en_to_ipa_es(word: str) -> str:
    out = word.lower()
    for pattern, replacement in _IPA_RULES:
        out = re.sub(pattern, replacement, out)
    if out and out[0] == "s" and len(out) > 1 and out[1] not in "aeiouɑɛɪɔʊ":
        out = "e" + out
    return out


_TRANSLIT_RULES: list[tuple[str, str]] = [
    (r"sh", "sh"),
    (r"ch", "ch"),
    (r"th", "z"),
    (r"ph", "f"),
    (r"ck", "k"),
    (r"qu", "ku"),
    (r"ee", "i"),
    (r"oo", "u"),
    (r"ea", "i"),
    (r"ai", "ei"),
    (r"ay", "ei"),
    (r"ou", "au"),
    (r"ow", "au"),
    (r"oa", "ou"),
    (r"oi", "oi"),
    (r"oy", "oi"),
    (r"ie", "ai"),
    (r"x", "ks"),
    (r"y([aeiou])", r"y\1"),
    (r"y$", "i"),
    (r"j", "y"),
    (r"v", "b"),
    (r"z", "s"),
    (r"w", "u"),
    (r"er$", "er"),
    (r"ing$", "in"),
    (r"tion$", "shon"),
    (r"sion$", "shon"),
    (r"ll", "l"),
]


def transliterate_to_es(word: str) -> str:
    out = word.lower()
    for pattern, replacement in _TRANSLIT_RULES:
        out = re.sub(pattern, replacement, out)
    if out and out[0] == "s" and len(out) > 1 and out[1] not in "aeiou":
        out = "e" + out
    return out
