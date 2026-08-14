import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { TimeseriesChart } from "@/map/popup/TimeseriesChart";
import type { PanelPoint, PanelResponse } from "@/types/api";
import { useAppStore } from "@/state/store";

const points: PanelPoint[] = [
  { adm_cd: "0011110515", year: 2024, quarter: 4, yq: "2024Q4", quarter_index: 4, time_id: 4, outcome: "vitality_index_base", focal_var: "lag4_age60_resident_share", estimate: -0.5, estimate_type: "local_beta", control_set: "lean", n_obs: 100, n_eff: 90, bw_obs_n: null },
  { adm_cd: "0011110515", year: 2025, quarter: 4, yq: "2025Q4", quarter_index: 4, time_id: 5, outcome: "vitality_index_base", focal_var: "lag4_age60_resident_share", estimate: -1.2, estimate_type: "local_beta", control_set: "lean", n_obs: 100, n_eff: 90, bw_obs_n: null },
];

function makeResponse(): PanelResponse {
  return {
    adm_cd: "0011110515",
    adm_nm: "청운효자동",
    gu_name: "종로구",
    control_set: "lean",
    outcome: "vitality_index_base",
    target_yq: "2025Q4",
    points,
  };
}

describe("TimeseriesChart (Supplementary tag)", () => {
  beforeEach(() => {
    useAppStore.setState({
      outcome: "vitality_index_base",
      controlSet: "lean",
      selectedAdmCd: "0011110515",
    });
    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      new Response(JSON.stringify(makeResponse()), {
        status: 200,
        headers: new Headers({ "content-type": "application/json" }),
      }),
    );
  });
  afterEach(() => {
    vi.restoreAllMocks();
    cleanup();
  });

  it("renders the (Supplementary) tag in the chart title", async () => {
    render(<TimeseriesChart admCd="0011110515" />);
    const tag = await screen.findByTestId("ts-supplementary-tag");
    expect(tag.textContent).toContain("Supplementary");
  });
});
