/**
 * Static fallback adapter for standalone frontend deployments (Cloudflare / GitHub Pages)
 * Loads static JSON artifacts from /data/ directly when FastAPI backend is unreachable.
 */
import type {
  CoefficientFeature,
  CoefficientFeatureCollection,
  CoefficientFeatureProps,
  ControlSet,
  FeatureGeometry,
  HealthResponse,
  LookupRow,
  Manifest,
  MetaResponse,
  Outcome,
  PanelPoint,
  PanelResponse,
  SummaryResponse,
  SummaryRow,
  ViewMode,
} from "@/types/api";

let manifestCache: MetaResponse | null = null;
let rawManifestCache: Manifest | null = null;
let geojsonCache: { type: string; features: Array<{ type: string; geometry: unknown; properties: { adm_cd: string; adm_nm?: string } }> } | null = null;
let lookupCache: Record<string, LookupRow> | null = null;
const coefficientsCache: Record<string, Record<string, Record<string, CoefficientFeatureProps>>> = {};
const summaryCache: Record<string, SummaryRow[]> = {};
const panelCache: Record<string, Record<string, Record<string, PanelPoint[]>>> = {};
const quarterMapCache: Record<string, Record<string, Record<string, Record<string, number | null>>>> = {};

const basePath = (path: string): string => {
  const base = import.meta.env.BASE_URL ?? "/";
  const cleanBase = base.endsWith("/") ? base : `${base}/`;
  const cleanPath = path.startsWith("/") ? path.slice(1) : path;
  return `${cleanBase}${cleanPath}`;
};

async function fetchJSON<T>(url: string): Promise<T> {
  const res = await fetch(basePath(url));
  if (!res.ok) {
    throw new Error(`Failed to load static artifact: ${url} (${res.status})`);
  }
  return (await res.json()) as T;
}

export async function staticGetMeta(): Promise<MetaResponse> {
  if (manifestCache) return manifestCache;
  interface ManifestRaw {
    generated_at?: string;
    project_root?: string;
    crs_in?: string;
    shp_file?: string;
    csv_adm_cd_total?: number;
    csv_adm_cd_matched?: number;
    missing_adm_cd?: string[];
    extra_adm_cd?: string[];
    geojson_features: number;
    csv_adm_cd_match_percent: number;
    crs_out: string;
    control_sets?: ControlSet[];
    outcomes?: Outcome[];
    focal_var?: string[];
    target_yq: string | string[];
    estimate_breaks: number[];
    delta_breaks: number[];
    delta_earliest_yq: string;
    delta_latest_yq: string;
    panel_quarters: string[];
    artifacts?: Record<string, string>;
  }
  const m = await fetchJSON<ManifestRaw>("data/_build_manifest.json");
  const target_yq = Array.isArray(m.target_yq) ? m.target_yq : [m.target_yq];
  const outcomes = (m.outcomes ?? [
    "vitality_index_base",
    "vitality_sub_economic",
    "vitality_sub_social",
    "vitality_sub_stability",
    "vitality_sub_temporal",
  ]) as Outcome[];
  const control_sets = (m.control_sets ?? ["lean", "extended"]) as ControlSet[];

  rawManifestCache = {
    generated_at: m.generated_at ?? "",
    project_root: m.project_root ?? "",
    crs_out: m.crs_out,
    crs_in: m.crs_in ?? "",
    geojson_features: m.geojson_features,
    shp_file: m.shp_file ?? "",
    control_sets,
    outcomes,
    focal_var: m.focal_var ?? ["lag4_age60_resident_share"],
    target_yq,
    csv_adm_cd_total: m.csv_adm_cd_total ?? 425,
    csv_adm_cd_matched: m.csv_adm_cd_matched ?? 425,
    csv_adm_cd_match_percent: m.csv_adm_cd_match_percent,
    missing_adm_cd: m.missing_adm_cd ?? [],
    extra_adm_cd: m.extra_adm_cd ?? [],
    panel_quarters: m.panel_quarters,
    estimate_breaks: m.estimate_breaks,
    artifacts: m.artifacts ?? {},
  };

  manifestCache = {
    outcomes,
    control_sets,
    focal_var: m.focal_var ?? ["lag4_age60_resident_share"],
    target_yq,
    panel_quarters: m.panel_quarters,
    estimate_breaks: m.estimate_breaks,
    delta_breaks: m.delta_breaks,
    delta_earliest_yq: m.delta_earliest_yq,
    delta_latest_yq: m.delta_latest_yq,
    n_locations: m.geojson_features,
    coverage_percent: m.csv_adm_cd_match_percent,
    crs: m.crs_out,
    artifacts: m.artifacts ?? {},
  };
  return manifestCache;
}

export async function staticGetHealth(): Promise<HealthResponse> {
  await staticGetMeta();
  return {
    ok: true,
    manifest: rawManifestCache!,
  };
}

