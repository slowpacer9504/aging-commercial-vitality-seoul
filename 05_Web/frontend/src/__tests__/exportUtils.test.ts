import { describe, it, expect, vi } from "vitest";
import { exportFeaturesToCsv, exportPanelToCsv } from "@/utils/exportUtils";
import type { CoefficientFeature, PanelPoint } from "@/types/api";

describe("exportUtils", () => {
  it("exportFeaturesToCsv triggers download with valid CSV content and BOM", () => {
    let capturedBlob: Blob | null = null;
    const originalCreateObjectURL = URL.createObjectURL;
    URL.createObjectURL = vi.fn((blob: Blob) => {
      capturedBlob = blob;
      return "blob:fake-url";
    });
    URL.revokeObjectURL = vi.fn();

    const mockFeatures: CoefficientFeature[] = [
      {
        type: "Feature",
        geometry: null,
        properties: {
          adm_cd: "0011110515",
          adm_nm: "청운효자동",
          gu_name: "종로구",
          living_area: "도심권",
          outcome: "vitality_index_base",
          control_set: "lean",
          target_yq: "2025Q4",
          view: "latest",
          focal_var: "lag4_age60_resident_share",
          estimate: -4.192,
          earliest_estimate: 1.5,
          latest_estimate: -4.192,
          earliest_yq: "2019Q4",
          latest_yq: "2025Q4",
          n_obs: 10599,
          n_eff: 90.0,
          bw_obs_n: null,
          local_cn_gtwr_earliest: null,
          local_cn_gtwr_latest: 18.2,
          collinearity_warn_latest: false,
          collinearity_warn_flag: false,
        },
      },
    ];

    exportFeaturesToCsv(mockFeatures, "test.csv");
    expect(capturedBlob).not.toBeNull();
    expect(capturedBlob?.type).toContain("text/csv");

    URL.createObjectURL = originalCreateObjectURL;
  });

  it("exportPanelToCsv triggers download for time series data", () => {
    let capturedBlob: Blob | null = null;
    const originalCreateObjectURL = URL.createObjectURL;
    URL.createObjectURL = vi.fn((blob: Blob) => {
      capturedBlob = blob;
      return "blob:fake-url";
    });
    URL.revokeObjectURL = vi.fn();

    const mockPoints: PanelPoint[] = [
      {
        adm_cd: "0011110515",
        year: 2025,
        quarter: 4,
        yq: "2025Q4",
        quarter_index: 25,
        time_id: 25,
        outcome: "vitality_index_base",
        focal_var: "lag4_age60_resident_share",
        estimate: -4.192,
        estimate_type: "latest",
        control_set: "lean",
        n_obs: 10599,
        n_eff: 90.0,
        bw_obs_n: null,
      },
    ];

    exportPanelToCsv(mockPoints, "청운효자동", "panel_test.csv");
    expect(capturedBlob).not.toBeNull();

    URL.createObjectURL = originalCreateObjectURL;
  });
});
