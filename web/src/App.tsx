import type { ReactElement } from "react";
import { Link, Route, Routes } from "react-router";

import { Layout } from "./components/Layout";
import { PageHead } from "./components/Panel";
import { CommandCenter } from "./pages/CommandCenter";
import { Attribution, Calibration } from "./pages/Lab";
import { Macro } from "./pages/Macro";
import { MarketsOverview } from "./pages/MarketsOverview";
import { PlannedPage } from "./pages/PlannedPage";
import { Sectors } from "./pages/Sectors";
import { Scanner, SignalLedger, TradeCards } from "./pages/Signals";
import { SymbolResearch } from "./pages/SymbolResearch";
import { DataFeeds, DataQuality } from "./pages/SystemPages";
import { ALL_PAGES } from "./siteMap";

/** The component behind every live page, keyed by site-map id. */
export const LIVE_PAGES: Record<string, ReactElement> = {
  "command-center": <CommandCenter />,
  "markets-overview": <MarketsOverview />,
  "markets-macro": <Macro />,
  "markets-sectors": <Sectors />,
  "signals-scanner": <Scanner />,
  "signals-cards": <TradeCards />,
  "signals-ledger": <SignalLedger />,
  "lab-calibration": <Calibration />,
  "lab-attribution": <Attribution />,
  "research-symbol": <SymbolResearch />,
  "system-feeds": <DataFeeds />,
  "system-quality": <DataQuality />,
};

function NotFound() {
  return (
    <PageHead crumb="404" title="No such page">
      <Link to="/">Back to the Command Center</Link>
    </PageHead>
  );
}

export function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        {ALL_PAGES.map((page) => (
          <Route
            key={page.id}
            path={page.path}
            element={page.status === "live" ? LIVE_PAGES[page.id] : <PlannedPage page={page} />}
          />
        ))}
        <Route path="/research" element={<SymbolResearch />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  );
}
