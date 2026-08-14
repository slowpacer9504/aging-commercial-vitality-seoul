import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SearchBox } from "@/controls/SearchBox";
import { useAppStore } from "@/state/store";

vi.mock("@/api/staticFallback", () => ({
  staticGetLookup: vi.fn(async () => ({
    "0011110515": {
      adm_cd: "0011110515",
      adm_nm: "청운효자동",
      gu_name: "종로구",
      living_area: "도심권",
    },
    "0011680640": {
      adm_cd: "0011680640",
      adm_nm: "역삼1동",
      gu_name: "강남구",
      living_area: "동남권",
    },
  })),
}));

describe("SearchBox", () => {
  beforeEach(() => {
    useAppStore.setState({ selectedAdmCd: null });
  });

  it("renders search input placeholder", () => {
    render(<SearchBox />);
    expect(screen.getByPlaceholderText(/Search dong/)).toBeTruthy();
  });

  it("filters and shows dropdown when typing", async () => {
    render(<SearchBox />);
    const input = screen.getByPlaceholderText(/Search dong/);
    fireEvent.change(input, { target: { value: "역삼" } });
    expect(await screen.findByText("역삼1동")).toBeTruthy();
    expect(screen.getByText("강남구")).toBeTruthy();
  });

  it("selects dong when clicking a result", async () => {
    render(<SearchBox />);
    const input = screen.getByPlaceholderText(/Search dong/);
    fireEvent.change(input, { target: { value: "역삼" } });
    const item = await screen.findByText("역삼1동");
    fireEvent.click(item);
    expect(useAppStore.getState().selectedAdmCd).toBe("0011680640");
  });
});
