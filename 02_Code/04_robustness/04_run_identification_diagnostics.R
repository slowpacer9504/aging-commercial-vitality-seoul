#!/usr/bin/env Rscript

#==============================================================================
# Script    : 04_run_identification_diagnostics.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Test whether the lagged-exposure TWFE design separates an aging
#             effect from dong-specific time trends, through a placebo lead
#             test, a dong-trend specification, and a persistence diagnostic.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-04
# Type      : robustness
# Inputs    : panel_main.parquet
# Outputs   : identification_placebo_lead.csv, identification_trend_spec.csv,
#             identification_exposure_persistence.csv
# DependsOn : 00_setup/config.R, 00_setup/packages.R, 99_utils/utils_io.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# The design justifies its 4-quarter lag as avoiding simultaneous response. A lag
# imposes temporal ordering, but ordering is not identification: if the exposure
# is close to a dong-specific linear trend, then a lagged value, a contemporaneous
# value, and a *lead* are all just positions on the same line, and any dong-level
# outcome trend correlated with the aging trend reproduces the coefficient. These
# three tables measure whether that is the situation here.
options(scipen = 999)

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
load_project_packages()
source(here::here("02_Code", "99_utils", "utils_io.R"))

ensure_dirs(cfg$required_dirs)
append_log(cfg$logs$model_run, sprintf("\n## [%s] 04_run_identification_diagnostics", timestamp()))

OUTCOMES <- c("vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal",
              "vitality_sub_stability", "vitality_index_base")
EXPOSURE <- "lag4_age60_resident_share"
EXPOSURE_SRC <- "age60_resident_share"
CONTROLS <- c("lag4_ln_resident_pop", "lag4_ln_land_price_adjusted",
              "lag4_transit_accessibility", "lag4_ln_workplace_worker_pop")
LEAD_K <- 4L

# The lead is built here and never written back to the panel: the shared-panel
# contract admits registered lag variables only, and a lead is a diagnostic
# construct rather than a model input.
panel_full <- arrow::read_parquet(cfg$paths$panel_main) |>
  dplyr::mutate(adm_cd = as.character(.data$adm_cd)) |>
  dplyr::arrange(.data$adm_cd, .data$quarter_index)

lead_name <- sprintf("lead%d_age60_resident_share", LEAD_K)
panel_full[[lead_name]] <- panel_full |>
  dplyr::group_by(.data$adm_cd) |>
  dplyr::mutate(v = dplyr::lead(.data[[EXPOSURE_SRC]], LEAD_K)) |>
  dplyr::ungroup() |>
  dplyr::pull(.data$v)

panel <- filter_analysis_window(panel_full)
have <- intersect(OUTCOMES, names(panel))
if (length(have) == 0L) stop("[ERROR] no outcomes present in the analysis panel", call. = FALSE)

ctrl_rhs <- paste(CONTROLS[CONTROLS %in% names(panel)], collapse = " + ")

fit_term <- function(fml, term, data) {
  m <- tryCatch(fixest::feols(stats::as.formula(fml), data = data, cluster = ~adm_cd, notes = FALSE),
                error = function(e) NULL)
  if (is.null(m) || !term %in% names(stats::coef(m))) {
    return(list(b = NA_real_, se = NA_real_, p = NA_real_, n = NA_integer_))
  }
  list(b = unname(stats::coef(m)[[term]]), se = unname(fixest::se(m)[[term]]),
       p = unname(fixest::pvalue(m)[[term]]), n = unname(stats::nobs(m)))
}


#==============================================================================
# 1. Placebo: Does Future Exposure Predict the Current Outcome?
#==============================================================================

# Under a causal reading the lag should carry the association and the lead should
# not. If the lead performs as well, the lag is not isolating a direction of
# effect; both are proxying a shared trend.
placebo <- purrr::map_dfr(have, function(y) {
  lag_fit <- fit_term(sprintf("%s ~ %s + %s | adm_cd + yq", y, EXPOSURE, ctrl_rhs), EXPOSURE, panel)
  lead_fit <- fit_term(sprintf("%s ~ %s + %s | adm_cd + yq", y, lead_name, ctrl_rhs), lead_name, panel)

  # Horse race: both together. Informative only if the two are separable, so the
  # within correlation is reported beside it.
  both_lag <- fit_term(sprintf("%s ~ %s + %s + %s | adm_cd + yq", y, EXPOSURE, lead_name, ctrl_rhs), EXPOSURE, panel)
  both_lead <- fit_term(sprintf("%s ~ %s + %s + %s | adm_cd + yq", y, EXPOSURE, lead_name, ctrl_rhs), lead_name, panel)

  tibble::tibble(
    outcome = y,
    lag_beta = lag_fit$b, lag_se = lag_fit$se, lag_p = lag_fit$p, lag_n = lag_fit$n,
    lead_beta = lead_fit$b, lead_se = lead_fit$se, lead_p = lead_fit$p, lead_n = lead_fit$n,
    horserace_lag_beta = both_lag$b, horserace_lag_p = both_lag$p,
    horserace_lead_beta = both_lead$b, horserace_lead_p = both_lead$p,
    lead_significant_at_5pct = is.finite(lead_fit$p) && lead_fit$p < 0.05,
    lag_survives_horserace = is.finite(both_lag$p) && both_lag$p < 0.05,
    placebo_failed = is.finite(lead_fit$p) && lead_fit$p < 0.05
  )
})

