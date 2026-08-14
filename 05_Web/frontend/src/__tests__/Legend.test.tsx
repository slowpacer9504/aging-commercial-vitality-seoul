import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { Legend } from "@/map/Legend";
import type { CoefficientFeature } from "@/types/api";

const breaks = [-10, -5, -2, -1, 0, 1, 2, 5, 10];
const mockFeatures: CoefficientFeature[] = [
  {
    type: "Feature",
    geometry: null,
    properties: {
      adm_cd: "001",
      adm_nm: "dong1",
      gu_name: "gu1",
      living_area: "area1",
      outcome: "vitality_index_base",
      control_set: "lean",
      target_yq: "2025Q4",
      view: "latest",
      focal_var: "var",
      estimate: -4.5,
      earliest_estimate: null,
      latest_estimate: null,
      earliest_yq: "2019Q4",
      latest_yq: "2025Q4",
      n_obs: 100,
      n_eff: 10,
      bw_obs_n: null,
      local_cn_gtwr_earliest: null,
      local_cn_gtwr_latest: null,
      collinearity_warn_latest: false,
      collinearity_warn_flag: false,
    },
  },
  {
    type: "Feature",
    geometry: null,
    properties: {
      adm_cd: "002",
      adm_nm: "dong2",
      gu_name: "gu2",
      living_area: "area2",
      outcome: "vitality_index_base",
      control_set: "lean",
      target_yq: "2025Q4",
      view: "latest",
      focal_var: "var",
      estimate: 3.2,
      earliest_estimate: null,
      latest_estimate: null,
      earliest_yq: "2019Q4",
      latest_yq: "2025Q4",
      n_obs: 100,
      n_eff: 10,
      bw_obs_n: null,
      local_cn_gtwr_earliest: null,
      local_cn_gtwr_latest: null,
      collinearity_warn_latest: false,
      collinearity_warn_flag: false,
    },
  },
];

describe("Legend", () => {
  it("renders latest view title and endpoints", () => {
    render(
      <Legend
        view="latest"
        breaks={breaks}
        selectedYq="2025Q4"
        features={mockFeatures}
      />,
    );
    expect(screen.getByText("Latest Effect Estimate (signed β̂, 2025Q4)")).toBeTruthy();
    expect(screen.getByText("-10.00")).toBeTruthy();
    expect(screen.getByText("+10.00")).toBeTruthy();
  });

  it("renders delta view title", () => {
    render(
      <Legend
        view="delta"
        breaks={breaks}
        selectedYq="2025Q4"
        features={mockFeatures}
      />,
    );
    expect(screen.getByText("Change in Effect (Δ β̂, earliest→latest)")).toBeTruthy();
  });
});
