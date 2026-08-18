"""Transaction cost model.

A backtest without costs is a plot of a number that was never available to
anyone. Three components, all modelled explicitly:

* **Commission** — per trade, and near zero at retail brokers now. The least
  important of the three, and the one most backtests bother to include.
* **Bid/ask spread** — you buy at the ask and sell at the bid. On a liquid
  large cap this is a couple of basis points; on anything smaller it is the
  dominant cost. V1 has no quote data, so this is an ASSUMPTION, flagged as
  such, and the default is deliberately conservative.
* **Slippage** — the market moves between the decision and the fill. Modelled
  as a fraction of the day's range where ATR is available, otherwise a flat
  assumption.

Every figure here is `estimated`, never `observed`. Real fill data would come
from a broker, and this platform has none.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class CostModel:
    """Assumptions about what trading actually costs.

    Defaults are deliberately pessimistic. A backtest that flatters itself is
    worse than no backtest, because it invites real money.
    """

    #: Flat commission per trade, in currency units.
    commission_per_trade: float = 0.0

    #: Commission as a fraction of notional (some brokers, most non-US).
    commission_bps: float = 0.0

    #: Half-spread as a fraction of price. 5bp round trip on a liquid large
    #: cap is realistic; the default assumes you cross the full spread.
    half_spread_bps: float = 2.5

    #: Slippage as a fraction of price, applied on top of the spread.
    slippage_bps: float = 5.0

    #: Minimum cost per trade, so tiny trades are not modelled as free.
    minimum_cost: float = 0.0

    def __post_init__(self) -> None:
        for name in ("commission_per_trade", "commission_bps", "half_spread_bps",
                     "slippage_bps", "minimum_cost"):
            if getattr(self, name) < 0:
                raise ValueError(f"{name} may not be negative")

    @property
    def round_trip_bps(self) -> float:
        """Total friction on a buy followed by a sell, in basis points."""
        return 2 * (self.half_spread_bps + self.slippage_bps) + 2 * self.commission_bps

    def fill_price(self, mid_price: float, *, is_buy: bool) -> float:
        """The price actually paid or received.

        Buys fill above the mid, sells below it. Never the other way round —
        a backtest that fills at the mid is claiming a free half-spread on
        every trade.
        """
        friction = (self.half_spread_bps + self.slippage_bps) / 10_000.0
        return mid_price * (1 + friction) if is_buy else mid_price * (1 - friction)

    def commission(self, notional: float) -> float:
        cost = self.commission_per_trade + abs(notional) * self.commission_bps / 10_000.0
        return max(cost, self.minimum_cost)

    def total_cost(self, mid_price: float, shares: float, *, is_buy: bool) -> float:
        """Full cost of one trade versus a frictionless mid fill."""
        fill = self.fill_price(mid_price, is_buy=is_buy)
        spread_cost = abs(fill - mid_price) * abs(shares)
        return spread_cost + self.commission(mid_price * abs(shares))

    def as_dict(self) -> dict:
        return {
            "commission_per_trade": self.commission_per_trade,
            "commission_bps": self.commission_bps,
            "half_spread_bps": self.half_spread_bps,
            "slippage_bps": self.slippage_bps,
            "minimum_cost": self.minimum_cost,
            "round_trip_bps": self.round_trip_bps,
            "value_type": "estimated",
            "note": (
                "Spread and slippage are ASSUMPTIONS. V1 has no quote or fill "
                "data, so real costs are unknown and these defaults are "
                "deliberately pessimistic."
            ),
        }


#: A liquid US large cap at a zero-commission retail broker.
LIQUID_LARGE_CAP = CostModel(
    commission_per_trade=0.0, half_spread_bps=1.0, slippage_bps=2.0
)

#: The default: conservative enough not to flatter a marginal strategy.
DEFAULT_COSTS = CostModel()

#: Anything less liquid. Spread dominates.
ILLIQUID = CostModel(commission_per_trade=0.0, half_spread_bps=15.0, slippage_bps=20.0)


@dataclass
class CostReport:
    """Where the money went. Printed with every backtest, because 'the
    strategy works before costs' is not a finding.
    """

    commission_paid: float = 0.0
    spread_paid: float = 0.0
    trade_count: int = 0
    notional_traded: float = 0.0
    details: list[dict] = field(default_factory=list)

    @property
    def total_cost(self) -> float:
        return self.commission_paid + self.spread_paid

    @property
    def cost_per_trade(self) -> float | None:
        return self.total_cost / self.trade_count if self.trade_count else None

    @property
    def cost_as_bps_of_notional(self) -> float | None:
        if self.notional_traded == 0:
            return None
        return self.total_cost / self.notional_traded * 10_000.0

    def record(self, *, commission: float, spread: float, notional: float) -> None:
        self.commission_paid += commission
        self.spread_paid += spread
        self.notional_traded += abs(notional)
        self.trade_count += 1

    def as_dict(self) -> dict:
        return {
            "total_cost": self.total_cost,
            "commission_paid": self.commission_paid,
            "spread_paid": self.spread_paid,
            "trade_count": self.trade_count,
            "notional_traded": self.notional_traded,
            "cost_per_trade": self.cost_per_trade,
            "cost_as_bps_of_notional": self.cost_as_bps_of_notional,
        }
