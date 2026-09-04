#!/usr/bin/env Rscript

#==============================================================================
# Script    : 03_run_influence_robustness.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Measure how much of the reported aging effect rests on individual
#             administrative dongs, by leave-one-dong-out influence on the TWFE
#             exposure coefficient and by re-estimation without the outcome-tail
#             dongs.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-04
# Type      : robustness
# Inputs    : panel_main.parquet, adm_region_lookup.parquet
# Outputs   : influence_dfbeta.csv, influence_outlier_dongs.csv,
#             influence_robustness_summary.csv
# DependsOn : 00_setup/config.R, 00_setup/packages.R, 99_utils/utils_io.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# Manual surface: this script is not part of cfg$canonical_pipeline_scripts and
# is run directly. It re-estimates the TWFE baseline many times, which is cheap,
# rather than the SPDM main, which is not; TWFE is the project's declared
# diagnostic layer and shares the main exposure and control contract, so an
# effect that survives here is the one worth re-checking under SPDM.
options(scipen = 999)

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
load_project_packages()
source(here::here("02_Code", "99_utils", "utils_io.R"))

ensure_dirs(cfg$required_dirs)
append_log(cfg$logs$model_run, sprintf("\n## [%s] 03_run_influence_robustness", timestamp()))

OUTCOMES <- c("vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal",
              "vitality_sub_stability", "vitality_index_base")
EXPOSURE <- "lag4_age60_resident_share"
CONTROLS <- c("lag4_ln_resident_pop", "lag4_ln_land_price_adjusted",
              "lag4_transit_accessibility", "lag4_ln_workplace_worker_pop")

# Outcome-tail threshold in pooled z units. 5 is deliberately permissive: it is
# not a rejection rule, only a way to name the dongs that sit far enough out to
# move a pooled standard deviation.
TAIL_Z <- suppressWarnings(as.numeric(Sys.getenv("INFLUENCE_TAIL_Z", unset = "5")))
if (!is.finite(TAIL_Z) || TAIL_Z <= 0) TAIL_Z <- 5

TOP_K <- suppressWarnings(as.integer(Sys.getenv("INFLUENCE_TOP_K", unset = "10")))
if (!is.finite(TOP_K) || TOP_K < 1L) TOP_K <- 10L


#==============================================================================
# 1. Input
#==============================================================================

panel <- read_panel_main_view("twfe", extra_cols = c("total_sales", "total_store_count"))
lookup <- arrow::read_parquet(cfg$paths$adm_region_lookup) |>
  dplyr::select(dplyr::all_of(c("adm_cd", "adm_nm", "gu_name")))

panel <- panel |>
  dplyr::mutate(adm_cd = as.character(adm_cd)) |>
  dplyr::left_join(lookup |> dplyr::mutate(adm_cd = as.character(adm_cd)), by = "adm_cd")

if (nrow(panel) == 0L) stop("[ERROR] empty analysis panel", call. = FALSE)

fe_formula <- function(outcome) {
  stats::as.formula(sprintf("%s ~ %s + %s | adm_cd + yq",
                            outcome, EXPOSURE, paste(CONTROLS, collapse = " + ")))
}

fit_beta <- function(dat, outcome) {
  m <- tryCatch(fixest::feols(fe_formula(outcome), data = dat, cluster = ~adm_cd, notes = FALSE),
                error = function(e) NULL)
  if (is.null(m) || !EXPOSURE %in% names(stats::coef(m))) {
    return(list(beta = NA_real_, se = NA_real_, p = NA_real_, n = NA_integer_))
  }
  list(beta = unname(stats::coef(m)[[EXPOSURE]]),
       se = unname(fixest::se(m)[[EXPOSURE]]),
       p = unname(fixest::pvalue(m)[[EXPOSURE]]),
       n = unname(stats::nobs(m)))
}


#==============================================================================
# 2. Outcome-Tail Dongs and Standard-Deviation Inflation
#==============================================================================

# A pooled z-score standardises by a standard deviation that the tail itself
# inflates, so a coefficient reported "per standard deviation" is denominated in
# a unit that a handful of dongs helped set. Quantify that directly.
tail_rows <- list()
sd_rows <- list()

for (oc in OUTCOMES) {
  x <- panel[[oc]]
  ok <- is.finite(x)
  if (!any(ok)) next
  mu <- mean(x[ok]); sdev <- stats::sd(x[ok])
  z <- (x - mu) / sdev

  flagged <- panel$adm_cd[ok & abs(z) > TAIL_Z]
  flagged <- unique(flagged)

  keep <- ok & !(panel$adm_cd %in% flagged)
  sd_excl <- if (any(keep)) stats::sd(panel[[oc]][keep]) else NA_real_

  sd_rows[[length(sd_rows) + 1L]] <- tibble::tibble(
    outcome = oc, tail_z = TAIL_Z,
    n_tail_obs = sum(ok & abs(z) > TAIL_Z), n_tail_dongs = length(flagged),
    sd_all = sdev, sd_excl_tail = sd_excl,
    sd_inflation_pct = 100 * (sdev / sd_excl - 1),
    min_z = min(z[ok]), max_z = max(z[ok])
  )

  if (length(flagged) > 0L) {
    for (d in flagged) {
      idx <- ok & panel$adm_cd == d
      tail_rows[[length(tail_rows) + 1L]] <- tibble::tibble(
        outcome = oc, adm_cd = d,
        adm_nm = panel$adm_nm[idx][1], gu_name = panel$gu_name[idx][1],
        n_extreme_obs = sum(abs(z[idx]) > TAIL_Z),
        min_z = min(z[idx]), max_z = max(z[idx]),
        median_total_sales = stats::median(panel$total_sales[idx], na.rm = TRUE),
        median_store_count = stats::median(panel$total_store_count[idx], na.rm = TRUE)
      )
    }
  }
}

