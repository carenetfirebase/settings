/* The banned-words gate. docs/UI_SPEC.md §5.
 *
 * This runs in the standard suite, not only at Phase 10 (CLAUDE.md). The
 * product ranks research priority; it does not recommend trades, and the copy
 * has to hold that line under pressure from every convenient shorthand.
 *
 * "live" is banned as a DATA descriptor specifically -- nothing in this system
 * is live, and saying so about filings or prices is the misrepresentation
 * UI_SPEC correction #4 exists to prevent.
 */
import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const SRC = join(import.meta.dirname, "..", "src");

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const full = join(dir, entry);
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
}

/** Only user-visible text: string and JSX literals, not identifiers or comments. */
function visibleText(content: string): string {
  const withoutComments = content
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/^\s*\/\/.*$/gm, " ");
  const strings = [...withoutComments.matchAll(/"([^"\\]*(?:\\.[^"\\]*)*)"|'([^'\\]*(?:\\.[^'\\]*)*)'/g)]
    .map((m) => m[1] ?? m[2] ?? "");
  const jsx = [...withoutComments.matchAll(/>([^<>{}]+)</g)].map((m) => m[1]);
  return [...strings, ...jsx].join("\n");
}

const BANNED: [RegExp, string][] = [
  [/\bbuy\b/i, "'buy' — the only company actions are Deep Dive, Investigate, Watch"],
  [/\bsell\b/i, "'sell' — same"],
  [/\brecommendation\b/i, "'recommendation' — this ranks research priority"],
  [/signal to buy/i, "'signal to buy'"],
  [/target price/i, "'target price'"],
  [/conviction to trade/i, "'conviction to trade'"],
  [/opportunity to enter/i, "'opportunity to enter'"],
  [/%\s*of\s*float/i, "'% of float' — free float is not available; use % of shares outstanding"],
  [/\blive\s+(data|feed|prices?|quotes?|updates?)\b/i, "'live' as a data descriptor — nothing here is live"],
  [/\bdata\s*updates?\s*:?\s*live\b/i, "'Data Updates: Live' — UI_SPEC correction #4"],
];

describe("copy rules", () => {
  const files = walk(SRC).filter((f) => /\.(ts|tsx)$/.test(f));

  it("contains no banned language in user-visible text", () => {
    const offenders: string[] = [];
    for (const file of files) {
      const text = visibleText(readFileSync(file, "utf8"));
      for (const [pattern, reason] of BANNED) {
        if (pattern.test(text)) offenders.push(`${relative(SRC, file)} → ${reason}`);
      }
    }
    expect(offenders, `Banned copy found:\n${offenders.join("\n")}`).toEqual([]);
  });

  it("the gate actually catches things", () => {
    // A gate that cannot fail is not a gate.
    const sample = 'const label = "Strong buy signal";';
    expect(BANNED.some(([p]) => p.test(visibleText(sample)))).toBe(true);
    expect(BANNED.some(([p]) => p.test(visibleText('const x = "Short interest % of float";')))).toBe(true);
  });
});
