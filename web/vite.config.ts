import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

import { API_PREFIXES, DEFAULT_API_ORIGIN } from "./src/api/routes.ts";

// The built site is served by the API under /app (see invest/api/web.py).
// In development, Vite serves the site and forwards API paths to `invest serve`.
const apiOrigin = process.env.INVEST_API_ORIGIN ?? DEFAULT_API_ORIGIN;

export default defineConfig({
  base: "/app/",
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    proxy: Object.fromEntries(API_PREFIXES.map((prefix) => [prefix, apiOrigin])),
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});
