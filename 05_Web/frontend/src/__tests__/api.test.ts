import { describe, it, expect, vi, beforeEach } from "vitest";
import { getCoefficients, getMeta, getPanel, getSummary } from "@/api/endpoints";
import type { Outcome } from "@/types/api";

const FIXTURE_META = {
  outcomes: ["vitality_index_base"],
  control_sets: ["lean", "extended"],
  focal_var: ["lag4_age60_resident_share"],
  target_yq: ["2025Q4"],
  panel_quarters: ["2019Q4", "2025Q4"],
  estimate_breaks: [-10, -5, -2, -1, 0, 1, 2, 5, 10],
  delta_breaks: [-20, -10, -5, -2, 0, 2, 5, 10, 20],
  delta_earliest_yq: "2019Q4",
  delta_latest_yq: "2025Q4",
  n_locations: 425,
  coverage_percent: 100.0,
  crs: "EPSG:4326",
  artifacts: {},
} as const;

function makeResponse(body: unknown, ok = true, status = 200): Response {
  return {
    ok,
    status,
    statusText: ok ? "OK" : "Unprocessable Entity",
    headers: new Headers({ "content-type": "application/json" }),
    json: async () => body,
    text: async () => JSON.stringify(body),
    blob: async () => new Blob(),
    arrayBuffer: async () => new ArrayBuffer(0),
    formData: async () => new FormData(),
    clone: () => makeResponse(body, ok, status),
    type: "basic",
    url: "",
    redirected: false,
    bodyUsed: false,
  } as unknown as Response;
}

describe("api endpoints", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("getMeta resolves to typed MetaResponse", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => makeResponse(FIXTURE_META)));
    const m = await getMeta();
    expect(m.target_yq).toEqual(["2025Q4"]);
    expect(m.n_locations).toBe(425);
  });

  it("getCoefficients hits /api/coefficients/{control_set}/{outcome}", async () => {
    const spy = vi.fn(async () => makeResponse({ type: "FeatureCollection", features: [] }));
    vi.stubGlobal("fetch", spy);
    await getCoefficients("lean", "vitality_index_base");
    expect(spy.mock.lastCall?.[0]).toBe(
      "/api/coefficients/lean/vitality_index_base?view=latest",
    );
  });

  it("getCoefficients encodes view=quarter and yq", async () => {
    const spy = vi.fn(async () => makeResponse({ type: "FeatureCollection", features: [] }));
    vi.stubGlobal("fetch", spy);
    await getCoefficients("lean", "vitality_index_base", "quarter", "2023Q2");
    const url = spy.mock.lastCall?.[0] as string;
    expect(url).toContain("view=quarter");
    expect(url).toContain("yq=2023Q2");
  });

  it("getCoefficients encodes view=delta without yq", async () => {
    const spy = vi.fn(async () => makeResponse({ type: "FeatureCollection", features: [] }));
    vi.stubGlobal("fetch", spy);
    await getCoefficients("lean", "vitality_index_base", "delta");
    const url = spy.mock.lastCall?.[0] as string;
    expect(url).toContain("view=delta");
    expect(url).not.toContain("yq=");
  });

  it("getPanel encodes params", async () => {
    const spy = vi.fn(async () =>
      makeResponse({
        adm_cd: "0011110515",
        adm_nm: "x",
        gu_name: "y",
        control_set: "lean",
        outcome: "vitality_index_base",
        target_yq: "2025Q4",
        points: [],
      }),
    );
    vi.stubGlobal("fetch", spy);
    await getPanel("0011110515", "vitality_index_base", "lean", "2022Q1", "2023Q4");
    const url = spy.mock.lastCall?.[0];
    expect(typeof url).toBe("string");
    expect(url as string).toContain("/api/panel/0011110515?");
    expect(url as string).toContain("outcome=vitality_index_base");
    expect(url as string).toContain("control_set=lean");
    expect(url as string).toContain("q_start=2022Q1");
    expect(url as string).toContain("q_end=2023Q4");
  });

  it("getSummary hits /api/summary/{c}", async () => {
    const spy = vi.fn(async () => makeResponse({ control_set: "lean", summaries: [] }));
    vi.stubGlobal("fetch", spy);
    await getSummary("lean");
    expect(spy.mock.lastCall?.[0]).toBe("/api/summary/lean");
  });

  it("non-2xx surfaces ApiError with code", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => makeResponse({ detail: { code: "invalid_outcome", detail: "bad" } }, false, 422)),
    );
    const badOutcome = "bad" as Outcome; // deliberately invalid; for type test only.
    let thrown: unknown;
    try {
      await getCoefficients("lean", badOutcome);
    } catch (e) {
      thrown = e;
    }
    expect(thrown).toMatchObject({ code: "invalid_outcome", status: 422, message: "bad" });
  });
});
