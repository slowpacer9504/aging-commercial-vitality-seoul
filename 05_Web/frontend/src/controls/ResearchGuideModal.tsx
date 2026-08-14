import type { FC } from "react";

interface Props {
  isOpen: boolean;
  onClose: () => void;
}

export const ResearchGuideModal: FC<Props> = ({ isOpen, onClose }) => {
  if (!isOpen) return null;

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        className="modal-content"
        onClick={e => e.stopPropagation()}
        role="dialog"
        aria-labelledby="guide-title"
        aria-modal="true"
      >
        <header className="modal-header">
          <div>
            <span className="modal-tag">Research Methodology & Interpretation</span>
            <h2 id="guide-title">Seoul Aging & Commercial Vitality GTWR Explorer</h2>
          </div>
          <button className="modal-close" onClick={onClose} aria-label="Close modal">
            ✕
          </button>
        </header>

        <div className="modal-body">
          <section className="guide-section">
            <h3>1. Research Background & Focal Variable</h3>
            <p>
              This explorer visualizes the local spatiotemporal coefficients from{" "}
              <strong>Geographically and Temporally Weighted Regression (GTWR)</strong> estimating the impact of
              residential aging on neighborhood commercial vitality in Seoul (425 administrative dongs, 2019Q4–2025Q4).
            </p>
            <div className="guide-callout">
              <strong>Focal Variable:</strong> <code>lag4_age60_resident_share</code> (1-year lagged share of residents aged 60 and over).
            </div>
          </section>

          <section className="guide-section">
            <h3>2. How to Interpret Local Coefficients (β̂)</h3>
            <div className="interpretation-grid">
              <div className="interp-card positive">
                <div className="card-indicator pos"></div>
                <h4>β̂ &gt; 0 (Red / Hotspot Shades)</h4>
                <p>
                  Positive association: An increase in senior residents is associated with <em>higher</em> commercial vitality in this neighborhood (e.g., active local neighborhood consumption, silver economy resilience).
                </p>
              </div>
              <div className="interp-card negative">
                <div className="card-indicator neg"></div>
                <h4>β̂ &lt; 0 (Blue / Coldspot Shades)</h4>
                <p>
                  Negative association: Neighborhoods where residential aging is associated with <em>contracting</em> commercial vitality (e.g., youth-oriented commercial zones or declining local demand).
                </p>
              </div>
            </div>
          </section>

          <section className="guide-section">
            <h3>3. Dependent Outcomes (Vitality Sub-indices)</h3>
            <ul className="guide-list">
              <li>
                <strong>Composite Vitality Index:</strong> Synthesized multi-dimensional vitality score.
              </li>
              <li>
                <strong>Economic Vitality:</strong> Sales volume, transaction density, and per-store revenue.
              </li>
              <li>
                <strong>Social Vitality:</strong> Floating population volume, pedestrian diversity, and cross-district visitation.
              </li>
              <li>
                <strong>Stability Vitality:</strong> Store operational longevity, survival rates, and franchise stability.
              </li>
              <li>
                <strong>Temporal Vitality:</strong> Evening, night-time, and weekend commercial activity shares.
              </li>
            </ul>
          </section>

          <section className="guide-section">
            <h3>4. Diagnostic Metrics & Interpretation</h3>
            <ul className="guide-list">
              <li>
                <strong>Local Condition Number (CN):</strong> Evaluates local multicollinearity for each dong and quarter. Values <strong>CN ≥ 30.0</strong> trigger a <code>Collinearity Warning Flag</code> indicating caution when interpreting point estimates.
              </li>
              <li>
                <strong>Temporal View Modes:</strong> The latest quarter (2025Q4) presents the baseline spatial pattern at the end of the study period, while quarterly animations and delta change (Δ) illustrate the evolution of aging effects before and after COVID-19.
              </li>
            </ul>
          </section>
        </div>

        <footer className="modal-footer">
          <button type="button" className="modal-btn-primary" onClick={onClose}>
            Got it, return to map
          </button>
        </footer>
      </div>
    </div>
  );
};
