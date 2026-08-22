"""Renders the research report.

Design rules, all of which follow from the ground rules rather than taste:

* A score never appears without its components.
* Missing data is printed as `INSUFFICIENT DATA`, never as a blank, a dash, or
  a zero. The reader must be able to tell "we looked and it was 0" from
  "we could not find out".
* Facts, calculations and estimates are visually distinguished, and the DCF
  section states that its assumptions are inputs rather than findings.
* The premium-data gap is stated in the report, not hidden in a config file.

Plain text rather than HTML: it renders in a terminal, diffs cleanly between
runs, and stores verbatim in `research_snapshots.report_text`.
"""

from __future__ import annotations

from datetime import date

from invest.engines.fundamentals import (
    AltmanResult,
    BeneishResult,
    DuPontResult,
    PiotroskiResult,
    RoicResult,
)
from invest.engines.scoring import PREMIUM_DEPENDENT_INPUTS, Score, ScoreSet
from invest.engines.valuation import ComparablesResult, ReverseDcfResult, ScenarioSet

# Wide enough for the score table to leave a readable detail column.
WIDTH = 100
INSUFFICIENT = "INSUFFICIENT DATA"


def _rule(char: str = "=") -> str:
    return char * WIDTH


def _heading(text: str) -> str:
    return f"\n{_rule()}\n{text.upper()}\n{_rule()}"


def _subheading(text: str) -> str:
    return f"\n{text}\n{_rule('-')}"


def fmt_number(value: float | None, *, decimals: int = 2, suffix: str = "") -> str:
    if value is None:
        return INSUFFICIENT
    return f"{value:,.{decimals}f}{suffix}"


def fmt_pct(value: float | None, *, decimals: int = 1, signed: bool = False) -> str:
    if value is None:
        return INSUFFICIENT
    sign = "+" if signed else ""
    return f"{value:{sign}.{decimals}%}"


def fmt_money(value: float | None) -> str:
    if value is None:
        return INSUFFICIENT
    for threshold, unit in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if abs(value) >= threshold:
            return f"${value / threshold:,.2f}{unit}"
    return f"${value:,.2f}"


def fmt_score(value: float | None) -> str:
    return INSUFFICIENT if value is None else f"{value:.1f}/100"


def _bar(value: float | None, width: int = 20) -> str:
    """A crude visual so the eye can scan components quickly."""
    if value is None:
        return "?" * width
    filled = round(value / 100 * width)
    return "#" * filled + "." * (width - filled)


#: Wide enough for the literal string INSUFFICIENT DATA, so a missing
#: component never breaks the column alignment.
SCORE_COL = len(INSUFFICIENT)
BAR_WIDTH = 8
DETAIL_INDENT = 2 + 26 + 1 + 6 + 1 + SCORE_COL + 2 + BAR_WIDTH + 2


def _wrap(text: str, indent: int) -> list[str]:
    """Wrap to the page width, hanging-indented under the detail column."""
    available = max(20, WIDTH - indent)
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if len(candidate) > available and current:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines or [""]


def render_score_block(score: Score) -> str:
    """A score with every component shown. Never a bare total."""
    lines = [_subheading(f"{score.name} Score: {fmt_score(score.value)}")]
    lines.append(
        f"  Input coverage: {score.coverage:.0%}"
        + ("" if score.is_reliable else "   <-- BELOW RELIABILITY THRESHOLD")
    )
    lines.append("")
    lines.append(
        f"  {'COMPONENT':<26} {'WEIGHT':>6} {'SCORE':>{SCORE_COL}}  "
        f"{'':<{BAR_WIDTH}}  DETAIL"
    )

    pad = " " * DETAIL_INDENT
    for component in score.components:
        value_text = INSUFFICIENT if component.value is None else f"{component.value:.1f}"
        detail_lines = _wrap(component.detail, DETAIL_INDENT)
        lines.append(
            f"  {component.name:<26} {component.weight:>6.0%} {value_text:>{SCORE_COL}}  "
            f"{_bar(component.value, BAR_WIDTH)}  {detail_lines[0]}"
        )
        for extra in detail_lines[1:]:
            lines.append(f"{pad}{extra}")
        if component.unavailable_reason:
            for i, extra in enumerate(_wrap(f"-> {component.unavailable_reason}", DETAIL_INDENT)):
                lines.append(f"{pad}{extra}" if i == 0 else f"{pad}   {extra}")

    return "\n".join(lines)


