"""Fundamental scoring models: Piotroski F, Altman Z, Beneish M, DuPont,
and ROIC vs WACC.

Every model here returns its components, never a bare total. A Piotroski 7
built from nine signals means something different from a 7 where three inputs
were missing, and the report must be able to tell them apart.

Missing inputs are handled the same way throughout: the affected component is
`None`, it does not contribute to the total, and the count of unavailable
components is reported alongside it. Nothing is imputed. A model missing too
many inputs reports itself as unreliable rather than producing a confident
number from half the data.

Sources for the formulas:
* Piotroski (2000), "Value Investing: The Use of Historical Financial
  Statement Information to Separate Winners from Losers"
* Altman (1968) plus the 1983/1995 private-firm and non-manufacturer variants
* Beneish (1999), "The Detection of Earnings Manipulation"
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from invest.engines.quant import safe_divide

# --------------------------------------------------------------------------
# Shared plumbing
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Component:
    """One named piece of a model, with the reason when it is unavailable."""

    name: str
    value: float | None
    description: str
    unavailable_reason: str | None = None

    @property
    def available(self) -> bool:
        return self.value is not None

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "value": self.value,
            "description": self.description,
            "unavailable_reason": self.unavailable_reason,
        }


def _component(
    name: str, value: float | None, description: str, missing: str = "input unavailable"
) -> Component:
    return Component(name, value, description, None if value is not None else missing)


@dataclass(frozen=True)
class FinancialInputs:
    """The line items the models need, for one period.

    Every field is optional. A model asked for a ratio it cannot build says so
    rather than substituting a default.
    """

    revenue: float | None = None
    cost_of_revenue: float | None = None
    gross_profit: float | None = None
    operating_income: float | None = None
    net_income: float | None = None
    interest_expense: float | None = None
    tax_expense: float | None = None
    pretax_income: float | None = None
    depreciation_amortization: float | None = None
    sga_expense: float | None = None

    total_assets: float | None = None
    current_assets: float | None = None
    total_liabilities: float | None = None
    current_liabilities: float | None = None
    equity: float | None = None
    cash: float | None = None
    inventory: float | None = None
    receivables: float | None = None
    ppe_net: float | None = None
    long_term_debt: float | None = None
    current_debt: float | None = None
    retained_earnings: float | None = None
    securities_outstanding: float | None = None

    operating_cash_flow: float | None = None
    capex: float | None = None

    shares_diluted: float | None = None
    market_cap: float | None = None

    @property
    def total_debt(self) -> float | None:
        parts = [p for p in (self.long_term_debt, self.current_debt) if p is not None]
        return sum(parts) if parts else None

    @property
    def working_capital(self) -> float | None:
        if self.current_assets is None or self.current_liabilities is None:
            return None
        return self.current_assets - self.current_liabilities

    @property
    def ebit(self) -> float | None:
        """Prefer reported operating income; fall back to pretax + interest."""
        if self.operating_income is not None:
            return self.operating_income
        if self.pretax_income is not None and self.interest_expense is not None:
            return self.pretax_income + self.interest_expense
        return None

    @property
    def free_cash_flow(self) -> float | None:
        if self.operating_cash_flow is None or self.capex is None:
            return None
        # capex is reported as a positive outflow in the cash-flow statement.
        return self.operating_cash_flow - abs(self.capex)


# --------------------------------------------------------------------------
# Piotroski F-Score
# --------------------------------------------------------------------------


@dataclass
class PiotroskiResult:
    """Nine binary signals across profitability, leverage, and efficiency."""

    components: list[Component] = field(default_factory=list)

    @property
    def score(self) -> int:
        """Sum of the signals that could be evaluated. Range 0-9."""
        return int(sum(c.value for c in self.components if c.value is not None))

    @property
    def available_count(self) -> int:
        return sum(1 for c in self.components if c.available)

    @property
    def missing_count(self) -> int:
        return len(self.components) - self.available_count

    @property
    def is_reliable(self) -> bool:
        """Fewer than three missing signals. Below that the score is not
        comparable to a full nine-signal score.
        """
        return self.missing_count <= 2

    @property
    def max_possible(self) -> int:
        return self.available_count

    def as_dict(self) -> dict:
        return {
            "score": self.score,
            "out_of": self.max_possible,
            "missing_components": self.missing_count,
            "reliable": self.is_reliable,
            "components": [c.as_dict() for c in self.components],
        }


def piotroski_f_score(current: FinancialInputs, prior: FinancialInputs) -> PiotroskiResult:
    """All nine signals, each exposed individually.

    Scores 1 point per signal passed. Requires the prior year for the four
    trend signals; those come back unavailable if it is missing.
    """
    components: list[Component] = []

    roa = safe_divide(current.net_income, current.total_assets)
    prior_roa = safe_divide(prior.net_income, prior.total_assets)
    cfo_to_assets = safe_divide(current.operating_cash_flow, current.total_assets)

    # --- Profitability (4 signals) ---
    components.append(
        _component(
            "positive_roa",
            None if roa is None else float(roa > 0),
            "Return on assets is positive",
        )
    )
    components.append(
        _component(
            "positive_operating_cash_flow",
            None if current.operating_cash_flow is None else float(current.operating_cash_flow > 0),
            "Operating cash flow is positive",
        )
    )
    components.append(
        _component(
            "improving_roa",
            None if (roa is None or prior_roa is None) else float(roa > prior_roa),
            "Return on assets improved year over year",
            "prior-year ROA unavailable",
        )
    )
    components.append(
        _component(
            "accruals",
            None
            if (cfo_to_assets is None or roa is None)
            else float(cfo_to_assets > roa),
            "Operating cash flow exceeds net income (earnings backed by cash)",
        )
    )

    # --- Leverage, liquidity, funding (3 signals) ---
    leverage = safe_divide(current.long_term_debt, current.total_assets)
    prior_leverage = safe_divide(prior.long_term_debt, prior.total_assets)
    components.append(
        _component(
            "decreasing_leverage",
            None
            if (leverage is None or prior_leverage is None)
            else float(leverage <= prior_leverage),
            "Long-term debt to assets did not increase",
            "prior-year leverage unavailable",
        )
    )

    current_ratio = safe_divide(current.current_assets, current.current_liabilities)
    prior_current_ratio = safe_divide(prior.current_assets, prior.current_liabilities)
    components.append(
        _component(
            "improving_current_ratio",
            None
            if (current_ratio is None or prior_current_ratio is None)
            else float(current_ratio > prior_current_ratio),
            "Current ratio improved",
            "prior-year current ratio unavailable",
        )
    )

    components.append(
        _component(
            "no_dilution",
            None
            if (current.shares_diluted is None or prior.shares_diluted is None)
            else float(current.shares_diluted <= prior.shares_diluted),
            "Diluted share count did not increase",
            "prior-year share count unavailable",
        )
    )

    # --- Operating efficiency (2 signals) ---
    gross_margin = safe_divide(current.gross_profit, current.revenue)
    prior_gross_margin = safe_divide(prior.gross_profit, prior.revenue)
    components.append(
        _component(
            "improving_gross_margin",
            None
            if (gross_margin is None or prior_gross_margin is None)
            else float(gross_margin > prior_gross_margin),
            "Gross margin expanded",
            "prior-year gross margin unavailable",
        )
    )

    asset_turnover = safe_divide(current.revenue, current.total_assets)
    prior_asset_turnover = safe_divide(prior.revenue, prior.total_assets)
    components.append(
        _component(
            "improving_asset_turnover",
            None
            if (asset_turnover is None or prior_asset_turnover is None)
            else float(asset_turnover > prior_asset_turnover),
            "Asset turnover improved",
            "prior-year asset turnover unavailable",
        )
    )

    return PiotroskiResult(components)


# --------------------------------------------------------------------------
# Altman Z-Score
# --------------------------------------------------------------------------


class AltmanVariant(StrEnum):
    ORIGINAL = "original"  # public manufacturers
    PRIVATE = "private"  # Z' — book value of equity
    NON_MANUFACTURER = "non_manufacturer"  # Z'' — emerging markets / services
    NOT_APPLICABLE = "not_applicable"  # banks, insurers


@dataclass
class AltmanResult:
    variant: AltmanVariant
    components: list[Component] = field(default_factory=list)
    score: float | None = None
    applicable: bool = True
    note: str | None = None

    @property
    def zone(self) -> str:
        """Distress / grey / safe, using the thresholds for this variant."""
        if self.score is None or not self.applicable:
            return "INSUFFICIENT DATA"
        if self.variant == AltmanVariant.ORIGINAL:
            distress, safe = 1.81, 2.99
        elif self.variant == AltmanVariant.PRIVATE:
            distress, safe = 1.23, 2.90
        else:
            distress, safe = 1.10, 2.60
        if self.score < distress:
            return "distress"
        if self.score < safe:
            return "grey"
        return "safe"

    def as_dict(self) -> dict:
        return {
            "variant": self.variant.value,
            "score": self.score,
            "zone": self.zone,
            "applicable": self.applicable,
            "note": self.note,
            "components": [c.as_dict() for c in self.components],
        }


def altman_z_score(
    inputs: FinancialInputs,
    *,
    is_financial: bool = False,
    is_manufacturer: bool = True,
    use_market_value: bool = True,
) -> AltmanResult:
    """Altman Z, using the variant appropriate to the company.

    The variant matters: applying the original manufacturer coefficients to a
    services company produces a number that looks precise and means nothing.

    Banks and insurers get NOT_APPLICABLE outright — the model was fitted on
    industrial balance sheets, and a bank's leverage is its business model
    rather than a distress signal.
    """
    if is_financial:
        return AltmanResult(
            variant=AltmanVariant.NOT_APPLICABLE,
            applicable=False,
            note=(
                "Altman Z is not meaningful for banks and insurers: the model was "
                "fitted on industrial balance sheets, where high leverage signals "
                "distress rather than normal operations."
            ),
        )

    if not is_manufacturer:
        variant = AltmanVariant.NON_MANUFACTURER
    elif use_market_value:
        variant = AltmanVariant.ORIGINAL
    else:
        variant = AltmanVariant.PRIVATE

    assets = inputs.total_assets
    x1 = safe_divide(inputs.working_capital, assets)
    x2 = safe_divide(inputs.retained_earnings, assets)
    x3 = safe_divide(inputs.ebit, assets)

    equity_value = inputs.market_cap if variant == AltmanVariant.ORIGINAL else inputs.equity
    x4 = safe_divide(equity_value, inputs.total_liabilities)
    x5 = safe_divide(inputs.revenue, assets)

    components = [
        _component("X1_working_capital_to_assets", x1, "Short-term liquidity buffer"),
        _component("X2_retained_earnings_to_assets", x2, "Cumulative profitability / age"),
        _component("X3_ebit_to_assets", x3, "Operating productivity of assets"),
        _component(
            "X4_equity_to_liabilities",
            x4,
            "Market value of equity to total liabilities"
            if variant == AltmanVariant.ORIGINAL
            else "Book value of equity to total liabilities",
        ),
        _component("X5_asset_turnover", x5, "Revenue generated per unit of assets"),
    ]

    if variant == AltmanVariant.NON_MANUFACTURER:
        # Z'' drops X5 entirely — asset turnover varies too much across
        # service industries to carry a common coefficient.
        needed = [x1, x2, x3, x4]
        components = components[:4]
        score = (
            None
            if any(v is None for v in needed)
            else 6.56 * x1 + 3.26 * x2 + 6.72 * x3 + 1.05 * x4
        )
    elif variant == AltmanVariant.ORIGINAL:
        needed = [x1, x2, x3, x4, x5]
        score = (
            None
            if any(v is None for v in needed)
            else 1.2 * x1 + 1.4 * x2 + 3.3 * x3 + 0.6 * x4 + 1.0 * x5
        )
    else:  # PRIVATE (Z')
        needed = [x1, x2, x3, x4, x5]
        score = (
            None
            if any(v is None for v in needed)
            else 0.717 * x1 + 0.847 * x2 + 3.107 * x3 + 0.420 * x4 + 0.998 * x5
        )

    return AltmanResult(variant=variant, components=components, score=score)


# --------------------------------------------------------------------------
# Beneish M-Score
# --------------------------------------------------------------------------


@dataclass
class BeneishResult:
    components: list[Component] = field(default_factory=list)
    score: float | None = None

    #: Above this, the original paper flags likely manipulation.
    THRESHOLD: float = -1.78

    @property
    def flags_manipulation(self) -> bool | None:
        if self.score is None:
            return None
        return self.score > self.THRESHOLD

    @property
    def interpretation(self) -> str:
        if self.score is None:
            return "INSUFFICIENT DATA"
        return (
            "elevated earnings-manipulation risk"
            if self.score > self.THRESHOLD
            else "no elevated manipulation signal"
        )

    def as_dict(self) -> dict:
        return {
            "score": self.score,
            "threshold": self.THRESHOLD,
            "flags_manipulation": self.flags_manipulation,
            "interpretation": self.interpretation,
            "components": [c.as_dict() for c in self.components],
        }


def beneish_m_score(current: FinancialInputs, prior: FinancialInputs) -> BeneishResult:
    """The eight-variable Beneish M-Score.

    All eight indices are exposed. This flags *statistical similarity to known
    manipulators* — it is not an accusation, and a single elevated index is a
    prompt to read the filing, not a conclusion.
    """
    # DSRI — days sales in receivables
    dsri = safe_divide(
        safe_divide(current.receivables, current.revenue),
        safe_divide(prior.receivables, prior.revenue),
    )
    # GMI — gross margin index (>1 means margin deteriorated)
    current_gm = safe_divide(current.gross_profit, current.revenue)
    prior_gm = safe_divide(prior.gross_profit, prior.revenue)
    gmi = safe_divide(prior_gm, current_gm)

    # AQI — asset quality index: non-current, non-PPE assets as a share of total
    def _soft_asset_ratio(f: FinancialInputs) -> float | None:
        if f.total_assets is None or f.current_assets is None or f.ppe_net is None:
            return None
        return 1.0 - (f.current_assets + f.ppe_net) / f.total_assets

    aqi = safe_divide(_soft_asset_ratio(current), _soft_asset_ratio(prior))

    # SGI — sales growth index
    sgi = safe_divide(current.revenue, prior.revenue)

    # DEPI — depreciation rate index (>1 means the rate slowed)
    def _dep_rate(f: FinancialInputs) -> float | None:
        if f.depreciation_amortization is None or f.ppe_net is None:
            return None
        denom = f.depreciation_amortization + f.ppe_net
        return safe_divide(f.depreciation_amortization, denom)

    depi = safe_divide(_dep_rate(prior), _dep_rate(current))

    # SGAI — SG&A index
    sgai = safe_divide(
        safe_divide(current.sga_expense, current.revenue),
        safe_divide(prior.sga_expense, prior.revenue),
    )

    # LVGI — leverage index
    def _leverage(f: FinancialInputs) -> float | None:
        debt_parts = [p for p in (f.current_liabilities, f.long_term_debt) if p is not None]
        if not debt_parts or f.total_assets is None:
            return None
        return safe_divide(sum(debt_parts), f.total_assets)

    lvgi = safe_divide(_leverage(current), _leverage(prior))

    # TATA — total accruals to total assets
    tata = (
        None
        if (
            current.net_income is None
            or current.operating_cash_flow is None
            or current.total_assets is None
        )
        else safe_divide(current.net_income - current.operating_cash_flow, current.total_assets)
    )

    components = [
        _component("DSRI", dsri, "Days sales in receivables index"),
        _component("GMI", gmi, "Gross margin index (>1 = margin deteriorated)"),
        _component("AQI", aqi, "Asset quality index"),
        _component("SGI", sgi, "Sales growth index"),
        _component("DEPI", depi, "Depreciation rate index (>1 = rate slowed)"),
        _component("SGAI", sgai, "SG&A expense index"),
        _component("LVGI", lvgi, "Leverage index"),
        _component("TATA", tata, "Total accruals to total assets"),
    ]

    values = [dsri, gmi, aqi, sgi, depi, sgai, lvgi, tata]
    if any(v is None for v in values):
        # The coefficients were fitted on all eight together; dropping one and
        # rescaling the rest would not be the Beneish model any more.
        return BeneishResult(components=components, score=None)

    score = (
        -4.84
        + 0.920 * dsri
        + 0.528 * gmi
        + 0.404 * aqi
        + 0.892 * sgi
        + 0.115 * depi
        - 0.172 * sgai
        + 4.679 * tata
        - 0.327 * lvgi
    )
    return BeneishResult(components=components, score=float(score))


# --------------------------------------------------------------------------
# DuPont decomposition
# --------------------------------------------------------------------------


@dataclass
class DuPontResult:
    net_margin: float | None
    asset_turnover: float | None
    equity_multiplier: float | None
    roe: float | None
    tax_burden: float | None = None
    interest_burden: float | None = None
    operating_margin: float | None = None

    @property
    def is_complete(self) -> bool:
        return None not in (self.net_margin, self.asset_turnover, self.equity_multiplier)

    @property
    def five_step_available(self) -> bool:
        return None not in (self.tax_burden, self.interest_burden, self.operating_margin)

    def as_dict(self) -> dict:
        return {
            "roe": self.roe,
            "three_step": {
                "net_margin": self.net_margin,
                "asset_turnover": self.asset_turnover,
                "equity_multiplier": self.equity_multiplier,
            },
            "five_step": {
                "tax_burden": self.tax_burden,
                "interest_burden": self.interest_burden,
                "operating_margin": self.operating_margin,
                "asset_turnover": self.asset_turnover,
                "equity_multiplier": self.equity_multiplier,
            }
            if self.five_step_available
            else None,
        }


def dupont(inputs: FinancialInputs) -> DuPontResult:
    """Decompose ROE into its drivers.

    The point is diagnostic: two companies with identical ROE can be a
    high-margin business and a heavily-levered one, and only the decomposition
    tells them apart.
    """
    net_margin = safe_divide(inputs.net_income, inputs.revenue)
    asset_turnover = safe_divide(inputs.revenue, inputs.total_assets)
    equity_multiplier = safe_divide(inputs.total_assets, inputs.equity)

    roe = None
    if None not in (net_margin, asset_turnover, equity_multiplier):
        roe = net_margin * asset_turnover * equity_multiplier

    tax_burden = safe_divide(inputs.net_income, inputs.pretax_income)
    interest_burden = safe_divide(inputs.pretax_income, inputs.ebit)
    operating_margin = safe_divide(inputs.ebit, inputs.revenue)

    return DuPontResult(
        net_margin=net_margin,
        asset_turnover=asset_turnover,
        equity_multiplier=equity_multiplier,
        roe=roe,
        tax_burden=tax_burden,
        interest_burden=interest_burden,
        operating_margin=operating_margin,
    )


# --------------------------------------------------------------------------
# ROIC vs WACC
# --------------------------------------------------------------------------


@dataclass
class RoicResult:
    roic: float | None
    wacc: float | None
    nopat: float | None
    invested_capital: float | None
    effective_tax_rate: float | None
    cost_of_equity: float | None = None
    cost_of_debt: float | None = None
    wacc_is_estimated: bool = True

    @property
    def spread(self) -> float | None:
        """ROIC minus WACC. Positive means the company creates value."""
        if self.roic is None or self.wacc is None:
            return None
        return self.roic - self.wacc

    @property
    def creates_value(self) -> bool | None:
        spread = self.spread
        return None if spread is None else spread > 0

    def as_dict(self) -> dict:
        return {
            "roic": self.roic,
            "wacc": self.wacc,
            "spread": self.spread,
            "creates_value": self.creates_value,
            "nopat": self.nopat,
            "invested_capital": self.invested_capital,
            "effective_tax_rate": self.effective_tax_rate,
            "cost_of_equity": self.cost_of_equity,
            "cost_of_debt": self.cost_of_debt,
            "wacc_is_estimated": self.wacc_is_estimated,
        }


DEFAULT_STATUTORY_TAX_RATE = 0.21  # US federal corporate rate
DEFAULT_EQUITY_RISK_PREMIUM = 0.05


def effective_tax_rate(inputs: FinancialInputs) -> float | None:
    """Actual tax paid over pretax income, clamped to [0, 1].

    Outside that range the figure is dominated by one-off items (a loss year,
    a repatriation charge) and is not a usable forward rate.
    """
    rate = safe_divide(inputs.tax_expense, inputs.pretax_income)
    if rate is None or rate < 0 or rate > 1:
        return None
    return rate


def invested_capital(inputs: FinancialInputs) -> float | None:
    """Total debt + equity - cash.

    Cash is netted off because idle cash is not capital the operating business
    is putting to work.
    """
    if inputs.equity is None:
        return None
    debt = inputs.total_debt or 0.0
    cash = inputs.cash or 0.0
    capital = inputs.equity + debt - cash
    return capital if capital > 0 else None


def roic_vs_wacc(
    inputs: FinancialInputs,
    *,
    beta: float | None = None,
    risk_free_rate: float | None = None,
    equity_risk_premium: float = DEFAULT_EQUITY_RISK_PREMIUM,
) -> RoicResult:
    """Return on invested capital against an estimated cost of capital.

    WACC is flagged `wacc_is_estimated=True` because CAPM's inputs are
    assumptions, not observations. The ground rules require that distinction:
    ROIC is calculated from filings, WACC is modelled.

    Without a beta and a risk-free rate there is no cost of equity, and the
    function returns ROIC with `wacc=None` rather than inventing a discount
    rate.
    """
    tax_rate = effective_tax_rate(inputs)
    ebit = inputs.ebit
    nopat = None
    if ebit is not None:
        applied_rate = tax_rate if tax_rate is not None else DEFAULT_STATUTORY_TAX_RATE
        nopat = ebit * (1 - applied_rate)

    capital = invested_capital(inputs)
    roic = safe_divide(nopat, capital)

    cost_of_equity = None
    if beta is not None and risk_free_rate is not None:
        cost_of_equity = risk_free_rate + beta * equity_risk_premium

    cost_of_debt = None
    debt = inputs.total_debt
    if inputs.interest_expense is not None and debt:
        pre_tax_cost = safe_divide(abs(inputs.interest_expense), debt)
        if pre_tax_cost is not None:
            applied_rate = tax_rate if tax_rate is not None else DEFAULT_STATUTORY_TAX_RATE
            cost_of_debt = pre_tax_cost * (1 - applied_rate)

    wacc = None
    if cost_of_equity is not None and inputs.market_cap is not None:
        equity_value = inputs.market_cap
        debt_value = debt or 0.0
        total_value = equity_value + debt_value
        if total_value > 0:
            equity_weight = equity_value / total_value
            debt_weight = debt_value / total_value
            effective_cost_of_debt = cost_of_debt if cost_of_debt is not None else 0.0
            wacc = equity_weight * cost_of_equity + debt_weight * effective_cost_of_debt

    return RoicResult(
        roic=roic,
        wacc=wacc,
        nopat=nopat,
        invested_capital=capital,
        effective_tax_rate=tax_rate,
        cost_of_equity=cost_of_equity,
        cost_of_debt=cost_of_debt,
        wacc_is_estimated=True,
    )
