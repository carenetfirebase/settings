"""Fundamental models, with hand-computed expected values.

Constructed inputs are chosen so the arithmetic is checkable by eye — round
numbers, ratios that land exactly.
"""

from __future__ import annotations

import pytest

from invest.engines.fundamentals import (
    AltmanVariant,
    FinancialInputs,
    altman_z_score,
    beneish_m_score,
    dupont,
    effective_tax_rate,
    invested_capital,
    piotroski_f_score,
    roic_vs_wacc,
)

# --------------------------------------------------------------------------
# Piotroski
# --------------------------------------------------------------------------


def strong_year() -> FinancialInputs:
    return FinancialInputs(
        revenue=1000,
        gross_profit=400,
        net_income=100,
        operating_cash_flow=150,
        total_assets=1000,
        current_assets=500,
        current_liabilities=250,
        long_term_debt=100,
        shares_diluted=1000,
    )


def weaker_prior() -> FinancialInputs:
    return FinancialInputs(
        revenue=900,
        gross_profit=315,  # 35% margin vs 40% now
        net_income=50,
        operating_cash_flow=60,
        total_assets=1000,
        current_assets=400,
        current_liabilities=250,
        long_term_debt=150,
        shares_diluted=1000,
    )


def test_perfect_piotroski_scores_nine() -> None:
    result = piotroski_f_score(strong_year(), weaker_prior())
    assert result.score == 9
    assert result.available_count == 9
    assert result.missing_count == 0
    assert result.is_reliable


def test_all_nine_components_are_exposed() -> None:
    """A score is never stored without its parts."""
    result = piotroski_f_score(strong_year(), weaker_prior())
    names = {c.name for c in result.components}
    assert names == {
        "positive_roa",
        "positive_operating_cash_flow",
        "improving_roa",
        "accruals",
        "decreasing_leverage",
        "improving_current_ratio",
        "no_dilution",
        "improving_gross_margin",
        "improving_asset_turnover",
    }


def test_loss_making_company_fails_profitability_signals() -> None:
    current = FinancialInputs(
        revenue=1000,
        gross_profit=100,
        net_income=-50,
        operating_cash_flow=-20,
        total_assets=1000,
        current_assets=200,
        current_liabilities=400,
        long_term_debt=500,
        shares_diluted=1200,
    )
    result = piotroski_f_score(current, weaker_prior())
    by_name = {c.name: c.value for c in result.components}
    assert by_name["positive_roa"] == 0.0
    assert by_name["positive_operating_cash_flow"] == 0.0
    assert by_name["no_dilution"] == 0.0  # 1200 > 1000
    assert result.score <= 3


def test_accruals_signal_hand_checked() -> None:
    """CFO/assets (0.15) > NI/assets (0.10) -> earnings are cash-backed."""
    result = piotroski_f_score(strong_year(), weaker_prior())
    accruals = next(c for c in result.components if c.name == "accruals")
    assert accruals.value == 1.0


def test_accruals_signal_fails_when_earnings_outrun_cash() -> None:
    current = strong_year()
    current = FinancialInputs(**{**current.__dict__, "operating_cash_flow": 50})  # < NI of 100
    result = piotroski_f_score(current, weaker_prior())
    accruals = next(c for c in result.components if c.name == "accruals")
    assert accruals.value == 0.0


def test_missing_prior_year_marks_trend_signals_unavailable() -> None:
    """Six of the nine signals are year-over-year comparisons (improving ROA,
    leverage, current ratio, dilution, gross margin, asset turnover). Without
    a prior year they report as unavailable, and the total is explicitly
    "out of 3" rather than a quietly deflated score out of 9.
    """
    result = piotroski_f_score(strong_year(), FinancialInputs())
    assert result.missing_count == 6
    assert result.is_reliable is False
    assert result.max_possible == 3

    unavailable = [c for c in result.components if not c.available]
    assert all(c.unavailable_reason for c in unavailable)


def test_score_is_never_inflated_by_missing_data() -> None:
    """Missing components contribute zero, and are reported, not counted as
    passes.
    """
    result = piotroski_f_score(FinancialInputs(), FinancialInputs())
    assert result.score == 0
    assert result.max_possible == 0
    assert result.is_reliable is False


# --------------------------------------------------------------------------
# Altman Z
# --------------------------------------------------------------------------


