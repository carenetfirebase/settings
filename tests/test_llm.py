"""LLM scope guards. docs/PHASES.md Phase 9.

Criterion 4 (extraction rate against 10 varied real 10-Ks) needs live EDGAR
and is not met. Criteria 1, 2, 3 and 5 are, and 5 is the interesting one: the
adversarial test runs against a *mocked* model that deliberately hallucinates,
which tests the enforcement rather than the model's good behaviour. That is
the right thing to test -- the enforcement is what has to hold when the model
misbehaves.
"""

from __future__ import annotations

import ast
from pathlib import Path
from typing import ClassVar

import pytest

from imt.llm.citations import (
    Citation,
    CitationType,
    Claim,
    FactSetRef,
    assert_no_uncited_facts,
    enforce,
    uncited_numeric_claims,
)
from imt.llm.sections import (
    ExtractionOutcome,
    Section,
    build_report,
    chunk,
    extract_section,
    strip_html,
)

REPO = Path(__file__).resolve().parents[1]

FACT_SET = FactSetRef(
    {
        "insider_purchase_value": 240_000_000,
        "insider_purchase_date": "2026-08-14",
        "revenue_fy2025": 1_000_000,
    }
)


class TestLlmNeverWritesNumbers:
    """Phase 9 criterion 1, and CLAUDE.md non-negotiable #4."""

    NUMERIC_TABLES: ClassVar[set[str]] = {
        "scores",
        "signal_features",
        "insider_transactions",
        "congressional_transactions",
        "xbrl_facts",
        "prices_daily",
        "short_interest",
        "short_volume",
        "government_contracts",
        "macro_observations",
        "contradiction_items",
    }

    def test_no_llm_module_imports_a_numeric_model(self) -> None:
        """The LLM writes to llm_outputs and nowhere else.

        Checked by import rather than by inspecting writes: a module that
        cannot name the model cannot write to it.
        """
        forbidden = {
            "Score",
            "SignalFeature",
            "InsiderTransaction",
            "CongressionalTransaction",
            "XbrlFact",
            "PriceDaily",
            "ShortInterest",
            "ShortVolume",
            "GovernmentContract",
            "MacroObservation",
            "ContradictionItem",
        }
        offenders: list[str] = []
        for path in sorted((REPO / "src" / "imt" / "llm").rglob("*.py")):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.module == "imt.db.models":
                    for alias in node.names:
                        if alias.name in forbidden:
                            offenders.append(f"{path.name} imports {alias.name}")
        assert offenders == [], f"LLM modules must not touch numeric tables: {offenders}"

    def test_no_llm_module_writes_a_numeric_table_name(self) -> None:
        offenders: list[str] = []
        for path in sorted((REPO / "src" / "imt" / "llm").rglob("*.py")):
            text = path.read_text(encoding="utf-8").lower()
            for table in self.NUMERIC_TABLES:
                if f'"{table}"' in text or f"'{table}'" in text:
                    offenders.append(f"{path.name} references {table}")
        assert offenders == []


