// Render the design mockups in docs/design/ to PNG.
//
//   node docs/design/render.mjs            # every *.html in this directory
//   node docs/design/render.mjs page.html  # just one
//
// Uses whichever Playwright is resolvable (a project install, or a global one
// via NODE_PATH). Renders at 2x so the PNG stays sharp on high-DPI screens.

import { readdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = dirname(fileURLToPath(import.meta.url));
const targets = process.argv.slice(2).length
  ? process.argv.slice(2).map((p) => resolve(p))
  : readdirSync(here).filter((f) => f.endsWith(".html")).map((f) => join(here, f));

const launchOptions = process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {};
const browser = await chromium.launch(launchOptions);
try {
  for (const file of targets) {
    const page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });
    const errors = [];
    page.on("pageerror", (err) => errors.push(err.message));
    await page.goto(pathToFileURL(file).href);
    await page.waitForLoadState("networkidle");
    if (errors.length) throw new Error(`${file}: ${errors.join("; ")}`);
    const out = file.replace(/\.html$/, ".png");
    await page.screenshot({ path: out, fullPage: false });
    console.log(`rendered ${out}`);
    await page.close();
  }
} finally {
  await browser.close();
}
