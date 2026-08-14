import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { SupplementaryBanner } from "@/controls/SupplementaryBanner";

describe("SupplementaryBanner", () => {
  it("renders the canonical / Supplementary labelling contract", () => {
    render(<SupplementaryBanner />);
    const el = screen.getByTestId("supplementary-banner");
    expect(el.textContent).toMatch(/Canonical/i);
    expect(el.textContent).toMatch(/Supplementary/i);
    expect(el.textContent).toMatch(/2025Q4/i);
  });
});
