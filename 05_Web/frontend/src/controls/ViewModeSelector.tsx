import type { FC } from "react";
import { VIEW_LABELS, VIEW_MODES } from "@/state/constants";
import { useAppStore } from "@/state/store";
import type { ViewMode } from "@/types/api";

const VIEW_BADGES: Record<ViewMode, string> = {
  latest: "Canonical",
  quarter: "Panel Explorer",
  delta: "Long-term Δ",
};

export const ViewModeSelector: FC = () => {
  const view = useAppStore(s => s.view);
  const setView = useAppStore(s => s.setView);

  return (
    <div className="control view-mode-selector" role="group" aria-labelledby="view-mode-label">
      <div className="control-header">
        <label id="view-mode-label" className="control-label">
          Analytical View
        </label>
      </div>
      <div className="view-mode-tabs">
        {VIEW_MODES.map(v => {
          const isSelected = v === view;
          return (
            <button
              key={v}
              type="button"
              className={`view-tab-btn ${isSelected ? "is-active" : ""}`}
              onClick={() => setView(v)}
              aria-pressed={isSelected}
            >
              <span className="tab-badge">{VIEW_BADGES[v]}</span>
              <span className="tab-label">{VIEW_LABELS[v]}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
};
