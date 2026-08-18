"""Valuation engine tests with hand-computed expected values.

The DCF cases use round assumptions so the discounting arithmetic can be
checked with a calculator.
"""

from __future__ import annotations

import pytest

from invest.engines.valuation import (
    DcfAssumptions,
    Scenario,
    comparables,
    compute_multiples,
    discounted_cash_flow,
    reverse_dcf,
    scenario_dcf,
    sensitivity_table,
)


def base_assumptions(**overrides) -> DcfAssumptions:
    defaults = {
        "growth_rate": 0.10,
        "terminal_growth_rate": 0.025,
        "discount_rate": 0.09,
        "forecast_years": 10,
    }
    defaults.update(overrides)
    return DcfAssumptions(**defaults)


# --------------------------------------------------------------------------
# Assumption guards
# --------------------------------------------------------------------------


def test_discount_rate_must_exceed_terminal_growth() -> None:
    """Otherwise the Gordon denominator (r - g) goes to zero and the model
    returns an enormous number that looks like a result.
    """
    with pytest.raises(ValueError, match="must exceed terminal_growth_rate"):
        DcfAssumptions(growth_rate=0.10, terminal_growth_rate=0.09, discount_rate=0.09)
    with pytest.raises(ValueError, match="must exceed terminal_growth_rate"):
        DcfAssumptions(growth_rate=0.10, terminal_growth_rate=0.12, discount_rate=0.09)


def test_terminal_growth_above_five_percent_is_rejected() -> None:
    """A company growing forever at 6% eventually outgrows the economy."""
    with pytest.raises(ValueError, match="outgrows the whole economy"):
        DcfAssumptions(growth_rate=0.10, terminal_growth_rate=0.06, discount_rate=0.12)


def test_forecast_years_must_be_positive() -> None:
    with pytest.raises(ValueError, match="forecast_years"):
        DcfAssumptions(
            growth_rate=0.10, terminal_growth_rate=0.02, discount_rate=0.09, forecast_years=0
        )


def test_margin_of_safety_bounds() -> None:
    with pytest.raises(ValueError, match="margin_of_safety"):
        DcfAssumptions(
            growth_rate=0.10,
            terminal_growth_rate=0.02,
            discount_rate=0.09,
            margin_of_safety=1.0,
        )


# --------------------------------------------------------------------------
# DCF arithmetic
# --------------------------------------------------------------------------


def test_single_year_dcf_hand_computed() -> None:
    """FCF 100, growth 0%, discount 10%, 1 year, terminal growth 0%.

    Year 1 CF     = 100
    Discounted    = 100 / 1.10           = 90.909091
    Terminal      = 100 * 1.0 / 0.10     = 1000
    Disc terminal = 1000 / 1.10          = 909.090909
    EV            = 90.909091 + 909.090909 = 1000.0
    """
    assumptions = DcfAssumptions(
        growth_rate=0.0, terminal_growth_rate=0.0, discount_rate=0.10, forecast_years=1
    )
    result = discounted_cash_flow(base_free_cash_flow=100, assumptions=assumptions)

    assert result.projected_cash_flows == pytest.approx([100.0])
    assert result.discounted_cash_flows == pytest.approx([90.909091], rel=1e-6)
    assert result.terminal_value == pytest.approx(1000.0)
    assert result.discounted_terminal_value == pytest.approx(909.090909, rel=1e-6)
    assert result.enterprise_value == pytest.approx(1000.0, rel=1e-9)


def test_perpetuity_identity() -> None:
    """A no-growth perpetuity of C discounted at r is worth exactly C/r,
    regardless of how many explicit forecast years are used first.
    """
    for years in (1, 5, 10, 30):
        assumptions = DcfAssumptions(
            growth_rate=0.0,
            terminal_growth_rate=0.0,
            discount_rate=0.10,
            forecast_years=years,
        )
        result = discounted_cash_flow(base_free_cash_flow=50, assumptions=assumptions)
        assert result.enterprise_value == pytest.approx(500.0, rel=1e-9)


def test_growth_projection_hand_computed() -> None:
    """FCF 100 growing 10%: years 1-3 are 110, 121, 133.1"""
    assumptions = DcfAssumptions(
        growth_rate=0.10, terminal_growth_rate=0.02, discount_rate=0.10, forecast_years=3
    )
    result = discounted_cash_flow(base_free_cash_flow=100, assumptions=assumptions)
    assert result.projected_cash_flows == pytest.approx([110.0, 121.0, 133.1])
    # Discounting at exactly the growth rate gives 100 back each year.
    assert result.discounted_cash_flows == pytest.approx([100.0, 100.0, 100.0])


