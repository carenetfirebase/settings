# SecondaryEOB

A local Windows automation engine for dental insurance EOB (Explanation of
Benefits) document processing: ingest bulk multi-patient EOB PDFs, isolate
individual patient records, permanently remove unrelated PHI, generate
patient-specific sanitized PDFs, and support manual or automated attachment
into dental PMS systems.

**This directory lives in the `settings` repo alongside the unrelated
`invest` project (see the top-level `README.md` / `src/invest/`). The two
are independent — nothing under `src/`, `alembic/`, or `tests/` at the repo
root belongs to SecondaryEOB, and SecondaryEOB code must never import from
or depend on it.**

## Status: PLANNING — implementation blocked pending approval

Per the project's own governing document (`docs/00-master-prompt.md`,
section 15), the first action on this project is architecture and
compliance planning, not code. That planning is complete and lives in
`docs/01-architecture-and-compliance-plan.md`. **No implementation code has
been written.** The plan ends with an explicit STOP; implementation begins
only after a human reviews and approves the MVP scope and risk assessment
in that document.

## Contents

- `docs/00-master-prompt.md` — the governing master build prompt, saved
  verbatim so it can be reused to seed future sessions on this project.
- `docs/01-architecture-and-compliance-plan.md` — Architecture Summary,
  Security Model Review, Compliance Gap Report, Secure Data Flow, MVP
  Scope, and Risk Assessment (sections A–F called for by the master
  prompt).

## Core rule

**Rules first. AI second.** The system is deterministic-first; an LLM
(LM Studio) is a fallback tool only, and is never the source of truth for
financial values, patient identity resolution, claim amounts, or redaction
decisions.

## Compliance posture

This system is **HIPAA-capable, not HIPAA-compliant by default.**
Compliance depends on correct deployment: encryption at rest and in
transit, enforced access control, immutable audit logging, backup/DR,
PHI lifecycle management, breach response procedures, and — outside of
code entirely — a Business Associate Agreement where required. See the
Compliance Gap Report in the plan doc for the full control list.