outlier_dongs <- if (length(tail_rows)) dplyr::bind_rows(tail_rows) |> dplyr::arrange(outcome, min_z) else tibble::tibble()
sd_summary <- dplyr::bind_rows(sd_rows)

write_csv_safe(outlier_dongs, cfg$paths$influence_outlier_dongs)


#==============================================================================
# 3. Leave-One-Dong-Out Influence on the Exposure Coefficient
#==============================================================================

# Threshold-free: instead of asking which observations look extreme, ask which
# dongs actually move the estimate. dfbeta is the change in the exposure
# coefficient when a single dong is removed from the estimation sample.
dongs <- sort(unique(panel$adm_cd))
dfbeta_rows <- list()

for (oc in OUTCOMES) {
  base <- fit_beta(panel, oc)
  if (!is.finite(base$beta)) next
  message(sprintf("[influence] %s: baseline beta=%.4f (n=%d), leaving out %d dongs",
                  oc, base$beta, base$n, length(dongs)))

  deltas <- vapply(dongs, function(d) {
    f <- fit_beta(panel[panel$adm_cd != d, , drop = FALSE], oc)
    f$beta - base$beta
  }, numeric(1))

  dfbeta_rows[[length(dfbeta_rows) + 1L]] <- tibble::tibble(
    outcome = oc, adm_cd = dongs,
    baseline_beta = base$beta, baseline_se = base$se, baseline_p = base$p,
    beta_without_dong = base$beta + deltas,
    dfbeta = deltas,
    dfbeta_in_se = deltas / base$se,
    pct_change = 100 * deltas / abs(base$beta)
  )
}

dfbeta <- dplyr::bind_rows(dfbeta_rows) |>
  dplyr::left_join(lookup |> dplyr::mutate(adm_cd = as.character(adm_cd)), by = "adm_cd") |>
  dplyr::arrange(outcome, dplyr::desc(abs(.data$dfbeta)))

write_csv_safe(dfbeta, cfg$paths$influence_dfbeta)


#==============================================================================
# 4. Exclusion Robustness
#==============================================================================

# Three comparisons per outcome, each re-estimating the identical specification:
#   tail      - drop the dongs whose outcome values sit beyond TAIL_Z
#   top_k     - drop the TOP_K most influential dongs by |dfbeta|
#   union     - drop every dong flagged in the tail of any outcome
union_tail <- unique(outlier_dongs$adm_cd)

summary_rows <- list()
for (oc in OUTCOMES) {
  base <- fit_beta(panel, oc)
  if (!is.finite(base$beta)) next

  oc_tail <- unique(outlier_dongs$adm_cd[outlier_dongs$outcome == oc])
  oc_top <- dfbeta |>
    dplyr::filter(.data$outcome == oc) |>
    dplyr::slice_max(order_by = abs(.data$dfbeta), n = TOP_K, with_ties = FALSE) |>
    dplyr::pull(.data$adm_cd)

  variants <- list(tail = oc_tail, top_k = oc_top, union_tail = union_tail)

  for (nm in names(variants)) {
    drop <- variants[[nm]]
    alt <- fit_beta(panel[!(panel$adm_cd %in% drop), , drop = FALSE], oc)
    summary_rows[[length(summary_rows) + 1L]] <- tibble::tibble(
      outcome = oc, variant = nm, n_dongs_dropped = length(drop),
      dropped_dongs = paste(sort(lookup$adm_nm[match(drop, lookup$adm_cd)]), collapse = ";"),
      baseline_beta = base$beta, baseline_se = base$se, baseline_p = base$p, baseline_n = base$n,
      alt_beta = alt$beta, alt_se = alt$se, alt_p = alt$p, alt_n = alt$n,
      pct_change = 100 * (alt$beta - base$beta) / abs(base$beta),
      sign_flip = is.finite(alt$beta) && sign(alt$beta) != sign(base$beta),
      loses_5pct_significance = is.finite(base$p) && is.finite(alt$p) && base$p < 0.05 && alt$p >= 0.05,
      gains_5pct_significance = is.finite(base$p) && is.finite(alt$p) && base$p >= 0.05 && alt$p < 0.05
    )
  }
}

robustness <- dplyr::bind_rows(summary_rows) |>
  dplyr::left_join(sd_summary |> dplyr::select(dplyr::all_of(c("outcome", "sd_all", "sd_excl_tail", "sd_inflation_pct"))),
                   by = "outcome")

write_csv_safe(robustness, cfg$paths$influence_robustness_summary)


#==============================================================================
# 5. Log
#==============================================================================

flips <- sum(robustness$sign_flip, na.rm = TRUE)
loses <- sum(robustness$loses_5pct_significance, na.rm = TRUE)

append_log(cfg$logs$data_qc, sprintf(
  "- Influence robustness: %d outcomes x %d variants; %d sign flips, %d lose 5%% significance; tail dongs=%d",
  length(OUTCOMES), 3L, flips, loses, length(union_tail)))

message(sprintf("[DONE] influence robustness: %d sign flips, %d lose 5%% significance across %d rows",
                flips, loses, nrow(robustness)))