def render_piotroski(result: PiotroskiResult | None) -> str:
    lines = [_subheading("Piotroski F-Score")]
    if result is None:
        lines.append(f"  {INSUFFICIENT}")
        return "\n".join(lines)

    lines.append(
        f"  Score: {result.score}/{result.max_possible}"
        + ("" if result.is_reliable else f"   <-- {result.missing_count} signals unavailable")
    )
    lines.append("")
    for component in result.components:
        if component.value is None:
            mark = "  ?  "
            note = f"  ({component.unavailable_reason})"
        else:
            mark = " PASS" if component.value else " FAIL"
            note = ""
        lines.append(f"  [{mark}] {component.name:<30} {component.description}{note}")
    return "\n".join(lines)


def render_altman(result: AltmanResult | None) -> str:
    lines = [_subheading("Altman Z-Score (bankruptcy risk)")]
    if result is None:
        lines.append(f"  {INSUFFICIENT}")
        return "\n".join(lines)

    if not result.applicable:
        lines.append(f"  NOT APPLICABLE ({result.variant.value})")
        if result.note:
            lines.append(f"  {result.note}")
        return "\n".join(lines)

    lines.append(f"  Variant: {result.variant.value}")
    lines.append(f"  Score:   {fmt_number(result.score)}  ->  zone: {result.zone.upper()}")
    lines.append("")
    for component in result.components:
        lines.append(
            f"  {component.name:<34} {fmt_number(component.value, decimals=4):>12}  "
            f"{component.description}"
        )
    return "\n".join(lines)


def render_beneish(result: BeneishResult | None) -> str:
    lines = [_subheading("Beneish M-Score (earnings manipulation risk)")]
    if result is None:
        lines.append(f"  {INSUFFICIENT}")
        return "\n".join(lines)

    lines.append(f"  Score: {fmt_number(result.score)}  (threshold {result.THRESHOLD})")
    lines.append(f"  Reading: {result.interpretation}")
    if result.score is None:
        lines.append("  Not scored: the model requires all eight indices.")
    lines.append("")
    for component in result.components:
        lines.append(
            f"  {component.name:<8} {fmt_number(component.value, decimals=4):>12}  "
            f"{component.description}"
        )
    if result.flags_manipulation:
        lines.append("")
        lines.append(
            "  NOTE: an elevated M-Score indicates statistical similarity to known\n"
            "  manipulators. It is a prompt to read the filings, not an accusation."
        )
    return "\n".join(lines)


def render_dupont(result: DuPontResult | None) -> str:
    lines = [_subheading("DuPont decomposition")]
    if result is None:
        lines.append(f"  {INSUFFICIENT}")
        return "\n".join(lines)

    lines.append(f"  ROE = {fmt_pct(result.roe)}")
    lines.append("")
    lines.append(f"  Net margin          {fmt_pct(result.net_margin):>10}")
    lines.append(f"  x Asset turnover    {fmt_number(result.asset_turnover):>10}")
    lines.append(f"  x Equity multiplier {fmt_number(result.equity_multiplier):>10}")
    if result.five_step_available:
        lines.append("")
        lines.append("  Five-step:")
        lines.append(f"    Tax burden        {fmt_number(result.tax_burden):>10}")
        lines.append(f"    Interest burden   {fmt_number(result.interest_burden):>10}")
        lines.append(f"    Operating margin  {fmt_pct(result.operating_margin):>10}")
    return "\n".join(lines)


