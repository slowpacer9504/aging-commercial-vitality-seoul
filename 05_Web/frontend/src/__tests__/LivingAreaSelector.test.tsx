import { describe, it, expect, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { LivingAreaSelector } from "@/controls/LivingAreaSelector";
import { useAppStore } from "@/state/store";

describe("LivingAreaSelector", () => {
  beforeEach(() => {
    useAppStore.setState({
      selectedLivingArea: null,
      selectedGu: null,
    });
  });

  it("renders living area filter label and chip buttons", () => {
    render(<LivingAreaSelector />);
    expect(screen.getByText("Living Area (생활권) Filter")).toBeTruthy();
    expect(screen.getByText("All Seoul")).toBeTruthy();
    expect(screen.getByText("도심권")).toBeTruthy();
    expect(screen.getByText("동북권")).toBeTruthy();
    expect(screen.getByText("서북권")).toBeTruthy();
    expect(screen.getByText("서남권")).toBeTruthy();
    expect(screen.getByText("동남권")).toBeTruthy();
  });

  it("selects a living area chip and updates store", () => {
    render(<LivingAreaSelector />);
    const dongbukChip = screen.getByText("동북권");
    fireEvent.click(dongbukChip);

    expect(useAppStore.getState().selectedLivingArea).toBe("동북권");
    expect(screen.getByText("Reset (All Seoul)")).toBeTruthy();
  });

  it("clears living area when Reset (All Seoul) is clicked", () => {
    useAppStore.setState({ selectedLivingArea: "도심권" });
    render(<LivingAreaSelector />);

    const resetBtn = screen.getByText("Reset (All Seoul)");
    fireEvent.click(resetBtn);

    expect(useAppStore.getState().selectedLivingArea).toBeNull();
  });
});