def altman_inputs() -> FinancialInputs:
    return FinancialInputs(
        total_assets=1000,
        current_assets=500,
        current_liabilities=200,
        retained_earnings=300,
        operating_income=150,
        revenue=1200,
        total_liabilities=400,
        equity=600,
        market_cap=800,
    )


def test_altman_original_hand_computed() -> None:
    """X1=(500-200)/1000=0.3, X2=300/1000=0.3, X3=150/1000=0.15,
    X4=800/400=2.0, X5=1200/1000=1.2
    Z = 1.2(0.3) + 1.4(0.3) + 3.3(0.15) + 0.6(2.0) + 1.0(1.2)
      = 0.36 + 0.42 + 0.495 + 1.2 + 1.2 = 3.675
    """
    result = altman_z_score(altman_inputs())
    assert result.variant == AltmanVariant.ORIGINAL
    assert result.score == pytest.approx(3.675)
    assert result.zone == "safe"


def test_altman_private_variant_uses_book_equity() -> None:
    """X4 = 600/400 = 1.5 (book), not 800/400 = 2.0 (market)
    Z' = 0.717(0.3) + 0.847(0.3) + 3.107(0.15) + 0.420(1.5) + 0.998(1.2)
       = 0.2151 + 0.2541 + 0.46605 + 0.63 + 1.1976 = 2.76285
    """
    result = altman_z_score(altman_inputs(), use_market_value=False)
    assert result.variant == AltmanVariant.PRIVATE
    assert result.score == pytest.approx(2.76285)
    assert result.zone == "grey"


def test_altman_non_manufacturer_drops_asset_turnover() -> None:
    """Z'' = 6.56(0.3) + 3.26(0.3) + 6.72(0.15) + 1.05(1.5)
           = 1.968 + 0.978 + 1.008 + 1.575 = 5.529
    X5 is excluded entirely, so only four components are reported.
    """
    result = altman_z_score(altman_inputs(), is_manufacturer=False)
    assert result.variant == AltmanVariant.NON_MANUFACTURER
    assert result.score == pytest.approx(5.529)
    assert len(result.components) == 4
    assert result.zone == "safe"


def test_altman_is_not_applied_to_banks() -> None:
    """Applying industrial coefficients to a bank produces a precise-looking
    number that means nothing.
    """
    result = altman_z_score(altman_inputs(), is_financial=True)
    assert result.variant == AltmanVariant.NOT_APPLICABLE
    assert result.applicable is False
    assert result.score is None
    assert result.zone == "INSUFFICIENT DATA"
    assert "banks" in result.note


def test_altman_zones_hand_checked() -> None:
    distressed = FinancialInputs(
        total_assets=1000,
        current_assets=100,
        current_liabilities=400,
        retained_earnings=-200,
        operating_income=10,
        revenue=300,
        total_liabilities=900,
        market_cap=100,
    )
    result = altman_z_score(distressed)
    # X1=-0.3, X2=-0.2, X3=0.01, X4=0.1111, X5=0.3
    # Z = -0.36 - 0.28 + 0.033 + 0.0667 + 0.3 = -0.2403
    assert result.score == pytest.approx(-0.24033, abs=1e-4)
    assert result.zone == "distress"


def test_altman_missing_input_gives_no_score() -> None:
    result = altman_z_score(FinancialInputs(total_assets=1000))
    assert result.score is None
    assert result.zone == "INSUFFICIENT DATA"
    assert any(not c.available for c in result.components)


# --------------------------------------------------------------------------
# Beneish
# --------------------------------------------------------------------------


def beneish_pair() -> tuple[FinancialInputs, FinancialInputs]:
    """Constructed so every index is exactly 1.0 (no change year over year)
    except the ones driven by accruals, which are zero.
    """
    common = {
        "revenue": 1000,
        "gross_profit": 400,
        "receivables": 100,
        "total_assets": 2000,
        "current_assets": 800,
        "ppe_net": 1000,
        "depreciation_amortization": 100,
        "sga_expense": 200,
        "current_liabilities": 300,
        "long_term_debt": 500,
        "net_income": 100,
        "operating_cash_flow": 100,
    }
    return FinancialInputs(**common), FinancialInputs(**common)


def test_beneish_all_indices_equal_one_when_nothing_changes() -> None:
    current, prior = beneish_pair()
    result = beneish_m_score(current, prior)
    by_name = {c.name: c.value for c in result.components}

    for index in ("DSRI", "GMI", "AQI", "SGI", "DEPI", "SGAI", "LVGI"):
        assert by_name[index] == pytest.approx(1.0), index
    assert by_name["TATA"] == pytest.approx(0.0)  # NI == CFO


