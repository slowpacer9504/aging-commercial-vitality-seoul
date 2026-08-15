import { useState, useEffect, useMemo, type FC } from "react";
import { useAppStore } from "@/state/store";
import {
  LIVING_AREAS,
  LIVING_AREA_GUS,
  type LivingArea,
} from "@/state/constants";
import { getCoefficients } from "@/api/endpoints";
import type { CoefficientFeature } from "@/types/api";

const fmt = (v: number | null | undefined, digits = 3): string =>
  v == null || Number.isNaN(v) ? "—" : v.toFixed(digits);

export const LivingAreaSelector: FC = () => {
  const selectedLivingArea = useAppStore(s => s.selectedLivingArea);
  const setSelectedLivingArea = useAppStore(s => s.setSelectedLivingArea);
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const view = useAppStore(s => s.view);
  const selectedYq = useAppStore(s => s.selectedYq);

  const [features, setFeatures] = useState<CoefficientFeature[]>([]);

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

  // Compute stats for the selected Living Area
  const areaStats = useMemo(() => {
    if (!selectedLivingArea || features.length === 0) return null;
    const targetGus = new Set(LIVING_AREA_GUS[selectedLivingArea] ?? []);
    const areaDongs = features.filter(f => {
      const gu = f.properties.gu_name;
      return gu ? targetGus.has(gu) : false;
    });

    if (areaDongs.length === 0) return null;

    const estimates = areaDongs
      .map(f => f.properties.estimate)
      .filter((v): v is number => v != null && Number.isFinite(v));

    const mean =
      estimates.length > 0
        ? estimates.reduce((a, b) => a + b, 0) / estimates.length
        : null;

    let maxDong = areaDongs[0]!;
    let minDong = areaDongs[0]!;
    for (const d of areaDongs) {
      if ((d.properties.estimate ?? -Infinity) > (maxDong.properties.estimate ?? -Infinity)) maxDong = d;
      if ((d.properties.estimate ?? Infinity) < (minDong.properties.estimate ?? Infinity)) minDong = d;
    }

    return {
      dongCount: areaDongs.length,
      guCount: targetGus.size,
      meanBeta: mean,
      maxDongName: `${maxDong.properties.gu_name ? `${maxDong.properties.gu_name} ` : ""}${maxDong.properties.adm_nm ?? maxDong.properties.adm_cd}`,
      maxDongBeta: maxDong.properties.estimate,
      minDongName: `${minDong.properties.gu_name ? `${minDong.properties.gu_name} ` : ""}${minDong.properties.adm_nm ?? minDong.properties.adm_cd}`,
      minDongBeta: minDong.properties.estimate,
    };
  }, [selectedLivingArea, features]);

  const handleSelectArea = (area: LivingArea) => {
    if (selectedLivingArea === area) {
      setSelectedLivingArea(null);
    } else {
      setSelectedLivingArea(area);
    }
  };

  return (
    <div
      className="control living-area-selector"
      role="group"
      aria-labelledby="living-area-filter-label"
    >
      <div className="control-header">
        <label id="living-area-filter-label" className="control-label">
          Living Area (생활권) Filter
        </label>
        {selectedLivingArea && (
          <button
            type="button"
            className="gu-clear-btn"
            onClick={() => setSelectedLivingArea(null)}
            aria-label="Clear living area filter"
          >
            Reset (All Seoul)
          </button>
        )}
      </div>

      <div className="living-area-chips" role="radiogroup" aria-label="Seoul Living Areas">
        <button
          type="button"
          className={`area-chip ${selectedLivingArea == null ? "is-active" : ""}`}
          onClick={() => setSelectedLivingArea(null)}
          aria-checked={selectedLivingArea == null}
          role="radio"
        >
          All Seoul
        </button>
        {LIVING_AREAS.map(area => {
          const isActive = selectedLivingArea === area;
          return (
            <button
              key={area}
              type="button"
              className={`area-chip ${isActive ? "is-active" : ""}`}
              onClick={() => handleSelectArea(area)}
              aria-checked={isActive}
              role="radio"
              title={`${area}: ${LIVING_AREA_GUS[area].join(", ")}`}
            >
              {area}
            </button>
          );
        })}
      </div>

      {selectedLivingArea && areaStats && (
        <div className="gu-stats-card">
          <div className="gu-stats-header">
            <span className="gu-stats-title">🏙️ {selectedLivingArea} Summary</span>
            <span className="gu-stats-count">
              {areaStats.guCount} Gus · {areaStats.dongCount} Dongs
            </span>
          </div>

          <div className="gu-stats-grid">
            <div className="gu-stat-item single-stat">
              <span className="stat-label">Mean Effect (β̂)</span>
              <span
                className={`stat-val ${(areaStats.meanBeta ?? 0) >= 0 ? "val-pos" : "val-neg"}`}
              >
                {fmt(areaStats.meanBeta)}
              </span>
            </div>
          </div>

          <div className="gu-minmax-row">
            <span title={`Highest impact in ${selectedLivingArea}`}>
              ▲ <strong>{areaStats.maxDongName}</strong> ({fmt(areaStats.maxDongBeta)})
            </span>
            <span title={`Lowest impact in ${selectedLivingArea}`}>
              ▼ <strong>{areaStats.minDongName}</strong> ({fmt(areaStats.minDongBeta)})
            </span>
          </div>
        </div>
      )}
    </div>
  );
};
