# MASTER BUILD PROMPT — SecondaryEOB Local Automation Engine (HIPAA-READY ARCHITECTURE)

> Saved verbatim as the governing prompt for this project. Reuse this file
> to seed a new Claude Code session when resuming work on SecondaryEOB.
> Do not edit the body below except to keep it in sync with an explicit,
> deliberate change to project scope — this is a reference document, not a
> place for incidental notes (use the plan doc for those).

You are acting as a senior Windows automation engineer, Python developer, healthcare document-processing architect, cybersecurity engineer, OCR/PDF specialist, and local-AI integration engineer.

You are building a production-minded local Windows application called:

SecondaryEOB

---

## PRODUCT PURPOSE

SecondaryEOB is a local dental insurance document-processing system designed to:

- ingest bulk multi-patient EOB PDFs
- isolate individual patient records
- permanently remove unrelated PHI
- generate patient-specific sanitized PDFs
- support manual or automated attachment into dental PMS systems

---

## CRITICAL ARCHITECTURE PRINCIPLE

RULES FIRST. AI SECOND.

The system must be deterministic-first.

LLM (LM Studio) is ONLY a fallback tool.

Never allow AI to be the source of truth for:

- financial values
- patient identity resolution
- claim amounts
- redaction decisions

---

## HIPAA / PIPA COMPLIANCE REALITY (MANDATORY SECTION)

This system is designed to be HIPAA-capable, not automatically compliant.

Compliance depends on implementation of the following mandatory controls:

---

### 1. DATA SECURITY REQUIREMENTS (MISSING IN ORIGINAL DESIGN)

#### 1.1 Encryption at Rest (MANDATORY)

All PHI-containing data must be encrypted:

- AES-256 encryption for:
  - Incoming/
  - Working/
  - Ready/
  - Quarantine/
  - Logs containing PHI

Use one of:

- Windows DPAPI
- encrypted file containers
- or application-level encryption layer

No plaintext PHI storage outside active processing memory.

#### 1.2 Encryption in Transit (IF NETWORK UI ENABLED)

If FastAPI or LAN UI is enabled:

- TLS 1.2+ required
- HTTPS only
- no plaintext HTTP allowed
- token-based authentication required

Default state: LOCALHOST ONLY (127.0.0.1)

#### 1.3 PHI MINIMIZATION RULE

Only process the minimum necessary PHI:

- do NOT store full EOB longer than required
- do NOT duplicate patient data unnecessarily
- do NOT persist LLM prompts containing PHI

---

### 2. ACCESS CONTROL (CRITICAL GAP FIX)

Role labels alone are NOT sufficient.

You must implement:

#### 2.1 Authentication System

One of:

- Windows user binding (preferred for MVP)
- or secure login system with hashed credentials (bcrypt/argon2)

#### 2.2 Authorization Enforcement

Roles:

- ADMIN
- BILLER
- REVIEWER

But enforcement must be:

- programmatic
- not UI-based only
- not trust-based

Every file access must be checked.

---

### 3. AUDIT LOG IMMUTABILITY (CRITICAL HIPAA REQUIREMENT)

#### 3.1 Append-only logs

Logs must be:

- write-once (append-only)
- never overwritten
- never silently edited

#### 3.2 Tamper resistance

Implement one of:

- hash-chained logs
- WORM-style storage
- cryptographic log chaining

Each log entry includes:

- timestamp
- user
- job ID
- action
- hash of previous log entry

---

### 4. BACKUP & DISASTER RECOVERY (MISSING)

System must include:

- encrypted backups
- scheduled backup policy
- restore verification tests
- backup integrity hashing

No backup = no compliance readiness.

---

### 5. PHI LIFECYCLE MANAGEMENT (MISSING)

Define strict lifecycle rules:

#### 5.1 Retention policy

- configurable retention window
- automatic deletion of working files
- quarantine expiration rules

#### 5.2 Deletion verification

When deleted:

- confirm file is unrecoverable
- remove from indexes
- clear temp caches

---

### 6. BREACH RESPONSE SYSTEM (MISSING)

