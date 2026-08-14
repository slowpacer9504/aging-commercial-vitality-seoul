import type { FC } from "react";
import type { CoefficientFeatureProps } from "@/types/api";

interface Props {
  x: number;
  y: number;
  props: CoefficientFeatureProps;
}

const fmt = (v: number | null | undefined, digits = 3): string =>
  v == null || Number.isNaN(v) ? "—" : v.toFixed(digits);

export const HoverTooltip: FC<Props> = ({ x, y, props }) => {
  const beta = props.estimate;
  const isPos = beta != null && beta > 0;
  const isNeg = beta != null && beta < 0;
  const flag = props.collinearity_warn_latest || props.collinearity_warn_flag;

  return (
    <div
      className="map-hover-tooltip"
      style={{
        left: `${x + 14}px`,
        top: `${y + 14}px`,
      }}
      role="tooltip"
      aria-hidden="true"
    >
      <div className="tooltip-header">
        <span className="tooltip-dong">{props.adm_nm ?? props.adm_cd}</span>
        {props.gu_name && <span className="tooltip-gu">{props.gu_name}</span>}
      </div>
      <div className="tooltip-body">
        <div className="tooltip-row">
          <span className="tooltip-label">Effect β̂</span>
          <span
            className={`tooltip-val ${isPos ? "val-pos" : isNeg ? "val-neg" : ""}`}
          >
            {fmt(beta)}
          </span>
        </div>
        {props.view === "latest" && props.earliest_estimate != null && (
          <div className="tooltip-row-sub">
            <span className="tooltip-label-sub">2019Q4 β̂</span>
            <span className="tooltip-val-sub">{fmt(props.earliest_estimate)}</span>
          </div>
        )}
        {flag && (
          <div className="tooltip-flag">
            <span>⚠ Collinearity Warn</span>
          </div>
        )}
      </div>
    </div>
  );
};
