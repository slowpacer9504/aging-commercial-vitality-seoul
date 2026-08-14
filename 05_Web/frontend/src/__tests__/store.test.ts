import { describe, it, expect, beforeEach } from "vitest";
import { useAppStore, DEFAULTS } from "@/state/store";

describe("appstore defaults and actions", () => {
  beforeEach(() => {
    useAppStore.setState({
      outcome: DEFAULTS.outcome,
      controlSet: DEFAULTS.controlSet,
      view: DEFAULTS.view,
      selectedYq: DEFAULTS.selectedYq,
      selectedAdmCd: null,
      compareAdmCd: null,
      selectedGu: null,
      theme: "light",
      tourStep: null,
      hoveredScatterAdmCd: null,
    });
  });

  it("defaults to 2025Q4 canonical latest-quarter", () => {
    expect(DEFAULTS.targetYq).toBe("2025Q4");
  });

  it("defaults to vitality_index_base / lean / latest view", () => {
    expect(useAppStore.getState().outcome).toBe("vitality_index_base");
    expect(useAppStore.getState().controlSet).toBe("lean");
    expect(useAppStore.getState().view).toBe("latest");
  });

  it("selecting an adm_cd updates state and clears on null", () => {
    useAppStore.getState().selectAdmCd("0011110515");
    expect(useAppStore.getState().selectedAdmCd).toBe("0011110515");
    useAppStore.getState().selectAdmCd(null);
    expect(useAppStore.getState().selectedAdmCd).toBeNull();
  });

  it("setting comparison dong updates compareAdmCd", () => {
    useAppStore.getState().selectAdmCd("0011110515");
    useAppStore.getState().setCompareAdmCd("0011680640");
    expect(useAppStore.getState().compareAdmCd).toBe("0011680640");
    useAppStore.getState().setCompareAdmCd(null);
    expect(useAppStore.getState().compareAdmCd).toBeNull();
  });

  it("setting district filter updates selectedGu", () => {
    useAppStore.getState().setSelectedGu("강남구");
    expect(useAppStore.getState().selectedGu).toBe("강남구");
    useAppStore.getState().setSelectedGu(null);
    expect(useAppStore.getState().selectedGu).toBeNull();
  });

  it("changing theme updates theme state", () => {
    useAppStore.getState().setTheme("dark");
    expect(useAppStore.getState().theme).toBe("dark");
  });

  it("setting tour step updates tourStep", () => {
    useAppStore.getState().setTourStep(2);
    expect(useAppStore.getState().tourStep).toBe(2);
    useAppStore.getState().setTourStep(null);
    expect(useAppStore.getState().tourStep).toBeNull();
  });

  it("setting hovered scatter adm_cd updates state", () => {
    useAppStore.getState().setHoveredScatterAdmCd("0011110515");
    expect(useAppStore.getState().hoveredScatterAdmCd).toBe("0011110515");
  });

  it("changing control_set clears selected adm_cd and comparison", () => {
    useAppStore.getState().selectAdmCd("0011110515");
    useAppStore.getState().setCompareAdmCd("0011680640");
    useAppStore.getState().setControlSet("extended");
    expect(useAppStore.getState().selectedAdmCd).toBeNull();
    expect(useAppStore.getState().compareAdmCd).toBeNull();
    expect(useAppStore.getState().controlSet).toBe("extended");
  });

  it("changing view clears selected adm_cd and stores the mode", () => {
    useAppStore.getState().selectAdmCd("0011110515");
    useAppStore.getState().setView("delta");
    expect(useAppStore.getState().selectedAdmCd).toBeNull();
    expect(useAppStore.getState().view).toBe("delta");
  });

  it("changing quarter updates selectedYq", () => {
    useAppStore.getState().setSelectedYq("2020Q1");
    expect(useAppStore.getState().selectedYq).toBe("2020Q1");
  });
});
