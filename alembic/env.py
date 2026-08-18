from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from invest.config import get_settings
from invest.db.models import Base

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# All current and future ORM models must register on this Base so
# autogenerate can see them.
target_metadata = Base.metadata

# A URL set programmatically (by the test harness, or by a caller driving
# Alembic through its Python API) wins. Otherwise fall back to app config.
# Without this precedence, `command.upgrade()` would silently migrate whatever
# DATABASE_URL points at instead of the database the caller asked for.
if not config.get_main_option("sqlalchemy.url", None):
    config.set_main_option("sqlalchemy.url", get_settings().database_url)


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
