import type { FC } from "react";
import { OUTCOMES, OUTCOME_LABELS } from "@/state/constants";
import { useAppStore } from "@/state/store";
import type { Outcome } from "@/types/api";

const OUTCOME_DESCRIPTIONS: Record<Outcome, string> = {
  vitality_index_base: "Overall commercial vitality (Composite)",
  vitality_sub_economic: "Sales, revenue & store density",
  vitality_sub_social: "Foot traffic & customer diversity",
  vitality_sub_stability: "Store survival & business tenure",
  vitality_sub_temporal: "Night & weekend operation share",
};

const OUTCOME_BADGES: Record<Outcome, string> = {
  vitality_index_base: "Main Index",
  vitality_sub_economic: "Economic",
  vitality_sub_social: "Social",
  vitality_sub_stability: "Stability",
  vitality_sub_temporal: "Temporal",
};

export const OutcomeSelector: FC = () => {
  const outcome = useAppStore(s => s.outcome);
  const setOutcome = useAppStore(s => s.setOutcome);

  return (
    <div className="control outcome-selector" role="group" aria-labelledby="outcome-label">
      <div className="control-header">
        <label id="outcome-label" className="control-label">
          Dependent Outcome
        </label>
        <span className="control-hint">Vitality Metric</span>
      </div>
      <div className="outcome-chips">
        {OUTCOMES.map(oc => {
          const isSelected = oc === outcome;
          return (
            <button
              key={oc}
              type="button"
              className={`outcome-chip ${isSelected ? "is-selected" : ""}`}
              onClick={() => setOutcome(oc)}
              aria-pressed={isSelected}
            >
              <div className="chip-badge">{OUTCOME_BADGES[oc]}</div>
              <div className="chip-name">{OUTCOME_LABELS[oc] ?? oc}</div>
              <div className="chip-desc">{OUTCOME_DESCRIPTIONS[oc]}</div>
            </button>
          );
        })}
      </div>
    </div>
  );
};