write_csv_safe(placebo, cfg$paths$identification_placebo)


#==============================================================================
# 2. Dong-Specific Linear Time Trends
#==============================================================================

# `adm_cd[quarter_index]` adds a separate linear trend per dong, absorbing exactly
# the differential-trend variation the baseline leans on. This is a demanding
# test: because the exposure is itself close to a trend, little identifying
# variation remains and standard errors inflate. A coefficient that vanishes here
# is not proven absent, but it is not separable from a trend either.
trend_spec <- purrr::map_dfr(have, function(y) {
  base <- fit_term(sprintf("%s ~ %s + %s | adm_cd + yq", y, EXPOSURE, ctrl_rhs), EXPOSURE, panel)
  trend <- fit_term(sprintf("%s ~ %s + %s | adm_cd[quarter_index] + yq", y, EXPOSURE, ctrl_rhs), EXPOSURE, panel)

  tibble::tibble(
    outcome = y,
    base_beta = base$b, base_se = base$se, base_p = base$p, base_n = base$n,
    trend_beta = trend$b, trend_se = trend$se, trend_p = trend$p, trend_n = trend$n,
    se_inflation = dplyr::if_else(is.finite(base$se) && base$se > 0, trend$se / base$se, NA_real_),
    sign_flip = is.finite(base$b) && is.finite(trend$b) && sign(base$b) != sign(trend$b),
    loses_5pct_significance = is.finite(base$p) && is.finite(trend$p) && base$p < 0.05 && trend$p >= 0.05,
    survives_dong_trends = is.finite(trend$p) && trend$p < 0.05
  )
})

write_csv_safe(trend_spec, cfg$paths$identification_trend_spec)


#==============================================================================
# 3. How Trend-Like Is the Exposure?
#==============================================================================

# If the exposure is a near-deterministic within-dong trend, a lag conveys no
# information a lead does not, and the two preceding tables have to be read in
# that light rather than as clean tests.
persist <- panel |>
  dplyr::filter(is.finite(.data[[EXPOSURE_SRC]])) |>
  dplyr::group_by(.data$adm_cd) |>
  dplyr::summarise(
    n_quarters = dplyr::n(),
    range_pp = 100 * (max(.data[[EXPOSURE_SRC]]) - min(.data[[EXPOSURE_SRC]])),
    trend_corr = suppressWarnings(stats::cor(.data$quarter_index, .data[[EXPOSURE_SRC]])),
    .groups = "drop"
  ) |>
  dplyr::mutate(abs_trend_corr = abs(.data$trend_corr))

# Within correlation between the lag and the lead, after two-way demeaning: this
# is what decides whether the horse race in section 1 is informative or
# degenerate.
pair <- panel |>
  dplyr::filter(is.finite(.data[[EXPOSURE]]), is.finite(.data[[lead_name]])) |>
  dplyr::group_by(.data$adm_cd) |>
  dplyr::mutate(a = .data[[EXPOSURE]] - mean(.data[[EXPOSURE]]),
                b = .data[[lead_name]] - mean(.data[[lead_name]])) |>
  dplyr::ungroup() |>
  dplyr::group_by(.data$yq) |>
  dplyr::mutate(a = .data$a - mean(.data$a), b = .data$b - mean(.data$b)) |>
  dplyr::ungroup()

within_r <- suppressWarnings(stats::cor(pair$a, pair$b))

persistence <- tibble::tibble(
  exposure = EXPOSURE_SRC,
  n_dongs = nrow(persist),
  median_range_pp = stats::median(persist$range_pp, na.rm = TRUE),
  median_abs_trend_corr = stats::median(persist$abs_trend_corr, na.rm = TRUE),
  share_abs_trend_corr_gt_0.9 = mean(persist$abs_trend_corr > 0.9, na.rm = TRUE),
  share_abs_trend_corr_gt_0.95 = mean(persist$abs_trend_corr > 0.95, na.rm = TRUE),
  lag_lead_raw_corr = suppressWarnings(stats::cor(panel[[EXPOSURE]], panel[[lead_name]], use = "complete.obs")),
  lag_lead_within_corr = within_r,
  lag_lead_within_vif = dplyr::if_else(is.finite(within_r) && abs(within_r) < 1, 1 / (1 - within_r^2), NA_real_),
  horserace_is_informative = is.finite(within_r) && abs(within_r) < 0.9,
  note = "trend_corr is corr(quarter_index, exposure) within dong; lag/lead correlation is after two-way demeaning"
)

write_csv_safe(persistence, cfg$paths$identification_exposure_persistence)


#==============================================================================
# 4. Log
#==============================================================================

n_placebo_fail <- sum(placebo$placebo_failed, na.rm = TRUE)
n_trend_survive <- sum(trend_spec$survives_dong_trends, na.rm = TRUE)

append_log(cfg$logs$data_qc, sprintf(
  "- Identification diagnostics: placebo lead significant for %d of %d outcomes; %d of %d survive dong-specific trends; exposure |corr(t)|>0.9 in %.1f%% of dongs",
  n_placebo_fail, nrow(placebo), n_trend_survive, nrow(trend_spec),
  100 * persistence$share_abs_trend_corr_gt_0.9))

message(sprintf(
  "[DONE] identification diagnostics: %d/%d placebo failures, %d/%d survive dong trends",
  n_placebo_fail, nrow(placebo), n_trend_survive, nrow(trend_spec)))
