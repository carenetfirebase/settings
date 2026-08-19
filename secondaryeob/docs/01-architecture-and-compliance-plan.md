# SecondaryEOB — Architecture & Compliance Plan

Produced per section 15 ("FIRST ACTION") of `00-master-prompt.md`. This is
a planning document, not implementation. **No code has been written for
SecondaryEOB.** Per the master prompt, this document ends with a STOP —
implementation begins only after a human approves the MVP scope (§E) and
has read the risk assessment (§F).

---

## A. Architecture Summary

SecondaryEOB is a local-only Windows application. It has no required
network dependency; the optional local API and the optional local LLM
(LM Studio) both default to loopback-only. The system is organized as a
strictly one-directional pipeline with a security control gating every
stage transition:

```
Intake -> Extraction -> Classification -> Parsing -> Redaction -> Validation -> Export
```

Layered on top of that pipeline, four cross-cutting HIPAA security layers
apply uniformly at every stage rather than being bolted on at the edges:

1. **Encryption layer** — every folder that can hold PHI
   (`Incoming/`, `Working/`, `Ready/`, `Quarantine/`, PHI-bearing logs) is
   encrypted at rest. Nothing PHI-bearing is ever written to disk in
   plaintext; plaintext exists only transiently in process memory during
   active processing of one document.
2. **Access control layer** — every file-system access and every pipeline
   stage transition is preceded by a programmatic authorization check
   against the caller's authenticated identity and role. There is no code
   path that touches a PHI-bearing file without going through this check.
3. **Audit layer** — every action that touches PHI (open, parse, redact,
   validate, export, delete) appends one hash-chained, tamper-evident log
   entry. Logs are write-once; nothing in the system has permission to
   modify or delete a prior entry.
4. **LLM isolation layer** — the optional LM Studio integration is
   confined to Zone B (see §D) and only ever receives anonymized,
   structural, or hashed input. It has no read path to raw PHI (Zone A)
   and no write path to redaction decisions, financial values, or patient
   identity resolution — those remain deterministic, rule-based, and
   independently auditable.

The architecture principle governing all of this: **rules first, AI
second.** The deterministic rule engine is the sole source of truth for
identity resolution, claim amounts, and redaction decisions. The LLM,
when enabled, is a fallback classifier/extractor whose output is treated
as untrusted until validated against deterministic checks, and which is
never in a position to cause a compliance failure on its own — because it
cannot reach Zone A or Zone C directly.

---

## B. Security Model Review

Gaps identified in an unhardened version of this design, and the control
that closes each one in this plan:

| Gap | Risk if unaddressed | Closing control |
|---|---|---|
| **Encryption** | PHI readable by anyone with filesystem access (malware, other local users, stolen/imaged disk, unencrypted backup) | AES-256 at rest on every PHI-bearing folder and PHI-bearing log; no plaintext PHI outside active process memory (§1 of master prompt) |
| **Access control** | Role labels shown in UI but not enforced — any process/user with filesystem access bypasses "roles" entirely | Authenticated identity (Windows user binding or hashed-credential login) + programmatic authorization check on every file access, not just UI gating (§2) |
| **Audit** | Logs editable or deletable — no way to prove what happened after an incident, no HIPAA-defensible record | Append-only, hash-chained log entries; tampering is detectable because it breaks the hash chain, not just discouraged (§3) |
| **LLM risk** | PHI leaked into local LLM memory/cache/logs; LLM output silently trusted for financial or identity decisions; malformed output causes bad redaction | Zone-confined LLM access (Zone B only, anonymized), disabled model memory, strict JSON validation with one retry then REVIEW REQUIRED, and a hard rule that LLM output is never authoritative for money, identity, or redaction (§8) |

Additional gaps closed by this plan that weren't yet named above:

- **No backup/DR story** → §4: encrypted, integrity-hashed, scheduled
  backups with restore verification tests. Without this, a single disk
  failure is a data-loss incident, and an unverified backup is not a
  compliance control, just a hope.
- **No PHI lifecycle bound** → §5: configurable retention window,
  automatic deletion of working files, quarantine expiration, and
  deletion *verification* (not just an unlink call).
- **No breach response path** → §6: breach detection logging, escalation
  flags, an incident report template, and a hard rule that suspected PHI
  exposure halts export rather than logging-and-continuing.
