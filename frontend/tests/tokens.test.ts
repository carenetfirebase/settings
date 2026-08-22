/* Phase 1 criterion 8: the token lint rule.
 *
 * Every colour, size, radius, and space value comes from tokens.css. A raw hex
 * anywhere else fails the build. This is not stylistic pedantry -- a one-off
 * colour is how a palette stops being a system, and in this UI colour carries
 * fixed meaning (green = confirming evidence, red = contradiction, amber =
 * stale). A decorative red is a lie.
 */
import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const SRC = join(import.meta.dirname, "..", "src");
const TOKENS_FILE = join(SRC, "styles", "tokens.css");

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const full = join(dir, entry);
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
}

const HEX = /#[0-9a-fA-F]{3,8}\b/g;
// Arbitrary Tailwind values: bg-[#fff], text-[13px], w-[42px]
const ARBITRARY = /\b[a-z-]+-\[(#[0-9a-fA-F]{3,8}|\d+px)\]/g;

describe("design tokens", () => {
  const files = walk(SRC).filter((f) => /\.(ts|tsx|css)$/.test(f) && f !== TOKENS_FILE);

  it("no raw hex value outside tokens.css", () => {
    const offenders: string[] = [];
    for (const file of files) {
      const content = readFileSync(file, "utf8");
      for (const match of content.matchAll(HEX)) {
        const line = content.slice(0, match.index).split("\n").length;
        offenders.push(`${relative(SRC, file)}:${line} → ${match[0]}`);
      }
    }
    expect(offenders, `Use a token from styles/tokens.css:\n${offenders.join("\n")}`).toEqual([]);
  });

  it("no arbitrary Tailwind colour or size values", () => {
    const offenders: string[] = [];
    for (const file of files) {
      const content = readFileSync(file, "utf8");
      for (const match of content.matchAll(ARBITRARY)) {
        offenders.push(`${relative(SRC, file)} → ${match[0]}`);
      }
    }
    expect(offenders, `Use a token:\n${offenders.join("\n")}`).toEqual([]);
  });

  it("tokens.css defines every token the spec requires", () => {
    const css = readFileSync(TOKENS_FILE, "utf8");
    const required = [
      "--bg-app", "--bg-panel", "--bg-raised", "--bg-inset",
      "--border", "--border-strong",
      "--text-primary", "--text-secondary", "--text-muted",
      "--positive", "--positive-deep", "--warning", "--negative", "--info", "--political",
      "--heat-pos-max", "--heat-neg-max",
      "--font-sans", "--font-mono",
    ];
    const missing = required.filter((token) => !css.includes(`${token}:`));
    expect(missing, `tokens.css is missing: ${missing.join(", ")}`).toEqual([]);
  });

  it("no box-shadow anywhere — depth comes from surface value", () => {
    const offenders = files.filter((f) => /box-shadow\s*:|shadow-(sm|md|lg|xl)/.test(readFileSync(f, "utf8")));
    expect(offenders.map((f) => relative(SRC, f))).toEqual([]);
  });
});
