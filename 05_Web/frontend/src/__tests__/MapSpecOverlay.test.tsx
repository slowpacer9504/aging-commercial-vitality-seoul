import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { MapSpecOverlay } from "@/map/MapSpecOverlay";
import { useAppStore } from "@/state/store";

describe("MapSpecOverlay", () => {
  it("renders active model, time, and outcome specifications", () => {
    useAppStore.setState({
      outcome: "vitality_index_base",
      controlSet: "lean",
      view: "latest",
      selectedYq: "2025Q4",
      selectedGu: "종로구",
    });

    render(<MapSpecOverlay />);

    expect(screen.getByText(/GTWR Spatial Estimates/)).toBeTruthy();
    expect(screen.getByText("종로구")).toBeTruthy();
    expect(screen.getByText(/Lean/)).toBeTruthy();
    expect(screen.getByText(/2025Q4 \(Latest\)/)).toBeTruthy();
    expect(screen.getByText(/Composite vitality index/)).toBeTruthy();
  });
});
