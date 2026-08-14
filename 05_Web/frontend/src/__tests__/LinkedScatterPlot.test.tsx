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
          estimate: 1.25,
          local_cn_gtwr_latest: 18.5,
          collinearity_warn_latest: false,
        },
      },
      {
        properties: {
          adm_cd: "0011680640",
          adm_nm: "역삼1동",
          gu_name: "강남구",
          estimate: -2.15,
          local_cn_gtwr_latest: 32.0,
          collinearity_warn_latest: true,
        },
      },
    ],
  })),
}));

describe("LinkedScatterPlot", () => {
  it("renders scatter widget header and toggle button", () => {
    render(<LinkedScatterPlot />);
    expect(screen.getByText("Diagnostics Scatter (CN vs β̂)")).toBeTruthy();
    expect(screen.getByText(/Local CN/)).toBeTruthy();
  });

  it("toggles scatter body visibility", () => {
    render(<LinkedScatterPlot />);
    const header = screen.getByText("Diagnostics Scatter (CN vs β̂)");
    fireEvent.click(header);
    expect(screen.queryByText(/Local CN/)).toBeNull();
  });
});
