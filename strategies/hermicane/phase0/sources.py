"""What data Phase 0 needs, where it comes from, and what to do without it (§3.1).

Every series below is named, attributed to a specific provider, and marked with
what happens if that provider cannot be reached. Nothing in this module invents
a series, and nothing substitutes one series for another without saying so in
the provenance record that ships alongside every panel.

Two rules from the handoff are enforced here in code rather than in prose:

* **First print, not revision.** `FRED_REVISED` sources are marked
  `first_print=False` and `loaders.load_actuals` refuses them for the actual
  column. The market traded the number that printed; a panel built from
  revised values is lookahead bias dressed as tidiness, and it inflates every
  downstream result.
* **No silent proxying.** A proxy is a `Source` in its own right with
  `proxy_for` set. It can be used, but the substitution is recorded and the
  report prints it in the provenance section.

`probe_all()` is the diagnostic: it attempts a real connection to each host and
classifies the failure, so "the data could not be obtained" is a reproducible
result rather than an assertion.
"""

from __future__ import annotations

import json
import socket
import ssl
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

PROBE_TIMEOUT_SECONDS = 12


class SourceUnavailable(RuntimeError):
    """A required series could not be obtained.

    Raised instead of returning partial or substituted data. The message
    carries the documented degradation so the caller can decide, explicitly,
    to run the reduced analysis.
    """

    def __init__(self, source: Source, detail: str) -> None:
        self.source = source
        self.detail = detail
        super().__init__(
            f"{source.key}: {detail}\n"
            f"  needed for : {source.needed_for}\n"
            f"  host       : {source.host}\n"
            f"  degradation: {source.degradation}"
        )


@dataclass(frozen=True)
class Source:
    key: str
    series: str
    resolution: str
    host: str
    probe_url: str
    #: What the panel cannot compute without it.
    needed_for: str
    #: The documented fallback. Never applied automatically — `SourceUnavailable`
    #: carries it to the operator, who chooses.
    degradation: str
    access: str = "free"
    #: False marks a series that publishes revisions. Such a source may be used
    #: for regime features, never for the traded actual.
    first_print: bool = True
    #: Set when this source stands in for another; recorded in provenance.
    proxy_for: str = ""

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


#: The §3.1 table, made executable. `probe_url` is a cheap, real request that
#: does not need an API key where one can be avoided.
REQUIRED_SOURCES: tuple[Source, ...] = (
    Source(
        key="xau_1m",
        series="XAUUSD OHLC",
        resolution="1-minute, 5+ years",
        host="datafeed.dukascopy.com",
        probe_url="https://datafeed.dukascopy.com/datafeed/XAUUSD/2024/00/02/00h_ticks.bi5",
        needed_for="impulse, pullback, micro-structure and every outcome column",
        degradation=(
            "Run event studies on 5-minute bars instead of 1-minute. The T+1 and "
            "T+3 reaction columns become T+5, the control's entry moves to T+5, "
            "and the micro-structure breakout filter cannot be evaluated at all."
        ),
        access="free (scriptable tick export); FirstRate Data and Databento are paid alternatives",
    ),
    Source(
        key="dxy_1m",
        series="DXY, or EURUSD+USDJPY legs to synthesise it",
        resolution="1-minute",
        host="datafeed.dukascopy.com",
        probe_url="https://datafeed.dukascopy.com/datafeed/EURUSD/2024/00/02/00h_ticks.bi5",
        needed_for="the macro-alignment filter",
        degradation=(
            "Drop the macro-alignment filter from the ablation. §1 argues it is "
            "not independent confirmation anyway, so its absence costs less than "
            "it appears to; report it as untested rather than as failed."
        ),
        proxy_for="ICE DXY",
    ),
    Source(
        key="us2y_intraday",
        series="US 2Y yield (or ZT/ZF front future as a proxy)",
        resolution="1-minute, event windows only",
        host="databento.com",
        probe_url="https://databento.com/",
        needed_for="Δ2Y over T+0→T+3, which IS the v2 direction signal",
        degradation=(
            "There is no acceptable degradation. Direction in v2 is defined as "
            "-sign(Δ2Y) × sign(beta); without an intraday 2Y series the control "
            "rule cannot be evaluated and Phase 0 cannot produce constants. "
            "A daily 2Y change is not a substitute: it spans the whole session "
            "and is contaminated by everything else that happened that day."
        ),
        access="paid",
    ),
    Source(
        key="dgs2_daily",
        series="US 2Y constant-maturity yield (DGS2)",
        resolution="daily",
        host="fred.stlouisfed.org",
        probe_url="https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS2",
        needed_for="the rolling beta regime estimator",
        degradation=(
            "None needed in practice — DGS2 is free and keyless. If FRED is "
            "unreachable the beta estimator cannot run, and with it the central "
            "thesis of v2 is untestable."
        ),
    ),
    Source(
        key="gold_daily",
        series="Gold daily close",
        resolution="daily",
        host="fred.stlouisfed.org",
        probe_url="https://fred.stlouisfed.org/graph/fredgraph.csv?id=GOLDPMGBD228NLBM",
        needed_for="the rolling beta regime estimator",
        degradation=(
            "Resample the 1-minute XAUUSD series to daily closes on the same "
            "clock. Acceptable, and recorded in provenance, because the beta "
            "estimator only needs a consistent daily sampling of the same asset."
        ),
    ),
    Source(
        key="actuals_first_print",
        series="First-print macro actuals (ALFRED vintages)",
        resolution="per release",
        host="alfred.stlouisfed.org",
        probe_url="https://alfred.stlouisfed.org/graph/fredgraph.csv?id=CPIAUCSL",
        needed_for="the surprise column",
        degradation=(
            "None. Substituting revised FRED values for first prints is the one "
            "shortcut this project must not take: it is lookahead bias and it "
            "inflates every result downstream."
        ),
    ),
    Source(
        key="consensus",
        series="Analyst consensus per release (and its dispersion, where published)",
        resolution="per release",
        host="api.tradingeconomics.com",
        probe_url="https://api.tradingeconomics.com/",
        needed_for="surprise = actual - consensus, and the z-scored surprise",
        degradation=(
            "Without consensus there is no surprise, and the whole event-study "
            "framing collapses to an unconditional post-release drift study. "
            "That study is still worth running — it is the control in §3.3, "
            "which needs only Δ2Y — but no surprise-conditioned filter can be "
            "evaluated. Flag affected events rather than dropping them silently."
        ),
        access="paid (Trading Economics); Econoday or a scraped Investing.com calendar are alternatives",
    ),
)

