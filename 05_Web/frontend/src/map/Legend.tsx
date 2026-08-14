import { useState, useMemo, type FC } from "react";
import type { CoefficientFeature, ViewMode } from "@/types/api";

interface Props {
  view: ViewMode;
  breaks: number[];
  selectedYq: string;
  features: CoefficientFeature[];
}

export const Legend: FC<Props> = ({ view, breaks, selectedYq, features }) => {
  const [isCollapsed, setIsCollapsed] = useState(false);

  // Compute distribution across the 9 bins for the mini histogram
  // Hook MUST be called unconditionally before any early return
  const counts = useMemo(() => {
    if (breaks.length !== 9) return new Array(9).fill(0);
    const arr = new Array(9).fill(0);
    for (const f of features) {
      const v = f.properties.estimate;
      if (v == null || !Number.isFinite(v)) continue;
      // find bin index [breaks[i], breaks[i+1]]
      if (v <= breaks[0]!) {
        arr[0]++;
      } else if (v >= breaks[8]!) {
        arr[8]++;
      } else {
        for (let i = 0; i < 8; i++) {
          if (v >= breaks[i]! && v < breaks[i + 1]!) {
            arr[i]++;
            break;
          }
        }
      }
    }
    return arr;
  }, [features, breaks]);

  if (breaks.length !== 9) return null;

  const title =
    view === "delta"
      ? "Change in Effect (Δ β̂, earliest→latest)"
      : view === "quarter"
        ? `Effect Estimate (signed β̂, ${selectedYq})`
        : "Latest Effect Estimate (signed β̂, 2025Q4)";

  const maxCount = Math.max(1, ...counts);

  return (
    <div className={`legend ${isCollapsed ? "is-collapsed" : ""}`} role="figure" aria-label="Color legend and distribution">
      <div className="legend-header" onClick={() => setIsCollapsed(!isCollapsed)}>
        <span className="legend-title">{title}</span>
        <button
          type="button"
          className="legend-toggle-btn"
          aria-expanded={!isCollapsed}
          aria-label={isCollapsed ? "Expand legend" : "Collapse legend"}
        >
          {isCollapsed ? "▲" : "▼"}
        </button>
      </div>

      {!isCollapsed && (
        <>
          {/* Mini histogram distribution */}
          <div className="legend-hist" title="Number of dongs in each interval">
            {counts.map((count, i) => {
              const pct = Math.round((count / maxCount) * 100);
              return (
                <div key={i} className="hist-col">
                  <div
                    className={`hist-bar s${i}`}
                    style={{ height: `${Math.max(4, pct)}%` }}
                title={`Bin ${i + 1}: ${count} dongs`}
              />
            </div>
          );
        })}
      </div>

      {/* Color Swatch Bar */}
      <div className="legend-bar">
        {breaks.map((_, i) => (
          <span key={i} className={`legend-swatch s${i}`} aria-hidden="true" />
        ))}
      </div>

        {/* Axis labels */}
        <div className="legend-axis">
          <span className="axis-item neg">
            {breaks[0]!.toFixed(2)}
            <span className="axis-sub">Negative impact</span>
          </span>
          <span className="axis-item zero">
            0.00
            <span className="axis-sub">Neutral</span>
          </span>
          <span className="axis-item pos">
            +{breaks[breaks.length - 1]!.toFixed(2)}
            <span className="axis-sub">Positive impact</span>
          </span>
        </div>
      </>
    )}
  </div>
);
};
