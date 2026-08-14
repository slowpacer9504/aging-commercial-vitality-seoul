import type { FC } from "react";
import { CONTROL_SETS, CONTROL_SET_LABELS } from "@/state/constants";
import { useAppStore } from "@/state/store";
import type { ControlSet } from "@/types/api";

const CONTROL_SET_SUBTITLES: Record<ControlSet, string> = {
  lean: "Baseline specification",
  extended: "Robustness & spatial controls",
};

export const ControlSetSelector: FC = () => {
  const controlSet = useAppStore(s => s.controlSet);
  const setControlSet = useAppStore(s => s.setControlSet);

  return (
    <div className="control control-set-selector" role="group" aria-labelledby="control-set-label">
      <div className="control-header">
        <label id="control-set-label" className="control-label">
          Model Specification
        </label>
      </div>
      <div className="segmented-group">
        {CONTROL_SETS.map(cs => {
          const isSelected = cs === controlSet;
          return (
            <button
              key={cs}
              type="button"
              className={`segment-btn ${isSelected ? "is-active" : ""}`}
              onClick={() => setControlSet(cs)}
              aria-pressed={isSelected}
            >
              <span className="segment-title">{CONTROL_SET_LABELS[cs] ?? cs}</span>
              <span className="segment-sub">{CONTROL_SET_SUBTITLES[cs]}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
};