SOURCES_BY_KEY = {source.key: source for source in REQUIRED_SOURCES}


@dataclass(frozen=True)
class ProbeResult:
    key: str
    host: str
    reachable: bool
    status: str
    detail: str

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


#: Failure classes worth telling apart. "blocked_by_policy" is the one that
#: means "this environment, not this URL" — retrying or rewriting the request
#: will not help, and the agent proxy README is explicit that it must be
#: reported rather than routed around.
BLOCKED_BY_POLICY = "blocked_by_policy"
UNREACHABLE = "unreachable"
HTTP_ERROR = "http_error"
OK = "ok"


def _classify(error: BaseException) -> tuple[str, str]:
    text = str(error)
    lowered = text.lower()
    if isinstance(error, urllib.error.HTTPError):
        if error.code in (403, 407):
            return BLOCKED_BY_POLICY, f"HTTP {error.code} from egress proxy"
        return HTTP_ERROR, f"HTTP {error.code}"
    if "tunnel connection failed" in lowered or "connect" in lowered and "403" in lowered:
        return BLOCKED_BY_POLICY, text
    if "403" in text or "407" in text:
        return BLOCKED_BY_POLICY, text
    if isinstance(error, (socket.timeout, TimeoutError)):
        return UNREACHABLE, "timed out"
    if isinstance(error, ssl.SSLError):
        return UNREACHABLE, f"TLS: {text}"
    return UNREACHABLE, text


def probe(source: Source, timeout: int = PROBE_TIMEOUT_SECONDS) -> ProbeResult:
    """Attempt one real request against a source's host.

    Deliberately a live network call. The point of this function is to produce
    evidence about the environment the harness is running in, and a cached or
    mocked answer would defeat it.
    """
    request = urllib.request.Request(
        source.probe_url,
        headers={"User-Agent": "hermicane-phase0/2.0 (research harness)"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return ProbeResult(source.key, source.host, True, OK, f"HTTP {response.status}")
    except urllib.error.HTTPError as error:
        status, detail = _classify(error)
        # A 404 or 400 still proves the host is reachable, which is what the
        # probe is actually asking.
        reachable = status == HTTP_ERROR
        return ProbeResult(source.key, source.host, reachable, status, detail)
    except Exception as error:  # noqa: BLE001 - classification is the whole job
        status, detail = _classify(error)
        return ProbeResult(source.key, source.host, False, status, detail)


def probe_all(timeout: int = PROBE_TIMEOUT_SECONDS) -> list[ProbeResult]:
    seen: dict[str, ProbeResult] = {}
    results: list[ProbeResult] = []
    for source in REQUIRED_SOURCES:
        if source.host in seen:
            cached = seen[source.host]
            results.append(ProbeResult(source.key, source.host, cached.reachable, cached.status, cached.detail))
            continue
        result = probe(source, timeout=timeout)
        seen[source.host] = result
        results.append(result)
    return results


@dataclass
class Provenance:
    """What actually went into a panel. Written next to every artefact.

    A result whose provenance says `synthetic` is a test of the machinery. A
    result whose provenance lists a proxy substitution is a real result with an
    asterisk. The distinction is carried in the artefacts themselves rather
    than in whoever remembers running the command.
    """

    generated_utc: str = field(default_factory=lambda: datetime.now(UTC).isoformat(timespec="seconds"))
    #: One of "real", "partial", "synthetic".
    quality: str = "synthetic"
    entries: list[dict[str, object]] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def record(self, key: str, origin: str, detail: str = "", proxy_for: str = "") -> None:
        self.entries.append(
            {"series": key, "origin": origin, "detail": detail, "proxy_for": proxy_for}
        )

    def note(self, text: str) -> None:
        self.notes.append(text)

    @property
    def is_real(self) -> bool:
        """True only when every recorded series came from a real feed.

        `report.py` gates the emission of `calibrated_constants.json` on this.
        It is the mechanism that stops a synthetic dry run from producing a
        file that looks like calibrated output.
        """
        return bool(self.entries) and all(entry["origin"] == "real" for entry in self.entries)

    def as_dict(self) -> dict[str, object]:
        return {
            "generated_utc": self.generated_utc,
            "quality": "real" if self.is_real else self.quality,
            "entries": self.entries,
            "notes": self.notes,
        }

    def write(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.as_dict(), indent=2) + "\n", encoding="utf-8")
