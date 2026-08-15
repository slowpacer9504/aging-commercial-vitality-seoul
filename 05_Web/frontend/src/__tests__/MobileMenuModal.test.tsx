import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MobileMenuModal } from "@/controls/MobileMenuModal";

describe("MobileMenuModal", () => {
  it("renders settings sheet items when open", () => {
    const onClose = vi.fn();
    const onStartTour = vi.fn();
    const onOpenScatter = vi.fn();
    const onExportMapPng = vi.fn();
    const onOpenGuide = vi.fn();

    render(
      <MobileMenuModal
        isOpen={true}
        onClose={onClose}
        onStartTour={onStartTour}
        onOpenScatter={onOpenScatter}
        onExportMapPng={onExportMapPng}
        onOpenGuide={onOpenGuide}
      />,
    );

    expect(screen.getByText("Settings & Tools")).toBeTruthy();
    expect(screen.getByText("Key Findings Tour")).toBeTruthy();
    expect(screen.getByText("Dynamics Scatter Plot")).toBeTruthy();
    expect(screen.getByText("Export Map View (PNG)")).toBeTruthy();
    expect(screen.getByText("Download Active Layer (CSV)")).toBeTruthy();
    expect(screen.getByText("Copy Shareable Link")).toBeTruthy();
    expect(screen.getByText("Research Guide & Model Spec")).toBeTruthy();
  });

  it("handles tour action click", () => {
    const onClose = vi.fn();
    const onStartTour = vi.fn();
    const onOpenScatter = vi.fn();
    const onExportMapPng = vi.fn();
    const onOpenGuide = vi.fn();

    render(
      <MobileMenuModal
        isOpen={true}
        onClose={onClose}
        onStartTour={onStartTour}
        onOpenScatter={onOpenScatter}
        onExportMapPng={onExportMapPng}
        onOpenGuide={onOpenGuide}
      />,
    );

    fireEvent.click(screen.getByText("Key Findings Tour"));
    expect(onClose).toHaveBeenCalled();
    expect(onStartTour).toHaveBeenCalled();
  });
});
