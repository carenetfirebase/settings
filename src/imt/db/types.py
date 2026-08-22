"""Shared column types.

``pg_enum`` exists because SQLAlchemy's default for a native Postgres enum is
to use the member *names* (``POLITICAL``) as labels, while every StrEnum here
is defined by its *value* (``political``) and the API contract, CHECK
constraints, and JSON payloads all use the value. Left at the default, a CHECK
constraint written against the documented value fails at migration time with
"invalid input value for enum".

Every enum column in the schema goes through here so the two can never drift.
"""

from __future__ import annotations

from enum import StrEnum

from sqlalchemy import Enum


def pg_enum(enum_cls: type[StrEnum], name: str, *, create_type: bool = True) -> Enum:
    """Native Postgres enum whose labels are the StrEnum's values."""
    return Enum(
        enum_cls,
        name=name,
        native_enum=True,
        create_type=create_type,
        values_callable=lambda cls: [member.value for member in cls],
    )
