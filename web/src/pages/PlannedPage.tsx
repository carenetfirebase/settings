import { Link } from "react-router";

import { PageHead } from "../components/Panel";
import { SITE_MAP, STATUS_LABEL, STATUS_MEANING, type Page } from "../siteMap";

/**
 * A page that is on the site map but not built yet.
 *
 * It says what the page will do and what data it needs, and shows nothing
 * that looks like a number. An empty promise is better than a fake chart.
 */
export function PlannedPage({ page }: { page: Page }) {
  const category = SITE_MAP.find((c) => c.pages.some((p) => p.id === page.id));

  return (
    <>
      <PageHead
        crumb={category?.title}
        title={page.title}
        aside={<span className="chip warn">{STATUS_LABEL[page.status]} · not built yet</span>}
      >
        {page.purpose}
      </PageHead>
      <section className="panel planned-card">
        <dl>
          <dt>Status</dt>
          <dd>
            <strong>{STATUS_LABEL[page.status]}</strong>: {STATUS_MEANING[page.status]}
          </dd>
          <dt>Data behind it</dt>
          <dd>{page.data}</dd>
          <dt>Rule</dt>
          <dd>
            Only inputs that meet all eight criteria in <code>docs/ENGINE_INPUTS.md</code> can move a
            score. Anything else on this page will be labelled as context.
          </dd>
        </dl>
        <div>
          <Link to="/">← Back to the Command Center</Link>
        </div>
      </section>
    </>
  );
}