def render_roic(result: RoicResult | None) -> str:
    lines = [_subheading("ROIC vs WACC (value creation)")]
    if result is None:
        lines.append(f"  {INSUFFICIENT}")
        return "\n".join(lines)

    lines.append(f"  ROIC             {fmt_pct(result.roic):>10}   [calculated from filings]")
    lines.append(f"  WACC             {fmt_pct(result.wacc):>10}   [ESTIMATED — CAPM assumptions]")
    lines.append(f"  Spread           {fmt_pct(result.spread, signed=True):>10}")
    if result.creates_value is not None:
        verdict = "creates value" if result.creates_value else "destroys value"
        lines.append(f"  Verdict: the business {verdict} against its cost of capital.")
    else:
        lines.append("  Verdict: INSUFFICIENT DATA — cost of capital could not be estimated.")
    lines.append("")
    lines.append(f"  NOPAT            {fmt_money(result.nopat):>14}")
    lines.append(f"  Invested capital {fmt_money(result.invested_capital):>14}")
    lines.append(f"  Effective tax    {fmt_pct(result.effective_tax_rate):>14}")
    return "\n".join(lines)


def render_valuation(
    scenarios: ScenarioSet | None,
    reverse: ReverseDcfResult | None = None,
    historical_growth: float | None = None,
) -> str:
    lines = [_subheading("Discounted cash flow  [ESTIMATED — assumptions, not findings]")]
    if scenarios is None:
        lines.append(f"  {INSUFFICIENT}")
        return "\n".join(lines)

    lines.append(
        f"  {'SCENARIO':<8} {'GROWTH':>8} {'DISCOUNT':>9} {'FAIR VALUE':>12} "
        f"{'UPSIDE':>9}  {'TV SHARE':>9}"
    )
    for name, result in (
        ("Bear", scenarios.bear),
        ("Base", scenarios.base),
        ("Bull", scenarios.bull),
    ):
        assumptions = result.assumptions
        lines.append(
            f"  {name:<8} {assumptions.growth_rate:>7.1%} "
            f"{assumptions.discount_rate:>8.1%} "
            f"{fmt_number(result.fair_value_per_share):>12} "
            f"{fmt_pct(result.upside, signed=True):>9}  "
            f"{fmt_pct(result.terminal_value_share):>9}"
        )
        if result.insufficient_data_reason:
            lines.append(f"  {'':<8} -> {result.insufficient_data_reason}")

    lines.append("")
    lines.append(
        "  TV SHARE is the fraction of value coming from the terminal assumption.\n"
        "  Above ~75%, the valuation is mostly a bet on the perpetuity rate."
    )

    if reverse is not None:
        lines.append("")
        lines.append("  Reverse DCF  [CALCULATED from the observed price]")
        if reverse.implied_growth_rate is None:
            lines.append(f"    {INSUFFICIENT}: {reverse.insufficient_data_reason}")
        else:
            lines.append(f"    {reverse.interpretation(historical_growth)}")

    return "\n".join(lines)


def render_comparables(result: ComparablesResult | None) -> str:
    lines = [_subheading("Comparable multiples")]
    if result is None:
        lines.append(f"  {INSUFFICIENT}")
        return "\n".join(lines)

    lines.append(f"  {'MULTIPLE':<16} {'SUBJECT':>12} {'PEER MEDIAN':>13} {'PREM/DISC':>11}")
    for name in result.subject:
        lines.append(
            f"  {name:<16} {fmt_number(result.subject[name]):>12} "
            f"{fmt_number(result.peer_medians.get(name)):>13} "
            f"{fmt_pct(result.premium_discount.get(name), signed=True):>11}"
        )
    if result.note:
        lines.append("")
        lines.append(f"  NOTE: {result.note}")
    return "\n".join(lines)


def render_insider(summary: dict | None) -> str:
    """Insider activity, with conviction trades separated from compensation.

    The distinction is the whole point: a page of option exercises tells you
    nothing about what insiders think of the price, and presenting it as
    "insider buying" would be actively misleading.
    """
    lines = [_subheading("Insider activity (Form 4)")]
    if not summary or not summary.get("total_filings"):
        lines.append(f"  {INSUFFICIENT} — no Form 4 filings ingested")
        return "\n".join(lines)

    discretionary = summary.get("transaction_count", 0)
    lines.append(f"  Filings in window          {summary['total_filings']}")
    lines.append(f"  Discretionary trades       {discretionary}")
    lines.append(
        f"  Non-discretionary          {summary['total_filings'] - discretionary}"
        "   (grants, exercises, tax withholding — not a view on price)"
    )
    lines.append("")
    lines.append(f"  Open-market buys           {summary.get('buys', 0)}")
    lines.append(f"  Open-market sells          {summary.get('sells', 0)}")
    lines.append(f"  Value bought               {fmt_money(summary.get('buy_value'))}")
    lines.append(f"  Value sold                 {fmt_money(summary.get('sell_value'))}")
    lines.append("")

    ratio = summary.get("net_buy_ratio")
    if ratio is None:
        lines.append(f"  Net conviction             {INSUFFICIENT} (no discretionary trades)")
    else:
        lines.append(f"  Net conviction             {ratio:+.2f}  (-1 = all selling, +1 = all buying)")
        lines.append(
            "  Sales are weighted at half a purchase: insiders sell for tax,\n"
            "  diversification and liquidity, but buy for one reason."
        )
    return "\n".join(lines)


