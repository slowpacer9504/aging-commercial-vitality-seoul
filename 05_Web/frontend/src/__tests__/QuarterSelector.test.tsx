import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { QuarterSelector } from "@/controls/QuarterSelector";
import { useAppStore } from "@/state/store";

vi.mock("@/api/endpoints", () => ({
  getMeta: vi.fn(async () => ({
    panel_quarters: ["2019Q4", "2020Q1", "2020Q2", "2025Q4"],
  })),
}));

describe("QuarterSelector", () => {
  beforeEach(() => {
    useAppStore.setState({ selectedYq: "2025Q4", view: "quarter" });
  });

  it("renders timeline title and current badge", async () => {
    render(<QuarterSelector />);
    expect(screen.getByText("Spatiotemporal Timeline")).toBeTruthy();
    expect(screen.getAllByText("2025Q4").length).toBeGreaterThanOrEqual(1);
  });

  it("toggles play/pause button state", async () => {
    render(<QuarterSelector />);
    const playBtn = screen.getByRole("button", { name: /Play timeline animation/ });
    expect(playBtn).toBeTruthy();
    fireEvent.click(playBtn);
    expect(screen.getByText("⏸ Pause")).toBeTruthy();
  });
});
