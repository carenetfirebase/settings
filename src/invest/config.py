"""Env-var driven application configuration. No hardcoded secrets.

Values are read from the process environment, with an optional `.env` file
(never committed) loaded for local development. See `.env.example`.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- Database ---
    database_url: str = "postgresql+psycopg://invest:invest@localhost:5432/invest"

    # --- SEC EDGAR ---
    # data.sec.gov requires a descriptive User-Agent identifying the app and a contact.
    # No API key exists or is needed.
    edgar_user_agent: str = "invest-research-platform (set EDGAR_USER_AGENT in .env)"

    # --- Macro / commodity data providers (free API keys) ---
    fred_api_key: str | None = None
    eia_api_key: str | None = None
    bls_api_key: str | None = None
    bea_api_key: str | None = None

    # --- App ---
    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    """Cached settings singleton. Use `get_settings.cache_clear()` in tests
    that mutate the environment.
    """
    return Settings()
