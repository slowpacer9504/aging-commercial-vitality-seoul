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

interface Props {
  isOpen: boolean;
  onClose: () => void;
}

export const ScatterPlotModal: FC<Props> = ({ isOpen, onClose }) => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const view = useAppStore(s => s.view);
  const selectedYq = useAppStore(s => s.selectedYq);
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);
  const selectAdmCd = useAppStore(s => s.selectAdmCd);
  const setHoveredScatterAdmCd = useAppStore(s => s.setHoveredScatterAdmCd);

  const [features, setFeatures] = useState<CoefficientFeature[]>([]);

  useEffect(() => {
    if (!isOpen) return;
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
  }, [isOpen, controlSet, outcome, view, selectedYq]);

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

  if (!isOpen) return null;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-content scatter-modal-content"
        onClick={e => e.stopPropagation()}
        role="dialog"
        aria-label="Diagnostics Scatter Plot"
      >
        <div className="modal-header">
          <div>
            <span className="modal-tag">Statistical Diagnostics</span>
            <h2>Local Collinearity (CN) vs Estimated Coefficient (β̂)</h2>
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
            425개 행정동별 GTWR 국지적 조건수(Local Condition Number, X축)와 추정 계수(β̂, Y축)의 산점도입니다.
            점 위에 마우스를 올리면 정보가 표시되고, 클릭 시 해당 동으로 즉시 이동합니다.
          </p>

          <div className="scatter-modal-chart-wrap" style={{ width: "100%", height: 340, minHeight: 340 }}>
            <ResponsiveContainer width="100%" height={340} minHeight={340}>
              <ScatterChart margin={{ top: 10, right: 20, bottom: 20, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis
                  type="number"
                  dataKey="x"
                  name="Local CN"
                  tick={{ fontSize: 11, fill: "#64748b" }}
                  axisLine={{ stroke: "#94a3b8" }}
                  label={{ value: "Local Condition Number (Threshold = 30.0)", position: "insideBottom", offset: -10, fill: "#64748b", fontSize: 12 }}
                  domain={[0, "auto"]}
                />
                <YAxis
                  type="number"
                  dataKey="y"
                  name="Local Beta"
                  tick={{ fontSize: 11, fill: "#64748b" }}
                  axisLine={{ stroke: "#94a3b8" }}
                  label={{ value: "Local Aging Coefficient (β̂)", angle: -90, position: "insideLeft", offset: 10, fill: "#64748b", fontSize: 12 }}
                  domain={["auto", "auto"]}
                />
                <Tooltip content={<CustomTooltip />} />
                <ReferenceLine y={0} stroke="#94a3b8" strokeDasharray="3 3" />
                <ReferenceLine x={30} stroke="#ef4444" strokeDasharray="3 3" label={{ value: "CN ≥ 30 (Warning)", fill: "#ef4444", fontSize: 11 }} />
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
                  {scatterData.map((entry, index) => {
                    const isSelected = entry.adm_cd === selectedAdmCd;
                    const fill = isSelected
                      ? "#2563eb"
                      : entry.y > 0
                        ? "#dc2626"
                        : "#2563eb";
                    return (
                      <Cell
                        key={`modal-cell-${index}`}
                        fill={fill}
                        fillOpacity={isSelected ? 1.0 : 0.7}
                        stroke={isSelected ? "#0f172a" : undefined}
                        strokeWidth={isSelected ? 2 : 0}
                        r={isSelected ? 6 : 4}
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
