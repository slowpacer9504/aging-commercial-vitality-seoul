import type { FC } from "react";

// Persistent banner per research_plan.md §7.4 line 224: latest-quarter betas
// are canonical; earliest-to-latest deltas (panel) are Supplementary appendix
// diagnostics. This banner appears on every screen.
export const SupplementaryBanner: FC = () => (
  <aside
    role="status"
    aria-live="polite"
    className="supplementary-banner"
    data-testid="supplementary-banner"
  >
    <strong>Canonical:</strong> latest-quarter (2025Q4) coefficients. The
    popup time-series is labelled <em>(Supplementary)</em> per the research
    contract.
  </aside>
);