def test_beneish_score_hand_computed() -> None:
    """With seven indices at 1.0 and TATA at 0:
    M = -4.84 + 0.920 + 0.528 + 0.404 + 0.892 + 0.115 - 0.172 + 0 - 0.327
      = -2.48
    """
    current, prior = beneish_pair()
    result = beneish_m_score(current, prior)
    assert result.score == pytest.approx(-2.48)
    assert result.flags_manipulation is False
    assert "no elevated" in result.interpretation


def test_all_eight_components_are_exposed() -> None:
    current, prior = beneish_pair()
    result = beneish_m_score(current, prior)
    assert {c.name for c in result.components} == {
        "DSRI",
        "GMI",
        "AQI",
        "SGI",
        "DEPI",
        "SGAI",
        "LVGI",
        "TATA",
    }


def test_beneish_flags_receivables_outrunning_sales() -> None:
    """Receivables tripling while sales are flat is the classic signature."""
    current, prior = beneish_pair()
    current = FinancialInputs(**{**current.__dict__, "receivables": 300})
    result = beneish_m_score(current, prior)
    dsri = next(c for c in result.components if c.name == "DSRI")
    assert dsri.value == pytest.approx(3.0)
    assert result.score > -2.48  # pushed upward


def test_beneish_flags_large_positive_accruals() -> None:
    """Net income far above operating cash flow carries the heaviest weight
    in the model (4.679).
    """
    current, prior = beneish_pair()
    current = FinancialInputs(**{**current.__dict__, "operating_cash_flow": -300})
    result = beneish_m_score(current, prior)
    tata = next(c for c in result.components if c.name == "TATA")
    assert tata.value == pytest.approx(0.2)  # (100 - -300)/2000
    assert result.flags_manipulation is True


def test_beneish_refuses_to_score_with_a_missing_index() -> None:
    """The coefficients were fitted on all eight together — dropping one and
    rescaling the rest would not be the Beneish model.
    """
    current, prior = beneish_pair()
    current = FinancialInputs(**{**current.__dict__, "sga_expense": None})
    result = beneish_m_score(current, prior)
    assert result.score is None
    assert result.flags_manipulation is None
    assert result.interpretation == "INSUFFICIENT DATA"
    # Components that could be computed are still shown.
    assert any(c.available for c in result.components)


# --------------------------------------------------------------------------
# DuPont
# --------------------------------------------------------------------------


def test_dupont_hand_computed() -> None:
    """net margin 100/1000 = 0.10
    asset turnover 1000/2000 = 0.50
    equity multiplier 2000/500 = 4.0
    ROE = 0.10 * 0.50 * 4.0 = 0.20
    """
    result = dupont(
        FinancialInputs(revenue=1000, net_income=100, total_assets=2000, equity=500)
    )
    assert result.net_margin == pytest.approx(0.10)
    assert result.asset_turnover == pytest.approx(0.50)
    assert result.equity_multiplier == pytest.approx(4.0)
    assert result.roe == pytest.approx(0.20)
    assert result.is_complete


def test_dupont_roe_matches_direct_calculation() -> None:
    inputs = FinancialInputs(revenue=1000, net_income=100, total_assets=2000, equity=500)
    assert dupont(inputs).roe == pytest.approx(inputs.net_income / inputs.equity)


def test_dupont_distinguishes_margin_from_leverage() -> None:
    """Two companies, same ROE, completely different businesses."""
    high_margin = dupont(
        FinancialInputs(revenue=1000, net_income=200, total_assets=1000, equity=1000)
    )
    levered = dupont(
        FinancialInputs(revenue=1000, net_income=50, total_assets=1000, equity=250)
    )
    assert high_margin.roe == pytest.approx(0.20)
    assert levered.roe == pytest.approx(0.20)
    assert high_margin.net_margin > levered.net_margin
    assert levered.equity_multiplier > high_margin.equity_multiplier


def test_dupont_five_step_hand_computed() -> None:
    """tax burden 100/125 = 0.8, interest burden 125/150 = 0.8333,
    operating margin 150/1000 = 0.15
    """
    result = dupont(
        FinancialInputs(
            revenue=1000,
            net_income=100,
            pretax_income=125,
            operating_income=150,
            total_assets=2000,
            equity=500,
        )
    )
    assert result.tax_burden == pytest.approx(0.80)
    assert result.interest_burden == pytest.approx(125 / 150)
    assert result.operating_margin == pytest.approx(0.15)
    assert result.five_step_available


