import { describe, it, expect } from "vitest";
import {
  LOCAL_VIF_WARN_THRESHOLD,
  hasCollinearityWarning,
  isVifWarn,
} from "@/utils/collinearity";

describe("collinearity threshold", () => {
  it("flags a VIF at or above the threshold", () => {
    expect(isVifWarn(LOCAL_VIF_WARN_THRESHOLD)).toBe(true);
    expect(isVifWarn(LOCAL_VIF_WARN_THRESHOLD + 5)).toBe(true);
    expect(isVifWarn(LOCAL_VIF_WARN_THRESHOLD - 0.01)).toBe(false);
    expect(isVifWarn(1.81)).toBe(false);
  });

  it("treats a missing VIF as unmeasured rather than safe or unsafe", () => {
    expect(isVifWarn(null)).toBe(false);
    expect(isVifWarn(undefined)).toBe(false);
    expect(isVifWarn(Number.NaN)).toBe(false);
  });

  it("warns on the weighted VIF", () => {
    expect(hasCollinearityWarning({ local_vif_max_latest: 19.3 })).toBe(true);
    expect(hasCollinearityWarning({ local_vif_max_latest: 1.8 })).toBe(false);
  });

  it("falls back to the pipeline flag for outputs predating the VIF column", () => {
    expect(hasCollinearityWarning({ collinearity_warn_latest: true })).toBe(true);
    expect(hasCollinearityWarning({ collinearity_warn_flag: true })).toBe(true);
    expect(hasCollinearityWarning({})).toBe(false);
  });

  it("does not let a high uncentered CN alone raise a warning", () => {
    // The uncentered GWmodel-convention CN runs in the hundreds on this panel
    // because it conditions on the local intercept; it must not drive the flag.
    expect(hasCollinearityWarning({ local_vif_max_latest: 1.81 })).toBe(false);
  });
});
