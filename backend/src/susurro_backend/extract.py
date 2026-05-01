from dataclasses import dataclass
from typing import Optional

import trafilatura


@dataclass
class Extracted:
    text: str
    title: Optional[str]
    url: str


class ExtractError(Exception):
    pass


def extract_article(url: str) -> Extracted:
    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        raise ExtractError("fetch failed")
    result = trafilatura.extract(
        downloaded,
        output_format="json",
        with_metadata=True,
        include_comments=False,
        include_tables=False,
        favor_precision=True,
    )
    if not result:
        raise ExtractError("no readable article content")
    import json
    parsed = json.loads(result)
    text = (parsed.get("text") or "").strip()
    if not text:
        raise ExtractError("empty article body")
    return Extracted(text=text, title=parsed.get("title"), url=url)
