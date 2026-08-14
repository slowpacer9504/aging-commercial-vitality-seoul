import { OUTCOMES, CONTROL_SETS, VIEW_MODES } from "@/types/api";
import type { ViewMode } from "@/types/api";

export const OUTCOME_LABELS: Record<string, string> = {
  vitality_index_base: "Composite vitality index",
  vitality_sub_economic: "Economic vitality",
  vitality_sub_social: "Social vitality",
  vitality_sub_stability: "Stability vitality",
  vitality_sub_temporal: "Temporal vitality",
};

export const CONTROL_SET_LABELS: Record<string, string> = {
  lean: "Lean controls (default)",
  extended: "Extended controls (sensitivity)",
};

export const VIEW_LABELS: Record<ViewMode, string> = {
  latest: "Latest quarter (2025Q4)",
  quarter: "Specific quarter",
  delta: "Change (Δ, earliest→latest)",
};

export { OUTCOMES, CONTROL_SETS, VIEW_MODES };
