"""Citation enforcement. SPEC §9, UI_SPEC correction #9.

The rule: **any claim rendered as "fact" must resolve to a source passage or a
database row.** Uncited claims are moved to "interpretation" before the
response leaves the server — API_CONTRACT is explicit that this is enforced
server-side, not client-side.

Why server-side matters. A frontend that renders uncited text under a
different heading is one careless component away from rendering it under
"Facts" instead. Moving the claim before it is serialized means the API cannot
emit an uncited fact at all, whatever the UI does with it.

## What this can and cannot do

It can guarantee that every displayed fact points at something real: the
citation must reference a fact the application supplied, not a document the
model recalled. That kills the most dangerous failure — an invented figure
presented with an invented source.

It cannot guarantee the model's *characterisation* of a real passage is
accurate. A plausible-but-wrong summary of a genuine filing section will pass
here, which is why the citation is displayed rather than merely checked: the
reader can open the source. SPEC §9 accepts that residual risk explicitly and
so does this module.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any

#: Digits with a currency symbol, percent, or magnitude suffix. Used to catch
#: the worst case: a specific-looking number in a sentence with no citation.
_NUMERIC_CLAIM = re.compile(
    r"(?:[$€£]\s?\d|(?<![\w.])\d[\d,]*\.?\d*\s?(?:%|percent|million|billion|bn|m\b|k\b))",
    re.IGNORECASE,
)


class CitationType(StrEnum):
    FILING = "filing"
    DATABASE_ROW = "database_row"
    PASSAGE = "passage"


@dataclass(frozen=True, slots=True)
class Citation:
    type: CitationType
    url: str | None = None
    accession: str | None = None
    #: Key into the fact set the application supplied. This is what makes a
    #: citation verifiable rather than decorative.
    fact_key: str | None = None
    passage: str | None = None


@dataclass(frozen=True, slots=True)
class Claim:
    text: str
    citation: Citation | None = None

    @property
    def is_cited(self) -> bool:
        return self.citation is not None


@dataclass(frozen=True, slots=True)
class EnforcementResult:
    """What survived, what moved, and why.

    ``moved`` is reported rather than silently applied so the count can be
    logged: a prompt whose output is 80% uncited is a prompt problem, and it
    should be visible without reading transcripts.
    """

    facts: tuple[Claim, ...]
    interpretation: tuple[Claim, ...]
    moved: tuple[tuple[Claim, str], ...] = ()

    @property
    def moved_count(self) -> int:
        return len(self.moved)


@dataclass(frozen=True, slots=True)
class FactSetRef:
    """The structured facts handed to the model.

    The model receives these and nothing else (SPEC §9), so a citation naming
    a key that is not here is a citation to something the model supplied
    itself — which is the definition of the failure being guarded against.
    """

    values: dict[str, Any] = field(default_factory=dict)

    def contains(self, key: str) -> bool:
        return key in self.values

    def hash(self) -> str:
        """Stable hash of the inputs, stored with every output (SPEC §9)."""
        blob = json.dumps(self.values, sort_keys=True, default=str)
        return "sha256:" + hashlib.sha256(blob.encode()).hexdigest()


def _reason_uncited(claim: Claim, fact_set: FactSetRef) -> str | None:
    """Why a claim cannot stand as a fact, or None if it can."""
    citation = claim.citation
    if citation is None:
        return "no_citation"

    if citation.type is CitationType.DATABASE_ROW:
        if not citation.fact_key:
            return "database_citation_without_key"
        if not fact_set.contains(citation.fact_key):
            # The model cited a key the application never supplied. It came
            # from the model, not from the data.
            return "fact_key_not_in_supplied_facts"

    if citation.type is CitationType.FILING and not (citation.url or citation.accession):
        return "filing_citation_without_reference"

    if citation.type is CitationType.PASSAGE and not citation.passage:
        return "passage_citation_without_text"

    return None


def enforce(claims: list[Claim], *, fact_set: FactSetRef) -> EnforcementResult:
    """Split claims into facts and interpretation.

    A claim survives as a fact only when its citation resolves to something
    the application supplied. Everything else moves, keeping its text — the
    content is not discarded, it is relabelled as what it actually is.
    """
    facts: list[Claim] = []
    interpretation: list[Claim] = []
    moved: list[tuple[Claim, str]] = []

    for claim in claims:
        reason = _reason_uncited(claim, fact_set)
        if reason is None:
            facts.append(claim)
            continue
        # Strip the unusable citation so the UI cannot render a source chip
        # pointing at nothing.
        moved.append((claim, reason))
        interpretation.append(Claim(text=claim.text, citation=None))

    return EnforcementResult(
        facts=tuple(facts), interpretation=tuple(interpretation), moved=tuple(moved)
    )


def uncited_numeric_claims(claims: list[Claim]) -> list[Claim]:
    """Uncited claims that contain a specific-looking figure.

    The most dangerous output shape: a number the model produced, in a
    sentence with no source. SPEC's non-negotiable #4 says the LLM never
    computes a number, so any figure it emits should have come from the
    supplied facts and be citable. One that is not is a hallucination
    candidate and worth logging loudly even though ``enforce`` has already
    relabelled it.
    """
    return [c for c in claims if not c.is_cited and _NUMERIC_CLAIM.search(c.text)]


def assert_no_uncited_facts(result: EnforcementResult, fact_set: FactSetRef) -> None:
    """Belt and braces before serialization.

    ``enforce`` already guarantees this; the assertion exists because the cost
    of a regression here is an invented figure presented to the reader as
    sourced, and that is worth a redundant check on the way out.
    """
    offenders = [
        f"{claim.text[:60]}… ({_reason_uncited(claim, fact_set)})"
        for claim in result.facts
        if _reason_uncited(claim, fact_set) is not None
    ]
    if offenders:
        raise AssertionError("Uncited claims reached the facts list:\n  " + "\n  ".join(offenders))
