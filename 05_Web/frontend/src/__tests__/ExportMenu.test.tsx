import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { ExportMenu } from "@/controls/ExportMenu";

describe("ExportMenu", () => {
  it("renders trigger button and opens dropdown menu", () => {
    const onExportMapPng = vi.fn();
    render(<ExportMenu onExportMapPng={onExportMapPng} />);

    const trigger = screen.getByRole("button", { name: /Share & Export/ });
    expect(trigger).toBeTruthy();

    fireEvent.click(trigger);
    expect(screen.getByText("Copy Shareable Link")).toBeTruthy();
    expect(screen.getByText("Export Map as PNG")).toBeTruthy();
    expect(screen.getByText("Export Coefficients (CSV)")).toBeTruthy();
  });

  it("calls onExportMapPng when clicking export map", () => {
    const onExportMapPng = vi.fn();
    render(<ExportMenu onExportMapPng={onExportMapPng} />);

    fireEvent.click(screen.getByRole("button", { name: /Share & Export/ }));
    const pngBtn = screen.getByText("Export Map as PNG");
    fireEvent.click(pngBtn);

    expect(onExportMapPng).toHaveBeenCalledTimes(1);
  });
});