- **Redaction assumed permanent without proof** → §10: redaction is
  validated by attempting to *recover* the redacted PHI (text extraction,
  OCR re-scan, metadata inspection) before export is allowed to proceed.
  Annotation-based "redaction" (a black box drawn over visible text, with
  the text still present underneath) is explicitly disallowed by this
  check, since it would fail the recovery attempt.

---

## C. Compliance Gap Report

### HIPAA — missing controls if this plan is not implemented in full

- **Security Rule §164.312(a)(2)(iv) / (e)(2)(ii)** — encryption at rest
  and in transit. Gap: none by default in an MVP that just moves files
  around. Closed by §1.
- **Security Rule §164.312(a)(1) / (d)** — access control and person/entity
  authentication. Gap: a "role" that's just a UI dropdown. Closed by §2.
- **Security Rule §164.312(b)** — audit controls. Gap: a plain log file
  that can be edited or deleted after the fact, which is not an audit
  control, it's a suggestion. Closed by §3.
- **Security Rule §164.308(a)(7)** — contingency plan (backup, disaster
  recovery, emergency mode). Gap: none by default. Closed by §4.
- **Privacy Rule "minimum necessary" standard** — Gap: no enforced bound
  on how long PHI is retained or how many copies exist. Closed by §5 and
  the PHI minimization rule in §1.3.
- **Security Rule §164.308(a)(6)** — security incident procedures. Gap:
  no defined breach detection or response process. Closed by §6.
- **45 CFR §164.502(e) / §164.308(b)(1)** — Business Associate Agreements.
  Gap: this is a legal instrument, not something code can satisfy. Flagged
  explicitly in §7 as an operational/legal requirement outside the
  software's control — **a deployer who connects this system to PHI on
  behalf of another covered entity without a BAA in place is not
  compliant no matter how the software is configured.**

### PIPA — missing controls if this plan is not implemented in full

(PIPA — provincial private-sector privacy legislation, e.g. Alberta's or
BC's *Personal Information Protection Act* — imposes obligations that
overlap HIPAA's but are broader in scope: they cover personal information
generally, not only PHI, and have their own breach-notification triggers.)

- **Reasonable security safeguards requirement** — closed by §1/§2 to the
  same standard as HIPAA's Security Rule.
- **Retention limitation** — PIPA generally requires personal information
  be retained no longer than necessary for the purpose it was collected
  for. Closed by §5's configurable retention window, but the *actual*
  retention window value is a policy decision the deployer must set
  correctly — the software provides the mechanism, not the number.
- **Breach notification duty** — PIPA (e.g., Alberta) has a mandatory
  notification-to-regulator duty for breaches posing real risk of
  significant harm, on a timeline the software cannot know about. §6
  provides the detection and incident-report generation; the deployer is
  responsible for actually notifying the regulator/affected individuals
  within the applicable jurisdiction's deadline.
- **Openness / accountability** — PIPA expects an identifiable person
  accountable for compliance and a documented policy. This is
  organizational, not code — flagged as an operational risk in §F.

### Operational risks (neither HIPAA nor PIPA controls, but block real-world compliance)

- No BAA workflow tracking — the software has no concept of "is a BAA in
  place for this deployment," and shouldn't invent one; that's a legal
  process the deployer runs outside the app.
- No defined data-retention *policy value* — the software will enforce
  whatever window is configured, including a misconfigured one (e.g. "0"
  or "forever"). Wrong configuration is a compliance failure the software
  cannot detect on its own.
- No workforce training / sanction policy tracking — HIPAA requires
  workforce training and sanctions for violations; this is entirely
  outside software scope.
- Single-workstation deployment assumption — if PHI ever needs to leave
  the local machine (e.g., syncing `Incoming/` via a cloud-synced folder
  like OneDrive/Dropbox without BAA-covered, encrypted-in-transit
  handling), every control in this plan is bypassed by that external
  channel. The plan cannot enforce controls on tools outside its process
  boundary — this must be a deployment/IT policy constraint.

---

## D. Data Flow (Secure Version)

