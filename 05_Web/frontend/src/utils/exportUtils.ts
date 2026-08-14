import type { MapRef } from "react-map-gl/maplibre";
import type { CoefficientFeature, PanelPoint } from "@/types/api";

function triggerDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * Capture MapLibre canvas and download as high-res PNG
 */
export function exportMapCanvasToPng(mapRef: MapRef | null, filename = "seoul_gtwr_map.png"): boolean {
  if (!mapRef) return false;
  try {
    const map = mapRef.getMap();
    const canvas = map.getCanvas();
    if (!canvas) return false;

    canvas.toBlob((blob) => {
      if (blob) {
        triggerDownload(blob, filename);
      }
    }, "image/png");
    return true;
  } catch (err) {
    console.error("Failed to export map canvas:", err);
    return false;
  }
}

/**
 * Export current 425 administrative dong coefficient estimates to CSV (UTF-8 with BOM for Excel)
 */
export function exportFeaturesToCsv(
  features: CoefficientFeature[],
  filename = "seoul_gtwr_coefficients.csv",
): void {
  const headers = [
    "adm_cd",
    "adm_nm",
    "gu_name",
    "living_area",
    "outcome",
    "control_set",
    "view",
    "target_yq",
    "estimate_beta",
    "earliest_estimate_2019Q4",
    "latest_estimate_2025Q4",
    "effective_n",
    "n_obs",
    "local_cn_latest",
    "collinearity_warning",
  ];

  const rows = features.map((f) => {
    const p = f.properties;
    return [
      `"${p.adm_cd}"`,
      `"${p.adm_nm ?? ""}"`,
      `"${p.gu_name ?? ""}"`,
      `"${p.living_area ?? ""}"`,
      `"${p.outcome}"`,
      `"${p.control_set}"`,
      `"${p.view}"`,
      `"${p.target_yq}"`,
      p.estimate ?? "",
      p.earliest_estimate ?? "",
      p.latest_estimate ?? "",
      p.n_eff != null ? p.n_eff.toFixed(2) : "",
      p.n_obs ?? "",
      p.local_cn_gtwr_latest != null ? p.local_cn_gtwr_latest.toFixed(2) : "",
      p.collinearity_warn_latest || p.collinearity_warn_flag ? "TRUE" : "FALSE",
    ].join(",");
  });

  const csvContent = "\uFEFF" + [headers.join(","), ...rows].join("\r\n");
  const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
  triggerDownload(blob, filename);
}

/**
 * Export panel trajectory for a specific dong to CSV
 */
export function exportPanelToCsv(
  points: PanelPoint[],
  admNm: string,
  filename = "dong_panel_trajectory.csv",
): void {
  const headers = [
    "adm_cd",
    "adm_nm",
    "year",
    "quarter",
    "yq",
    "time_id",
    "outcome",
    "control_set",
    "estimate_beta",
    "effective_n",
    "n_obs",
    "bw_obs_n",
  ];

  const rows = points.map((p) => {
    return [
      `"${p.adm_cd}"`,
      `"${admNm}"`,
      p.year,
      p.quarter,
      `"${p.yq}"`,
      p.time_id,
      `"${p.outcome}"`,
      `"${p.control_set}"`,
      p.estimate ?? "",
      p.n_eff != null ? p.n_eff.toFixed(2) : "",
      p.n_obs ?? "",
      p.bw_obs_n ?? "",
    ].join(",");
  });

  const csvContent = "\uFEFF" + [headers.join(","), ...rows].join("\r\n");
  const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
  triggerDownload(blob, filename);
}
