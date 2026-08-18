"""SQLAlchemy declarative base.

Domain tables (entities, securities, price_observations, fundamentals, ...)
are added in step 2 via Alembic migrations. This file exists now so Alembic's
`env.py` has a stable `target_metadata` to import from day one.
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
