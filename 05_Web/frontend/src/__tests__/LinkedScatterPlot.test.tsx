import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { LinkedScatterPlot } from "@/sidebar/LinkedScatterPlot";

vi.mock("@/api/endpoints", () => ({
  getCoefficients: vi.fn(async () => ({
    features: [
      {
        properties: {
          adm_cd: "0011110515",
          adm_nm: "청운효자동",
          gu_name: "종로구",
          earliest_estimate: 1.25,
          latest_estimate: 2.10,
        },
      },
      {
        properties: {
          adm_cd: "0011680640",
          adm_nm: "역삼1동",
          gu_name: "강남구",
          earliest_estimate: -1.05,
          latest_estimate: -2.15,
        },
      },
    ],
  })),
}));

describe("LinkedScatterPlot", () => {
  it("renders dynamic trajectory scatter widget header and toggle button", () => {
    render(<LinkedScatterPlot />);
    expect(screen.getByText("Dynamics (2019Q4 vs 2025Q4)")).toBeTruthy();
    expect(screen.getByText(/2019Q4 β̂/)).toBeTruthy();
  });

  it("toggles scatter body visibility", () => {
    render(<LinkedScatterPlot />);
    const header = screen.getByText("Dynamics (2019Q4 vs 2025Q4)");
    fireEvent.click(header);
    expect(screen.queryByText(/2019Q4 β̂/)).toBeNull();
  });
});