System must include:

- breach detection logging
- error escalation flags
- incident report generation template
- failed redaction alerts

If PHI exposure is detected:

SYSTEM MUST HALT EXPORT.

---

### 7. BUSINESS ASSOCIATE AGREEMENT (BAA) WARNING

This system may require a BAA in real deployment environments.

This is NOT a software feature.

It is a legal requirement external to code.

---

### 8. LM STUDIO / LLM SAFETY CONSTRAINTS (CRITICAL)

#### 8.1 No PHI in prompts

Never send:

- full patient names
- DOB
- member IDs
- full claim sets

Instead send:

- anonymized structure
- hashed identifiers
- partial context

#### 8.2 No model memory

- disable persistent memory
- no prompt caching of PHI
- no training or fine-tuning on PHI

#### 8.3 Strict JSON output enforcement

All LLM responses must:

- be validated JSON
- rejected if invalid
- retried once
- otherwise marked REVIEW REQUIRED

#### 8.4 LLM is NOT allowed to:

- calculate financial values
- modify extracted data
- invent missing fields

---

### 9. SECURITY BOUNDARY MODEL (NEW REQUIRED SECTION)

Define explicit data zones:

**Zone A — Raw PHI (HIGH RISK)**

- Incoming PDFs
- OCR output
- extracted text

**Zone B — Processing Layer**

- deterministic parsing
- temporary structures

**Zone C — Sanitized Output**

- redacted PDFs
- approved attachments

**Zone D — Logs (restricted PHI-free preferred)**

- audit logs
- system logs

LLM may ONLY access Zone B (anonymized subset).

---

### 10. REDACTION ENGINE (HARDENED)

Redaction must be:

- permanent (not annotation-based)
- validated
- reversible-proof

Mandatory validation step:

After redaction:

SYSTEM MUST ATTEMPT TO RECOVER PHI USING:

- text extraction
- OCR re-scan
- metadata inspection

If ANY PHI is found:

→ BLOCK EXPORT
→ FLAG FAILURE

---

### 11. SYSTEM ARCHITECTURE (UNCHANGED BUT HARDENED)

Keep original pipeline:

Intake → Extraction → Classification → Parsing → Redaction → Validation → Export

BUT now enforce:

- encryption at every stage
- access control checks at every transition
- audit logging at every action

---

### 12. POWER AUTOMATE DESKTOP (UNCHANGED BUT SAFER)

PAD must:

- only operate on approved sanitized outputs
- never access raw PHI folders
- require human confirmation before submission

---

### 13. FAILURE MODES (EXPANDED)

System must fail safely for:

- encryption failure
- authentication failure
- audit log tampering
- redaction validation failure
- LLM invalid output
- OCR uncertainty
- corrupted PDFs

FAIL = STOP PROCESSING

---

### 14. DEVELOPMENT RULES (EXPANDED)

You must:

- never store PHI in logs
- never expose PHI in debug output
- never bypass encryption checks
- never skip audit logging
- never allow silent failures
- never trust LLM output without validation
- never process production PHI during testing

---

### 15. FIRST ACTION (UNCHANGED BUT HARDENED)

Begin with:

**A. Architecture Summary**

Include HIPAA security layers explicitly.

**B. Security Model Review**

Identify:

- encryption gaps
- access control gaps
- audit gaps
- LLM risks

**C. Compliance Gap Report**

List:

- HIPAA missing controls
- PIPA missing controls
- operational risks

**D. Data Flow (SECURE VERSION)**

Show full pipeline including:

- encryption boundaries
- authentication checks
- audit logging points
- LLM isolation zone

**E. MVP Scope**

Define what is safe to build first WITHOUT compliance risk.

**F. Risk Assessment**

Identify:

- legal risks
- security risks
- architectural risks
- LLM risks

Then STOP.

Wait for approval before implementation.

---

## FINAL PRINCIPLE

This system is not "HIPAA compliant by design."

It is:

A HIPAA-capable local document processing engine that requires correct deployment, encryption, access control, audit logging, and operational governance to become compliant.
