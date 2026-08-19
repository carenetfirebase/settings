# SecondaryEOB

A local Windows automation engine for dental insurance EOB (Explanation of
Benefits) document processing: ingest bulk multi-patient EOB PDFs, isolate
individual patient records, permanently remove unrelated PHI, generate
patient-specific sanitized PDFs, and support attachment into dental PMS
systems.

**This directory lives in the `settings` repo alongside the unrelated
`invest` project (see the top-level `README.md` / `src/invest/`). The two
are independent — nothing under the repo root's `src/`, `alembic/`, or
`tests/` belongs to SecondaryEOB, and SecondaryEOB never imports from it.**

## Status: MVP implemented

The plan in `docs/01-architecture-and-compliance-plan.md` was approved and
its MVP scope (§E) is built: the deterministic pipeline end to end, with
encryption, access control, audit logging, and redaction validation in
place from the first commit rather than retrofitted.

95 tests pass. What is **not** built is listed under "Deferred" below —
those are go-live blockers, not optional extras.

## Core rule

**Rules first. AI second.** Every value this system reports is produced by
deterministic code. There is no LLM in this build at all (deferred, see
below); when one is added it may never be the source of truth for
financial values, patient identity, claim amounts, or redaction decisions.

## Compliance posture

**HIPAA-capable, not HIPAA-compliant by default.** Compliance depends on
correct deployment — and on controls this code cannot provide, including a
Business Associate Agreement, which is a legal instrument rather than a
software feature. See the Compliance Gap Report in the plan document.

## Try it

```bash
pip install -e ".[dev]"

export SECONDARYEOB_ROOT=~/seob-work
export SECONDARYEOB_PASSPHRASE='...'      # dev only; Windows uses DPAPI

secondaryeob init          # create zones, print your subject id
# add {"<subject>": "BILLER"} to config/role_assignments.json
secondaryeob whoami
secondaryeob process       # Incoming/ -> Ready/
secondaryeob verify-audit
secondaryeob status
secondaryeob purge         # retention deletion (ADMIN only)
```

Nothing runs until an account is explicitly assigned a role — an
unrecognised account gets no fallback role.

## How it is put together

```
src/secondaryeob/
  zones.py        the Zone A/B/C/D security boundary model
  config.py       env-driven settings; refuses unsafe deployments
  errors.py       fail-closed error hierarchy (FAIL = STOP)
  session.py      assembles and proves every control at startup
  cli.py          the command-line interface
  lifecycle.py    retention windows and verified deletion
  crypto/         AES-256-GCM vault; DPAPI / scrypt key wrapping
  audit/          append-only hash-chained log
  auth/           identity binding, role matrix, the access guard
  pipeline/       intake -> ... -> export, one module per stage
```

## The rules this codebase enforces

Enforced by code and tests, not by convention:

- **No plaintext PHI on disk.** Every PHI-bearing file is AES-256-GCM
  encrypted. Plaintext exists only in process memory during active
  processing; extraction runs from memory so no temp file is ever written.
- **Zone binding is cryptographic.** Each ciphertext commits to its zone
  and filename via GCM additional authenticated data, so moving a Zone A
  file into `Ready/` and reading it as sanitized output fails the tag
  check rather than succeeding quietly.
- **Access control is programmatic, not UI-level.** Every read, write, and
  delete goes through the guard, which resolves the file's zone and checks
  the required permission before any byte is touched. There is no code
  path to a PHI file that skips it.
- **Separation of duty.** ADMIN configures and purges but cannot read raw
  PHI or export. REVIEWER approves but cannot export. Only BILLER runs the
  production path.
- **The audit log is append-only and hash-chained.** Modifying, deleting,
  or reordering an entry breaks the chain, and the chain is verified at
  every startup — not by a maintenance command nobody runs. Grants are
  logged as well as denials, so "who read this file" is answerable.
- **Audit logs are PHI-free by construction.** Entries carry job IDs,
  content hashes, and pseudonyms. A key/value screen rejects the obvious
  PHI carriers as a backstop.
- **Redaction is permanent removal, not annotation.** Content streams are
  rewritten with the glyphs deleted; a test asserts that the
  draw-a-black-box approach is caught and blocked.
- **Redaction is not trusted — it is attacked.** Every output is
  adversarially re-examined by four independent techniques (text
  extraction, OCR re-scan, metadata inspection, raw object scan). Any
  recovered PHI blocks the export and raises a suspected-breach entry.
- **A technique that cannot run is a failure, not a pass.** If OCR is
  unavailable, validation is incomplete and export is blocked, because
  "we did not look" is not "we found nothing".
- **Fail closed, everywhere.** Corrupt PDFs, absent text layers,
  unrecognised layouts, and unparseable figures all halt and quarantine.
  Nothing is guessed, interpolated, or defaulted to zero.
- **Synthetic data only in tests.** Every name, member ID, and date in the
  suite is invented.

## Deferred — go-live blockers, not optional extras

These are deferred because they depend on the foundation above being
correct first, **not** because they are low-risk. None of them should be
skipped before real PHI is processed:

- **Backup and disaster recovery**, including *key escrow*. DPAPI ties the
  key to a Windows profile; lose the profile with no escrow and the PHI is
  unrecoverable. That is an availability failure, not just a
  confidentiality control.
- **Audit chain anchoring.** The chain is tamper-*evident*, not
  tamper-*proof*: an attacker with write access can rewrite the file and
  recompute every hash. Real resistance needs the head hash anchored
  somewhere they do not control (WORM storage, or periodic off-box
  publication).
- **LM Studio / LLM fallback** for payer layouts the rules do not cover.
  Highest-risk component; the Zone B boundary and the strict-JSON contract
  are specified in the plan but nothing is wired.
- **OCR for extraction** (it is currently used only to *validate*).
  Image-only pages halt today.
- **Breach response tooling** beyond halt-and-log: incident report
  templates and the escalation workflow.
- **Power Automate Desktop flow.** `Ready/` is the intended handoff point,
  with human confirmation before submission; the flow itself is not built.
- **Network UI.** Localhost-only, and a non-loopback bind is refused
  outright until TLS 1.2+ and token auth exist.

## Known limitations

- **Classification covers three anchor layouts.** Real payer EOBs vary
  more than that. An unrecognised layout is refused and quarantined rather
  than guessed — the failure is loud, but it is still a failure, and
  broader payer coverage needs real (non-PHI) sample layouts to build
  against.
- **The OCR fuzzy matcher is a tuned heuristic.** Names are compared by
  edit distance with a 0.75 threshold; structured identifiers get no error
  budget and are matched exactly after OCR-confusable canonicalization,
  because two member IDs from one payer differ in only a couple of
  characters. This split is tested in both directions, but the thresholds
  are judgement calls that should be re-reviewed against real OCR output.
- **`pseudonym` is a pseudonym, not de-identification.** It is stable and
  derived from PHI, so anyone holding it and the source document can
  correlate them. It keeps PHI out of logs and filenames; it is not a Safe
  Harbor method.
- **Deletion is not media sanitisation.** Files are unlinked and the
  residual blocks are ciphertext, which is the real protection.
  Overwrite-before-unlink is deliberately not attempted — on SSDs and
  copy-on-write filesystems it would be false assurance. End-of-life media
  handling stays an operational control (NIST SP 800-88).
- **Not exercised on Windows.** DPAPI key wrapping and SID-based identity
  are implemented but developed and tested on Linux against the scrypt
  passphrase provider. Both Windows paths need verification on a real
  workstation before deployment.
