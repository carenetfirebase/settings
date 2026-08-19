"""Identity resolution via Windows user binding (master prompt §2.1).

The MVP binds identity to the logged-on OS account rather than running its
own login. On Windows the account is identified by SID, not username: a
username can be deleted and recreated, and a renamed account keeps its
SID, so the SID is the stable subject for both the role assignment and the
DPAPI key binding.

Role assignment lives in a JSON file that only ADMIN can write. It maps
subject -> role. An unknown subject gets no role at all rather than a
default one — an unrecognised account is not a REVIEWER, it is a person
the system has never heard of, and it should not be able to read anything.
"""

from __future__ import annotations

import getpass
import json
import sys
from dataclasses import dataclass
from pathlib import Path

from ..errors import AuthenticationError, ConfigError
from .roles import Permission, Role, permissions_for

_ROLE_MAP_FILENAME = "role_assignments.json"


@dataclass(frozen=True)
class Principal:
    """An authenticated actor and the role they hold."""

    #: Stable subject identifier: a Windows SID, or ``posix:<uid>:<user>``
    #: on development machines.
    subject: str
    #: Display name for audit entries. A workforce username, not a patient
    #: name, so it is safe to log.
    username: str
    role: Role

    @property
    def permissions(self) -> frozenset[Permission]:
        return permissions_for(self.role)

    def has(self, permission: Permission) -> bool:
        return permission in self.permissions


def _windows_subject() -> str:  # pragma: no cover - Windows only
    """Return the current user's SID as a string."""
    import ctypes
    from ctypes import wintypes

    advapi32 = ctypes.windll.advapi32
    kernel32 = ctypes.windll.kernel32

    TOKEN_QUERY = 0x0008
    TokenUser = 1

    token = wintypes.HANDLE()
    if not advapi32.OpenProcessToken(
        kernel32.GetCurrentProcess(), TOKEN_QUERY, ctypes.byref(token)
    ):
        raise AuthenticationError("could not open the current process token")

    try:
        size = wintypes.DWORD()
        advapi32.GetTokenInformation(token, TokenUser, None, 0, ctypes.byref(size))
        buffer = ctypes.create_string_buffer(size.value)
        if not advapi32.GetTokenInformation(
            token, TokenUser, buffer, size, ctypes.byref(size)
        ):
            raise AuthenticationError("could not read the token user")

        # TOKEN_USER starts with a SID_AND_ATTRIBUTES whose first member
        # is a PSID.
        sid = ctypes.cast(buffer, ctypes.POINTER(ctypes.c_void_p)).contents
        sid_string = ctypes.c_wchar_p()
        if not advapi32.ConvertSidToStringSidW(sid, ctypes.byref(sid_string)):
            raise AuthenticationError("could not convert the SID to a string")
        try:
            return str(sid_string.value)
        finally:
            kernel32.LocalFree(sid_string)
    finally:
        kernel32.CloseHandle(token)


def current_subject() -> tuple[str, str]:
    """Return ``(subject, username)`` for the current OS session."""
    try:
        username = getpass.getuser()
    except Exception as exc:  # pragma: no cover - environment dependent
        raise AuthenticationError("could not determine the logged-on user") from exc

    if sys.platform == "win32":  # pragma: no cover - Windows only
        return _windows_subject(), username

    import os

    return f"posix:{os.getuid()}:{username}", username


def load_role_assignments(config_dir: Path) -> dict[str, str]:
    """Load the subject -> role mapping."""
    path = config_dir / _ROLE_MAP_FILENAME
    if not path.exists():
        raise ConfigError(
            f"no role assignments at {path}. Every account must be explicitly "
            "assigned ADMIN, BILLER, or REVIEWER before it can touch PHI."
        )
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ConfigError(f"role assignments at {path} are not valid JSON: {exc}") from exc
    if not isinstance(raw, dict):
        raise ConfigError(f"role assignments at {path} must be a JSON object")
    return {str(k): str(v) for k, v in raw.items()}


def resolve_identity(config_dir: Path) -> Principal:
    """Authenticate the current OS session and resolve its role.

    Raises:
        AuthenticationError: the account has no role assignment, or the
            assigned role is not a real role.
    """
    subject, username = current_subject()
    assignments = load_role_assignments(config_dir)

    role_name = assignments.get(subject)
    if role_name is None:
        raise AuthenticationError(
            f"account {subject!r} has no role assignment. Access is denied by "
            "default: an unrecognised account is not granted a fallback role."
        )
    try:
        role = Role(role_name.strip().upper())
    except ValueError as exc:
        raise AuthenticationError(
            f"account {subject!r} is assigned unknown role {role_name!r}"
        ) from exc

    return Principal(subject=subject, username=username, role=role)