def test_equity_value_subtracts_net_debt() -> None:
    assumptions = DcfAssumptions(
        growth_rate=0.0, terminal_growth_rate=0.0, discount_rate=0.10, forecast_years=1
    )
    result = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=assumptions, shares_outstanding=10, net_debt=200
    )
    assert result.enterprise_value == pytest.approx(1000.0)
    assert result.equity_value == pytest.approx(800.0)
    assert result.fair_value_per_share == pytest.approx(80.0)


def test_net_cash_increases_equity_value() -> None:
    """Negative net debt is net cash and must add to equity value."""
    assumptions = DcfAssumptions(
        growth_rate=0.0, terminal_growth_rate=0.0, discount_rate=0.10, forecast_years=1
    )
    result = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=assumptions, shares_outstanding=10, net_debt=-200
    )
    assert result.equity_value == pytest.approx(1200.0)
    assert result.fair_value_per_share == pytest.approx(120.0)


def test_margin_of_safety_hand_computed() -> None:
    assumptions = DcfAssumptions(
        growth_rate=0.0,
        terminal_growth_rate=0.0,
        discount_rate=0.10,
        forecast_years=1,
        margin_of_safety=0.30,
    )
    result = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=assumptions, shares_outstanding=10
    )
    assert result.fair_value_per_share == pytest.approx(100.0)
    assert result.fair_value_with_margin == pytest.approx(70.0)


def test_upside_hand_computed() -> None:
    assumptions = DcfAssumptions(
        growth_rate=0.0, terminal_growth_rate=0.0, discount_rate=0.10, forecast_years=1
    )
    result = discounted_cash_flow(
        base_free_cash_flow=100,
        assumptions=assumptions,
        shares_outstanding=10,
        current_price=80,
    )
    # Fair value 100 vs price 80 -> +25%
    assert result.upside == pytest.approx(0.25)


def test_terminal_value_share_is_reported() -> None:
    """The single most important honesty check on a DCF."""
    result = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=base_assumptions(), shares_outstanding=10
    )
    share = result.terminal_value_share
    assert 0.0 < share < 1.0
    # A 10-year forecast with a 2.5% perpetuity puts most value in the tail.
    assert share > 0.5


def test_negative_cash_flow_returns_insufficient_data() -> None:
    """Growing a negative cash flow produces a confident-looking number with
    no economic meaning.
    """
    result = discounted_cash_flow(
        base_free_cash_flow=-50, assumptions=base_assumptions(), shares_outstanding=10
    )
    assert result.fair_value_per_share is None
    assert result.is_valid is False
    assert "not positive" in result.insufficient_data_reason


def test_missing_cash_flow_returns_insufficient_data() -> None:
    result = discounted_cash_flow(base_free_cash_flow=None, assumptions=base_assumptions())
    assert result.is_valid is False
    assert "unavailable" in result.insufficient_data_reason


def test_missing_share_count_still_reports_enterprise_value() -> None:
    result = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=base_assumptions(), shares_outstanding=None
    )
    assert result.enterprise_value is not None
    assert result.fair_value_per_share is None
    assert "share count" in result.insufficient_data_reason


def test_result_is_labelled_estimated() -> None:
    """Ground rule 7: a DCF is an estimate, not an observation."""
    result = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=base_assumptions(), shares_outstanding=10
    )
    assert result.as_dict()["value_type"] == "estimated"


def test_assumptions_are_recorded_with_the_result() -> None:
    """A valuation whose assumptions are not recorded cannot be argued with."""
    result = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=base_assumptions(), shares_outstanding=10
    )
    recorded = result.as_dict()["assumptions"]
    assert recorded["growth_rate"] == 0.10
    assert recorded["discount_rate"] == 0.09
    assert recorded["terminal_growth_rate"] == 0.025
    assert recorded["forecast_years"] == 10


# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------


def test_scenarios_are_ordered_bear_base_bull() -> None:
    scenarios = scenario_dcf(
        base_free_cash_flow=100,
        base_assumptions=base_assumptions(),
        shares_outstanding=10,
    )
    assert scenarios.bear.fair_value_per_share < scenarios.base.fair_value_per_share
    assert scenarios.base.fair_value_per_share < scenarios.bull.fair_value_per_share


def test_scenarios_vary_growth_and_discount_rate_together() -> None:
    """A pessimistic future arrives with a higher required return, not just
    slower growth.
    """
    scenarios = scenario_dcf(
        base_free_cash_flow=100,
        base_assumptions=base_assumptions(),
        shares_outstanding=10,
    )
    assert scenarios.bear.assumptions.growth_rate < scenarios.base.assumptions.growth_rate
    assert scenarios.bear.assumptions.discount_rate > scenarios.base.assumptions.discount_rate
    assert scenarios.bull.assumptions.discount_rate < scenarios.base.assumptions.discount_rate


