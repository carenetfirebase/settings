import { useEffect, useState, type FormEvent } from "react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router";

import { paths } from "../api/client";
import type { HealthResponse, RegimeResponse } from "../api/types";
import { useApi } from "../api/useApi";
import { humanize } from "../lib/format";
import { SITE_MAP, STATUS_LABEL, type Page } from "../siteMap";
import { useTheme } from "./theme";

/** Where a nav entry points. Symbol pages open the research picker. */
export function navTarget(page: Page): string {
  return page.path.replace(/\/:ticker$/, "");
}

export const REGIME_TONE: Record<string, "good" | "bad" | "warn" | undefined> = {
  expansion: "good",
  recovery: "good",
  late_cycle: "warn",
  stress: "bad",
};

function BrandMark() {
  return (
    <span className="brand-mark" aria-hidden="true">
      <svg width="14" height="14" viewBox="0 0 14 14">
        <path d="M1 10 L5 6 L8 8.5 L13 3" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </span>
  );
}

function Sidebar({ health }: { health: HealthResponse | undefined }) {
  return (
    <nav className="sidebar" aria-label="Main">
      <NavLink to="/" className="brand" end>
        <BrandMark />
        <span>
          <span className="brand-name">invest</span>
          <span className="brand-sub" style={{ display: "block" }}>trading terminal</span>
        </span>
      </NavLink>
      {SITE_MAP.map((category) => (
        <div key={category.id} className="nav-group">
          {category.pages.length > 1 || category.title !== category.pages[0]?.title ? (
            <div className="nav-label">{category.title}</div>
          ) : null}
          {category.pages.map((page) => (
            <NavLink
              key={page.id}
              to={navTarget(page)}
              end={page.path === "/"}
              className={({ isActive }) =>
                `nav-item${isActive ? " active" : ""}${page.status === "live" ? "" : " planned"}`
              }
            >
              <span>{page.title}</span>
              {page.status !== "live" && <span className="status-tag">{STATUS_LABEL[page.status]}</span>}
            </NavLink>
          ))}
        </div>
      ))}
      <div className="sidebar-foot">
        <span>
          <span className={`dot ${health ? "good" : "bad"}`} style={{ marginRight: 6 }} />
          {health ? `API ${health.version} · read-only` : "API offline"}
        </span>
        <span>No broker connected · trading arrives in V1</span>
      </div>
    </nav>
  );
}

function TickerSearch() {
  const navigate = useNavigate();
  const [value, setValue] = useState("");

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const ticker = value.trim().toUpperCase();
    if (!ticker) return;
    setValue("");
    navigate(`/research/${encodeURIComponent(ticker)}`);
  };

  return (
    <form className="search" role="search" onSubmit={submit}>
      <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
        <circle cx="6" cy="6" r="4.5" stroke="currentColor" strokeWidth="1.5" fill="none" />
        <path d="M9.5 9.5 L13 13" stroke="currentColor" strokeWidth="1.5" />
      </svg>
      <label className="visually-hidden" htmlFor="ticker-search">Open a symbol</label>
      <input
        id="ticker-search"
        placeholder="Symbol, e.g. NVDA"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        autoComplete="off"
        spellCheck={false}
      />
    </form>
  );
}

export function Layout() {
  const health = useApi<HealthResponse>(paths.health());
  const regime = useApi<RegimeResponse>(paths.regime());
  const { theme, toggle } = useTheme();
  const [navOpen, setNavOpen] = useState(false);
  const location = useLocation();

  useEffect(() => setNavOpen(false), [location.pathname]);

  const regimeTone = regime.data ? REGIME_TONE[regime.data.regime] : undefined;

  return (
    <div className={`app${navOpen ? " nav-open" : ""}`}>
      <Sidebar health={health.data} />
      {navOpen && <div className="scrim" onClick={() => setNavOpen(false)} aria-hidden="true" />}
      <div className="main">
        <header className="topbar">
          <button
            type="button"
            className="icon-button menu-button"
            aria-label="Open navigation"
            aria-expanded={navOpen}
            onClick={() => setNavOpen((open) => !open)}
          >
            ☰
          </button>
          <TickerSearch />
          <span className={`pill hide-narrow ${health.data ? "good" : health.error ? "bad" : ""}`}>
            <span className={`dot ${health.data ? "good" : health.error ? "bad" : ""}`} />
            <strong>{health.data ? "API connected" : health.error ? "API offline" : "Connecting…"}</strong>
          </span>
          {regime.data && (
            <NavLink to="/markets/macro" className={`pill hide-narrow ${regimeTone ?? ""}`} title="Macro regime is context: it never moves a score">
              <strong>Macro: {humanize(regime.data.regime)}</strong> context
            </NavLink>
          )}
          <span className="spacer" />
          <span className="pill warn hide-narrow" title="Paper and live trading arrive in V1">
            RESEARCH MODE
          </span>
          <button
            type="button"
            className="icon-button"
            onClick={toggle}
            aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
            title={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
          >
            {theme === "dark" ? "☀" : "☾"}
          </button>
        </header>
        <main className="content">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