```
                    ┌─────────────────────────────────────────────────────┐
                    │  AUTH: identity + role resolved once per session    │
                    │  (Windows user binding, or hashed-credential login) │
                    └─────────────────────────────────────────────────────┘
                                          │
                                          ▼
 ┌───────────────┐   AuthZ check   ┌───────────────┐  AuthZ check  ┌────────────────┐
 │   INTAKE       │ ──────────────▶│  EXTRACTION    │──────────────▶│ CLASSIFICATION │
 │ Zone A (raw    │  Audit: OPEN   │ Zone A (OCR /  │  Audit: EXTR  │ Zone A→B bridge│
 │ PHI, encrypted │                │ text extract)  │               │ (deterministic │
 │ at rest)       │                │                │               │ rules first)   │
 └───────────────┘                └───────────────┘               └────────┬───────┘
                                                                             │
                                             AuthZ check                    │ optional,
                                                                             │ anonymized-
                                                                             │ only fallback
                                                                             ▼
                                                                   ┌───────────────────┐
                                                                   │ LLM ISOLATION ZONE │
                                                                   │ Zone B only.       │
                                                                   │ Anonymized/hashed  │
                                                                   │ input. No memory,  │
                                                                   │ no PHI prompts.    │
                                                                   │ Strict JSON only,  │
                                                                   │ retry-once, else   │
                                                                   │ REVIEW REQUIRED.   │
                                                                   │ Never authoritative│
                                                                   │ for $ / identity / │
                                                                   │ redaction.         │
                                                                   └─────────┬─────────┘
                                                                             │
                                          AuthZ check                       ▼
 ┌───────────────┐                ┌───────────────┐                ┌────────────────┐
 │   PARSING      │◀───────────────│ (rule engine reconciles LLM  │ if used, else    │
 │ Zone B         │                │ fallback output — LLM output │ direct from      │
 │ (deterministic │                │ never overrides deterministic│ Classification)  │
 │ structures)    │                │ parse without validation)    │                  │
 └───────┬───────┘                └───────────────────────────────┴──────────────────┘
         │  AuthZ check
         ▼
 ┌───────────────┐   Validation:   ┌───────────────┐
 │  REDACTION     │  attempt PHI   │  VALIDATION    │
 │ Zone A→C       │  recovery via  │ Recovery check │
 │ permanent,     │  text extract, │ found PHI?     │
 │ non-annotation │─────────────▶ │ OCR re-scan,    │
 │ removal        │                │ metadata scan  │
 └───────────────┘                └───────┬────────┘
                                           │
                              PHI found ───┼─── no PHI found
                                 │                    │
                                 ▼                    ▼
                       ┌──────────────────┐  ┌────────────────┐   AuthZ check   ┌──────────┐
                       │ BLOCK EXPORT     │  │  Zone C:        │────────────────▶│  EXPORT  │
                       │ FLAG FAILURE     │  │  sanitized,     │  Audit: EXPORT   │ Ready/   │
                       │ Audit: FAILURE   │  │  approved       │                  │ (PAD may │
                       │ (halt, no export)│  │  output         │                  │ read only│
                       └──────────────────┘  └─────────────────┘                  │ this)    │
                                                                                    └──────────┘

 Zone D (audit / system logs, PHI-free where possible) receives one hash-
 chained entry at every AuthZ check and every stage transition shown
 above — Intake open, extraction run, classification result, LLM call
 (metadata only: model, timestamp, success/fail — never the prompt
 content if it could carry PHI), parse result, redaction action,
 validation result, export, and any failure/halt. Encryption applies to
 every zone-A/B/C store; Zone D is kept PHI-free by construction wherever
 possible (job IDs and hashes instead of names/DOBs), and encrypted
 anyway since job/file correlation is still sensitive metadata.
```

Key properties this diagram is asserting, not just illustrating:

- The LLM is *architecturally* unable to see Zone A (raw PHI) or write to
  Zone C (sanitized output) — it sits in a side-branch off Classification
  that only ever receives Zone B (already-anonymized) data and returns a
  fallback suggestion the rule engine may accept or discard.
- Redaction is followed by a mandatory adversarial validation step
  (attempt to recover what was just redacted) before Zone C is considered
  real. Failing that check halts the pipeline rather than exporting.
- Every arrow crossing a stage boundary is gated by an authorization
  check and produces an audit entry — these aren't drawn as a separate
  "layer" on top because they are not optional middleware, they're part
  of what makes an arrow valid to traverse.

---

## E. MVP Scope

**Goal: build the smallest system that demonstrates the full pipeline and
the full control set end-to-end, on synthetic (non-production) data, with
no compliance shortcuts taken and nothing deferred that would be unsafe to
defer.**