def test_fair_value_range_spans_bear_to_bull() -> None:
    scenarios = scenario_dcf(
        base_free_cash_flow=100,
        base_assumptions=base_assumptions(),
        shares_outstanding=10,
    )
    low, high = scenarios.fair_value_range
    assert low == pytest.approx(scenarios.bear.fair_value_per_share)
    assert high == pytest.approx(scenarios.bull.fair_value_per_share)


def test_scenario_enum_values() -> None:
    assert Scenario.BEAR == "bear"
    assert Scenario.BASE == "base"
    assert Scenario.BULL == "bull"


# --------------------------------------------------------------------------
# Reverse DCF
# --------------------------------------------------------------------------


def test_reverse_dcf_recovers_the_growth_rate_it_was_given() -> None:
    """Round trip: value at 12% growth, then solve for the implied growth of
    that price. Must come back to 12%.
    """
    assumptions = DcfAssumptions(
        growth_rate=0.12, terminal_growth_rate=0.025, discount_rate=0.09, forecast_years=10
    )
    forward = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=assumptions, shares_outstanding=10
    )

    reverse = reverse_dcf(
        market_price=forward.fair_value_per_share,
        base_free_cash_flow=100,
        shares_outstanding=10,
        discount_rate=0.09,
        terminal_growth_rate=0.025,
        forecast_years=10,
    )
    assert reverse.converged
    assert reverse.implied_growth_rate == pytest.approx(0.12, abs=1e-4)


def test_reverse_dcf_round_trips_with_net_debt() -> None:
    assumptions = DcfAssumptions(
        growth_rate=0.06, terminal_growth_rate=0.02, discount_rate=0.08, forecast_years=10
    )
    forward = discounted_cash_flow(
        base_free_cash_flow=250,
        assumptions=assumptions,
        shares_outstanding=40,
        net_debt=500,
    )
    reverse = reverse_dcf(
        market_price=forward.fair_value_per_share,
        base_free_cash_flow=250,
        shares_outstanding=40,
        discount_rate=0.08,
        terminal_growth_rate=0.02,
        forecast_years=10,
        net_debt=500,
    )
    assert reverse.implied_growth_rate == pytest.approx(0.06, abs=1e-4)


def test_higher_price_implies_higher_growth() -> None:
    def implied(price: float) -> float:
        return reverse_dcf(
            market_price=price,
            base_free_cash_flow=100,
            shares_outstanding=10,
            discount_rate=0.09,
        ).implied_growth_rate

    assert implied(400) < implied(600)


def test_reverse_dcf_reports_when_price_is_unreachable() -> None:
    """An extreme price cannot be justified by any growth rate in the bracket,
    and saying so is more useful than clamping to the boundary.
    """
    result = reverse_dcf(
        market_price=10_000_000,
        base_free_cash_flow=100,
        shares_outstanding=10,
        discount_rate=0.09,
    )
    assert result.implied_growth_rate is None
    assert "outside the achievable valuation range" in result.insufficient_data_reason


def test_reverse_dcf_requires_positive_inputs() -> None:
    assert reverse_dcf(
        market_price=None, base_free_cash_flow=100, shares_outstanding=10, discount_rate=0.09
    ).implied_growth_rate is None
    assert reverse_dcf(
        market_price=50, base_free_cash_flow=-100, shares_outstanding=10, discount_rate=0.09
    ).implied_growth_rate is None
    assert reverse_dcf(
        market_price=50, base_free_cash_flow=100, shares_outstanding=0, discount_rate=0.09
    ).implied_growth_rate is None


def test_reverse_dcf_interpretation_compares_to_history() -> None:
    assumptions = DcfAssumptions(
        growth_rate=0.15, terminal_growth_rate=0.025, discount_rate=0.09, forecast_years=10
    )
    forward = discounted_cash_flow(
        base_free_cash_flow=100, assumptions=assumptions, shares_outstanding=10
    )
    reverse = reverse_dcf(
        market_price=forward.fair_value_per_share,
        base_free_cash_flow=100,
        shares_outstanding=10,
        discount_rate=0.09,
    )
    text = reverse.interpretation(historical_growth=0.05)
    assert "acceleration" in text

    text_easy = reverse.interpretation(historical_growth=0.25)
    assert "does not require" in text_easy


def test_reverse_dcf_is_labelled_calculated_not_estimated() -> None:
    """The price is an observation, so the implied growth is a calculation
    from it — unlike a forward DCF, which rests on chosen assumptions.
    """
    result = reverse_dcf(
        market_price=500, base_free_cash_flow=100, shares_outstanding=10, discount_rate=0.09
    )
    assert result.as_dict()["value_type"] == "calculated"


# --------------------------------------------------------------------------
# Sensitivity
# --------------------------------------------------------------------------


