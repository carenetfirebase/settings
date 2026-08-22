"""On-disk HTTP response cache.

Purpose is not speed, it is not re-hammering a source. A backfill that has to
restart should replay from disk rather than re-issue 4,000 requests to a site
that bans on volume.

The cache is keyed by method, URL, and User-Agent. It stores the body verbatim
plus the time of retrieval, and never rewrites an entry in place — a changed
response writes a new entry under a new content hash, which is the same
append-only discipline ``raw_documents`` uses in the database.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass(frozen=True, slots=True)
class CachedResponse:
    status_code: int
    body: bytes
    retrieved_at: datetime
    url: str

    @property
    def content_hash(self) -> str:
        return hashlib.sha256(self.body).hexdigest()


def cache_key(method: str, url: str, user_agent: str) -> str:
    raw = f"{method.upper()}\n{url}\n{user_agent}".encode()
    return hashlib.sha256(raw).hexdigest()


class ResponseCache:
    """Content-addressed response store under ``cache_dir``."""

    def __init__(self, cache_dir: Path) -> None:
        self._dir = cache_dir

    def _paths(self, key: str) -> tuple[Path, Path]:
        # Shard by the first two hex characters so no directory holds 100k files.
        shard = self._dir / key[:2]
        return shard / f"{key}.body", shard / f"{key}.meta.json"

    def get(self, key: str, *, max_age_seconds: float | None = None) -> CachedResponse | None:
        body_path, meta_path = self._paths(key)
        if not body_path.is_file() or not meta_path.is_file():
            return None
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            retrieved_at = datetime.fromisoformat(meta["retrieved_at"])
        except (OSError, ValueError, KeyError):
            # A corrupt entry is a cache miss, never an exception that stops a job.
            return None
        if max_age_seconds is not None:
            age = (datetime.now(retrieved_at.tzinfo) - retrieved_at).total_seconds()
            if age > max_age_seconds:
                return None
        return CachedResponse(
            status_code=int(meta["status_code"]),
            body=body_path.read_bytes(),
            retrieved_at=retrieved_at,
            url=str(meta["url"]),
        )

    def put(self, key: str, response: CachedResponse) -> None:
        body_path, meta_path = self._paths(key)
        body_path.parent.mkdir(parents=True, exist_ok=True)
        body_path.write_bytes(response.body)
        meta_path.write_text(
            json.dumps(
                {
                    "status_code": response.status_code,
                    "retrieved_at": response.retrieved_at.isoformat(),
                    "url": response.url,
                    "content_hash": response.content_hash,
                },
                indent=2,
                sort_keys=True,
            ),
            encoding="utf-8",
        )
