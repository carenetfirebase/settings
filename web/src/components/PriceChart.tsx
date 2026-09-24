import {
  CandlestickSeries,
  ColorType,
  HistogramSeries,
  LineSeries,
  createChart,
  type UTCTimestamp,
} from "lightweight-charts";
import { useEffect, useMemo, useRef } from "react";

import type { PriceBar } from "../api/types";
import { isNum, sma } from "../lib/format";
import { cssVar, useTheme } from "./theme";

interface CompleteBar {
  time: UTCTimestamp;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number | null;
}

function toTime(isoDate: string): UTCTimestamp {
  return (Date.parse(`${isoDate}T00:00:00Z`) / 1000) as UTCTimestamp;
}

/** Bars with every OHLC field present. Incomplete bars are left as gaps. */
export function completeBars(bars: readonly PriceBar[]): CompleteBar[] {
  const out: CompleteBar[] = [];
  for (const b of bars) {
    if (isNum(b.open) && isNum(b.high) && isNum(b.low) && isNum(b.close)) {
      out.push({ time: toTime(b.obs_date), open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume });
    }
  }
  return out;
}

/**
 * Daily candles with 50- and 200-day averages and a separate volume pane.
 *
 * Up candles are hollow and down candles filled, so direction reads without
 * colour. Volume sits in its own pane with its own scale: never a second axis
 * on the price plot.
 */
export function PriceChart({ bars }: { bars: readonly PriceBar[] }) {
  const host = useRef<HTMLDivElement>(null);
  const { theme } = useTheme();
  const data = useMemo(() => completeBars(bars), [bars]);
  const skipped = bars.length - data.length;

  const hasMa50 = data.length >= 50;
  const hasMa200 = data.length >= 200;

  useEffect(() => {
    const el = host.current;
    if (!el || data.length === 0) return;

    const closes = data.map((b) => b.close);
    const up = cssVar("--up");
    const down = cssVar("--down");
    const chart = createChart(el, {
      autoSize: true,
      layout: {
        background: { type: ColorType.Solid, color: cssVar("--surface-1") },
        textColor: cssVar("--ink-3"),
        fontFamily: cssVar("--font"),
        fontSize: 11,
        panes: { separatorColor: cssVar("--border-strong") },
      },
      grid: {
        vertLines: { color: cssVar("--grid") },
        horzLines: { color: cssVar("--grid") },
      },
      rightPriceScale: { borderColor: cssVar("--baseline") },
      timeScale: { borderColor: cssVar("--baseline") },
      crosshair: { mode: 0 },
      // The library defaults to navigator.language, which some Linux browsers
      // report as a POSIX tag ("en-US@posix") that Intl rejects, blanking the
      // chart. Pin it, as the rest of the site's formatting does.
      localization: { locale: "en-US" },
    });

    const candles = chart.addSeries(CandlestickSeries, {
      upColor: cssVar("--surface-1"),
      borderUpColor: up,
      wickUpColor: up,
      downColor: down,
      borderDownColor: down,
      wickDownColor: down,
    });
    candles.setData(data.map(({ time, open, high, low, close }) => ({ time, open, high, low, close })));

    const overlay = (window: number, color: string) => {
      const line = chart.addSeries(LineSeries, {
        color,
        lineWidth: 2,
        priceLineVisible: false,
        lastValueVisible: false,
        crosshairMarkerVisible: false,
      });
      const values = sma(closes, window);
      line.setData(
        data.flatMap((b, i) => {
          const v = values[i];
          return isNum(v) ? [{ time: b.time, value: v }] : [];
        }),
      );
    };
    if (hasMa200) overlay(200, cssVar("--ma-slow"));
    if (hasMa50) overlay(50, cssVar("--accent"));

    const volume = chart.addSeries(
      HistogramSeries,
      { priceFormat: { type: "volume" }, priceLineVisible: false, lastValueVisible: false },
      1,
    );
    volume.setData(
      data.flatMap((b) =>
        isNum(b.volume)
          ? [{ time: b.time, value: b.volume, color: `${b.close >= b.open ? up : down}59` }]
          : [],
      ),
    );
    chart.panes()[1]?.setStretchFactor(0.22);
    chart.panes()[0]?.setStretchFactor(0.78);

    chart.timeScale().fitContent();
    return () => chart.remove();
    // `theme` is a dependency because it changes the tokens read above.
  }, [data, theme, hasMa50, hasMa200]);

  if (data.length === 0) {
    return (
      <div className="state">
        <strong>No price history stored</strong>
        <div>
          Run <code>invest ingest prices</code> to load daily bars.
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="chart-legend" style={{ padding: "0 14px 8px" }}>
        {hasMa50 && (
          <span>
            <i style={{ background: "var(--accent)" }} />
            50-day avg
          </span>
        )}
        {hasMa200 && (
          <span>
            <i style={{ background: "var(--ma-slow)" }} />
            200-day avg
          </span>
        )}
        <span className="muted">Hollow = up day · filled = down day</span>
        {skipped > 0 && <span className="muted">{skipped} incomplete bars left as gaps</span>}
      </div>
      <div ref={host} className="chart-host" role="img" aria-label={`Daily price chart, ${data.length} bars`} />
    </div>
  );
}
