import { useEffect, useState, useMemo, type FC } from "react";
import { useAppStore } from "@/state/store";
import { getCoefficients } from "@/api/endpoints";
import { staticGetLookup } from "@/api/staticFallback";
import type { CoefficientFeatureProps, LookupRow } from "@/types/api";
import { DiagnosticsTable } from "./DiagnosticsTable";
import { TimeseriesChart } from "./TimeseriesChart";

export const FeaturePopup: FC = () => {
  const admCd = useAppStore(s => s.selectedAdmCd);
  const compareAdmCd = useAppStore(s => s.compareAdmCd);
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const view = useAppStore(s => s.view);
  const selectedYq = useAppStore(s => s.selectedYq);
  const clear = useAppStore(s => s.selectAdmCd);
  const setCompareAdmCd = useAppStore(s => s.setCompareAdmCd);

  const [propsA, setPropsA] = useState<CoefficientFeatureProps | null>(null);
  const [propsB, setPropsB] = useState<CoefficientFeatureProps | null>(null);
  const [lookup, setLookup] = useState<Record<string, LookupRow>>({});
  const [isSelectingCompare, setIsSelectingCompare] = useState(false);
  const [compareQuery, setCompareQuery] = useState("");

  useEffect(() => {
    staticGetLookup().then(setLookup).catch(() => {});
  }, []);

  // Fetch primary Dong A data
  useEffect(() => {
    if (!admCd) {
      setPropsA(null);
      return;
    }
    let cancelled = false;
    getCoefficients(controlSet, outcome, view, view === "quarter" ? selectedYq : undefined)
      .then(fc => {
        if (cancelled) return;
        const fA = fc.features.find(ft => ft.properties.adm_cd === admCd) ?? null;
        setPropsA(fA ? fA.properties : null);

        if (compareAdmCd) {
          const fB = fc.features.find(ft => ft.properties.adm_cd === compareAdmCd) ?? null;
          setPropsB(fB ? fB.properties : null);
        } else {
          setPropsB(null);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setPropsA(null);
          setPropsB(null);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [admCd, compareAdmCd, outcome, controlSet, view, selectedYq]);

  // Handle ESC key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (compareAdmCd) {
          setCompareAdmCd(null);
        } else {
          clear(null);
        }
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [clear, compareAdmCd, setCompareAdmCd]);

  // Filter dongs for comparison search
  const compareSearchResults = useMemo(() => {
    const q = compareQuery.trim().toLowerCase();
    if (!q) return Object.values(lookup).slice(0, 10);
    return Object.values(lookup)
      .filter(item => {
        if (item.adm_cd === admCd) return false;
        const dong = (item.adm_nm || "").toLowerCase();
        const gu = (item.gu_name || "").toLowerCase();
        return dong.includes(q) || gu.includes(q) || item.adm_cd.includes(q);
      })
      .slice(0, 10);
  }, [lookup, compareQuery, admCd]);

  if (!admCd || !propsA) return null;

  return (
    <>
      <div
        className="bottom-sheet-backdrop"
        onClick={() => {
          clear(null);
          setCompareAdmCd(null);
        }}
        aria-hidden="true"
      />
      <aside
        className={`feature-popup-drawer ${compareAdmCd ? "is-comparing" : ""}`}
        role="dialog"
        aria-label={`GTWR Diagnostics for ${propsA.adm_nm ?? admCd}`}
      >
        <div className="sheet-drag-handle-wrap" aria-hidden="true">
          <div className="sheet-drag-handle" />
        </div>
        <header className="drawer-header">
          <div className="drawer-title-group">
            <div className="drawer-badges">
              <span className="badge-gu">{propsA.gu_name ?? "Seoul"}</span>
              {propsA.living_area && <span className="badge-area">{propsA.living_area}</span>}
              <span className="badge-code">{propsA.adm_cd}</span>
            </div>
            <h2 className="drawer-title">{propsA.adm_nm ?? propsA.adm_cd}</h2>
          </div>
          <div className="drawer-actions-top">
            <button
              type="button"
              className="drawer-close-btn"
              onClick={() => {
                clear(null);
                setCompareAdmCd(null);
              }}
              aria-label="Close detail panel"
            >
              ✕
            </button>
          </div>
        </header>

      {/* Inline Compare Bar */}
      <div className="drawer-compare-bar">
        {!compareAdmCd ? (
          !isSelectingCompare ? (
            <button
              type="button"
              className="add-compare-btn"
              onClick={() => setIsSelectingCompare(true)}
            >
              <span>+ Compare with another dong (비교 동 선택)</span>
            </button>
          ) : (
            <div className="compare-picker-wrap">
              <div className="compare-picker-header">
                <span className="compare-picker-title">Select Comparison Dong</span>
                <button
                  type="button"
                  className="picker-cancel-btn"
                  onClick={() => {
                    setIsSelectingCompare(false);
                    setCompareQuery("");
                  }}
                >
                  ✕
                </button>
              </div>
              <input
                type="text"
                className="compare-search-input"
                placeholder="Search dong to compare (e.g. 역삼1동, 혜화동)…"
                value={compareQuery}
                onChange={e => setCompareQuery(e.target.value)}
                autoFocus
              />
              <ul className="compare-results-list">
                {compareSearchResults.map(item => (
                  <li
                    key={item.adm_cd}
                    className="compare-result-item"
                    onClick={() => {
                      setCompareAdmCd(item.adm_cd);
                      setIsSelectingCompare(false);
                      setCompareQuery("");
                    }}
                  >
                    <span className="comp-name">{item.adm_nm}</span>
                    <span className="comp-gu">{item.gu_name}</span>
                  </li>
                ))}
              </ul>
            </div>
          )
        ) : (
          <div className="active-compare-status">
            <span className="status-label">
              Comparing with: <strong>{propsB?.adm_nm ?? compareAdmCd}</strong>
            </span>
            <button
              type="button"
              className="clear-compare-btn"
              onClick={() => setCompareAdmCd(null)}
              title="Remove comparison dong"
            >
              ✕ Remove
            </button>
          </div>
        )}
      </div>

      <div className="drawer-body">
        <DiagnosticsTable props={propsA} compareProps={propsB} />
        <TimeseriesChart admCd={admCd} compareAdmCd={compareAdmCd} />
      </div>
    </aside>
  </>
);
};
