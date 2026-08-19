"""PyInstaller entry point.

A console_scripts entry point is generated at install time and so does not
exist in a frozen build. This module gives PyInstaller a real file to
analyse and freeze.
"""

from __future__ import annotations

import sys

from secondaryeob.cli import main

if __name__ == "__main__":
    sys.exit(main())
