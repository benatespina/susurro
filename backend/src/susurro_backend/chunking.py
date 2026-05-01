import re
from typing import Iterable

MAX_CHUNK_CHARS = 1500

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?…])\s+")
_COMMA_SPLIT = re.compile(r"(?<=[,;:])\s+")


def _split_long(piece: str, max_chars: int) -> Iterable[str]:
    if len(piece) <= max_chars:
        yield piece
        return
    sub = _COMMA_SPLIT.split(piece)
    buf = ""
    for s in sub:
        if not s:
            continue
        if len(s) > max_chars:
            if buf:
                yield buf
                buf = ""
            for i in range(0, len(s), max_chars):
                yield s[i : i + max_chars]
            continue
        if buf and len(buf) + 1 + len(s) > max_chars:
            yield buf
            buf = s
        else:
            buf = f"{buf} {s}" if buf else s
    if buf:
        yield buf


def chunk_text(text: str, max_chars: int = MAX_CHUNK_CHARS) -> Iterable[str]:
    sentences = [s.strip() for s in _SENTENCE_SPLIT.split(text.strip()) if s.strip()]
    buf = ""
    for sentence in sentences:
        if len(sentence) > max_chars:
            if buf:
                yield buf
                buf = ""
            yield from _split_long(sentence, max_chars)
            continue
        if buf and len(buf) + 1 + len(sentence) > max_chars:
            yield buf
            buf = sentence
        else:
            buf = f"{buf} {sentence}" if buf else sentence
    if buf:
        yield buf