def test_sensitivity_table_shape() -> None:
    table = sensitivity_table(
        base_free_cash_flow=100,
        base_assumptions=base_assumptions(),
        shares_outstanding=10,
    )
    assert len(table.discount_rates) == 5
    assert len(table.growth_rates) == 5
    assert len(table.values) == 5
    assert all(len(row) == 5 for row in table.values)


def test_sensitivity_value_rises_with_growth_and_falls_with_discount_rate() -> None:
    table = sensitivity_table(
        base_free_cash_flow=100,
        base_assumptions=base_assumptions(),
        shares_outstanding=10,
    )
    first_row = [v for v in table.values[0] if v is not None]
    assert first_row == sorted(first_row)  # increasing in growth

    column = [row[2] for row in table.values if row[2] is not None]
    assert column == sorted(column, reverse=True)  # decreasing in discount rate


def test_invalid_grid_cells_are_holes_not_zeros() -> None:
    """Where the discount rate drops to or below terminal growth, the cell is
    None. A zero there would read as 'worthless'.
    """
    table = sensitivity_table(
        base_free_cash_flow=100,
        base_assumptions=base_assumptions(discount_rate=0.03, terminal_growth_rate=0.025),
        shares_outstanding=10,
        discount_deltas=(-0.02, 0.0, 0.02),
    )
    assert table.values[0][0] is None


def test_sensitivity_range_shows_the_spread() -> None:
    table = sensitivity_table(
        base_free_cash_flow=100,
        base_assumptions=base_assumptions(),
        shares_outstanding=10,
    )
    low, high = table.value_range
    assert high > low * 1.5  # the choice of assumptions dominates the answer


# --------------------------------------------------------------------------
# Comparables
# --------------------------------------------------------------------------


def test_multiples_hand_computed() -> None:
    multiples = compute_multiples(
        market_cap=1000,
        net_income=50,
        revenue=500,
        book_value=250,
        free_cash_flow=40,
        ebitda=100,
        net_debt=200,
    )
    assert multiples["pe"] == pytest.approx(20.0)  # 1000/50
    assert multiples["ps"] == pytest.approx(2.0)  # 1000/500
    assert multiples["pb"] == pytest.approx(4.0)  # 1000/250
    assert multiples["p_fcf"] == pytest.approx(25.0)  # 1000/40
    assert multiples["ev_ebitda"] == pytest.approx(12.0)  # (1000+200)/100
    assert multiples["ev_sales"] == pytest.approx(2.4)  # 1200/500
    assert multiples["fcf_yield"] == pytest.approx(0.04)
    assert multiples["earnings_yield"] == pytest.approx(0.05)


def test_negative_earnings_give_no_pe_rather_than_a_negative_one() -> None:
    """-15x is not 'cheap'; it is undefined. A negative P/E would sort to the
    top of a 'cheapest' ranking.
    """
    multiples = compute_multiples(market_cap=1000, net_income=-50, revenue=500)
    assert multiples["pe"] is None
    assert multiples["ps"] == pytest.approx(2.0)  # sales multiple still valid
    assert multiples["earnings_yield"] == pytest.approx(-0.05)  # yield may be negative


def test_missing_inputs_give_none_multiples() -> None:
    multiples = compute_multiples(market_cap=1000)
    assert multiples["pe"] is None
    assert multiples["pb"] is None
    assert multiples["ev_ebitda"] is None


def test_comparables_use_median_not_mean() -> None:
    """One peer at 300x would drag a mean into uselessness."""
    subject = {"pe": 20.0}
    peers = [{"pe": 15.0}, {"pe": 18.0}, {"pe": 21.0}, {"pe": 300.0}]
    result = comparables(subject, peers)
    assert result.peer_medians["pe"] == pytest.approx(19.5)  # (18+21)/2


def test_premium_discount_hand_computed() -> None:
    result = comparables({"pe": 30.0}, [{"pe": 20.0}, {"pe": 20.0}, {"pe": 20.0}])
    assert result.peer_medians["pe"] == pytest.approx(20.0)
    assert result.premium_discount["pe"] == pytest.approx(0.50)  # 50% premium


def test_comparables_flag_thin_peer_groups() -> None:
    """A median over two peers is an anecdote, not a benchmark."""
    result = comparables({"pe": 20.0}, [{"pe": 18.0}, {"pe": 22.0}])
    assert result.peer_count == 2
    assert "not a reliable peer benchmark" in result.note


def test_comparables_ignore_peers_missing_that_multiple() -> None:
    result = comparables({"pe": 20.0}, [{"pe": 10.0}, {"pe": None}, {"pe": 30.0}])
    assert result.peer_medians["pe"] == pytest.approx(20.0)  # median of 10 and 30


def test_comparables_with_no_usable_peers_returns_none() -> None:
    result = comparables({"pe": 20.0}, [{"pe": None}, {"pe": None}])
    assert result.peer_medians["pe"] is None
    assert result.premium_discount["pe"] is None
