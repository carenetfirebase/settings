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

    # argtypes/restype are declared for every call: ctypes otherwise
    # assumes a C ``int`` return, which truncates 64-bit handles and
    # pointers on win64. use_last_error keeps the failure code accurate.
    advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    TOKEN_QUERY = 0x0008
    TokenUser = 1
    ERROR_INSUFFICIENT_BUFFER = 122

    kernel32.GetCurrentProcess.restype = wintypes.HANDLE
    kernel32.GetCurrentProcess.argtypes = []
    kernel32.CloseHandle.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.LocalFree.restype = ctypes.c_void_p
    kernel32.LocalFree.argtypes = [ctypes.c_void_p]

    advapi32.OpenProcessToken.restype = wintypes.BOOL
    advapi32.OpenProcessToken.argtypes = [
        wintypes.HANDLE,
        wintypes.DWORD,
        ctypes.POINTER(wintypes.HANDLE),
    ]
    advapi32.GetTokenInformation.restype = wintypes.BOOL
    advapi32.GetTokenInformation.argtypes = [
        wintypes.HANDLE,
        ctypes.c_int,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(wintypes.DWORD),
    ]
    advapi32.ConvertSidToStringSidW.restype = wintypes.BOOL
    advapi32.ConvertSidToStringSidW.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(wintypes.LPWSTR),
    ]

    def _fail(what: str) -> AuthenticationError:
        error = ctypes.get_last_error()
        return AuthenticationError(
            f"{what}: {ctypes.FormatError(error)} (win32 error {error})"
        )

    token = wintypes.HANDLE()
    if not advapi32.OpenProcessToken(
        kernel32.GetCurrentProcess(), TOKEN_QUERY, ctypes.byref(token)
    ):
        raise _fail("could not open the current process token")

    try:
        # First call sizes the buffer and is expected to fail with
        # ERROR_INSUFFICIENT_BUFFER; any other failure is real.
        size = wintypes.DWORD()
        advapi32.GetTokenInformation(token, TokenUser, None, 0, ctypes.byref(size))
        error = ctypes.get_last_error()
        if error != ERROR_INSUFFICIENT_BUFFER:
            raise _fail("could not size the token information buffer")

        buffer = ctypes.create_string_buffer(size.value)
        if not advapi32.GetTokenInformation(
            token, TokenUser, buffer, size.value, ctypes.byref(size)
        ):
            raise _fail("could not read the token user")

        # TOKEN_USER begins with a SID_AND_ATTRIBUTES whose first member
        # is the PSID, so the first pointer-sized field is the SID.
        sid = ctypes.cast(buffer, ctypes.POINTER(ctypes.c_void_p)).contents
        sid_string = wintypes.LPWSTR()
        if not advapi32.ConvertSidToStringSidW(sid, ctypes.byref(sid_string)):
            raise _fail("could not convert the SID to a string")
        try:
            value = sid_string.value
            if not value:
                raise AuthenticationError("the SID converted to an empty string")
            return str(value)
        finally:
            kernel32.LocalFree(ctypes.cast(sid_string, ctypes.c_void_p))
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
