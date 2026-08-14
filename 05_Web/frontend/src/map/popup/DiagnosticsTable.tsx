import type { FC } from "react";
import type { CoefficientFeatureProps } from "@/types/api";

interface Props {
  props: CoefficientFeatureProps;
  compareProps?: CoefficientFeatureProps | null;
}

const fmt = (v: number | null | undefined, digits = 3): string =>
  v == null || Number.isNaN(v) ? "—" : v.toFixed(digits);

const estimateLabel = (props: CoefficientFeatureProps): string => {
  if (props.view === "delta") return "Δ β̂ (latest − earliest)";
  if (props.view === "quarter") return `β̂ (${props.target_yq})`;
  return "β̂ (latest, 2025Q4)";
};

export const DiagnosticsTable: FC<Props> = ({ props, compareProps }) => {
  const flagA = props.collinearity_warn_latest || props.collinearity_warn_flag;
  const cnLatestA = props.local_cn_gtwr_latest ?? 0;
  const cnPctA = Math.min(100, Math.round((cnLatestA / 40) * 100));

  const betaA = props.estimate;
  const isPosA = betaA != null && betaA > 0;
  const isNegA = betaA != null && betaA < 0;

  // Single Dong Mode
  if (!compareProps) {
    return (
      <div className="diagnostics-panel" aria-label="Local diagnostics">
        {/* Focal Metric Hero Card */}
        <div className="diag-hero-card">
          <div className="diag-hero-title">{estimateLabel(props)}</div>
          <div className={`diag-hero-val ${isPosA ? "val-pos" : isNegA ? "val-neg" : ""}`}>
            {fmt(props.estimate)}
          </div>
          <div className="diag-hero-sub">
            Focal: <code>{props.focal_var}</code>
          </div>
        </div>

        {/* Metric Grid */}
        <div className="diag-grid">
          <div className="diag-cell">
            <span className="diag-k">adm_cd</span>
            <span className="diag-v">{props.adm_cd}</span>
          </div>
          <div className="diag-cell">
            <span className="diag-k">Target YQ</span>
            <span className="diag-v">{props.target_yq}</span>
          </div>
          <div className="diag-cell">
            <span className="diag-k">2019Q4 β̂</span>
            <span className="diag-v">{fmt(props.earliest_estimate)}</span>
          </div>
          <div className="diag-cell">
            <span className="diag-k">2025Q4 β̂</span>
            <span className="diag-v">{fmt(props.latest_estimate)}</span>
          </div>
          <div className="diag-cell">
            <span className="diag-k">Effective n</span>
            <span className="diag-v">{fmt(props.n_eff, 1)}</span>
          </div>
          <div className="diag-cell">
            <span className="diag-k">Spatiotemporal N</span>
            <span className="diag-v">{props.n_obs ?? "—"}</span>
          </div>
        </div>

        {/* Multicollinearity Section */}
        <div className="diag-cn-section">
          <div className="cn-header">
            <span className="cn-title">Local Multicollinearity (CN)</span>
            <span className={`cn-val ${cnLatestA >= 30 ? "cn-warn" : "cn-safe"}`}>
              {fmt(props.local_cn_gtwr_latest, 1)} / 30.0
            </span>
          </div>
          <div className="cn-gauge-bar">
            <div
              className={`cn-gauge-fill ${cnLatestA >= 30 ? "is-warn" : ""}`}
              style={{ width: `${cnPctA}%` }}
            />
          </div>
          <div className="cn-footer">
            <span>Threshold: 30.0</span>
            {flagA ? (
              <span className="badge-warn" data-testid="collinearity-warn-on" role="status">
                ⚠ Collinearity Flag
              </span>
            ) : (
              <span className="badge-ok" role="status">
                ✓ Normal CN
              </span>
            )}
          </div>
        </div>
      </div>
    );
  }

  // Dual Comparison Mode (Dong A vs Dong B)
  const flagB = compareProps.collinearity_warn_latest || compareProps.collinearity_warn_flag;
  const cnLatestB = compareProps.local_cn_gtwr_latest ?? 0;
  const betaB = compareProps.estimate;
  const isPosB = betaB != null && betaB > 0;
  const isNegB = betaB != null && betaB < 0;

  return (
    <div className="diagnostics-panel compare-mode" aria-label="Dual diagnostics comparison">
      <div className="compare-hero-grid">
        <div className="compare-hero-card dong-a">
          <div className="compare-badge a">Dong A (Primary)</div>
          <div className="compare-dong-name">{props.adm_nm ?? props.adm_cd}</div>
          <div className={`compare-beta ${isPosA ? "val-pos" : isNegA ? "val-neg" : ""}`}>
            β̂ = {fmt(props.estimate)}
          </div>
        </div>

        <div className="compare-hero-card dong-b">
          <div className="compare-badge b">Dong B (Comparison)</div>
          <div className="compare-dong-name">{compareProps.adm_nm ?? compareProps.adm_cd}</div>
          <div className={`compare-beta ${isPosB ? "val-pos" : isNegB ? "val-neg" : ""}`}>
            β̂ = {fmt(compareProps.estimate)}
          </div>
        </div>
      </div>

      <table className="compare-table">
        <thead>
          <tr>
            <th>Diagnostic Metric</th>
            <th className="th-a">{props.adm_nm ?? "Dong A"}</th>
            <th className="th-b">{compareProps.adm_nm ?? "Dong B"}</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>adm_cd</td>
            <td><code>{props.adm_cd}</code></td>
            <td><code>{compareProps.adm_cd}</code></td>
          </tr>
          <tr>
            <td>District (Gu)</td>
            <td>{props.gu_name ?? "—"}</td>
            <td>{compareProps.gu_name ?? "—"}</td>
          </tr>
          <tr>
            <td>{estimateLabel(props)}</td>
            <td className={isPosA ? "val-pos" : isNegA ? "val-neg" : ""}>{fmt(props.estimate)}</td>
            <td className={isPosB ? "val-pos" : isNegB ? "val-neg" : ""}>{fmt(compareProps.estimate)}</td>
          </tr>
          <tr>
            <td>2019Q4 Earliest β̂</td>
            <td>{fmt(props.earliest_estimate)}</td>
            <td>{fmt(compareProps.earliest_estimate)}</td>
          </tr>
          <tr>
            <td>Effective n</td>
            <td>{fmt(props.n_eff, 1)}</td>
            <td>{fmt(compareProps.n_eff, 1)}</td>
          </tr>
          <tr>
            <td>Local CN (Latest)</td>
            <td className={cnLatestA >= 30 ? "cn-warn" : "cn-safe"}>{fmt(props.local_cn_gtwr_latest, 1)}</td>
            <td className={cnLatestB >= 30 ? "cn-warn" : "cn-safe"}>{fmt(compareProps.local_cn_gtwr_latest, 1)}</td>
          </tr>
          <tr>
            <td>Collinearity Warning</td>
            <td>{flagA ? <span className="badge-warn">⚠ Flag</span> : <span className="badge-ok">Normal</span>}</td>
            <td>{flagB ? <span className="badge-warn">⚠ Flag</span> : <span className="badge-ok">Normal</span>}</td>
          </tr>
        </tbody>
      </table>
    </div>
  );
};
