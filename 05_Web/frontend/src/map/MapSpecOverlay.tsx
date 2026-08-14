import type { FC } from "react";
import { useAppStore } from "@/state/store";
import { OUTCOME_LABELS } from "@/state/constants";

export const MapSpecOverlay: FC = () => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const view = useAppStore(s => s.view);
  const selectedYq = useAppStore(s => s.selectedYq);
  const selectedGu = useAppStore(s => s.selectedGu);

  const outcomeLabel = OUTCOME_LABELS[outcome] ?? outcome;
  const controlLabel = controlSet === "lean" ? "Lean" : "Extended";

  let timeLabel = "2025Q4 (Latest)";
  if (view === "quarter") {
    timeLabel = selectedYq;
  } else if (view === "delta") {
    timeLabel = "Δ (2019Q4 → 2025Q4)";
  }

  return (
    <div className="map-spec-overlay" role="status" aria-label="Current map specifications">
      <div className="spec-badge-header">
        <span className="spec-main-tag">GTWR Spatial Estimates</span>
        {selectedGu && <span className="spec-gu-tag">{selectedGu}</span>}
      </div>
      <div className="spec-items-row">
        <span className="spec-item">
          <strong className="spec-k">Model:</strong> {controlLabel}
        </span>
        <span className="spec-divider">•</span>
        <span className="spec-item">
          <strong className="spec-k">Time:</strong> {timeLabel}
        </span>
        <span className="spec-divider">•</span>
        <span className="spec-item">
          <strong className="spec-k">Outcome:</strong> {outcomeLabel}
        </span>
      </div>
    </div>
  );
};
