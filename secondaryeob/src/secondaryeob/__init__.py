"""SecondaryEOB — local dental EOB document-processing engine.

HIPAA-capable, not HIPAA-compliant by default. See
``docs/01-architecture-and-compliance-plan.md`` for the controls a
deployment must have in place before this touches real PHI.

Core principle: rules first, AI second. Every value this system reports
is produced by deterministic code. The LLM integration is deferred in the
MVP and, when added, may never be the source of truth for financial
values, patient identity, claim amounts, or redaction decisions.
"""

from __future__ import annotations

__version__ = "0.1.0"

__all__ = ["__version__"]