### In scope for MVP

1. **Deterministic pipeline, no LLM.** Intake → Extraction (text-layer PDF
   only, no OCR yet) → Classification (rule-based patient boundary
   detection within a multi-patient PDF) → Parsing → Redaction →
   Validation (recovery-attempt check) → Export. LM Studio integration is
   explicitly deferred — it is the highest-risk component (§8/§9) and
   provides no value until the deterministic path is proven correct and
   auditable on its own.
2. **Encryption at rest**, applied from day one to every working folder —
   this is not something to "add later," since anything built without it
   would need every subsequent PHI-touching feature re-audited once it's
   retrofitted. Windows DPAPI is the MVP mechanism (simplest correct
   option for a single-workstation deployment; an application-level
   layer can be layered in later if multi-machine deployment is ever
   needed).
3. **Single-user Windows-binding authentication** (the "preferred for
   MVP" option in §2.1) with a fixed ADMIN/BILLER/REVIEWER role stored
   locally and checked programmatically at every file access — not a
   config file with three named accounts, but not a full login/IdP
   system either, since that's disproportionate for a single-workstation
   MVP.
4. **Append-only, hash-chained audit log** from the first commit. Like
   encryption, this can't be bolted on later without leaving a gap in the
   record for everything built before it existed.
5. **Non-annotation redaction with recovery-attempt validation** (§10),
   including the "block export on any recovered PHI" rule. This is the
   feature the entire product exists to deliver correctly, so it is not
   something the MVP can approximate.
6. **Manual PAD handoff only.** Power Automate Desktop reads only from the
   `Ready/` (Zone C) folder and requires human confirmation before
   submission (§12) — no automated PMS write path in the MVP.
7. **Basic retention timer** (§5.1) with a conservative default (e.g.
   auto-purge `Working/` after a short, configurable window) — simple to
   build, and required so the MVP doesn't accumulate PHI indefinitely
   during development.
8. **Synthetic/fixture data only during development and testing** — per
   §14, no production PHI is processed until the MVP has passed its own
   security review (§B above, re-run against the actual implementation).

### Explicitly deferred (not because they're optional long-term — because
building them before the above is solid would mean building on an
unverified foundation)

- LM Studio / LLM fallback path (§8, §9) — highest LLM-specific risk
  surface (PHI-in-prompt leakage, memory/caching, unvalidated output);
  deferred until the deterministic path has an audited track record.
- OCR for scanned (non-text-layer) PDFs — OCR uncertainty is itself a
  named failure mode (§13); text-layer PDFs alone are enough to prove the
  pipeline.
- Backup/DR automation (§4) — needed before any production data is
  processed, but not before the pipeline mechanics are proven on
  synthetic data; sequenced right after MVP validation, before go-live.
- Breach response tooling beyond basic detection logging (§6) — the halt-
  on-detection behavior is in scope now; the incident-report-template and
  escalation workflow can follow once there's a real system to generate
  incidents about.
- Network/LAN UI (§1.2) — MVP is localhost-only by default and stays that
  way until there's an explicit, reviewed reason to expose it.
- Multi-machine / multi-user deployment — MVP is single-workstation.

### Definition of "safe to build first without compliance risk"