class TestCitationEnforcement:
    """Phase 9 criterion 3."""

    def test_a_cited_database_claim_survives_as_fact(self) -> None:
        claims = [
            Claim(
                "CEO purchased $2.4M on the open market on 2026-08-14.",
                Citation(CitationType.DATABASE_ROW, fact_key="insider_purchase_value"),
            )
        ]
        result = enforce(claims, fact_set=FACT_SET)
        assert len(result.facts) == 1
        assert result.interpretation == ()

    def test_an_uncited_claim_moves_to_interpretation(self) -> None:
        claims = [Claim("The company appears well positioned for growth.")]
        result = enforce(claims, fact_set=FACT_SET)
        assert result.facts == ()
        assert len(result.interpretation) == 1
        assert result.moved[0][1] == "no_citation"

    def test_text_is_kept_not_discarded(self) -> None:
        """Uncited content is relabelled as what it is, not deleted."""
        text = "Management seems confident."
        result = enforce([Claim(text)], fact_set=FACT_SET)
        assert result.interpretation[0].text == text

    def test_a_citation_to_an_unsupplied_key_is_rejected(self) -> None:
        """This is the dangerous case.

        The model produced a citation naming data the application never gave
        it, which means the reference came from the model. A plausible
        fact_key is exactly what a confident hallucination looks like.
        """
        claims = [
            Claim(
                "Revenue grew 40% year over year.",
                Citation(CitationType.DATABASE_ROW, fact_key="revenue_growth_fy2026"),
            )
        ]
        result = enforce(claims, fact_set=FACT_SET)
        assert result.facts == ()
        assert result.moved[0][1] == "fact_key_not_in_supplied_facts"

    def test_a_filing_citation_needs_a_reference(self) -> None:
        claims = [Claim("The filing discusses supply risk.", Citation(CitationType.FILING))]
        result = enforce(claims, fact_set=FACT_SET)
        assert result.moved[0][1] == "filing_citation_without_reference"

    def test_the_stripped_citation_cannot_render_a_source_chip(self) -> None:
        """A chip pointing at nothing is worse than no chip."""
        claims = [Claim("Revenue grew.", Citation(CitationType.DATABASE_ROW, fact_key="nope"))]
        result = enforce(claims, fact_set=FACT_SET)
        assert result.interpretation[0].citation is None

    def test_the_final_assertion_passes_on_enforced_output(self) -> None:
        claims = [
            Claim("Cited.", Citation(CitationType.DATABASE_ROW, fact_key="revenue_fy2025")),
            Claim("Uncited."),
        ]
        result = enforce(claims, fact_set=FACT_SET)
        assert_no_uncited_facts(result, FACT_SET)

    def test_the_final_assertion_catches_a_planted_violation(self) -> None:
        """A gate that cannot fail is not a gate."""
        from imt.llm.citations import EnforcementResult

        planted = EnforcementResult(facts=(Claim("Invented."),), interpretation=())
        with pytest.raises(AssertionError, match="Uncited claims reached"):
            assert_no_uncited_facts(planted, FACT_SET)


class TestAdversarial:
    """Phase 9 criterion 5.

    Given a fact set with a missing revenue figure, the model must not invent
    one. Run against a deliberately misbehaving mock, because what needs
    testing is the enforcement, not the model's manners.
    """

    SPARSE = FactSetRef({"insider_purchase_value": 240_000_000})

    def hallucinating_model(self) -> list[Claim]:
        """A model doing the worst plausible thing: a confident figure with a
        citation to a key it was never given."""
        return [
            Claim(
                "Revenue for FY2025 was $4.2 billion.",
                Citation(CitationType.DATABASE_ROW, fact_key="revenue_fy2025"),
            ),
            Claim(
                "CEO purchased $2.4M on the open market.",
                Citation(CitationType.DATABASE_ROW, fact_key="insider_purchase_value"),
            ),
        ]

    def test_the_invented_figure_does_not_reach_the_facts_list(self) -> None:
        result = enforce(self.hallucinating_model(), fact_set=self.SPARSE)
        fact_text = " ".join(c.text for c in result.facts)
        assert "4.2 billion" not in fact_text
        assert "purchased $2.4M" in fact_text

    def test_the_real_claim_still_survives(self) -> None:
        """Enforcement is not a blanket rejection -- the cited claim stands."""
        result = enforce(self.hallucinating_model(), fact_set=self.SPARSE)
        assert len(result.facts) == 1

    def test_uncited_numeric_claims_are_flagged_for_logging(self) -> None:
        """SPEC non-negotiable #4: the LLM never produces a number. An uncited
        figure is a hallucination candidate worth logging loudly."""
        claims = [
            Claim("Revenue was $4.2 billion."),
            Claim("Margins improved by 12%."),
            Claim("Management sounded cautious."),
        ]
        flagged = uncited_numeric_claims(claims)
        assert len(flagged) == 2
        assert all("$" in c.text or "%" in c.text for c in flagged)

    def test_fact_set_hash_is_stable_and_order_independent(self) -> None:
        """Stored with every output (SPEC §9) so a result can be reproduced."""
        a = FactSetRef({"x": 1, "y": 2})
        b = FactSetRef({"y": 2, "x": 1})
        assert a.hash() == b.hash()
        assert a.hash().startswith("sha256:")


