import { useEffect, useState, useMemo, type FC } from "react";
import {
  ComposedChart,
  Area,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  CartesianGrid,
} from "recharts";
import { getAggregatePanel } from "@/api/endpoints";
import type { AggregatePanelPoint } from "@/types/api";
import { useAppStore } from "@/state/store";
import { OUTCOME_LABELS } from "@/state/constants";

interface Props {
  name: string;
  regionType: "living_area" | "gu";
  admCds: string[];
}

interface CustomTooltipProps {
  active?: boolean;
  payload?: Array<{ payload: AggregatePanelPoint }>;
  label?: string;
}

const CustomTooltip: FC<CustomTooltipProps> = ({ active, payload, label }) => {
  if (active && payload && payload.length) {
    const pt = payload[0]?.payload;
    if (!pt) return null;
    const isPos = pt.mean >= 0;

    return (
      <div className="regional-chart-tooltip">
        <div className="chart-tooltip-q">{label}</div>
        <div className="chart-tooltip-entry">
          <span>Mean Effect (β̂): </span>
          <strong className={isPos ? "val-pos" : "val-neg"}>
            {pt.mean.toFixed(3)}
          </strong>
        </div>
        <div className="chart-tooltip-entry sub-entry">
          <span>Median β̂: </span>
          <span>{pt.median.toFixed(3)}</span>
        </div>
        <div className="chart-tooltip-entry sub-entry">
          <span>IQR (25%–75%): </span>
          <span>{pt.q25.toFixed(3)} ~ {pt.q75.toFixed(3)}</span>
        </div>
        <div className="chart-tooltip-entry sub-entry">
          <span>Full Range (Min–Max): </span>
          <span>{pt.min.toFixed(3)} ~ {pt.max.toFixed(3)}</span>
        </div>
        <div className="chart-tooltip-entry sub-entry dong-count-note">
          <span>Active Dongs: </span>
          <span>{pt.count}</span>
        </div>
      </div>
    );
  }
  return null;
};

export const RegionalTrajectoryChart: FC<Props> = ({ name, regionType, admCds }) => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);

  const [points, setPoints] = useState<AggregatePanelPoint[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (admCds.length === 0) {
      setPoints([]);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    getAggregatePanel(admCds, outcome, controlSet, name, regionType)
      .then(res => {
        if (!cancelled) {
          setPoints(res.points);
        }
      })
      .catch(e => {
        if (!cancelled) setError(String(e?.message ?? e));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [name, regionType, admCds, outcome, controlSet]);

  const yDomain = useMemo(() => {
    if (points.length === 0) return [0, 0];
    let min = Infinity;
    let max = -Infinity;
    for (const pt of points) {
      if (pt.min < min) min = pt.min;
      if (pt.max > max) max = pt.max;
    }
    const pad = Math.max((max - min) * 0.08, 0.5);
    return [Math.floor((min - pad) * 10) / 10, Math.ceil((max + pad) * 10) / 10];
  }, [points]);

  const handleExportCsv = () => {
    if (points.length === 0) return;
    const outcomeLabel = OUTCOME_LABELS[outcome] ?? outcome;
    const header = "Region,Region_Type,Control_Set,Outcome,Year_Quarter,Mean_Beta,Median_Beta,Min_Beta,Max_Beta,Q25_Beta,Q75_Beta,Dong_Count\n";
    const rows = points.map(pt =>
      `"${name}","${regionType}","${controlSet}","${outcomeLabel}","${pt.yq}",${pt.mean.toFixed(5)},${pt.median.toFixed(5)},${pt.min.toFixed(5)},${pt.max.toFixed(5)},${pt.q25.toFixed(5)},${pt.q75.toFixed(5)},${pt.count}`
    ).join("\n");

    const blob = new Blob([header + rows], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `trajectory_${regionType}_${name}_${outcome}_${controlSet}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="regional-trajectory-card">
      <div className="regional-chart-header">
        <div className="regional-chart-title">
          <span>📈 {name} Trajectory (2019Q4–2025Q4)</span>
        </div>
        <button
          type="button"
          className="regional-export-btn"
          onClick={handleExportCsv}
          title="Download aggregate trajectory CSV dataset"
          aria-label="Download CSV"
          disabled={loading || points.length === 0}
        >
          CSV
        </button>
      </div>

      <div className="regional-chart-legend">
        <span className="legend-item"><span className="legend-line" /> Mean β̂</span>
        <span className="legend-item"><span className="legend-box iqr" /> IQR (50%)</span>
        <span className="legend-item"><span className="legend-box full" /> Min–Max</span>
      </div>

      {loading ? (
        <div className="regional-chart-status">Loading {name} trajectory…</div>
      ) : error ? (
        <div className="regional-chart-status error">Error: {error}</div>
      ) : points.length === 0 ? (
        <div className="regional-chart-status">No trajectory points available.</div>
      ) : (
        <div className="regional-chart-body" style={{ width: "100%", height: 135 }}>
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart
              data={points}
              margin={{ top: 8, right: 10, left: -24, bottom: 0 }}
            >
              <CartesianGrid strokeDasharray="2 2" stroke="var(--border-subtle, #e2e8f0)" opacity={0.5} />
              <XAxis
                dataKey="yq"
                tick={{ fontSize: 9, fill: "var(--text-muted, #64748b)" }}
                tickFormatter={(val: string) => {
                  if (val === "2019Q4" || val === "2021Q4" || val === "2023Q4" || val === "2025Q4") {
                    return val;
                  }
                  return "";
                }}
                interval={0}
                axisLine={{ stroke: "var(--border-subtle, #cbd5e1)" }}
                tickLine={false}
              />
              <YAxis
                domain={yDomain}
                tick={{ fontSize: 9, fill: "var(--text-muted, #64748b)" }}
                tickFormatter={(v: number) => v.toFixed(1)}
                axisLine={{ stroke: "var(--border-subtle, #cbd5e1)" }}
                tickLine={false}
              />
              <Tooltip content={<CustomTooltip />} />
              <ReferenceLine y={0} stroke="#94a3b8" strokeDasharray="3 3" strokeWidth={1} />

              {/* Outer Ribbon: Full Min-Max Range */}
              <Area
                type="monotone"
                dataKey="ribbon"
                stroke="#8b5cf6"
                strokeWidth={1}
                strokeOpacity={0.4}
                fill="#8b5cf6"
                fillOpacity={0.16}
                isAnimationActive={false}
              />

              {/* Inner Ribbon: IQR (25% - 75%) */}
              <Area
                type="monotone"
                dataKey="iqr"
                stroke="none"
                fill="#6366f1"
                fillOpacity={0.24}
                isAnimationActive={false}
              />

              {/* Center Line: Regional Mean */}
              <Line
                type="monotone"
                dataKey="mean"
                stroke="#4f46e5"
                strokeWidth={2}
                dot={false}
                activeDot={{ r: 3.5, strokeWidth: 1.5, stroke: "#ffffff" }}
                isAnimationActive={false}
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
};