The MVP is safe specifically because every item in it either (a) has no
PHI-handling risk (it's pipeline mechanics on synthetic data) or (b) is
one of the controls that gets *harder*, not easier, to add correctly
after the fact (encryption, access control, audit logging, redaction
validation). Nothing in the deferred list is deferred because it's low-
risk — it's deferred because it depends on the in-scope foundation being
correct first.

---

## F. Risk Assessment

### Legal risks

- **Operating without a BAA** where one is legally required (e.g. the
  software processes PHI on behalf of a dental practice that is itself a
  covered entity, and the operator of this software is a business
  associate). Severity: high. Mitigation: software cannot resolve this;
  flagged prominently (§7) as a pre-deployment legal step, not a
  configuration option.
- **PIPA breach-notification deadlines missed** because the software
  detects a breach (§6) but the deployer has no defined process to act on
  the incident report within the jurisdiction's mandatory window.
  Severity: high, jurisdiction-dependent. Mitigation: incident report
  generation is in scope; the notification workflow itself is explicitly
  an operational responsibility, not a software feature, and should be
  documented as such to whoever deploys this.
- **Misconfigured retention policy** treated as compliant because "the
  software has a retention feature," when the configured window itself
  violates minimum-necessary/retention-limitation principles. Severity:
  medium. Mitigation: ship a conservative default, document the
  requirement clearly, but this remains a deployer decision the software
  can't fully guard against.

### Security risks

- **Single point of failure: the encryption key.** If DPAPI-protected
  keys are tied to a Windows user profile and that profile/machine is
  lost without a documented recovery process, PHI becomes permanently
  unrecoverable — which is a availability risk, not just a confidentiality
  one. Mitigation: backup/DR (§4) must include key recovery, not just
  data recovery, and this needs explicit design before go-live even
  though it's sequenced after the MVP.
- **Local malware / insider access on the workstation.** Encryption at
  rest protects against a stolen disk or misdirected backup, but not
  against a compromised, already-unlocked session on the same machine the
  authorized user is using. Mitigation: this is a workstation-hardening
  and endpoint-security concern outside the application's boundary;
  should be named explicitly as a deployment prerequisite (patched OS,
  endpoint protection, no shared logins).
- **Sync tools bypassing the pipeline's folder controls.** If `Incoming/`,
  `Working/`, `Ready/`, or `Quarantine/` are inside a cloud-synced
  directory (OneDrive, Dropbox, etc.) without that sync path itself being
  BAA-covered and encrypted in transit, PHI leaves the controlled
  boundary regardless of what the application does. Mitigation:
  deployment documentation must explicitly forbid this, and ideally the
  application should refuse to run against a working directory it detects
  as being inside a known sync-client folder.
- **Audit log hash-chain break going unnoticed.** A tamper-evident log is
  only useful if something actually checks the chain. Mitigation: chain
  verification needs to be an active, scheduled check (or at minimum a
  check run at every application startup), not just a property that
  exists passively.

### Architectural risks

- **Deterministic parser brittleness across EOB layout variation.**
  Dental EOBs come from many payers with different layouts; a rule-based
  parser tuned to known layouts will misparse or fail closed on unseen
  ones. This is the reason an LLM fallback exists at all in the full
  design — but per the core principle, a parse failure must surface as
  REVIEW REQUIRED, never as a silent best-guess. Mitigation: the MVP's
  scope (deterministic-only, no LLM yet) makes this risk visible early,
  which is preferable to it being masked by an LLM fallback quietly
  papering over parser gaps.
- **Redaction-validation false negatives.** The recovery-attempt check
  (§10) is only as good as the extraction/OCR/metadata techniques it
  uses; a technique that could recover PHI but isn't implemented in the
  validator is a gap the validator can't see. Mitigation: treat the
  validator's technique list as a living, adversarially-reviewed set, not
  a one-time implementation.
- **PAD as an unmonitored side channel.** Power Automate Desktop is
  external automation tooling outside this codebase's direct control;
  even with the "reads only from `Ready/`, human-confirmed" rule (§12),
  enforcement of that rule lives in the PAD flow definition itself, which
  this plan can specify but not runtime-enforce from inside the Python
  application. Mitigation: treat the PAD flow as part of the audited
  system, reviewed alongside code changes, not as an external black box.

### LLM risks

- **PHI leakage into prompts despite anonymization intent.** "Anonymized
  structure" is easy to say and easy to get subtly wrong (e.g. a claim
  amount + procedure code + date combination that's re-identifying even
  without a name). Mitigation: define and test the anonymization
  transform itself as a security-reviewed component, not an assumed
  property of "we didn't send the name field."
- **Silent trust creep.** Even with "LLM output is never authoritative"
  as a stated rule, review cost pressure over time is a known failure
  mode where a REVIEW REQUIRED path quietly becomes a rubber-stamp.
  Mitigation: this is a process risk more than a code risk — worth
  naming now so it's something the deployer watches for, not something
  the software alone can prevent.
- **Local model updates changing behavior unexpectedly.** Since LM Studio
  is local and swappable, a model update/swap could change JSON-
  compliance rates or subtly change extraction behavior without a
  corresponding code change. Mitigation: pin and version the model used
  in production, and re-validate the strict-JSON/retry-once/REVIEW-
  REQUIRED behavior (§8.3) whenever the model changes.

---

## STOP

This completes sections A–F. Per the master prompt (§15), implementation
does not begin until this plan — specifically the MVP scope (§E) and the
risk assessment (§F) — has been reviewed and approved.
