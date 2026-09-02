#==============================================================================
# Script    : 10_search_gtwr_lamda_bw_cv.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Locate the lamda / bandwidth region by leave-one-out cross
#             validation without fitting GTWR, so the expensive main run and the
#             sensitivity sidecars are executed once at a chosen specification.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-02
# Status    : QUARTERLY_OPTIONAL / manual search sidecar
# Type      : spatial_panel_diagnostic
# Inputs    : panel_main.parquet, administrative boundary
# Outputs   : gtwr_lamda_bw_cv_search_<control_set>.csv
# DependsOn : utils_gtwr_main.R
#==============================================================================
#
# Why this can skip the GTWR fit
# ------------------------------
# A GTWR local coefficient is weighted least squares at each focal point, and the
# CV score GWmodel::bw.gtwr() minimizes is the leave-one-out residual sum of
# squares over those local fits. Neither needs the full coefficient surface or
# the hat-matrix traces that gtwr() also produces, so the score can be assembled
# from the same distance-and-weight machinery the collinearity diagnostics use.
# That machinery is already validated: the backfill sidecar reproduces the stored
# local_cn to 2.5e-12, and a WLS built the same way reproduces the stored local
# betas to 5.8e-10.
#
# Two properties keep the search cheap
# ------------------------------------
#   - The distance column for a focal point depends on lamda but not on the
#     bandwidth, and the adaptive kernel only needs the bw-th smallest distance.
#     One sort therefore serves every bandwidth in the grid.
#   - Weights do not depend on the response, so one weight vector serves every
#     outcome. A single common complete-case sample is used for that reason.
#
# The cost is therefore driven by (number of lamda values) x (focal sample size),
# not by the size of the full grid.
#
# What this is and is not
# -----------------------
# This locates a region and shows whether the optimum is interior or sits on a
# grid boundary. It is a search tool, not a reporting one. CV optimizes
# prediction rather than inference, the focal sample estimates the CV surface
# rather than reproducing bw.gtwr()'s exact value, and the project's bandwidth
# contract weighs outcome comparability and coefficient stability alongside fit.
# Report the official bandwidth from 06_select_gtwr_bandwidth.R and the
# robustness tables from 07/08 around whatever specification is adopted.
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
source(here::here("02_Code", "99_utils", "utils_model.R"))
source(here::here("02_Code", "99_utils", "utils_spatial.R"))
source(here::here("02_Code", "99_utils", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 10_search_gtwr_lamda_bw_cv", timestamp()))

parse_grid <- function(txt, fallback) {
  out <- suppressWarnings(as.numeric(trimws(strsplit(as.character(txt), ",", fixed = TRUE)[[1]])))
  out <- out[is.finite(out)]
  if (length(out) == 0L) fallback else sort(unique(out))
}

# The lamda grid spans the dimensionless range and includes 0.9867, the point
# reproducing the previous raw-unit lamda of 0.05, so the incumbent
# specification appears in the surface rather than outside it.
CV_LAMDA_GRID <- parse_grid(
  Sys.getenv("GTWR_CV_SEARCH_LAMDA_GRID", unset = "0.1,0.25,0.5,0.75,0.9,0.9867"),
  c(0.1, 0.25, 0.5, 0.75, 0.9, 0.9867)
)
CV_BW_GRID <- as.integer(parse_grid(
  Sys.getenv("GTWR_CV_SEARCH_BW_GRID", unset = "30,60,90,120,180"),
  c(30, 60, 90, 120, 180)
))
CV_FOCAL_N <- suppressWarnings(as.integer(Sys.getenv("GTWR_CV_SEARCH_FOCAL_N", unset = "300")))
if (!is.finite(CV_FOCAL_N) || CV_FOCAL_N < 30L) CV_FOCAL_N <- 300L
CV_SEED <- suppressWarnings(as.integer(Sys.getenv("GTWR_CV_SEARCH_SEED", unset = "20260902")))
if (!is.finite(CV_SEED)) CV_SEED <- 20260902L

empty_cv_search_tbl <- function() {
  tibble::tibble(
    control_set = character(),
    outcome = character(),
    focal_var = character(),
    lamda = numeric(),
    st_bw = integer(),
    cv_rmse = numeric(),
    cv_score = numeric(),
    n_focal_used = integer(),
    n_obs_common = integer(),
    median_n_dongs = numeric(),
    median_n_quarters = numeric(),
    rel_to_best_outcome = numeric(),
    is_best_for_outcome = logical(),
    lamda_on_grid_edge = logical(),
    st_bw_on_grid_edge = logical()
  )
}

#==============================================================================
# 1. Adaptive Kernel Weights From a Single Sort
#==============================================================================

# GWmodel::gw.weight() re-derives the bw-th smallest distance on every call. The
# search evaluates many bandwidths against one distance column, so the order
# statistic is taken once and reused. Equivalence with gw.weight() is asserted
# before the search starts rather than assumed.
adaptive_weights_from_sorted <- function(dv, sorted_dv, bw, kernel) {
  if (bw < 1L || bw > length(sorted_dv)) return(NULL)
  dk <- sorted_dv[[bw]]
  if (!is.finite(dk) || dk <= 0) return(NULL)
  ratio <- dv / dk
  w <- switch(
    kernel,
    bisquare = ifelse(ratio < 1, (1 - ratio^2)^2, 0),
    tricube  = ifelse(ratio < 1, (1 - ratio^3)^3, 0),
    boxcar   = ifelse(ratio < 1, 1, 0),
    gaussian = exp(-0.5 * ratio^2),
    exponential = exp(-ratio),
    NULL
  )
  w
}

assert_weight_equivalence <- function(loc, tv, scales, kernel, lamda_grid, bw_grid, probes) {
  worst <- 0
  for (lam in lamda_grid) {
    for (i in probes) {
      dv <- gtwr_st_dist_column(loc, tv, i, lamda = lam, ksi = cfg$gtwr_ksi, scales = scales)
      sorted_dv <- sort(dv)
      for (bw in bw_grid) {
        mine <- adaptive_weights_from_sorted(dv, sorted_dv, bw, kernel)
        ref <- GWmodel::gw.weight(dv, bw = bw, kernel = kernel, adaptive = TRUE)
        if (is.null(mine)) next
        worst <- max(worst, max(abs(mine - as.numeric(ref))))
      }
    }
  }
  worst
}

#==============================================================================
# 2. Leave-One-Out CV Over the Focal Sample
#==============================================================================

# One local WLS with observation i down-weighted to zero, solved for every
# outcome at once because the weights do not depend on the response.
loo_residuals <- function(mm, Y, w, i) {
  w[[i]] <- 0
  keep <- is.finite(w) & w > 0
  if (sum(keep) < ncol(mm) + 1L) return(rep(NA_real_, ncol(Y)))
  X <- mm[keep, , drop = FALSE]
  XtW <- t(X * w[keep])
  beta <- tryCatch(solve(XtW %*% X, XtW %*% Y[keep, , drop = FALSE]), error = function(e) NULL)
  if (is.null(beta)) return(rep(NA_real_, ncol(Y)))
  as.numeric(Y[i, ]) - as.numeric(mm[i, , drop = FALSE] %*% beta)
}

#==============================================================================
# 3. Execution
#==============================================================================

{
  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  out_path <- file.path(
    cfg$dir_tables,
    sprintf("gtwr_lamda_bw_cv_search_%s.csv", cfg$gtwr_main_output_tag(control_set))
  )

  outcomes <- cfg$gtwr_main_outcomes
  focal_var <- cfg$gtwr_main_exposure_vars[[1]]
  rhs_vars <- unique(c(focal_var, gtwr_main_control_candidate_cols()))

  panel_xy <- read_panel_main_view("gtwr") |>
    dplyr::mutate(adm_cd = as.character(adm_cd)) |>
    prepare_gtwr_points()

  # One common complete-case sample across all outcomes, so a single weight
  # vector serves every response. This differs slightly from each spec's own
  # sample and is acceptable for selection, not for reporting.
  keep_cols <- unique(c("adm_cd", "yq", "quarter_index", "time_id", "x", "y", outcomes, rhs_vars))
  d <- panel_xy |>
    dplyr::select(dplyr::all_of(keep_cols)) |>
    dplyr::mutate(dplyr::across(dplyr::all_of(c(outcomes, rhs_vars, "x", "y")), ~ suppressWarnings(as.numeric(.x)))) |>
    tidyr::drop_na() |>
    dplyr::arrange(.data$time_id, .data$adm_cd)

  if (nrow(d) == 0L) {
    write_csv_safe(empty_cv_search_tbl(), out_path)
    stop("[ERROR] No complete cases shared across all GTWR outcomes.", call. = FALSE)
  }

  loc <- gtwr_location_dist(d)
  if (is.null(loc)) stop("[ERROR] Could not build the location distance matrix.", call. = FALSE)
  tv <- suppressWarnings(as.numeric(d$time_id))
  scales <- gtwr_st_scales(loc, tv)
  mm <- stats::model.matrix(stats::reformulate(rhs_vars), data = d)
  Y <- as.matrix(d[, outcomes, drop = FALSE])

  set.seed(CV_SEED)
  focal_idx <- sort(sample.int(nrow(d), min(CV_FOCAL_N, nrow(d))))

  append_log(cfg$logs$model_run, sprintf(
    "- CV search: n_common=%d, focal=%d, lamda={%s}, st_bw={%s}, spans s=%.1f t=%.0f",
    nrow(d), length(focal_idx),
    paste(CV_LAMDA_GRID, collapse = "|"), paste(CV_BW_GRID, collapse = "|"),
    scales$s, scales$t
  ))

  worst_w <- assert_weight_equivalence(
    loc, tv, scales, cfg$gtwr_kernel, CV_LAMDA_GRID, CV_BW_GRID, focal_idx[seq_len(min(3L, length(focal_idx)))]
  )
  if (!is.finite(worst_w) || worst_w > 1e-10) {
    stop(sprintf(
      "[ERROR] Reused-sort kernel weights diverge from GWmodel::gw.weight (max abs diff %.3e). Refusing to search on weights the package would not produce.",
      worst_w
    ), call. = FALSE)
  }
  message(sprintf("[CHECK] kernel weight equivalence vs gw.weight: max_abs_diff=%.3e", worst_w))

  rows <- list()
  for (lam in CV_LAMDA_GRID) {
    # sq[[b]] accumulates squared LOO residuals per outcome for bandwidth b.
    sq <- lapply(CV_BW_GRID, function(...) numeric(ncol(Y)))
    used <- integer(length(CV_BW_GRID))
    dongs <- lapply(CV_BW_GRID, function(...) numeric(0))
    quarters <- lapply(CV_BW_GRID, function(...) numeric(0))

    for (i in focal_idx) {
      dv <- gtwr_st_dist_column(loc, tv, i, lamda = lam, ksi = cfg$gtwr_ksi, scales = scales)
      sorted_dv <- sort(dv)
      for (b in seq_along(CV_BW_GRID)) {
        w <- adaptive_weights_from_sorted(dv, sorted_dv, CV_BW_GRID[[b]], cfg$gtwr_kernel)
        if (is.null(w)) next
        pos <- is.finite(w) & w > 0
        r <- loo_residuals(mm, Y, w, i)
        if (all(is.na(r))) next
        sq[[b]] <- sq[[b]] + r^2
        used[[b]] <- used[[b]] + 1L
        dongs[[b]] <- c(dongs[[b]], dplyr::n_distinct(d$adm_cd[pos]))
        quarters[[b]] <- c(quarters[[b]], dplyr::n_distinct(tv[pos]))
      }
    }

    for (b in seq_along(CV_BW_GRID)) {
      if (used[[b]] == 0L) next
      rows[[length(rows) + 1L]] <- tibble::tibble(
        control_set = control_set,
        outcome = outcomes,
        focal_var = focal_var,
        lamda = lam,
        st_bw = CV_BW_GRID[[b]],
        cv_rmse = sqrt(sq[[b]] / used[[b]]),
        cv_score = sq[[b]],
        n_focal_used = used[[b]],
        n_obs_common = nrow(d),
        median_n_dongs = stats::median(dongs[[b]]),
        median_n_quarters = stats::median(quarters[[b]])
      )
    }
    append_log(cfg$logs$model_run, sprintf("- CV search completed lamda=%s", format(lam)))
  }

  if (length(rows) == 0L) {
    write_csv_safe(empty_cv_search_tbl(), out_path)
    stop("[ERROR] CV search produced no evaluable combinations.", call. = FALSE)
  }

  # Flagging boundary optima matters here: under the previous raw-unit grid the
  # criterion fell monotonically to the largest value in four of five outcomes,
  # so the optimum was never enclosed.
  result <- dplyr::bind_rows(rows) |>
    dplyr::group_by(.data$outcome) |>
    dplyr::mutate(
      rel_to_best_outcome = .data$cv_rmse / min(.data$cv_rmse, na.rm = TRUE),
      is_best_for_outcome = .data$cv_rmse == min(.data$cv_rmse, na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      lamda_on_grid_edge = .data$is_best_for_outcome &
        (.data$lamda == min(CV_LAMDA_GRID) | .data$lamda == max(CV_LAMDA_GRID)),
      st_bw_on_grid_edge = .data$is_best_for_outcome &
        (.data$st_bw == min(CV_BW_GRID) | .data$st_bw == max(CV_BW_GRID))
    ) |>
    dplyr::select(dplyr::all_of(names(empty_cv_search_tbl()))) |>
    dplyr::arrange(.data$outcome, .data$lamda, .data$st_bw)

  write_csv_safe(result, out_path)

  best <- result |> dplyr::filter(.data$is_best_for_outcome)
  message("\n[BEST BY OUTCOME]")
  for (k in seq_len(nrow(best))) {
    message(sprintf(
      "  %-24s lamda=%-7s st_bw=%-4d  rmse=%.5f  nbhd=%.0f dongs x %.0f quarters%s",
      best$outcome[[k]], format(best$lamda[[k]]), best$st_bw[[k]], best$cv_rmse[[k]],
      best$median_n_dongs[[k]], best$median_n_quarters[[k]],
      if (best$lamda_on_grid_edge[[k]] || best$st_bw_on_grid_edge[[k]]) "   <-- ON GRID EDGE" else ""
    ))
  }
  if (any(best$lamda_on_grid_edge | best$st_bw_on_grid_edge)) {
    message("\n[WARN] At least one optimum sits on a grid boundary; widen the grid before adopting a value.")
  }
  append_log(cfg$logs$model_run, sprintf("- CV search written: %s", basename(out_path)))
}
