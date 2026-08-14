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
  x: number; // Local CN
  y: number; // Local beta estimate
  isWarn: boolean;
}

interface CustomTooltipProps {
  active?: boolean;
  payload?: Array<{ payload: ScatterPoint }>;
}

const CustomTooltip: FC<CustomTooltipProps> = ({ active, payload }) => {
  if (active && payload && payload.length) {
    const d = payload[0]!.payload;
    const isPos = d.y > 0;
    const isNeg = d.y < 0;
    return (
      <div className="scatter-tooltip-card">
        <div className="scatter-tt-title">
          <strong>{d.adm_nm}</strong> <span className="scatter-tt-gu">({d.gu_name})</span>
        </div>
        <div className="scatter-tt-row">
          <span>Local β̂:</span>
          <strong className={isPos ? "val-pos" : isNeg ? "val-neg" : ""}>
            {d.y.toFixed(3)}
          </strong>
        </div>
        <div className="scatter-tt-row">
          <span>Local CN:</span>
          <strong className={d.isWarn ? "cn-warn" : "cn-safe"}>
            {d.x.toFixed(1)} {d.isWarn && "⚠"}
          </strong>
        </div>
      </div>
    );
  }
  return null;
};

export const LinkedScatterPlot: FC = () => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const view = useAppStore(s => s.view);
  const selectedYq = useAppStore(s => s.selectedYq);
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);
  const selectAdmCd = useAppStore(s => s.selectAdmCd);
  const setHoveredScatterAdmCd = useAppStore(s => s.setHoveredScatterAdmCd);

  const [features, setFeatures] = useState<CoefficientFeature[]>([]);
  const [isOpen, setIsOpen] = useState(true);

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

  const scatterData: ScatterPoint[] = useMemo(() => {
    return features
      .map(f => {
        const p = f.properties;
        const beta = p.estimate;
        const cn = p.local_cn_gtwr_latest ?? 15.0;
        if (beta == null || Number.isNaN(beta)) return null;
        return {
          adm_cd: p.adm_cd,
          adm_nm: p.adm_nm ?? p.adm_cd,
          gu_name: p.gu_name ?? "Seoul",
          x: cn,
          y: beta,
          isWarn: (p.local_cn_gtwr_latest ?? 0) >= 30 || Boolean(p.collinearity_warn_latest),
        };
      })
      .filter((d): d is ScatterPoint => d !== null);
  }, [features]);

  return (
    <div className="linked-scatter-widget" role="region" aria-label="Linked Scatter Diagnostic">
      <div className="scatter-widget-header" onClick={() => setIsOpen(!isOpen)}>
        <div className="scatter-title-wrap">
          <span className="scatter-icon">📈</span>
          <span className="scatter-title">Diagnostics Scatter (CN vs β̂)</span>
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
          <div className="scatter-chart-wrap">
            <ResponsiveContainer width="100%" height={160}>
              <ScatterChart margin={{ top: 8, right: 10, bottom: 0, left: -20 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                <XAxis
                  type="number"
                  dataKey="x"
                  name="Local CN"
                  tick={{ fontSize: 9, fill: "#64748b" }}
                  axisLine={{ stroke: "#cbd5e1" }}
                  tickLine={false}
                  domain={[0, "auto"]}
                />
                <YAxis
                  type="number"
                  dataKey="y"
                  name="Local Beta"
                  tick={{ fontSize: 9, fill: "#64748b" }}
                  axisLine={{ stroke: "#cbd5e1" }}
                  tickLine={false}
                  domain={["auto", "auto"]}
                />
                <Tooltip content={<CustomTooltip />} />
                <ReferenceLine y={0} stroke="#94a3b8" strokeDasharray="3 3" />
                <ReferenceLine x={30} stroke="#ef4444" strokeDasharray="2 2" />
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
                  {scatterData.map((entry, index) => {
                    const isSelected = entry.adm_cd === selectedAdmCd;
                    const fill = isSelected
                      ? "#2563eb"
                      : entry.y > 0
                        ? "#dc2626"
                        : "#2563eb";
                    return (
                      <Cell
                        key={`cell-${index}`}
                        fill={fill}
                        fillOpacity={isSelected ? 1.0 : 0.65}
                        stroke={isSelected ? "#0f172a" : undefined}
                        strokeWidth={isSelected ? 2 : 0}
                        r={isSelected ? 5 : 3}
                      />
                    );
                  })}
                </Scatter>
              </ScatterChart>
            </ResponsiveContainer>
          </div>
          <div className="scatter-axis-note">
            <span>X: Local CN (Red line: 30 Threshold)</span>
            <span>Y: Local β̂ (0: Neutral)</span>
          </div>
        </div>
      )}
    </div>
  );
};
