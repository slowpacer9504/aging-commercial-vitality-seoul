import { OUTCOMES, CONTROL_SETS, VIEW_MODES } from "@/types/api";
import type { ViewMode } from "@/types/api";

export const OUTCOME_LABELS: Record<string, string> = {
  vitality_index_base: "Composite vitality index",
  vitality_sub_economic: "Economic vitality",
  vitality_sub_social: "Social vitality",
  vitality_sub_stability: "Stability vitality",
  vitality_sub_temporal: "Temporal vitality",
};

export const CONTROL_SET_LABELS: Record<string, string> = {
  lean: "Lean controls (default)",
  extended: "Extended controls (sensitivity)",
};

export const VIEW_LABELS: Record<ViewMode, string> = {
  latest: "Latest quarter (2025Q4)",
  quarter: "Specific quarter",
  delta: "Change (Δ, earliest→latest)",
};

export const LIVING_AREAS = [
  "도심권",
  "동북권",
  "서북권",
  "서남권",
  "동남권",
] as const;

export type LivingArea = (typeof LIVING_AREAS)[number];

export const LIVING_AREA_GUS: Record<LivingArea, string[]> = {
  도심권: ["종로구", "중구", "용산구"],
  동북권: ["성동구", "광진구", "동대문구", "중랑구", "성북구", "강북구", "도봉구", "노원구"],
  서북권: ["은평구", "서대문구", "마포구"],
  서남권: ["양천구", "강서구", "구로구", "금천구", "영등포구", "동작구", "관악구"],
  동남권: ["서초구", "강남구", "송파구", "강동구"],
};

export const GU_TO_LIVING_AREA: Record<string, LivingArea> = Object.entries(
  LIVING_AREA_GUS
).reduce((acc, [area, gus]) => {
  for (const gu of gus) {
    acc[gu] = area as LivingArea;
  }
  return acc;
}, {} as Record<string, LivingArea>);

export const LIVING_AREA_CENTERS: Record<LivingArea, [number, number, number]> = {
  도심권: [126.985, 37.555, 12.0],
  동북권: [127.050, 37.615, 11.5],
  서북권: [126.920, 37.580, 11.8],
  서남권: [126.890, 37.495, 11.4],
  동남권: [127.080, 37.495, 11.6],
};

export { OUTCOMES, CONTROL_SETS, VIEW_MODES };
