"""Authentication and programmatic authorization (master prompt §2)."""

from __future__ import annotations

from .guard import Guard
from .identity import Principal, resolve_identity
from .roles import Permission, Role, permissions_for

__all__ = [
    "Guard",
    "Permission",
    "Principal",
    "Role",
    "permissions_for",
    "resolve_identity",
]
