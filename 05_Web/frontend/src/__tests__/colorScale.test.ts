import { describe, it, expect } from "vitest";
import { colorFor, makeColorScale } from "@/map/colorScale";

const BREAKS = [-10, -5, -2, -1, 0, 1, 2, 5, 10];

describe("colorScale.colorFor", () => {
  it("maps negative estimate to blue family (coldspot)", () => {
    expect(colorFor(-7, BREAKS)).toBe("#4575b4"); // -7: in bucket 1 (blue)
  });
  it("maps strongly positive estimate to red family (hotspot)", () => {
    expect(colorFor(7, BREAKS)).toBe("#a50026"); // 7: in bucket 8 (deep red)
  });
  it("maps 0 estimate to the neutral color", () => {
    expect(colorFor(0, BREAKS)).toBe("#ffffff");
  });
  it("maps missing/null estimate to grey", () => {
    expect(colorFor(null, BREAKS)).toBe("#cccccc");
    expect(colorFor(NaN, BREAKS)).toBe("#cccccc");
  });
  it("clamps out-of-domain values to extremes", () => {
    expect(colorFor(-99999, BREAKS)).toBe("#313695"); // Coldest blue
    expect(colorFor(99999, BREAKS)).toBe("#a50026"); // Hottest red
  });
  it("selected mid bucket values reach expected midpoint classes", () => {
    expect(colorFor(-1.5, BREAKS)).toBe("#abd9e9"); // -1.5 <= breaks[3] = -1 -> bucket 3 (light blue)
    expect(colorFor(0.5, BREAKS)).toBe("#fdae61"); // 0.5 <= breaks[5] = 1   -> bucket 5 (light orange)
  });
});

describe("colorScale.makeColorScale", () => {
  it("accepts a 9-entry breaks vector centered at 0", () => {
    expect(() => makeColorScale(BREAKS)).not.toThrow();
  });
  it("rejects breaks with wrong count", () => {
    expect(() => makeColorScale([-2, -1, 0, 1, 2])).toThrow(/9 entries/);
  });
  it("rejects breaks not centered at 0", () => {
    expect(() => makeColorScale([-10, -5, -2, -1, 1, 1, 2, 5, 10])).toThrow(/centre break must be 0/);
  });
});