export async function staticGetLookup(): Promise<Record<string, LookupRow>> {
  if (!lookupCache) {
    lookupCache = await fetchJSON<Record<string, LookupRow>>("data/json/lookup.json");
  }
  return lookupCache;
}

export async function staticGetGeoJSON(): Promise<typeof geojsonCache> {
  if (!geojsonCache) {
    geojsonCache = await fetchJSON("data/geojson/seoul_adm_dong.geojson");
  }
  return geojsonCache;
}

export async function staticGetCoefficients(
  controlSet: ControlSet,
  outcome: Outcome,
  view: ViewMode = "latest",
  yq?: string,
): Promise<CoefficientFeatureCollection> {
  const [geo, lookup] = await Promise.all([staticGetGeoJSON(), staticGetLookup()]);
  if (!coefficientsCache[controlSet]) {
    coefficientsCache[controlSet] = await fetchJSON(`data/json/coefficients_${controlSet}.json`);
  }
  const outcomeCoeffs = coefficientsCache[controlSet]?.[outcome] ?? {};

  let quarterEstimates: Record<string, number | null> | null = null;
  if (view === "quarter" && yq) {
    if (!quarterMapCache[controlSet]) {
      try {
        quarterMapCache[controlSet] = await fetchJSON(`data/json/quarter_estimates_${controlSet}.json`);
      } catch {
        quarterMapCache[controlSet] = {};
      }
    }
    quarterEstimates = quarterMapCache[controlSet]?.[outcome]?.[yq] ?? null;
  }

  const features: CoefficientFeature[] = (geo?.features ?? []).map(f => {
    const adm_cd = f.properties.adm_cd;
    const baseProps = outcomeCoeffs[adm_cd] ?? ({} as Partial<CoefficientFeatureProps>);
    const lk = lookup[adm_cd];

    let estimate: number | null = baseProps.estimate ?? null;
    if (view === "delta") {
      if (baseProps.latest_estimate != null && baseProps.earliest_estimate != null) {
        estimate = baseProps.latest_estimate - baseProps.earliest_estimate;
      } else {
        estimate = null;
      }
    } else if (view === "quarter" && quarterEstimates) {
      estimate = quarterEstimates[adm_cd] ?? null;
    }

    const props: CoefficientFeatureProps = {
      adm_cd,
      adm_nm: lk?.adm_nm ?? f.properties.adm_nm ?? adm_cd,
      gu_name: lk?.gu_name ?? null,
      living_area: lk?.living_area ?? null,
      outcome,
      control_set: controlSet,
      target_yq: view === "quarter" && yq ? yq : (baseProps.target_yq ?? "2025Q4"),
      view,
      focal_var: baseProps.focal_var ?? "lag4_age60_resident_share",
      estimate,
      earliest_estimate: baseProps.earliest_estimate ?? null,
      latest_estimate: baseProps.latest_estimate ?? null,
      earliest_yq: baseProps.earliest_yq ?? "2019Q4",
      latest_yq: baseProps.latest_yq ?? "2025Q4",
      n_obs: baseProps.n_obs ?? null,
      n_eff: baseProps.n_eff ?? null,
      bw_obs_n: baseProps.bw_obs_n ?? null,
      local_cn_gtwr_earliest: baseProps.local_cn_gtwr_earliest ?? null,
      local_cn_gtwr_latest: baseProps.local_cn_gtwr_latest ?? null,
      collinearity_warn_latest: Boolean(baseProps.collinearity_warn_latest),
      collinearity_warn_flag: Boolean(baseProps.collinearity_warn_flag),
    };

    return {
      type: "Feature" as const,
      geometry: (f.geometry as FeatureGeometry | null) ?? null,
      properties: props,
    };
  });

  return {
    type: "FeatureCollection" as const,
    features,
  };
}

export async function staticGetPanel(
  admCd: string,
  outcome: Outcome,
  controlSet: ControlSet = "lean",
): Promise<PanelResponse> {
  const lookup = await staticGetLookup();
  const lk = lookup[admCd];
  if (!panelCache[controlSet]) {
    try {
      panelCache[controlSet] = await fetchJSON(`data/json/panel_${controlSet}.json`);
    } catch {
      panelCache[controlSet] = {};
    }
  }
  const points = panelCache[controlSet]?.[admCd]?.[outcome] ?? [];
  return {
    adm_cd: admCd,
    adm_nm: lk?.adm_nm ?? null,
    gu_name: lk?.gu_name ?? null,
    outcome,
    control_set: controlSet,
    target_yq: "2025Q4",
    points,
  };
}

export async function staticGetSummary(controlSet: ControlSet): Promise<SummaryResponse> {
  if (!summaryCache[controlSet]) {
    summaryCache[controlSet] = await fetchJSON(`data/json/summary_${controlSet}.json`);
  }
  return {
    control_set: controlSet,
    summaries: summaryCache[controlSet] ?? [],
  };
}
