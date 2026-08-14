import { useState, useEffect, useMemo, type FC } from "react";
import { useAppStore } from "@/state/store";
import { staticGetLookup } from "@/api/staticFallback";
import { getCoefficients } from "@/api/endpoints";
import type { CoefficientFeature, LookupRow } from "@/types/api";

const SEOUL_GUS = [
  "강남구", "강동구", "강북구", "강서구", "관악구",
  "광진구", "구로구", "금천구", "노원구", "도봉구",
  "동대문구", "동작구", "마포구", "서대문구", "서초구",
  "성동구", "성북구", "송파구", "양천구", "영등포구",
  "용산구", "은평구", "종로구", "중구", "중랑구",
];

const fmt = (v: number | null | undefined, digits = 3): string =>
  v == null || Number.isNaN(v) ? "—" : v.toFixed(digits);

export const GuFilterSelector: FC = () => {
  const selectedGu = useAppStore(s => s.selectedGu);
  const setSelectedGu = useAppStore(s => s.setSelectedGu);
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const view = useAppStore(s => s.view);
  const selectedYq = useAppStore(s => s.selectedYq);

  const [features, setFeatures] = useState<CoefficientFeature[]>([]);
  const [, setLookup] = useState<Record<string, LookupRow>>({});

  useEffect(() => {
    staticGetLookup().then(setLookup).catch(() => {});
  }, []);

  useEffect(() => {
    let cancelled = false;
    getCoefficients(controlSet, outcome, view, view === "quarter" ? selectedYq : undefined)
      .then(fc => {
        if (!cancelled) setFeatures(fc.features ?? []);
      })
      .catch(() => {
        if (!cancelled) setFeatures([]);
      });
    return () => {
      cancelled = true;
    };
  }, [controlSet, outcome, view, selectedYq]);

  // Compute stats for the selected Gu
  const guStats = useMemo(() => {
    if (!selectedGu || features.length === 0) return null;
    const guDongs = features.filter(f => f.properties.gu_name === selectedGu);
    if (guDongs.length === 0) return null;

    const estimates = guDongs
      .map(f => f.properties.estimate)
      .filter((v): v is number => v != null && Number.isFinite(v));

    const mean = estimates.length > 0 ? estimates.reduce((a, b) => a + b, 0) / estimates.length : null;
    const warnCount = guDongs.filter(
      f => f.properties.collinearity_warn_latest || f.properties.collinearity_warn_flag,
    ).length;

    let maxDong = guDongs[0]!;
    let minDong = guDongs[0]!;
    for (const d of guDongs) {
      if ((d.properties.estimate ?? -Infinity) > (maxDong.properties.estimate ?? -Infinity)) maxDong = d;
      if ((d.properties.estimate ?? Infinity) < (minDong.properties.estimate ?? Infinity)) minDong = d;
    }

    return {
      dongCount: guDongs.length,
      meanBeta: mean,
      warnCount,
      maxDongName: maxDong.properties.adm_nm ?? maxDong.properties.adm_cd,
      maxDongBeta: maxDong.properties.estimate,
      minDongName: minDong.properties.adm_nm ?? minDong.properties.adm_cd,
      minDongBeta: minDong.properties.estimate,
    };
  }, [selectedGu, features]);

  return (
    <div className="control gu-filter-selector" role="group" aria-labelledby="gu-filter-label">
      <div className="control-header">
        <label id="gu-filter-label" className="control-label">
          District (Gu) Filter
        </label>
        {selectedGu && (
          <button
            type="button"
            className="gu-clear-btn"
            onClick={() => setSelectedGu(null)}
            aria-label="Clear district filter"
          >
            Reset (All Seoul)
          </button>
        )}
      </div>

      <select
        className="gu-select"
        value={selectedGu ?? ""}
        onChange={e => setSelectedGu(e.target.value || null)}
        aria-label="Select Autonomous District (Gu)"
      >
        <option value="">All 25 Autonomous Districts (전체 서울)</option>
        {SEOUL_GUS.map(gu => (
          <option key={gu} value={gu}>
            {gu}
          </option>
        ))}
      </select>

      {guStats && (
        <div className="gu-stats-card">
          <div className="gu-stats-header">
            <span className="gu-stats-title">📍 {selectedGu} Summary</span>
            <span className="gu-stats-count">{guStats.dongCount} Dongs</span>
          </div>
          <div className="gu-stats-grid">
            <div className="gu-stat-item">
              <span className="stat-label">Mean β̂</span>
              <span
                className={`stat-val ${(guStats.meanBeta ?? 0) > 0 ? "val-pos" : "val-neg"}`}
              >
                {fmt(guStats.meanBeta)}
              </span>
            </div>
            <div className="gu-stat-item">
              <span className="stat-label">Collinearity Warn</span>
              <span className={`stat-val ${guStats.warnCount > 0 ? "cn-warn" : "cn-safe"}`}>
                {guStats.warnCount} flagged
              </span>
            </div>
          </div>
          <div className="gu-minmax-row">
            <span title={`Highest impact in ${selectedGu}`}>
              ▲ <strong>{guStats.maxDongName}</strong> ({fmt(guStats.maxDongBeta)})
            </span>
            <span title={`Lowest impact in ${selectedGu}`}>
              ▼ <strong>{guStats.minDongName}</strong> ({fmt(guStats.minDongBeta)})
            </span>
          </div>
        </div>
      )}
    </div>
  );
};
