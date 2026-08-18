from invest.config import Settings


def test_settings_reads_database_url_from_env(monkeypatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://u:p@somehost:5432/somedb")
    settings = Settings()
    assert settings.database_url == "postgresql+psycopg://u:p@somehost:5432/somedb"


def test_settings_default_database_url_points_at_local_docker_compose() -> None:
    settings = Settings(_env_file=None)
    assert settings.database_url == "postgresql+psycopg://invest:invest@localhost:5432/invest"


def test_settings_optional_provider_keys_default_to_none() -> None:
    settings = Settings(_env_file=None)
    assert settings.fred_api_key is None
    assert settings.eia_api_key is None
    assert settings.bls_api_key is None
    assert settings.bea_api_key is None
