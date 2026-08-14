import { useState, useEffect, useMemo, type FC } from "react";
import {
  ScatterChart,
  Scatter,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
  Cell,
} from "recharts";
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

interface CustomTooltipProps {
  active?: boolean;
  payload?: Array<{ payload: ScatterPoint }>;
}

function getQuadrantLabel(x: number, y: number): string {
  if (x >= 0 && y >= 0) return "Persistent Hotspot (+/+)";
  if (x < 0 && y >= 0) return "Turnaround to Positive (-/+)";
  if (x < 0 && y < 0) return "Persistent Coldspot (-/-)";
  return "Deteriorated to Negative (+/-)";
}

const CustomTooltip: FC<CustomTooltipProps> = ({ active, payload }) => {
  if (active && payload && payload.length) {
    const d = payload[0]!.payload;
    const deltaSign = d.delta > 0 ? "+" : "";
    return (
      <div className="scatter-tooltip-card">
        <div className="scatter-tt-title">
          <strong>{d.adm_nm}</strong> <span className="scatter-tt-gu">({d.gu_name})</span>
        </div>
        <div className="scatter-tt-row">
          <span>2019Q4 β̂:</span>
          <strong>{d.x.toFixed(3)}</strong>
        </div>
        <div className="scatter-tt-row">
          <span>2025Q4 β̂:</span>
          <strong>{d.y.toFixed(3)}</strong>
        </div>
        <div className="scatter-tt-row">
          <span>Change (Δ):</span>
          <strong className={d.delta > 0 ? "val-pos" : d.delta < 0 ? "val-neg" : ""}>
            {deltaSign}{d.delta.toFixed(3)}
          </strong>
        </div>
        <div className="scatter-tt-quadrant">
          {getQuadrantLabel(d.x, d.y)}
        </div>
      </div>
    );
  }
  return null;
};

export const LinkedScatterPlot: FC = () => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const selectedGu = useAppStore(s => s.selectedGu);
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);
  const selectAdmCd = useAppStore(s => s.selectAdmCd);
  const setHoveredScatterAdmCd = useAppStore(s => s.setHoveredScatterAdmCd);

  const [features, setFeatures] = useState<CoefficientFeature[]>([]);
  const [isOpen, setIsOpen] = useState(true);

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
        >
          {isOpen ? "▲" : "▼"}
        </button>
      </div>

      {isOpen && (
        <div className="scatter-widget-body">
          <div className="scatter-axis-note">
            <span>X: 2019Q4 β̂ (Pre-COVID)</span>
            <span>Y: 2025Q4 β̂ (Post-COVID)</span>
          </div>
          <div className="scatter-chart-wrap" style={{ minHeight: 165 }}>
            {scatterData.length > 0 ? (
              <ResponsiveContainer width="100%" height={160} minHeight={160}>
                <ScatterChart margin={{ top: 8, right: 10, bottom: 0, left: -20 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                  <XAxis
                    type="number"
                    dataKey="x"
                    name="2019Q4 Beta"
                    tick={{ fontSize: 9, fill: "#64748b" }}
                    axisLine={{ stroke: "#cbd5e1" }}
                    tickLine={false}
                    domain={["auto", "auto"]}
                  />
                  <YAxis
                    type="number"
                    dataKey="y"
                    name="2025Q4 Beta"
                    tick={{ fontSize: 9, fill: "#64748b" }}
                    axisLine={{ stroke: "#cbd5e1" }}
                    tickLine={false}
                    domain={["auto", "auto"]}
                  />
                  <Tooltip content={<CustomTooltip />} />
                  <ReferenceLine y={0} stroke="#94a3b8" strokeDasharray="3 3" />
                  <ReferenceLine x={0} stroke="#94a3b8" strokeDasharray="3 3" />
                  <Scatter
                    data={scatterData}
                    onClick={(entry: unknown) => {
                      const item = entry as { payload?: ScatterPoint; adm_cd?: string } | undefined;
                      const cd = item?.payload?.adm_cd ?? item?.adm_cd;
                      if (cd) selectAdmCd(cd);
                    }}
                    onMouseEnter={(entry: unknown) => {
                      const item = entry as { payload?: ScatterPoint; adm_cd?: string } | undefined;
                      const cd = item?.payload?.adm_cd ?? item?.adm_cd;
                      if (cd) setHoveredScatterAdmCd(cd);
                    }}
                    onMouseLeave={() => setHoveredScatterAdmCd(null)}
                  >
                    {scatterData.map(entry => {
                      let fill = entry.delta > 0 ? "#2563eb" : "#ef4444";
                      let opacity = 0.75;
                      let radius = 3;

                      if (selectedGu && !entry.isGuMatch) {
                        fill = "#94a3b8";
                        opacity = 0.2;
                        radius = 2.2;
                      } else if (entry.isSelected) {
                        fill = "#f59e0b";
                        opacity = 1.0;
                        radius = 5.5;
                      }

                      return (
                        <Cell
                          key={entry.adm_cd}
                          fill={fill}
                          fillOpacity={opacity}
                          r={radius}
                        />
                      );
                    })}
                  </Scatter>
                </ScatterChart>
              </ResponsiveContainer>
            ) : (
              <div style={{ height: 160, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, color: "var(--text-muted)" }}>
                Loading trajectory dynamics…
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
