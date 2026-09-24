import { afterEach, describe, expect, it, vi } from "vitest";

import { ApiError, UNREACHABLE_MESSAGE, getJson, paths, withQuery } from "./client";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("withQuery", () => {
  it("drops empty values and repeats arrays", () => {
    expect(withQuery("/x", { a: 1, b: null, c: undefined, d: "", e: ["p", "q"] })).toBe(
      "/x?a=1&e=p&e=q",
    );
  });

  it("returns the bare path when nothing is set", () => {
    expect(withQuery("/x", {})).toBe("/x");
  });
});

describe("paths", () => {
  it("encodes tickers and carries as_of", () => {
    expect(paths.prices("BRK.B", { limit: 10 })).toBe("/securities/BRK.B/prices?limit=10");
    expect(paths.analysis("A/B", "2026-06-30")).toBe("/securities/A%2FB/analysis?as_of=2026-06-30");
  });
});

describe("getJson", () => {
  it("returns parsed JSON on success", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ ok: 1 }), { status: 200 })));
    await expect(getJson("/health")).resolves.toEqual({ ok: 1 });
  });

  it("surfaces the API's own detail text", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({ detail: "ZZZ is not in the security master." }), { status: 404 })),
    );
    const error = await getJson("/securities/ZZZ").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).status).toBe(404);
    expect((error as ApiError).message).toBe("ZZZ is not in the security master.");
  });

  it("reports an unreachable API distinctly", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => {
      throw new TypeError("Failed to fetch");
    }));
    const error = (await getJson("/health").catch((e: unknown) => e)) as ApiError;
    expect(error.unreachable).toBe(true);
    expect(error.message).toBe(UNREACHABLE_MESSAGE);
  });
});