def test_dupont_with_no_equity_reports_none() -> None:
    result = dupont(FinancialInputs(revenue=1000, net_income=100, total_assets=2000, equity=0))
    assert result.equity_multiplier is None
    assert result.roe is None
    assert result.is_complete is False


# --------------------------------------------------------------------------
# ROIC vs WACC
# --------------------------------------------------------------------------


def test_effective_tax_rate_hand_computed() -> None:
    assert effective_tax_rate(FinancialInputs(tax_expense=21, pretax_income=100)) == pytest.approx(
        0.21
    )


def test_effective_tax_rate_rejects_nonsense_ranges() -> None:
    """A loss year or a repatriation charge produces a rate that is not a
    usable forward assumption.
    """
    assert effective_tax_rate(FinancialInputs(tax_expense=50, pretax_income=-100)) is None
    assert effective_tax_rate(FinancialInputs(tax_expense=200, pretax_income=100)) is None


def test_invested_capital_nets_off_cash() -> None:
    """Idle cash is not capital the operating business is putting to work."""
    result = invested_capital(
        FinancialInputs(equity=1000, long_term_debt=500, current_debt=100, cash=200)
    )
    assert result == pytest.approx(1400)  # 1000 + 600 - 200


def test_roic_hand_computed() -> None:
    """EBIT 200, tax rate 25% -> NOPAT 150
    invested capital = 600 equity + 400 debt - 0 cash = 1000
    ROIC = 150/1000 = 0.15
    """
    result = roic_vs_wacc(
        FinancialInputs(
            operating_income=200,
            pretax_income=200,
            tax_expense=50,
            equity=600,
            long_term_debt=400,
            cash=0,
        )
    )
    assert result.effective_tax_rate == pytest.approx(0.25)
    assert result.nopat == pytest.approx(150)
    assert result.invested_capital == pytest.approx(1000)
    assert result.roic == pytest.approx(0.15)


def test_wacc_hand_computed() -> None:
    """cost of equity = 4% + 1.2 * 5% = 10%
    cost of debt = (40/400) * (1 - 0.25) = 7.5%
    weights: equity 600/(600+400) = 0.6, debt 0.4
    WACC = 0.6*0.10 + 0.4*0.075 = 0.06 + 0.03 = 0.09
    """
    result = roic_vs_wacc(
        FinancialInputs(
            operating_income=200,
            pretax_income=200,
            tax_expense=50,
            equity=600,
            long_term_debt=400,
            interest_expense=40,
            market_cap=600,
            cash=0,
        ),
        beta=1.2,
        risk_free_rate=0.04,
    )
    assert result.cost_of_equity == pytest.approx(0.10)
    assert result.cost_of_debt == pytest.approx(0.075)
    assert result.wacc == pytest.approx(0.09)


def test_value_creation_spread_hand_checked() -> None:
    result = roic_vs_wacc(
        FinancialInputs(
            operating_income=200,
            pretax_income=200,
            tax_expense=50,
            equity=600,
            long_term_debt=400,
            interest_expense=40,
            market_cap=600,
            cash=0,
        ),
        beta=1.2,
        risk_free_rate=0.04,
    )
    assert result.spread == pytest.approx(0.15 - 0.09)
    assert result.creates_value is True


def test_wacc_is_always_labelled_estimated() -> None:
    """Ground rule 7: ROIC is calculated from filings, WACC is modelled from
    assumptions, and the two must not be presented as the same kind of thing.
    """
    result = roic_vs_wacc(FinancialInputs(operating_income=200, equity=600))
    assert result.wacc_is_estimated is True


def test_no_wacc_without_beta_and_risk_free_rate() -> None:
    """Rather than inventing a discount rate."""
    result = roic_vs_wacc(
        FinancialInputs(operating_income=200, equity=600, long_term_debt=400, market_cap=600)
    )
    assert result.wacc is None
    assert result.spread is None
    assert result.creates_value is None
    assert result.roic is not None  # ROIC is still computable


def test_negative_invested_capital_is_rejected() -> None:
    """Cash exceeding equity plus debt makes the ratio meaningless."""
    assert invested_capital(FinancialInputs(equity=100, long_term_debt=0, cash=500)) is None
