import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { DiagnosticsTable } from "@/map/popup/DiagnosticsTable";
import type { CoefficientFeatureProps } from "@/types/api";

const base: CoefficientFeatureProps = {
  adm_cd: "0011110515",
  adm_nm: "청운효자동",
  gu_name: "종로구",
  living_area: "도심권",
  outcome: "vitality_index_base",
  control_set: "lean",
  target_yq: "2025Q4",
  view: "latest",
  focal_var: "lag4_age60_resident_share",
  estimate: -4.1921,
  earliest_estimate: 1.5,
  latest_estimate: -4.1921,
  earliest_yq: "2019Q4",
  latest_yq: "2025Q4",
  n_obs: 10599,
  n_eff: 90,
  bw_obs_n: null,
};

describe("DiagnosticsTable", () => {
  it("renders adm_cd and the canonical latest β̂", () => {
    render(<DiagnosticsTable props={base} />);
    expect(screen.getByText("0011110515")).toBeTruthy();
    expect(screen.getAllByText(/-4\.192/).length).toBeGreaterThanOrEqual(1);
  });
  it("labels the primary row as Δ for delta view", () => {
    const deltaProps = { ...base, view: "delta" as const, estimate: -5.6921 };
    render(<DiagnosticsTable props={deltaProps} />);
    expect(screen.getByText("Δ β̂ (latest − earliest)")).toBeTruthy();
  });
});
