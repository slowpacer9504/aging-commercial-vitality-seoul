import { useEffect, useState, type FC } from "react";
import { getSummary } from "@/api/endpoints";
import type { SummaryRow } from "@/types/api";
import { useAppStore } from "@/state/store";
import { OUTCOME_LABELS } from "@/state/constants";

const fmt = (v: number | null | undefined, digits = 3): string =>
  v === null || v === undefined || Number.isNaN(v) ? "—" : v.toFixed(digits);

const OUTCOME_ORDER: Record<string, number> = {
  vitality_sub_economic: 1,
  vitality_sub_social: 2,
  vitality_sub_stability: 3,
  vitality_sub_temporal: 4,
  vitality_index_base: 5,
};

export const GlobalSummary: FC = () => {
  const currentOutcome = useAppStore(s => s.outcome);
  const setOutcome = useAppStore(s => s.setOutcome);
  const controlSet = useAppStore(s => s.controlSet);

  const [summaries, setSummaries] = useState<SummaryRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    getSummary(controlSet)
      .then(res => {
        if (cancelled) return;
        const sorted = [...res.summaries].sort(
          (a, b) =>
            (OUTCOME_ORDER[a.outcome] ?? a.outcome_order ?? 999) -
              (OUTCOME_ORDER[b.outcome] ?? b.outcome_order ?? 999) ||
            a.outcome.localeCompare(b.outcome),
        );
        setSummaries(sorted);
      })
      .catch(e => {
        if (cancelled) setError(String(e?.message ?? e));
        setSummaries([]);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [controlSet]);

  return (
    <section className="global-summary" aria-label="Global GTWR Model Summary">
      <div className="summary-section-header">
        <h3 className="summary-section-title">Global Model Diagnostics</h3>
        <span className="summary-spec-tag">{controlSet} specification</span>
      </div>

      {loading && <p className="summary-loading">Loading summary metrics…</p>}
      {error && (
        <p className="summary-error" role="alert">
          {error}
        </p>
      )}

      <div className="summary-card-list">
        {summaries.map(s => {
          const isSelected = s.outcome === currentOutcome;
          const posPct = s.share_positive != null ? (s.share_positive * 100).toFixed(1) : "—";
          const isMeanPos = s.mean_beta != null && s.mean_beta > 0;

          return (
            <div
              key={s.outcome}
              className={`summary-model-card ${isSelected ? "is-selected" : ""}`}
              onClick={() => setOutcome(s.outcome as never)}
              role="button"
              tabIndex={0}
              onKeyDown={e => {
                if (e.key === "Enter" || e.key === " ") setOutcome(s.outcome as never);
              }}
            >
              <div className="card-top">
                <span className="card-outcome-name">
                  {OUTCOME_LABELS[s.outcome] ?? s.outcome}
                </span>
                {isSelected && <span className="active-badge">Active View</span>}
              </div>

              <div className="card-metrics-grid">
                <div className="metric-box">
                  <span className="metric-k">Mean β̂</span>
                  <span className={`metric-v ${isMeanPos ? "val-pos" : "val-neg"}`}>
                    {fmt(s.mean_beta)}
                  </span>
                </div>
                <div className="metric-box">
                  <span className="metric-k">Share &gt; 0</span>
                  <span className="metric-v">{posPct}%</span>
                </div>
                <div className="metric-box">
                  <span className="metric-k">GTW AICc</span>
                  <span className="metric-v">{fmt(s.gtw_aicc, 1)}</span>
                </div>
                <div className="metric-box">
                  <span className="metric-k">Max Local CN</span>
                  <span className={`metric-v ${(s.max_local_cn_gtwr ?? 0) >= 30 ? "cn-warn" : ""}`}>
                    {fmt(s.max_local_cn_gtwr, 1)}
                  </span>
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
};