def render_header(
    *,
    ticker: str,
    company_name: str,
    cik: str | None,
    as_of: date,
    price: float | None,
    model_version: str,
) -> str:
    lines = [_rule()]
    lines.append(f"INVESTMENT RESEARCH REPORT — {ticker}")
    lines.append(_rule())
    lines.append(f"  Company        {company_name}")
    lines.append(f"  CIK            {cik or INSUFFICIENT}")
    lines.append(f"  As of          {as_of.isoformat()}  (point-in-time cutoff)")
    lines.append(f"  Last price     {fmt_number(price)}")
    lines.append(f"  Model version  {model_version}")
    return "\n".join(lines)


def render_footer(scores: ScoreSet) -> str:
    lines = [_heading("Data limitations")]
    lines.append("  The following inputs are PREMIUM-DATA DEPENDENT and were NOT used,")
    lines.append("  because no free source provides them. Their absence is reflected in")
    lines.append("  the Confidence score, which is capped accordingly:")
    for item in PREMIUM_DEPENDENT_INPUTS:
        lines.append(f"    - {item}")

    lines.append("")
    lines.append("  Political trade disclosures are stored but FIREWALLED: they are")
    lines.append("  research context only and contribute nothing to any score.")

    warnings = scores.all_warnings
    if warnings:
        lines.append(_heading("Warnings"))
        for warning in warnings:
            wrapped = _wrap(warning, 4)
            lines.append(f"  ! {wrapped[0]}")
            lines.extend(f"    {extra}" for extra in wrapped[1:])

    lines.append(_heading("Provenance"))
    lines.append("  observed     = taken from a filing or price feed as published")
    lines.append("  calculated   = deterministic arithmetic over observed values")
    lines.append("  estimated    = rests on modelled assumptions (DCF, WACC)")
    lines.append("  Nothing in this report was generated or judged by a language model.")
    lines.append("")
    lines.append("  This is not investment advice.")
    lines.append(_rule())
    return "\n".join(lines)


def render_report(
    *,
    ticker: str,
    company_name: str,
    cik: str | None,
    as_of: date,
    price: float | None,
    scores: ScoreSet,
    piotroski: PiotroskiResult | None = None,
    altman: AltmanResult | None = None,
    beneish: BeneishResult | None = None,
    dupont: DuPontResult | None = None,
    roic: RoicResult | None = None,
    scenarios: ScenarioSet | None = None,
    reverse: ReverseDcfResult | None = None,
    comparables_result: ComparablesResult | None = None,
    historical_growth: float | None = None,
    insider_summary: dict | None = None,
) -> str:
    """Assemble the full report."""
    sections = [
        render_header(
            ticker=ticker,
            company_name=company_name,
            cik=cik,
            as_of=as_of,
            price=price,
            model_version=scores.model_version,
        ),
        _heading("Scores"),
        render_score_block(scores.quality),
        render_score_block(scores.setup),
        render_score_block(scores.confidence),
        _heading("Fundamental models"),
        render_piotroski(piotroski),
        render_altman(altman),
        render_beneish(beneish),
        render_dupont(dupont),
        render_roic(roic),
        _heading("Valuation"),
        render_valuation(scenarios, reverse, historical_growth),
        render_comparables(comparables_result),
        _heading("Insider activity"),
        render_insider(insider_summary),
        render_footer(scores),
    ]
    return "\n".join(sections) + "\n"
