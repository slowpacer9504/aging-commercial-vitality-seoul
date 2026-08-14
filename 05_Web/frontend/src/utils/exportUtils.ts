import type { MapRef } from "react-map-gl/maplibre";
import type { ControlSet, Outcome, ViewMode, CoefficientFeature, PanelPoint } from "@/types/api";

const OUTCOME_SLUGS: Record<string, string> = {
  vitality_index_base: "composite",
  vitality_sub_economic: "economic",
  vitality_sub_social: "social",
  vitality_sub_stability: "stability",
  vitality_sub_temporal: "temporal",
};

export function getSpecSlug(
  outcome: Outcome,
  controlSet: ControlSet,
  view: ViewMode,
  selectedYq: string,
  selectedGu?: string | null,
): string {
  const out = OUTCOME_SLUGS[outcome] ?? outcome;
  const ctrl = controlSet;
  const time = view === "quarter" ? selectedYq : view === "delta" ? "delta" : "2025Q4";
  const gu = selectedGu ? `_${selectedGu}` : "";
  return `${out}_${ctrl}_${time}${gu}`;
}

export function generateMapPngFilename(
  outcome: Outcome,
  controlSet: ControlSet,
  view: ViewMode,
  selectedYq: string,
  selectedGu?: string | null,
): string {
  const slug = getSpecSlug(outcome, controlSet, view, selectedYq, selectedGu);
  return `seoul_gtwr_${slug}.png`;
}

export function generateCoeffCsvFilename(
  outcome: Outcome,
  controlSet: ControlSet,
  view: ViewMode,
  selectedYq: string,
  selectedGu?: string | null,
): string {
  const slug = getSpecSlug(outcome, controlSet, view, selectedYq, selectedGu);
  return `seoul_gtwr_coefficients_${slug}.csv`;
}

export function generatePanelCsvFilename(
  admNm: string,
  outcome: Outcome,
  controlSet: ControlSet,
): string {
  const out = OUTCOME_SLUGS[outcome] ?? outcome;
  const cleanName = admNm.replace(/\s+/g, "_");
  return `dong_trajectory_${cleanName}_${out}_${controlSet}.csv`;
}

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

export interface MapExportSpecInfo {
  outcomeLabel: string;
  controlSetLabel: string;
  timeLabel: string;
  guLabel?: string | null;
}

/**
 * Capture MapLibre canvas, burn-in academic specification watermark, and download as high-res PNG
 */
export function exportMapCanvasToPng(
  mapRef: MapRef | null,
  specInfo?: MapExportSpecInfo,
  filename = "seoul_gtwr_choropleth.png",
): boolean {
  if (!mapRef) return false;
  try {
    const map = mapRef.getMap();
    if (!map) return false;

    map.once("render", () => {
      try {
        const rawCanvas = map.getCanvas();
        if (!rawCanvas) return;

        // Create an offscreen canvas to compose map + watermark
        const offscreen = document.createElement("canvas");
        offscreen.width = rawCanvas.width;
        offscreen.height = rawCanvas.height;
        const ctx = offscreen.getContext("2d");
        if (!ctx) {
          rawCanvas.toBlob(blob => {
            if (blob) triggerDownload(blob, filename);
          }, "image/png");
          return;
        }

        // 1. Draw raw map canvas
        ctx.drawImage(rawCanvas, 0, 0);

        // 2. Render watermark badge if specInfo is provided
        if (specInfo) {
          const scale = Math.max(1, offscreen.width / 1200);
          const padX = 16 * scale;
          const padY = 16 * scale;
          const cardW = Math.min(offscreen.width - padX * 2, 540 * scale);
          const cardH = 58 * scale;
          const radius = 8 * scale;

          // Watermark background card
          ctx.save();
          ctx.fillStyle = "rgba(15, 23, 42, 0.88)";
          ctx.strokeStyle = "rgba(255, 255, 255, 0.2)";
          ctx.lineWidth = 1.5 * scale;

          ctx.beginPath();
          ctx.roundRect(padX, padY, cardW, cardH, radius);
          ctx.fill();
          ctx.stroke();

          // Text Line 1: Header
          ctx.fillStyle = "#f59e0b";
          ctx.font = `bold ${Math.round(11 * scale)}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
          const title = specInfo.guLabel
            ? `Seoul GTWR Local Estimates · [${specInfo.guLabel}]`
            : "Seoul GTWR Spatiotemporal Local Estimates";
          ctx.fillText(title, padX + 12 * scale, padY + 20 * scale);

          // Text Line 2: Specifications
          ctx.fillStyle = "#ffffff";
          ctx.font = `${Math.round(11.5 * scale)}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
          const specs = `Model: ${specInfo.controlSetLabel}  |  Time: ${specInfo.timeLabel}  |  Outcome: ${specInfo.outcomeLabel}`;
          ctx.fillText(specs, padX + 12 * scale, padY + 42 * scale);

          // Bottom-Right Attribution watermark
          ctx.fillStyle = "rgba(15, 23, 42, 0.75)";
          const attrW = 280 * scale;
          const attrH = 22 * scale;
          const attrX = offscreen.width - attrW - padX;
          const attrY = offscreen.height - attrH - padY;
          ctx.beginPath();
          ctx.roundRect(attrX, attrY, attrW, attrH, 4 * scale);
          ctx.fill();

          ctx.fillStyle = "#cbd5e1";
          ctx.font = `${Math.round(9.5 * scale)}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
          ctx.fillText("Data: Seoul Commercial Analysis (425 Dongs)", attrX + 8 * scale, attrY + 15 * scale);

          ctx.restore();
        }

        offscreen.toBlob(blob => {
          if (blob) {
            triggerDownload(blob, filename);
          }
        }, "image/png");
      } catch (e) {
        console.error("Canvas capture error inside render handler:", e);
      }
    });

    map.triggerRepaint();
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

  const rows = features.map(f => {
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

  const rows = points.map(p => {
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
