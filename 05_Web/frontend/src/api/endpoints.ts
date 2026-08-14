// typed endpoint helpers with static fallback support
import { getJSON } from "./client";
import {
  staticGetCoefficients,
  staticGetHealth,
  staticGetMeta,
  staticGetPanel,
  staticGetSummary,
} from "./staticFallback";
import type {
  CoefficientFeatureCollection,
  ControlSet,
  HealthResponse,
  MetaResponse,
  Outcome,
  PanelResponse,
  SummaryResponse,
  ViewMode,
} from "@/types/api";

const withFallback = async <T>(apiCall: () => Promise<T>, fallbackCall: () => Promise<T>): Promise<T> => {
  try {
    return await apiCall();
  } catch (e) {
    if (
      e instanceof TypeError ||
      (e && typeof e === "object" && "status" in e && (e as { status: number }).status === 404)
    ) {
      return fallbackCall();
    }
    throw e;
  }
};

export const getHealth = (): Promise<HealthResponse> =>
  withFallback(() => getJSON("/api/health"), staticGetHealth);

export const getMeta = (): Promise<MetaResponse> =>
  withFallback(() => getJSON("/api/meta"), staticGetMeta);

export const getCoefficients = (
  controlSet: ControlSet,
  outcome: Outcome,
  view: ViewMode = "latest",
  yq?: string,
): Promise<CoefficientFeatureCollection> => {
  const p = new URLSearchParams({ view });
  if (view === "quarter" && yq) p.set("yq", yq);
  const qs = p.toString();
  return withFallback(
    () =>
      getJSON(
        `/api/coefficients/${encodeURIComponent(controlSet)}/${encodeURIComponent(outcome)}${qs ? `?${qs}` : ""}`,
      ),
    () => staticGetCoefficients(controlSet, outcome, view, yq),
  );
};

export const getPanel = (
  admCd: string,
  outcome: Outcome,
  controlSet: ControlSet = "lean",
  qStart?: string,
  qEnd?: string,
): Promise<PanelResponse> => {
  const p = new URLSearchParams({
    outcome,
    control_set: controlSet,
  });
  if (qStart) p.set("q_start", qStart);
  if (qEnd) p.set("q_end", qEnd);
  return withFallback(
    () => getJSON(`/api/panel/${encodeURIComponent(admCd)}?${p.toString()}`),
    () => staticGetPanel(admCd, outcome, controlSet),
  );
};

export const getSummary = (controlSet: ControlSet): Promise<SummaryResponse> =>
  withFallback(
    () => getJSON(`/api/summary/${encodeURIComponent(controlSet)}`),
    () => staticGetSummary(controlSet),
  );
