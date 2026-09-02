# referral_core

The domain core for Quick Referral: models, specialty templates, tooth
notation, dental vocabulary, structured extraction, the identifier guardrail,
referral codes and ambiguity detection.

Pure Dart. No Flutter, no platform channels, no I/O, no packages beyond the
test tooling. That is deliberate — it keeps the logic testable in milliseconds
without a device or emulator, and it lets any surface reuse the same engine.

```
dart pub get
dart analyze
dart test
```

## Where it sits

```
carenetapp/
  packages/referral_core/   <- this package
  lib/features/quick_referral/
      data/          Firestore + encrypted local store + outbox
      application/   controllers, in the app's existing state solution
      presentation/  capture, confirm, inbox, detail, settings
```

The app depends on it with a path dependency:

```yaml
dependencies:
  referral_core:
    path: packages/referral_core
```

## What is not stored

There is no patient identity anywhere in this package: no name, date of birth,
contact detail, chart number, appointment reference, image or free-text note.
`ReferralDraft.forbiddenKeyFragments` lists the key fragments that must never
appear in a serialised draft, and a test in `test/privacy_test.dart` fails the
build if one does.

Excluding those fields does **not** make the data non-identifiable. A
timestamp, an operatory and a diagnosis may still be re-identifiable against a
clinic's own schedule. Nothing here should be read as a claim about which
regulations do or do not apply.

Transcripts and audio never reach this package's outputs. `extract` takes a
transient string and returns structured fields; `ParsedReferralResult` holds no
transcript, and `unrecognisedSegments` is for display only and is never written
to a draft.

## How to add a specialty

Add a `ReferralTemplate` to `ReferralTemplates.all` in
`lib/src/templates/templates.dart`, and a value to the `Specialty` enum with a
stable `wire` string. Nothing else needs to change — extraction, required-field
checking, the handoff formatter and the inbox summary all read the registry.

## How to add a reason, finding or symptom

Add a `ClinicalConcept` to the relevant list on the template. The `id` is what
is stored, the `display` is what people read, and `synonyms` are the spoken
forms that map onto it.

Two rules the test suite enforces:

- Synonyms must be lower case with no punctuation. Matching runs on normalised
  text, so a hyphen or a capital makes a phrase permanently unreachable —
  `test/templates_test.dart` fails on one.
- Concept ids must be unique within a template.

Longer phrases win over shorter ones, so `impacted third molars` claims the
text before `impacted` can.

## How tooth numbering works

FDI, Universal and Palmer are all supported, and the professional's configured
notation is the only one used to validate what they said. FDI is the internal
canonical form because it is unambiguous in two characters — it is a key, never
a display value.

Nothing is translated across notations silently. When a code is not a tooth in
the professional's own system but is one in another, `ToothInterpretation`
reports it as a cross-notation candidate and the extractor raises a
clarification instead of rewriting it.

This matters more than it looks. `36` is invalid in Universal, so it is
catchable. **`18` is valid in both** — an upper-right third molar in FDI, a
lower-left second molar in Universal. Different tooth, different arch, no error
to detect.

Change the setting via `ProfessionalReferralPreferences.toothNotation`.

## How referral codes work

Five characters of Crockford base32 (`0-9A-Z` without `I`, `L`, `O`, `U`),
drawn from `Random.secure()`. The code encodes nothing — not the professional,
the clinical content, the time, or a counter.

The alphabet is chosen for transcription, because the code's job is to be read
off a screen and typed into the clinic's own system. `ReferralCode.normalise`
decodes forgivingly: `RO K4P`, `R0-k4p` and `r0k4p` all resolve to `R0K4P`.

`generateUnique` takes a "is this taken" predicate and regenerates on
collision, widening the code rather than looping forever if the namespace is
somehow saturated.

## How timestamps work

Instants are stored in UTC. `ProfessionalReferralPreferences.timezone` holds
the IANA zone name for display.

This package carries no timezone database, so rendering takes an explicit
offset: `ReferralTime.formatStamp(draft.createdAt, offset)`. The app layer,
which has a real zone implementation, supplies the offset in effect for that
instant. That keeps daylight-saving correctness where it belongs and keeps the
dependency out of the core.

## How attribution works

The application never learns which patient a referral belongs to. Staff resolve
that from their own schedule, using the code and the timestamp.

A timestamp alone is not enough in a practice running several chairs, so
drafts carry an optional `operatory` — a room number, which is clinic
infrastructure and not a patient identifier. It is the difference between three
candidate patients at 10:42 and one.

`AmbiguityDetector` covers what is left: when two drafts fall within a window
with nothing to tell them apart, both are flagged so the inbox can warn rather
than present a draft that cannot honestly be matched. Different rooms resolve a
collision; a missing room on either side does not.

## How duplicates are prevented

`DraftFactory` generates the UUID before the first write, so the draft is
always written at a known id. A double tap, a network retry and an offline
replay are all the same `set`. No server-side dedupe is required.

## How to configure default specialists

Store `ReferralDestination` records per professional and specialty, one flagged
`isDefault`. When the professional says "usual" or "default",
`useDefaultDestination` is set and `DestinationResolver.defaultFor` picks the
flagged destination, falling back to the only active one for that specialty. It
never borrows a destination from a different specialty.

## How to configure retention

`ProfessionalReferralPreferences.draftRetentionDays` (default 90) sets
`expiresAt` at capture. Sweeping is the app's job: locally at start-up, and
server-side on a schedule.

**This is a default, not a legal position.** Production retention policy is a
decision for the practice and belongs in configuration, not in this package.

## Analytics

`ReferralAnalyticsEvent` is the complete event vocabulary — there is no
free-form event name. `ReferralAnalyticsParams.sanitise` strips every key
outside a fixed allow list, so specialty, tooth, findings, urgency, referral
codes and transcripts cannot reach an analytics provider even if a caller
passes them.

## Authorisation

`ReferralDraftRepository` scopes every method by `professionalId`.
Implementations must enforce that at the datastore, not in the signature and
not in the UI. With Firestore, nest under the account's uid so a forgotten
`where` clause cannot return another professional's drafts:

```
/professionals/{uid}/referralDrafts/{draftId}

match /professionals/{uid}/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}
```

Add field validation that rejects unknown keys, so a patient identifier cannot
be written by a future code path even if one tries.

## What this package deliberately does not do

- No speech recognition. `SpeechRecognitionService` belongs in the app layer,
  where the platform APIs are.
- No network, storage or serialisation to a specific backend. Models expose
  `toMap`/`fromMap` over plain types; the Firestore adapter lives in the app.
- No phonetic matching yet. It is the right answer for recogniser error, and
  it is deferred until the speech spike measures how much error there is.
