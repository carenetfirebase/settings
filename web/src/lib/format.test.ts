import { describe, expect, it } from "vitest";

import {
  MISSING,
  direction,
  fmtCompact,
  fmtDate,
  fmtMoney,
  fmtNumber,
  fmtPct,
  humanize,
  sma,
} from "./format";

describe("missing values are never shown as zero", () => {
  it.each([null, undefined, Number.NaN, Number.POSITIVE_INFINITY])("%s", (value) => {
    expect(fmtNumber(value)).toBe(MISSING);
    expect(fmtPct(value)).toBe(MISSING);
    expect(fmtCompact(value)).toBe(MISSING);
    expect(fmtMoney(value)).toBe(MISSING);
  });

  it("zero is a real value", () => {
    expect(fmtNumber(0)).toBe("0.00");
    expect(fmtPct(0)).toBe("0.0%");
  });
});

describe("fmtNumber", () => {
  it("groups thousands and fixes digits", () => {
    expect(fmtNumber(1234.5)).toBe("1,234.50");
    expect(fmtNumber(1234.5, 0)).toBe("1,235");
  });

  it("uses a typographic minus and optional plus", () => {
    expect(fmtNumber(-2.5, 1)).toBe("−2.5");
    expect(fmtNumber(2.5, 1, true)).toBe("+2.5");
  });

  it("never prints negative zero", () => {
    expect(fmtNumber(-0.001, 2)).toBe("0.00");
    expect(fmtNumber(0.001, 2, true)).toBe("0.00");
  });
});

describe("fmtPct", () => {
  it("treats input as a fraction", () => {
    expect(fmtPct(0.1234)).toBe("12.3%");
    expect(fmtPct(-0.05, 1, true)).toBe("−5.0%");
    expect(fmtPct(0.05, 1, true)).toBe("+5.0%");
  });
});

describe("fmtCompact and fmtMoney", () => {
  it("abbreviates large numbers", () => {
    expect(fmtCompact(1_234_567)).toBe("1.2M");
    expect(fmtCompact(-3_400_000_000)).toBe("−3.4B");
    expect(fmtCompact(950)).toBe("950");
  });

  it("puts the sign before the dollar", () => {
    expect(fmtMoney(-12.5)).toBe("−$12.50");
    expect(fmtMoney(2_500_000, true)).toBe("$2.5M");
  });
});

describe("fmtDate", () => {
  it("reads API dates as calendar dates, not local midnight", () => {
    expect(fmtDate("2026-09-24")).toBe("Sep 24, 2026");
  });

  it("returns MISSING for empty or invalid input", () => {
    expect(fmtDate(null)).toBe(MISSING);
    expect(fmtDate("not a date")).toBe(MISSING);
  });
});

describe("direction", () => {
  it("pairs a glyph with every tone", () => {
    expect(direction(1.2)).toEqual({ glyph: "▲", tone: "up" });
    expect(direction(-0.1)).toEqual({ glyph: "▼", tone: "down" });
    expect(direction(0)).toEqual({ glyph: "–", tone: "flat" });
    expect(direction(null)).toEqual({ glyph: "–", tone: "flat" });
  });
});

describe("humanize", () => {
  it("turns API keys into labels", () => {
    expect(humanize("investment_quality")).toBe("Investment quality");
  });

  it("keeps acronyms and model names readable", () => {
    expect(humanize("roic_vs_wacc")).toBe("ROIC vs WACC");
    expect(humanize("rsi")).toBe("RSI");
    expect(humanize("piotroski_f_score")).toBe("Piotroski F score");
    expect(humanize("position_52w")).toBe("Position 52-week");
  });
});

describe("sma", () => {
  it("averages a full window and pads the start with null", () => {
    expect(sma([1, 2, 3, 4], 2)).toEqual([null, 1.5, 2.5, 3.5]);
  });

  it("does not average across a gap", () => {
    expect(sma([1, null, 3, 4, 5], 2)).toEqual([null, null, null, 3.5, 4.5]);
  });

  it("rejects a zero window", () => {
    expect(() => sma([1], 0)).toThrow();
  });
});
