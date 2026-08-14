import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { StoryTourBanner } from "@/tour/StoryTourBanner";
import { useAppStore } from "@/state/store";

describe("StoryTourBanner", () => {
  beforeEach(() => {
    useAppStore.setState({ tourStep: null });
  });

  it("does not render when tourStep is null", () => {
    const { container } = render(<StoryTourBanner />);
    expect(container.firstChild).toBeNull();
  });

  it("renders scene 1 and navigates to scene 2", () => {
    const onMoveCamera = vi.fn();
    useAppStore.setState({ tourStep: 0 });

    render(<StoryTourBanner onMoveCamera={onMoveCamera} />);

    expect(screen.getByText(/Key Findings Guided Tour/)).toBeTruthy();
    expect(screen.getByText(/Scene 1 of 5/)).toBeTruthy();
    expect(onMoveCamera).toHaveBeenCalled();

    const nextBtn = screen.getByRole("button", { name: /Next Scene/i });
    fireEvent.click(nextBtn);

    expect(useAppStore.getState().tourStep).toBe(1);
  });

  it("exits tour when clicking exit button", () => {
    useAppStore.setState({ tourStep: 0 });
    render(<StoryTourBanner />);

    const exitBtn = screen.getByRole("button", { name: /Exit story tour/i });
    fireEvent.click(exitBtn);

    expect(useAppStore.getState().tourStep).toBeNull();
  });
});
