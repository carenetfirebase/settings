import type { Config } from "tailwindcss";

/* Mirrors frontend/src/styles/tokens.css. Every value here is a var()
 * reference, never a literal -- if a colour existed in both places they would
 * drift, and the lint rule would have nothing to enforce. */
const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        app: "var(--bg-app)",
        panel: "var(--bg-panel)",
        raised: "var(--bg-raised)",
        inset: "var(--bg-inset)",
        border: "var(--border)",
        "border-strong": "var(--border-strong)",
        primary: "var(--text-primary)",
        secondary: "var(--text-secondary)",
        muted: "var(--text-muted)",
        positive: "var(--positive)",
        "positive-deep": "var(--positive-deep)",
        warning: "var(--warning)",
        negative: "var(--negative)",
        info: "var(--info)",
        political: "var(--political)",
      },
      fontFamily: { sans: "var(--font-sans)", mono: "var(--font-mono)" },
      fontSize: {
        label: "var(--text-label)",
        caption: "var(--text-caption)",
        body: "var(--text-body)",
        heading: "var(--text-heading)",
        value: "var(--text-value)",
        kpi: "var(--text-kpi)",
      },
      borderRadius: {
        panel: "var(--radius-panel)",
        control: "var(--radius-control)",
      },
      boxShadow: { none: "none" },
    },
  },
  plugins: [],
};
export default config;
