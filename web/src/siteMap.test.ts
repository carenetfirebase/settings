import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { ALL_PAGES, SITE_MAP, STATUS_LABEL } from "./siteMap";

const here = dirname(fileURLToPath(import.meta.url));
const doc = readFileSync(resolve(here, "../../docs/SITE_MAP.md"), "utf8");

/** Table rows of the doc, keyed by page title: "| Title | Status | ...". */
function docRows(): Map<string, string> {
  const rows = new Map<string, string>();
  for (const line of doc.split("\n")) {
    const cells = line.split("|").map((c) => c.trim());
    if (cells.length < 4 || cells[1] === "Page" || cells[1]?.startsWith("---")) continue;
    const [, title, status] = cells;
    if (title && status) rows.set(title, status);
  }
  return rows;
}

describe("site map", () => {
  it("has unique ids and paths", () => {
    expect(new Set(ALL_PAGES.map((p) => p.id)).size).toBe(ALL_PAGES.length);
    expect(new Set(ALL_PAGES.map((p) => p.path)).size).toBe(ALL_PAGES.length);
  });

  it("every page has a purpose and a data source", () => {
    for (const page of ALL_PAGES) {
      expect(page.purpose.length, page.id).toBeGreaterThan(20);
      expect(page.data.length, page.id).toBeGreaterThan(5);
    }
  });

  it("agrees with docs/SITE_MAP.md, page for page and status for status", () => {
    const rows = docRows();
    const inCode = new Map(ALL_PAGES.map((p) => [p.title, STATUS_LABEL[p.status]]));
    expect(Object.fromEntries(rows)).toEqual(Object.fromEntries(inCode));
  });

  it("lists every category in the doc's contents", () => {
    for (const category of SITE_MAP) {
      expect(doc).toContain(`[${category.title}]`);
    }
  });
});

describe("live pages are really built", () => {
  const app = readFileSync(resolve(here, "App.tsx"), "utf8");

  it("every live page has a component in App.tsx", () => {
    for (const page of ALL_PAGES.filter((p) => p.status === "live")) {
      expect(app, `${page.id} is marked live but has no component`).toContain(`"${page.id}": <`);
    }
  });

  it("no planned page has a component yet", () => {
    for (const page of ALL_PAGES.filter((p) => p.status !== "live")) {
      expect(app).not.toContain(`"${page.id}": <`);
    }
  });
});
