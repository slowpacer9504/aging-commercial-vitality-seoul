import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { GuFilterSelector } from "@/controls/GuFilterSelector";
import { useAppStore } from "@/state/store";

vi.mock("@/api/staticFallback", () => ({
  staticGetLookup: vi.fn(async () => ({})),
}));

vi.mock("@/api/endpoints", () => ({
  getCoefficients: vi.fn(async () => ({
    features: [
      {
        properties: {
          adm_cd: "001",
          adm_nm: "역삼1동",
          gu_name: "강남구",
          estimate: -2.5,
          collinearity_warn_latest: false,
        },
      },
      {
        properties: {
          adm_cd: "002",
          adm_nm: "삼성1동",
          gu_name: "강남구",
          estimate: 1.2,
          collinearity_warn_latest: false,
        },
      },
    ],
  })),
  getAggregatePanel: vi.fn(async () => ({
    name: "강남구",
    region_type: "gu",
    control_set: "lean",
    outcome: "vitality_index_base",
    dong_count: 2,
    points: [
      {
        yq: "2019Q4",
        year: 2019,
        quarter: 4,
        mean: -0.65,
        median: -0.65,
        min: -2.5,
        max: 1.2,
        q25: -1.5,
        q75: 0.2,
        ribbon: [-2.5, 1.2],
        iqr: [-1.5, 0.2],
        count: 2,
      },
    ],
  })),
}));

describe("GuFilterSelector", () => {
  beforeEach(() => {
    useAppStore.setState({ selectedGu: null });
  });

  it("renders district select dropdown", () => {
    render(<GuFilterSelector />);
    expect(screen.getByText("District (Gu) Filter")).toBeTruthy();
    expect(screen.getByText(/All 25 Autonomous Districts/)).toBeTruthy();
  });

  it("selects a district and updates store", async () => {
    render(<GuFilterSelector />);
    const select = screen.getByRole("combobox");
    fireEvent.change(select, { target: { value: "강남구" } });
    expect(useAppStore.getState().selectedGu).toBe("강남구");
    expect(await screen.findByText("📍 강남구 Summary")).toBeTruthy();
    expect(screen.getByText("2 Dongs")).toBeTruthy();
  });
});
