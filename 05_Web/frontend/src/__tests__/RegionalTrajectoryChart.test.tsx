import { describe, it, expect, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { RegionalTrajectoryChart } from "@/controls/RegionalTrajectoryChart";
import * as endpoints from "@/api/endpoints";

vi.mock("@/api/endpoints", () => ({
  getAggregatePanel: vi.fn().mockResolvedValue({
    name: "도심권",
    region_type: "living_area",
    control_set: "lean",
    outcome: "vitality_index_base",
    dong_count: 3,
    points: [
      {
        yq: "2019Q4",
        year: 2019,
        quarter: 4,
        mean: -1.25,
        median: -1.2,
        min: -2.5,
        max: 0.1,
        q25: -1.8,
        q75: -0.7,
        ribbon: [-2.5, 0.1],
        iqr: [-1.8, -0.7],
        count: 3,
      },
      {
        yq: "2025Q4",
        year: 2025,
        quarter: 4,
        mean: -0.85,
        median: -0.8,
        min: -1.9,
        max: 0.4,
        q25: -1.3,
        q75: -0.3,
        ribbon: [-1.9, 0.4],
        iqr: [-1.3, -0.3],
        count: 3,
      },
    ],
  }),
}));

describe("RegionalTrajectoryChart", () => {
  it("renders regional trajectory title, legend, and export button", async () => {
    render(
      <RegionalTrajectoryChart
        name="도심권"
        regionType="living_area"
        admCds={["0011110515", "0011110530", "0011110540"]}
      />
    );

    expect(screen.getByText("📈 도심권 Trajectory (2019Q4–2025Q4)")).toBeTruthy();
    expect(screen.getByText("CSV")).toBeTruthy();
    expect(screen.getByText("Mean β̂")).toBeTruthy();
    expect(screen.getByText("IQR (50%)")).toBeTruthy();
    expect(screen.getByText("Min–Max")).toBeTruthy();

    await waitFor(() => {
      expect(endpoints.getAggregatePanel).toHaveBeenCalled();
    });
  });
});
