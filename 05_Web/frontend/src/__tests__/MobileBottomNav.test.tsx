import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MobileBottomNav } from "@/controls/MobileBottomNav";

describe("MobileBottomNav", () => {
  it("renders all four mobile navigation tabs", () => {
    const onOpenControls = vi.fn();
    const onOpenScatter = vi.fn();
    const onStartTour = vi.fn();

    render(
      <MobileBottomNav
        onOpenControls={onOpenControls}
        onOpenScatter={onOpenScatter}
        onStartTour={onStartTour}
        isSidebarOpen={false}
      />,
    );

    expect(screen.getByText("Map")).toBeTruthy();
    expect(screen.getByText("Controls")).toBeTruthy();
    expect(screen.getByText("Dynamics")).toBeTruthy();
    expect(screen.getByText("Tour")).toBeTruthy();
  });

  it("handles button click events correctly", () => {
    const onOpenControls = vi.fn();
    const onOpenScatter = vi.fn();
    const onStartTour = vi.fn();

    render(
      <MobileBottomNav
        onOpenControls={onOpenControls}
        onOpenScatter={onOpenScatter}
        onStartTour={onStartTour}
        isSidebarOpen={false}
      />,
    );

    fireEvent.click(screen.getByText("Controls"));
    expect(onOpenControls).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByText("Dynamics"));
    expect(onOpenScatter).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByText("Tour"));
    expect(onStartTour).toHaveBeenCalledTimes(1);
  });
});
