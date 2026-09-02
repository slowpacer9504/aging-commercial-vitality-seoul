/**
 * Local collinearity diagnostic threshold and helpers.
 *
 * GTWR reports three local collinearity metrics per dong. They answer different
 * questions and are all displayed:
 *
 *  - `local_vif_max_*` — the largest weighted variance inflation factor in the
 *    local design. The only one with an established rule of thumb (VIF > 10), so
 *    it alone raises the warning flag.
 *  - `local_cn_centered_*` — condition number of the weighted, *centered* design,
 *    describing conditioning within the predictor space. Shown without a
 *    threshold: Belsley's 30 is defined for the uncentered construction and does
 *    not transfer to a centered one.
 *  - `local_cn_gtwr_*` — the uncentered condition number of GWmodel's
 *    `gwr.collin.diagno()` convention, which conditions on the local intercept as
 *    well as the predictors. It runs high on this panel because the intercept is
 *    nearly dependent with the log-scaled controls. Reported for comparability
 *    with the GWR literature; it is not corrected by the centered figure, the two
 *    simply condition on different things.
 *
 * Outputs produced before this contract was introduced carry only the uncentered
 * metric; the centered CN and VIF arrive as null until GTWR is rerun.
 */

export const LOCAL_VIF_WARN_THRESHOLD = 10;

/** Full-scale value for the diagnostic gauge, giving the threshold ~⅓ of the bar. */
export const LOCAL_VIF_GAUGE_MAX = 30;

export const isVifWarn = (vif: number | null | undefined): boolean =>
  vif != null && !Number.isNaN(vif) && vif >= LOCAL_VIF_WARN_THRESHOLD;

/**
 * True when the weighted VIF breaches its threshold. Falls back to the flag the
 * pipeline already computed, which is the only signal available for outputs that
 * predate the VIF column.
 */
export const hasCollinearityWarning = (props: {
  local_vif_max_latest?: number | null;
  collinearity_warn_latest?: boolean;
  collinearity_warn_flag?: boolean;
}): boolean =>
  isVifWarn(props.local_vif_max_latest) ||
  Boolean(props.collinearity_warn_latest) ||
  Boolean(props.collinearity_warn_flag);