class TestSectionExtraction:
    FILING = """
    <html><body>
    <p>TABLE OF CONTENTS</p>
    <p>Item 1A. Risk Factors .......... 12</p>
    <p>Item 7. Management's Discussion and Analysis .......... 40</p>
    <p>Item 1. Business</p>
    <p>{business}</p>
    <p>Item 1A. Risk Factors</p>
    <p>{risks}</p>
    <p>Item 1B. Unresolved Staff Comments</p>
    <p>None.</p>
    </body></html>
    """.format(business="We make things. " * 60, risks="Supply chain disruption. " * 60)

    def test_extracts_the_body_not_the_contents_entry(self) -> None:
        """Filings list every item twice. Taking the first match returns a
        one-line heading and lets the model summarize from memory."""
        result = extract_section(self.FILING, Section.RISK_FACTORS)
        assert result.succeeded
        assert "Supply chain disruption" in result.text
        assert ".........." not in result.text

    def test_stops_at_the_next_section(self) -> None:
        result = extract_section(self.FILING, Section.RISK_FACTORS)
        assert "Unresolved Staff Comments" not in result.text

    def test_a_missing_section_returns_nothing_not_the_wrong_one(self) -> None:
        """Summarizing Item 7A while labelling it Item 7 would produce a
        confident summary of the wrong thing."""
        result = extract_section(self.FILING, Section.MDNA)
        assert not result.succeeded
        assert result.text == ""

    def test_a_contents_only_match_is_not_treated_as_a_section(self) -> None:
        """A TOC entry for a section with no body has no following heading to
        stop at, so it runs to the end of the document and arrives looking
        like a long healthy section. Dot leaders give it away."""
        toc = "Item 1A. Risk Factors .......... 12\nItem 2. Properties"
        result = extract_section(toc, Section.RISK_FACTORS)
        assert not result.succeeded
        assert result.outcome is ExtractionOutcome.HEADING_NOT_FOUND

    def test_strip_html_preserves_paragraph_structure(self) -> None:
        text = strip_html("<p>One</p><p>Two</p>")
        assert "One" in text and "Two" in text

    def test_extraction_report_documents_the_rate(self) -> None:
        """Phase 9 criterion 4's shape. The rate is measured, not assumed."""
        results = [
            extract_section(self.FILING, Section.RISK_FACTORS),
            extract_section(self.FILING, Section.MDNA),
            extract_section(self.FILING, Section.BUSINESS),
        ]
        report = build_report(results)
        assert report.attempted == 3
        assert 0 < report.success_rate < 100
        assert "heading_not_found" in report.render()


class TestChunking:
    def test_short_text_is_one_chunk(self) -> None:
        assert chunk("short") == ["short"]

    def test_long_text_splits_with_overlap(self) -> None:
        text = "Sentence one. " * 2000
        chunks = chunk(text, max_chars=1000)
        assert len(chunks) > 1
        assert all(len(c) <= 1000 for c in chunks)

    def test_prefers_paragraph_boundaries(self) -> None:
        text = ("A" * 400) + "\n\n" + ("B" * 400) + "\n\n" + ("C" * 400)
        chunks = chunk(text, max_chars=500)
        assert chunks[0].endswith("A")

    def test_empty_text_yields_nothing(self) -> None:
        assert chunk("") == []
