"""The starting research universe.

These rows are a **bootstrap**, not an authority. CIKs are seeded so the
platform is usable offline, but every one is written with
`data_quality_flag='unverified_bootstrap'` until it has been confirmed against
SEC EDGAR's own `company_tickers.json` (see `invest universe verify`). A wrong
CIK would silently attach one company's financials to another company's price
history, so the seed is treated as a claim to be checked rather than a fact.

`is_financial` marks banks and insurers, whose balance sheets make the standard
Altman Z-score inapplicable — it selects the model variant in step 6.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class SeedEntry:
    ticker: str
    name: str
    cik: str  # 10-digit zero-padded
    exchange: str
    sector: str
    is_financial: bool = False

    @property
    def stooq_symbol(self) -> str:
        """Stooq addresses US listings as `<ticker>.us`, lowercased."""
        return f"{self.ticker.lower()}.us"


SEED_UNIVERSE: tuple[SeedEntry, ...] = (
    SeedEntry("AAPL", "Apple Inc.", "0000320193", "NASDAQ", "Information Technology"),
    SeedEntry("MSFT", "Microsoft Corporation", "0000789019", "NASDAQ", "Information Technology"),
    SeedEntry("NVDA", "NVIDIA Corporation", "0001045810", "NASDAQ", "Information Technology"),
    SeedEntry("CSCO", "Cisco Systems, Inc.", "0000858877", "NASDAQ", "Information Technology"),
    SeedEntry("AMZN", "Amazon.com, Inc.", "0001018724", "NASDAQ", "Consumer Discretionary"),
    SeedEntry("TSLA", "Tesla, Inc.", "0001318605", "NASDAQ", "Consumer Discretionary"),
    SeedEntry("HD", "The Home Depot, Inc.", "0000354950", "NYSE", "Consumer Discretionary"),
    SeedEntry("GOOGL", "Alphabet Inc.", "0001652044", "NASDAQ", "Communication Services"),
    SeedEntry("META", "Meta Platforms, Inc.", "0001326801", "NASDAQ", "Communication Services"),
    SeedEntry("JPM", "JPMorgan Chase & Co.", "0000019617", "NYSE", "Financials", True),
    SeedEntry("BAC", "Bank of America Corporation", "0000070858", "NYSE", "Financials", True),
    SeedEntry("V", "Visa Inc.", "0001403161", "NYSE", "Financials"),
    SeedEntry("JNJ", "Johnson & Johnson", "0000200406", "NYSE", "Health Care"),
    SeedEntry("UNH", "UnitedHealth Group Incorporated", "0000731766", "NYSE", "Health Care"),
    SeedEntry("MRK", "Merck & Co., Inc.", "0000310158", "NYSE", "Health Care"),
    SeedEntry("PFE", "Pfizer Inc.", "0000078003", "NYSE", "Health Care"),
    SeedEntry("XOM", "Exxon Mobil Corporation", "0000034088", "NYSE", "Energy"),
    SeedEntry("CVX", "Chevron Corporation", "0000093410", "NYSE", "Energy"),
    SeedEntry("PG", "The Procter & Gamble Company", "0000080424", "NYSE", "Consumer Staples"),
    SeedEntry("KO", "The Coca-Cola Company", "0000021344", "NYSE", "Consumer Staples"),
    SeedEntry("WMT", "Walmart Inc.", "0000104169", "NYSE", "Consumer Staples"),
)


@dataclass(frozen=True)
class FundSeed:
    """An exchange-traded fund the signal engine reads.

    Funds carry no CIK here: they are not operating companies, have no XBRL
    financials, and are identified by ticker alone. The benchmark fund is the
    trend-gate instrument; sector funds carry the stock sector they stand for,
    spelled exactly as in `SEED_UNIVERSE`, so a stock can be matched to its
    sector's relative strength.
    """

    ticker: str
    name: str
    exchange: str
    #: "benchmark" (the S&P 500 proxy the trend gate reads) or "sector".
    role: str
    sector: str | None = None

    @property
    def stooq_symbol(self) -> str:
        return f"{self.ticker.lower()}.us"


#: The tradable S&P 500 proxy. The trend gate reads its month-end closes.
BENCHMARK_FUND = "SPY"

FUND_UNIVERSE: tuple[FundSeed, ...] = (
    FundSeed("SPY", "SPDR S&P 500 ETF Trust", "NYSEARCA", "benchmark"),
    FundSeed(
        "XLK", "Technology Select Sector SPDR Fund", "NYSEARCA", "sector", "Information Technology"
    ),
    FundSeed(
        "XLC",
        "Communication Services Select Sector SPDR Fund",
        "NYSEARCA",
        "sector",
        "Communication Services",
    ),
    FundSeed(
        "XLY",
        "Consumer Discretionary Select Sector SPDR Fund",
        "NYSEARCA",
        "sector",
        "Consumer Discretionary",
    ),
    FundSeed(
        "XLP", "Consumer Staples Select Sector SPDR Fund", "NYSEARCA", "sector", "Consumer Staples"
    ),
    FundSeed("XLE", "Energy Select Sector SPDR Fund", "NYSEARCA", "sector", "Energy"),
    FundSeed("XLF", "Financial Select Sector SPDR Fund", "NYSEARCA", "sector", "Financials"),
    FundSeed("XLV", "Health Care Select Sector SPDR Fund", "NYSEARCA", "sector", "Health Care"),
    FundSeed("XLI", "Industrial Select Sector SPDR Fund", "NYSEARCA", "sector", "Industrials"),
    FundSeed("XLB", "Materials Select Sector SPDR Fund", "NYSEARCA", "sector", "Materials"),
    FundSeed("XLRE", "Real Estate Select Sector SPDR Fund", "NYSEARCA", "sector", "Real Estate"),
    FundSeed("XLU", "Utilities Select Sector SPDR Fund", "NYSEARCA", "sector", "Utilities"),
)

#: Stock sector -> the sector fund that stands for it.
SECTOR_FUND_BY_SECTOR: dict[str, str] = {
    f.sector: f.ticker for f in FUND_UNIVERSE if f.role == "sector" and f.sector
}

SECTOR_FUND_TICKERS: tuple[str, ...] = tuple(f.ticker for f in FUND_UNIVERSE if f.role == "sector")


#: The benchmark used for beta and relative strength. Stooq serves the S&P 500
#: index as `^spx`; it is an index, not a tradable security.
BENCHMARK_TICKER = "^SPX"
BENCHMARK_STOOQ_SYMBOL = "^spx"


def by_ticker(ticker: str) -> SeedEntry | None:
    upper = ticker.upper()
    return next((e for e in SEED_UNIVERSE if e.ticker == upper), None)
