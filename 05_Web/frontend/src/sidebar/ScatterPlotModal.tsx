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

interface Props {
  isOpen: boolean;
  onClose: () => void;
}

export const ScatterPlotModal: FC<Props> = ({ isOpen, onClose }) => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const selectedGu = useAppStore(s => s.selectedGu);
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);
  const selectAdmCd = useAppStore(s => s.selectAdmCd);
  const setHoveredScatterAdmCd = useAppStore(s => s.setHoveredScatterAdmCd);

  const [features, setFeatures] = useState<CoefficientFeature[]>([]);

  useEffect(() => {
    if (!isOpen) return;
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
  }, [isOpen, controlSet, outcome]);

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

  if (!isOpen) return null;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-content scatter-modal-content"
        onClick={e => e.stopPropagation()}
        role="dialog"
        aria-label="Dynamic Trajectory Scatter Plot"
      >
        <div className="modal-header">
          <div>
            <span className="modal-tag">Spatiotemporal Dynamics</span>
            <h2>Earliest (2019Q4) vs Latest (2025Q4) Trajectory</h2>
          </div>
          <button
            type="button"
            className="modal-close"
            onClick={onClose}
            aria-label="Close modal"
          >
            ✕
          </button>
        </div>

        <div className="modal-body">
          <p className="scatter-modal-desc">
            Analyzes the four-quadrant dynamic trajectory of local aging coefficients (&beta;&#770;) across 425 administrative dongs between the baseline quarter (2019Q4, X-axis) and the latest quarter (2025Q4, Y-axis). Click any point to close the modal and focus the map on that administrative dong.
          </p>

          <div className="scatter-modal-chart-wrap" style={{ width: "100%", height: 360, minHeight: 360 }}>
            <ResponsiveContainer width="100%" height={360} minHeight={360}>
              <ScatterChart margin={{ top: 10, right: 20, bottom: 20, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis
                  type="number"
                  dataKey="x"
                  name="2019Q4 Beta"
                  tick={{ fontSize: 11, fill: "#64748b" }}
                  axisLine={{ stroke: "#94a3b8" }}
                  label={{ value: "Earliest Period Coefficient (β̂, 2019Q4)", position: "insideBottom", offset: -10, fill: "#64748b", fontSize: 12 }}
                  domain={["auto", "auto"]}
                />
                <YAxis
                  type="number"
                  dataKey="y"
                  name="2025Q4 Beta"
                  tick={{ fontSize: 11, fill: "#64748b" }}
                  axisLine={{ stroke: "#94a3b8" }}
                  label={{ value: "Latest Period Coefficient (β̂, 2025Q4)", angle: -90, position: "insideLeft", offset: 10, fill: "#64748b", fontSize: 12 }}
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
                    if (cd) {
                      selectAdmCd(cd);
                      onClose();
                    }
                  }}
                  onMouseEnter={(entry: unknown) => {
                    const item = entry as { payload?: ScatterPoint; adm_cd?: string } | undefined;
                    const cd = item?.payload?.adm_cd ?? item?.adm_cd;
                    if (cd) setHoveredScatterAdmCd(cd);
                  }}
                  onMouseLeave={() => setHoveredScatterAdmCd(null)}
                >
                  {scatterData.map(entry => {
                    let fill = entry.delta > 0 ? "#ef4444" : "#2563eb";
                    let opacity = 0.75;
                    let radius = 4;

                    if (selectedGu && !entry.isGuMatch) {
                      fill = "#94a3b8";
                      opacity = 0.2;
                      radius = 2.5;
                    } else if (entry.isSelected) {
                      fill = "#f59e0b";
                      opacity = 1.0;
                      radius = 6.5;
                    }

                    return (
                      <Cell
                        key={`modal-cell-${entry.adm_cd}`}
                        fill={fill}
                        fillOpacity={opacity}
                        r={radius}
                      />
                    );
                  })}
                </Scatter>
              </ScatterChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="modal-footer">
          <button type="button" className="modal-btn-primary" onClick={onClose}>
            Close
          </button>
        </div>
      </div>
    </div>
  );
};
