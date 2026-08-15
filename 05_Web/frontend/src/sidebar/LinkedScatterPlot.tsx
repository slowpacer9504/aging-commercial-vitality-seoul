import { useState, useEffect, useMemo, type FC, type MouseEvent } from "react";
import { useAppStore } from "@/state/store";
import { getCoefficients } from "@/api/endpoints";
import type { CoefficientFeature } from "@/types/api";

interface ScatterPoint {
  adm_cd: string;
  adm_nm: string;
  gu_name: string;
  x: number; // 2019Q4 estimate
  y: number; // 2025Q4 estimate
  delta: number; // 2025Q4 - 2019Q4
  isGuMatch: boolean;
  isSelected: boolean;
}

function getQuadrantLabel(x: number, y: number): string {
  if (x >= 0 && y >= 0) return "Persistent Hotspot (+/+)";
  if (x < 0 && y >= 0) return "Turnaround to Positive (-/+)";
  if (x < 0 && y < 0) return "Persistent Coldspot (-/-)";
  return "Deteriorated to Negative (+/-)";
}

export const LinkedScatterPlot: FC = () => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const selectedGu = useAppStore(s => s.selectedGu);
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);
  const selectAdmCd = useAppStore(s => s.selectAdmCd);
  const setHoveredScatterAdmCd = useAppStore(s => s.setHoveredScatterAdmCd);

  const [features, setFeatures] = useState<CoefficientFeature[]>([]);
  const [isOpen, setIsOpen] = useState(true);
  const [hoveredPoint, setHoveredPoint] = useState<{ point: ScatterPoint; px: number; py: number } | null>(null);

  useEffect(() => {
    let cancelled = false;
    getCoefficients(controlSet, outcome, "latest")
      .then(fc => {
        if (!cancelled) setFeatures(fc.features ?? []);
      })
      .catch(() => {
        if (!cancelled) setFeatures([]);
      });
    return () => {
      cancelled = true;
    };
  }, [controlSet, outcome]);

  const scatterData: ScatterPoint[] = useMemo(() => {
    return features
      .map(f => {
        const p = f.properties;
        const x = p.earliest_estimate;
        const y = p.latest_estimate;
        if (x == null || y == null || Number.isNaN(x) || Number.isNaN(y)) return null;
        return {
          adm_cd: p.adm_cd,
          adm_nm: p.adm_nm ?? p.adm_cd,
          gu_name: p.gu_name ?? "Seoul",
          x,
          y,
          delta: y - x,
          isGuMatch: selectedGu ? p.gu_name === selectedGu : true,
          isSelected: p.adm_cd === selectedAdmCd,
        };
      })
      .filter((d): d is ScatterPoint => d !== null);
  }, [features, selectedGu, selectedAdmCd]);

  // Dimensions for SVG plotting
  const width = 290;
  const height = 160;
  const pad = { top: 12, right: 14, bottom: 24, left: 30 };

  const { minX, maxX, minY, maxY } = useMemo(() => {
    if (scatterData.length === 0) {
      return { minX: -20, maxX: 20, minY: -20, maxY: 20 };
    }
    const xs = scatterData.map(d => d.x);
    const ys = scatterData.map(d => d.y);
    const rawMinX = Math.min(...xs);
    const rawMaxX = Math.max(...xs);
    const rawMinY = Math.min(...ys);
    const rawMaxY = Math.max(...ys);

    // Symmetric or buffered domain
    const absX = Math.max(Math.abs(rawMinX), Math.abs(rawMaxX), 5);
    const absY = Math.max(Math.abs(rawMinY), Math.abs(rawMaxY), 5);

    return {
      minX: -absX * 1.1,
      maxX: absX * 1.1,
      minY: -absY * 1.1,
      maxY: absY * 1.1,
    };
  }, [scatterData]);

  const scaleX = (val: number) => {
    return pad.left + ((val - minX) / (maxX - minX)) * (width - pad.left - pad.right);
  };

  const scaleY = (val: number) => {
    return height - pad.bottom - ((val - minY) / (maxY - minY)) * (height - pad.top - pad.bottom);
  };

  const zeroX = scaleX(0);
  const zeroY = scaleY(0);

  const handlePointHover = (e: MouseEvent, point: ScatterPoint) => {
    const rect = e.currentTarget.getBoundingClientRect();
    setHoveredPoint({
      point,
      px: rect.left + rect.width / 2,
      py: rect.top,
    });
    setHoveredScatterAdmCd(point.adm_cd);
  };

  const handlePointLeave = () => {
    setHoveredPoint(null);
    setHoveredScatterAdmCd(null);
  };

  return (
    <div className="linked-scatter-widget" role="region" aria-label="Dynamic Trajectory Scatter">
      <div className="scatter-widget-header" onClick={() => setIsOpen(!isOpen)}>
        <div className="scatter-title-wrap">
          <span className="scatter-icon">📈</span>
          <span className="scatter-title">Dynamics (2019Q4 vs 2025Q4)</span>
        </div>
        <button
          type="button"
          className="scatter-toggle-btn"
          aria-expanded={isOpen}
          aria-label="Toggle scatter plot widget"
        >
          {isOpen ? "▲" : "▼"}
        </button>
      </div>

      {isOpen && (
        <div className="scatter-widget-body">
          <div className="scatter-axis-note">
            <span>X: 2019Q4 β̂ (Earliest)</span>
            <span>Y: 2025Q4 β̂ (Latest)</span>
          </div>

          <div className="scatter-chart-wrap" style={{ position: "relative", width: "100%", height: 165 }}>
            <svg
              viewBox={`0 0 ${width} ${height}`}
              width="100%"
              height="100%"
              style={{ display: "block", overflow: "visible" }}
            >
              {/* Plot Background */}
              <rect
                x={pad.left}
                y={pad.top}
                width={width - pad.left - pad.right}
                height={height - pad.top - pad.bottom}
                fill="var(--bg-subtle)"
                rx={4}
              />

              {/* Zero Reference Lines */}
              <line
                x1={zeroX}
                y1={pad.top}
                x2={zeroX}
                y2={height - pad.bottom}
                stroke="#94a3b8"
                strokeWidth={1}
                strokeDasharray="3 3"
              />
              <line
                x1={pad.left}
                y1={zeroY}
                x2={width - pad.right}
                y2={zeroY}
                stroke="#94a3b8"
                strokeWidth={1}
                strokeDasharray="3 3"
              />

              {/* Ticks & Labels */}
              <text x={pad.left + 2} y={zeroY - 4} fontSize={8} fill="#64748b" textAnchor="start">
                0
              </text>
              <text x={zeroX + 4} y={height - pad.bottom - 4} fontSize={8} fill="#64748b">
                0
              </text>
              <text x={width - pad.right} y={height - pad.bottom + 12} fontSize={8.5} fill="#64748b" textAnchor="end">
                {maxX.toFixed(0)}
              </text>
              <text x={pad.left} y={height - pad.bottom + 12} fontSize={8.5} fill="#64748b" textAnchor="start">
                {minX.toFixed(0)}
              </text>
              <text x={pad.left - 4} y={pad.top + 8} fontSize={8.5} fill="#64748b" textAnchor="end">
                {maxY.toFixed(0)}
              </text>
              <text x={pad.left - 4} y={height - pad.bottom} fontSize={8.5} fill="#64748b" textAnchor="end">
                {minY.toFixed(0)}
              </text>

              {/* Scatter Points */}
              {scatterData.map(d => {
                const cx = scaleX(d.x);
                const cy = scaleY(d.y);
                const isSelected = d.isSelected;
                const isGuMatch = !selectedGu || d.isGuMatch;
                const fill = d.delta > 0 ? "#ef4444" : "#2563eb";
                const opacity = isSelected ? 1 : isGuMatch ? 0.75 : 0.18;
                const r = isSelected ? 5.5 : isGuMatch ? 3.2 : 2.2;

                return (
                  <circle
                    key={d.adm_cd}
                    cx={cx}
                    cy={cy}
                    r={r}
                    fill={isSelected ? "#f59e0b" : fill}
                    fillOpacity={opacity}
                    stroke={isSelected ? "#b45309" : isGuMatch ? "#ffffff" : "transparent"}
                    strokeWidth={isSelected ? 1.8 : 0.5}
                    style={{ cursor: "pointer", transition: "r 0.1s" }}
                    onClick={() => selectAdmCd(d.adm_cd)}
                    onMouseEnter={e => handlePointHover(e, d)}
                    onMouseLeave={handlePointLeave}
                  />
                );
              })}
            </svg>

            {/* Custom Tooltip */}
            {hoveredPoint && (
              <div
                className="scatter-tooltip-card"
                style={{
                  position: "absolute",
                  top: 10,
                  right: 10,
                  zIndex: 30,
                  pointerEvents: "none",
                }}
              >
                <div className="scatter-tt-title">
                  <strong>{hoveredPoint.point.adm_nm}</strong>{" "}
                  <span className="scatter-tt-gu">({hoveredPoint.point.gu_name})</span>
                </div>
                <div className="scatter-tt-row">
                  <span>2019Q4 β̂:</span>
                  <strong>{hoveredPoint.point.x.toFixed(3)}</strong>
                </div>
                <div className="scatter-tt-row">
                  <span>2025Q4 β̂:</span>
                  <strong>{hoveredPoint.point.y.toFixed(3)}</strong>
                </div>
                <div className="scatter-tt-row">
                  <span>Change (Δ):</span>
                  <strong className={hoveredPoint.point.delta > 0 ? "val-pos" : "val-neg"}>
                    {hoveredPoint.point.delta > 0 ? "+" : ""}
                    {hoveredPoint.point.delta.toFixed(3)}
                  </strong>
                </div>
                <div className="scatter-tt-quadrant">
                  {getQuadrantLabel(hoveredPoint.point.x, hoveredPoint.point.y)}
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
