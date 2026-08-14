import { useEffect, useState, type FC } from "react";
import {
  Line,
  LineChart,
  ReferenceLine,
  ReferenceArea,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  CartesianGrid,
  Legend,
} from "recharts";
import { getPanel } from "@/api/endpoints";
import { staticGetLookup } from "@/api/staticFallback";
import { exportPanelToCsv } from "@/utils/exportUtils";
import type { PanelPoint, LookupRow } from "@/types/api";
import { useAppStore } from "@/state/store";
import { OUTCOME_LABELS } from "@/state/constants";

interface Props {
  admCd: string;
  compareAdmCd?: string | null;
}

interface CustomTooltipProps {
  active?: boolean;
  payload?: Array<{ name: string; value: number; color: string }>;
  label?: string;
}

const CustomTooltip: FC<CustomTooltipProps> = ({ active, payload, label }) => {
  if (active && payload && payload.length) {
    return (
      <div className="chart-custom-tooltip">
        <div className="chart-tooltip-q">{label}</div>
        {payload.map((item, idx) => {
          const val = item.value;
          const isPos = val != null && val > 0;
          const isNeg = val != null && val < 0;
          return (
            <div key={idx} className="chart-tooltip-entry" style={{ color: item.color }}>
              <span>{item.name}: </span>
              <strong className={isPos ? "val-pos" : isNeg ? "val-neg" : ""}>
                {val != null ? val.toFixed(4) : "—"}
              </strong>
            </div>
          );
        })}
      </div>
    );
  }
  return null;
};

export const TimeseriesChart: FC<Props> = ({ admCd, compareAdmCd }) => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);

  const [pointsA, setPointsA] = useState<PanelPoint[]>([]);
  const [pointsB, setPointsB] = useState<PanelPoint[]>([]);
  const [lookup, setLookup] = useState<Record<string, LookupRow>>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    staticGetLookup().then(setLookup).catch(() => {});
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);

    const promises = [getPanel(admCd, outcome, controlSet)];
    if (compareAdmCd) {
      promises.push(getPanel(compareAdmCd, outcome, controlSet));
    }

    Promise.all(promises)
      .then(([resA, resB]) => {
        if (cancelled) return;
        setPointsA(resA?.points ?? []);
        setPointsB(resB?.points ?? []);
      })
      .catch(e => {
        if (cancelled) setError(String(e?.message ?? e));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [admCd, compareAdmCd, outcome, controlSet]);

  if (loading) return <div className="ts-loading">Loading panel trajectory…</div>;
  if (error) return <div className="ts-error">Error: {error}</div>;
  if (pointsA.length === 0) {
    return <div className="ts-empty">No panel data for this dong + outcome.</div>;
  }

  const nameA = lookup[admCd]?.adm_nm ?? admCd;
  const nameB = compareAdmCd ? lookup[compareAdmCd]?.adm_nm ?? compareAdmCd : null;

  // Merge points into unified time series
  const data = pointsA.map(pA => {
    const pB = pointsB.find(b => b.yq === pA.yq);
    return {
      yq: pA.yq,
      estimateA: pA.estimate ?? null,
      estimateB: pB ? pB.estimate ?? null : null,
    };
  });

  const outcomeLabel = OUTCOME_LABELS[outcome] ?? outcome;

  const handleExportCsv = () => {
    exportPanelToCsv(pointsA, nameA, `${admCd}_${outcome}_trajectory.csv`);
  };

  return (
    <article className="timeseries-chart" role="figure" aria-label="Supplementary time series">
      <div className="ts-header">
        <div>
          <h3 className="ts-title">
            β̂ Trajectory (2019Q4–2025Q4)
            <span className="ts-supplementary" data-testid="ts-supplementary-tag">
              {" "}
              (Supplementary)
            </span>
          </h3>
          <span className="ts-outcome-tag">{outcomeLabel}</span>
        </div>
        <button
          type="button"
          className="ts-export-btn"
          onClick={handleExportCsv}
          title="Download trajectory data as CSV"
        >
          📥 CSV
        </button>
      </div>

      <div className="ts-chart-container">
        <ResponsiveContainer width="100%" height={210}>
          <LineChart data={data} margin={{ top: 10, right: 12, bottom: 4, left: -10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" vertical={false} />
            <XAxis
              dataKey="yq"
              tick={{ fontSize: 10, fill: "#64748b" }}
              interval={3}
              axisLine={{ stroke: "#cbd5e1" }}
              tickLine={false}
            />
            <YAxis
              tick={{ fontSize: 10, fill: "#64748b" }}
              axisLine={{ stroke: "#cbd5e1" }}
              tickLine={false}
              domain={["auto", "auto"]}
            />
            <Tooltip content={<CustomTooltip />} />
            {compareAdmCd && <Legend wrapperStyle={{ fontSize: 11, paddingTop: 4 }} />}

            {/* COVID-19 Period Highlight Band */}
            <ReferenceArea
              x1="2020Q1"
              x2="2022Q2"
              fill="#f8fafc"
              fillOpacity={0.8}
              stroke="#e2e8f0"
              strokeDasharray="2 2"
            />

            {/* Zero Baseline */}
            <ReferenceLine y={0} stroke="#94a3b8" strokeDasharray="3 3" strokeWidth={1} />

            {/* Line A: Primary Dong */}
            <Line
              type="monotone"
              name={nameA}
              dataKey="estimateA"
              stroke="#2563eb"
              strokeWidth={2}
              dot={{ r: 2.5, fill: "#2563eb", strokeWidth: 1 }}
              activeDot={{ r: 5, fill: "#1d4ed8" }}
              isAnimationActive={false}
            />

            {/* Line B: Comparison Dong (if present) */}
            {compareAdmCd && (
              <Line
                type="monotone"
                name={nameB ?? "Dong B"}
                dataKey="estimateB"
                stroke="#9333ea"
                strokeWidth={2}
                strokeDasharray="4 3"
                dot={{ r: 2.5, fill: "#9333ea", strokeWidth: 1 }}
                activeDot={{ r: 5, fill: "#7e22ce" }}
                isAnimationActive={false}
              />
            )}
          </LineChart>
        </ResponsiveContainer>
      </div>

      <div className="ts-legend-note">
        <span>Gray band: COVID-19 period (2020Q1–2022Q2)</span>
        <span>Baseline (0): Neutral impact</span>
      </div>
    </article>
  );
};
