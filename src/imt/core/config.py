"""Configuration: environment settings plus the YAML files under ``config/``.

Settings come from the environment (``.env``); source, weight, universe, and
sector definitions come from YAML so they are diffable and reviewable. Nothing
here reads a secret into a log line.
"""

from __future__ import annotations

import functools
from pathlib import Path
from typing import Any

import yaml
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


def repo_root() -> Path:
    """Repository root, resolved from this file rather than the cwd.

    Jobs are launched by Task Scheduler from an arbitrary working directory,
    so anything that resolves config relative to ``.`` breaks in production
    while passing in development.
    """
    return Path(__file__).resolve().parents[3]


def config_dir() -> Path:
    return repo_root() / "config"


class Settings(BaseSettings):
    """Environment-derived settings. Secrets live here and nowhere else."""

    model_config = SettingsConfigDict(
        env_file=".env", env_prefix="", extra="ignore", case_sensitive=False
    )

    sec_contact: str = Field(default="", alias="IMT_SEC_CONTACT")
    database_url: str = Field(
        default="postgresql+psycopg://imt:imt@127.0.0.1:5432/imt", alias="IMT_DATABASE_URL"
    )
    cache_dir: Path = Field(default=Path(".cache/http"), alias="IMT_CACHE_DIR")
    log_level: str = Field(default="INFO", alias="IMT_LOG_LEVEL")

    fred_api_key: str = Field(default="", alias="FRED_API_KEY")
    eia_api_key: str = Field(default="", alias="EIA_API_KEY")
    openfda_api_key: str = Field(default="", alias="OPENFDA_API_KEY")
    sam_api_key: str = Field(default="", alias="SAM_API_KEY")
    finra_api_key: str = Field(default="", alias="FINRA_API_KEY")

    llm_base_url: str = Field(default="http://localhost:1234/v1", alias="IMT_LLM_BASE_URL")
    llm_model: str = Field(default="", alias="IMT_LLM_MODEL")

    def user_agent(self) -> str:
        """The SEC requires a contact string. An empty one gets the IP blocked.

        We fail loudly here rather than sending a request that earns a ban.
        """
        if not self.sec_contact.strip():
            raise ValueError(
                "IMT_SEC_CONTACT is not set. The SEC blocks IPs whose User-Agent "
                "carries no contact address. Set it in .env before any ingest."
            )
        template = load_sources()["user_agent_template"]
        assert isinstance(template, str)
        return template.format(contact=self.sec_contact.strip())


@functools.lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


def _load_yaml(name: str) -> dict[str, Any]:
    path = config_dir() / name
    if not path.is_file():
        raise FileNotFoundError(f"Missing config file: {path}")
    with path.open("r", encoding="utf-8") as fh:
        loaded = yaml.safe_load(fh)
    if not isinstance(loaded, dict):
        raise ValueError(f"{path} must contain a mapping at the top level")
    return loaded


@functools.lru_cache(maxsize=1)
def load_sources() -> dict[str, Any]:
    return _load_yaml("sources.yaml")


@functools.lru_cache(maxsize=1)
def load_universe_config() -> dict[str, Any]:
    return _load_yaml("universe.yaml")


@functools.lru_cache(maxsize=1)
def load_sector_map() -> dict[str, Any]:
    return _load_yaml("sector_map.yaml")


@functools.lru_cache(maxsize=1)
def load_raw_weights() -> dict[str, Any]:
    return _load_yaml("weights.yaml")


def source_config(source_id: str) -> dict[str, Any]:
    sources = load_sources()["sources"]
    if source_id not in sources:
        raise KeyError(
            f"Unknown source '{source_id}'. Every outbound request must come from a "
            f"source declared in config/sources.yaml."
        )
        # This is the mechanism that stops a scraper for a banned site being
        # added quietly -- there is no code path to a host we did not declare.
    result = sources[source_id]
    assert isinstance(result, dict)
    return result


def forbidden_hosts() -> frozenset[str]:
    hosts = load_sources().get("forbidden_hosts", [])
    return frozenset(str(h).lower() for h in hosts)


def clear_config_cache() -> None:
    """Test helper. Production never calls this."""
    for fn in (
        get_settings,
        load_sources,
        load_universe_config,
        load_sector_map,
        load_raw_weights,
    ):
        fn.cache_clear()
