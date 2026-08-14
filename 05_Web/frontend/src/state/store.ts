// zustand global store with URL state deep-linking and theme/tour support. Strict types; no `any`.
import { create } from "zustand";
import type { ControlSet, Outcome, ViewMode } from "@/types/api";
import { OUTCOMES, CONTROL_SETS, VIEW_MODES } from "@/types/api";

const DEFAULT_OUTCOME: Outcome = "vitality_index_base";
const DEFAULT_CONTROL_SET: ControlSet = "lean";
const DEFAULT_VIEW: ViewMode = "latest";
const DEFAULT_SELECTED_YQ = "2025Q4";
export const DEFAULT_TARGET_YQ = "2025Q4";

export interface AppState {
  outcome: Outcome;
  controlSet: ControlSet;
  view: ViewMode;
  selectedYq: string;
  selectedAdmCd: string | null;
  compareAdmCd: string | null;
  selectedGu: string | null;
  theme: "light" | "dark";
  tourStep: number | null;
  hoveredScatterAdmCd: string | null;

  setOutcome: (o: Outcome) => void;
  setControlSet: (c: ControlSet) => void;
  setView: (v: ViewMode) => void;
  setSelectedYq: (yq: string) => void;
  selectAdmCd: (admCd: string | null) => void;
  setCompareAdmCd: (admCd: string | null) => void;
  setSelectedGu: (gu: string | null) => void;
  setTheme: (theme: "light" | "dark") => void;
  setTourStep: (step: number | null) => void;
  setHoveredScatterAdmCd: (admCd: string | null) => void;
}

// Parse initial state from window.location.search if in browser
function getInitialState(): {
  outcome: Outcome;
  controlSet: ControlSet;
  view: ViewMode;
  selectedYq: string;
  selectedAdmCd: string | null;
  compareAdmCd: string | null;
  selectedGu: string | null;
  theme: "light" | "dark";
} {
  let theme: "light" | "dark" = "light";
  if (typeof window !== "undefined") {
    const savedTheme = localStorage.getItem("seoul_gtwr_theme");
    if (savedTheme === "dark" || savedTheme === "light") {
      theme = savedTheme;
    }
  }

  if (typeof window === "undefined" || !window.location.search) {
    return {
      outcome: DEFAULT_OUTCOME,
      controlSet: DEFAULT_CONTROL_SET,
      view: DEFAULT_VIEW,
      selectedYq: DEFAULT_SELECTED_YQ,
      selectedAdmCd: null,
      compareAdmCd: null,
      selectedGu: null,
      theme,
    };
  }

  const p = new URLSearchParams(window.location.search);
  const outcomeParam = p.get("outcome") as Outcome | null;
  const controlSetParam = p.get("control_set") as ControlSet | null;
  const viewParam = p.get("view") as ViewMode | null;
  const yqParam = p.get("yq");
  const dongParam = p.get("dong");
  const compareParam = p.get("compare");
  const guParam = p.get("gu");

  const outcome = outcomeParam && OUTCOMES.includes(outcomeParam) ? outcomeParam : DEFAULT_OUTCOME;
  const controlSet =
    controlSetParam && CONTROL_SETS.includes(controlSetParam) ? controlSetParam : DEFAULT_CONTROL_SET;
  const view = viewParam && VIEW_MODES.includes(viewParam) ? viewParam : DEFAULT_VIEW;
  const selectedYq = yqParam && /^\d{4}Q[1-4]$/.test(yqParam) ? yqParam : DEFAULT_SELECTED_YQ;

  return {
    outcome,
    controlSet,
    view,
    selectedYq,
    selectedAdmCd: dongParam || null,
    compareAdmCd: compareParam || null,
    selectedGu: guParam || null,
    theme,
  };
}

// Sync store changes to window.location.search
export function updateUrlQuery(state: Partial<AppState>) {
  if (typeof window === "undefined") return;
  const p = new URLSearchParams(window.location.search);

  if (state.outcome && state.outcome !== DEFAULT_OUTCOME) {
    p.set("outcome", state.outcome);
  } else if (state.outcome) {
    p.delete("outcome");
  }

  if (state.controlSet && state.controlSet !== DEFAULT_CONTROL_SET) {
    p.set("control_set", state.controlSet);
  } else if (state.controlSet) {
    p.delete("control_set");
  }

  if (state.view && state.view !== DEFAULT_VIEW) {
    p.set("view", state.view);
  } else if (state.view) {
    p.delete("view");
  }

  if (state.selectedYq && state.selectedYq !== DEFAULT_SELECTED_YQ) {
    p.set("yq", state.selectedYq);
  } else if (state.selectedYq) {
    p.delete("yq");
  }

  if (state.selectedAdmCd) {
    p.set("dong", state.selectedAdmCd);
  } else if (state.selectedAdmCd === null) {
    p.delete("dong");
  }

  if (state.compareAdmCd) {
    p.set("compare", state.compareAdmCd);
  } else if (state.compareAdmCd === null) {
    p.delete("compare");
  }

  if (state.selectedGu) {
    p.set("gu", state.selectedGu);
  } else if (state.selectedGu === null) {
    p.delete("gu");
  }

  const qs = p.toString();
  const newUrl = `${window.location.pathname}${qs ? `?${qs}` : ""}`;
  window.history.replaceState(null, "", newUrl);
}

const initial = getInitialState();

export const useAppStore = create<AppState>((set) => ({
  outcome: initial.outcome,
  controlSet: initial.controlSet,
  view: initial.view,
  selectedYq: initial.selectedYq,
  selectedAdmCd: initial.selectedAdmCd,
  compareAdmCd: initial.compareAdmCd,
  selectedGu: initial.selectedGu,
  theme: initial.theme,
  tourStep: null,
  hoveredScatterAdmCd: null,

  setOutcome: (outcome) => {
    set({ outcome });
    updateUrlQuery({ outcome });
  },
  setControlSet: (controlSet) => {
    set({ controlSet, selectedAdmCd: null, compareAdmCd: null });
    updateUrlQuery({ controlSet, selectedAdmCd: null, compareAdmCd: null });
  },
  setView: (view) => {
    set({ view, selectedAdmCd: null, compareAdmCd: null });
    updateUrlQuery({ view, selectedAdmCd: null, compareAdmCd: null });
  },
  setSelectedYq: (selectedYq) => {
    set({ selectedYq });
    updateUrlQuery({ selectedYq });
  },
  selectAdmCd: (selectedAdmCd) => {
    set({ selectedAdmCd });
    updateUrlQuery({ selectedAdmCd });
  },
  setCompareAdmCd: (compareAdmCd) => {
    set({ compareAdmCd });
    updateUrlQuery({ compareAdmCd });
  },
  setSelectedGu: (selectedGu) => {
    set({ selectedGu });
    updateUrlQuery({ selectedGu });
  },
  setTheme: (theme) => {
    set({ theme });
    if (typeof window !== "undefined") {
      localStorage.setItem("seoul_gtwr_theme", theme);
    }
  },
  setTourStep: (tourStep) => set({ tourStep }),
  setHoveredScatterAdmCd: (hoveredScatterAdmCd) => set({ hoveredScatterAdmCd }),
}));

// Re-export defaults for tests.
export const DEFAULTS = {
  outcome: DEFAULT_OUTCOME,
  controlSet: DEFAULT_CONTROL_SET,
  view: DEFAULT_VIEW,
  selectedYq: DEFAULT_SELECTED_YQ,
  targetYq: DEFAULT_TARGET_YQ,
} as const;
