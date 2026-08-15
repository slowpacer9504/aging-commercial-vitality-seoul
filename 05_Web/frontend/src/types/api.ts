// Strict TypeScript types mirroring the backend Pydantic models in
// 05_Web/backend/app/models.py. Keep in sync; no `any` allowed.

export type ControlSet = "lean" | "extended";

export const VIEW_MODES = ["latest", "quarter", "delta"] as const;
export type ViewMode = (typeof VIEW_MODES)[number];

export const OUTCOMES = [
  "vitality_sub_economic",
  "vitality_sub_social",
  "vitality_sub_stability",
  "vitality_sub_temporal",
  "vitality_index_base",
] as const;
export type Outcome = (typeof OUTCOMES)[number];

export const CONTROL_SETS: readonly ControlSet[] = ["lean", "extended"];

export interface LookupRow {
  adm_cd: string;
  adm_nm: string;
  adstrd_nm?: string | null;
  gu_prefix?: string | null;
  gu_name?: string | null;
  gu_order?: number | null;
  living_area?: string | null;
  living_area_order?: number | null;
  boundary_year?: string | null;
}

export interface FeatureGeometry {
  type: "Polygon" | "MultiPolygon";
  coordinates: unknown; // nested number arrays; opaque at the TS boundary
}

export interface CoefficientFeatureProps {
  adm_cd: string;
  adm_nm: string | null;
  gu_name: string | null;
  living_area: string | null;
  outcome: Outcome;
  control_set: ControlSet;
  target_yq: string;
  view: ViewMode;
  focal_var: string;
  estimate: number | null;
  earliest_estimate: number | null;
  latest_estimate: number | null;
  earliest_yq: string | null;
  latest_yq: string | null;
  n_obs: number | null;
  n_eff: number | null;
  bw_obs_n: number | null;
  local_cn_gtwr_earliest: number | null;
  local_cn_gtwr_latest: number | null;
  collinearity_warn_latest: boolean;
  collinearity_warn_flag: boolean;
}

export interface CoefficientFeature {
  type: "Feature";
  properties: CoefficientFeatureProps;
  geometry: FeatureGeometry | null;
}

export interface CoefficientFeatureCollection {
  type: "FeatureCollection";
  features: CoefficientFeature[];
}

export interface PanelPoint {
  adm_cd: string;
  year: number;
  quarter: number;
  yq: string;
  quarter_index: number;
  time_id: number;
  outcome: Outcome;
  focal_var: string;
  estimate: number | null;
  estimate_type: string | null;
  control_set: ControlSet;
  n_obs: number | null;
  n_eff: number | null;
  bw_obs_n: number | null;
}

export interface PanelResponse {
  adm_cd: string;
  adm_nm: string | null;
  gu_name: string | null;
  control_set: ControlSet;
  outcome: Outcome;
  target_yq: string;
  points: PanelPoint[];
}

export interface AggregatePanelPoint {
  yq: string;
  year: number;
  quarter: number;
  mean: number;
  median: number;
  min: number;
  max: number;
  q25: number;
  q75: number;
  ribbon: [number, number];
  iqr: [number, number];
  count: number;
}

export interface AggregatePanelResponse {
  name: string;
  region_type: "living_area" | "gu";
  control_set: ControlSet;
  outcome: Outcome;
  dong_count: number;
  points: AggregatePanelPoint[];
}

export interface SummaryRow {
  method: string;
  outcome: Outcome;
  focal_var: string;
  target_yq: string;
  estimate_type: string;
  earliest_yq: string;
  latest_yq: string;
  n_locations: number;
  n_valid: number;
  mean_beta: number | null;
  sd_beta: number | null;
  p25_beta: number | null;
  p50_beta: number | null;
  p75_beta: number | null;
  share_positive: number | null;
  st_bw: number | null;
  global_lm_r2: number | null;
  global_lm_r2_adj: number | null;
  gtw_aic: number | null;
  gtw_aicc: number | null;
  gtw_enp: number | null;
  gtw_edf: number | null;
  collinearity_warn_n: number | null;
  collinearity_warn_share: number | null;
  latest_missing_n: number | null;
  latest_coverage_share: number | null;
  max_local_cn_gtwr: number | null;
  control_set: ControlSet;
  outcome_group: string | null;
  outcome_order: number | null;
}

export interface SummaryResponse {
  control_set: ControlSet;
  summaries: SummaryRow[];
}

export interface MetaResponse {
  outcomes: Outcome[];
  control_sets: ControlSet[];
  focal_var: string[];
  target_yq: string[];
  panel_quarters: string[];
  estimate_breaks: number[];
  delta_breaks: number[];
  delta_earliest_yq: string;
  delta_latest_yq: string;
  n_locations: number;
  coverage_percent: number;
  crs: string;
  artifacts: Record<string, string>;
}

export interface Manifest {
  generated_at: string;
  project_root: string;
  crs_out: string;
  crs_in: string;
  geojson_features: number;
  shp_file: string;
  control_sets: ControlSet[];
  outcomes: Outcome[];
  focal_var: string[];
  target_yq: string[];
  csv_adm_cd_total: number;
  csv_adm_cd_matched: number;
  csv_adm_cd_match_percent: number;
  missing_adm_cd: string[];
  extra_adm_cd: string[];
  panel_quarters: string[];
  estimate_breaks: number[];
  artifacts: Record<string, string>;
}

export interface HealthResponse {
  ok: boolean;
  manifest: Manifest;
}

export interface ApiErrorDetail {
  detail: {
    code: string;
    detail: string;
    hint?: string | null;
  };
}
