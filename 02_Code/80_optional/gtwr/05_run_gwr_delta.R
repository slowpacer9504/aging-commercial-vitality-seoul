#==============================================================================
# Script    : 05_run_gwr_delta.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Emit a quarterly GWR-delta appendix bundle using the fixed
#             2019Q1-2021Q4 vs 2023Q1-2025Q4 comparison window metadata.
# Author    : Codex
# Created   : 2026-04-22
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet
# Outputs   : gwr_delta_main_models.csv, gwr_delta_local_coefficients.csv,
#             gwr_delta_floating_models.csv,
#             gwr_delta_floating_local_coefficients.csv,
#             gwr_delta_controls_used.csv
# DependsOn : 01_run_twfe_main.R
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 05_run_gwr_delta", timestamp()))

empty_gwr_delta_main_tbl <- function() {
  tibble::tibble(
    gwr_family = character(),
    method = character(),
    outcome = character(),
    focal_var = character(),
    exposure = character(),
    estimate_type = character(),
    early_start_year = integer(),
    early_end_year = integer(),
    late_start_year = integer(),
    late_end_year = integer(),
    window_scope = character(),
    window_n_year = integer(),
    n_locations = integer(),
    n_valid = integer(),
    n_early = integer(),
    n_late = integer(),
    mean_beta = numeric(),
    sd_beta = numeric(),
    p25_beta = numeric(),
    p50_beta = numeric(),
    p75_beta = numeric(),
    share_positive = numeric(),
    bandwidth = numeric(),
    kernel = character(),
    adaptive = logical(),
    gw_r2_early = numeric(),
    gw_r2_adj_early = numeric(),
    edf_early = numeric(),
    gw_r2_late = numeric(),
    gw_r2_adj_late = numeric(),
    edf_late = numeric(),
    bw_obs_n = integer(),
    elapsed_sec = numeric(),
    status = character(),
    message = character()
  )
}

empty_gwr_delta_local_tbl <- function() {
  tibble::tibble(
    gwr_family = character(),
    adm_cd = character(),
    outcome = character(),
    focal_var = character(),
    coef_early = numeric(),
    coef_late = numeric(),
    estimate = numeric(),
    estimate_type = character(),
    early_start_year = integer(),
    early_end_year = integer(),
    late_start_year = integer(),
    late_end_year = integer(),
    window_scope = character(),
    window_n_year = integer(),
    bandwidth = numeric(),
    kernel = character(),
    adaptive = logical(),
    method = character(),
    status = character(),
    message = character()
  )
}

empty_controls_tbl <- function() {
  tibble::tibble(
    gwr_family = character(),
    outcome = character(),
    focal_var = character(),
    optional_candidates = character(),
    selected_controls = character(),
    base_n_obs = integer(),
    base_n_units = integer(),
    selection_status = character(),
    window_scope = character(),
    window_n_year = integer(),
    status = character(),
    message = character()
  )
}

build_deferred_rows <- function(panel, outcomes, focal_vars, gwr_family, control_candidates) {
  purrr::map2_dfr(outcomes, focal_vars[rep(1L, length(outcomes))], function(outcome, focal_var) {
    vars <- unique(c("adm_cd", "year", outcome, focal_var, control_candidates))
    d_fit <- panel |>
      dplyr::select(dplyr::all_of(intersect(vars, names(panel)))) |>
      tidyr::drop_na()

    message <- if (nrow(d_fit) < 400L || dplyr::n_distinct(d_fit$adm_cd) < 30L) {
      "quarterly_gwr_delta_deferred: insufficient quarterly support for 3Y vs 3Y local comparison"
    } else {
      "quarterly_gwr_delta_deferred: appendix local delta estimation is not activated; quarterly comparison window metadata preserved"
    }

    empty_gwr_delta_main_tbl() |>
      dplyr::add_row(
        gwr_family = gwr_family,
        method = "GWmodel::gwr.basic",
        outcome = outcome,
        focal_var = focal_var,
        exposure = focal_var,
        estimate_type = "late_window_minus_early_window",
        early_start_year = 2019L,
        early_end_year = 2021L,
        late_start_year = 2023L,
        late_end_year = 2025L,
        window_scope = "quarterly_3y_vs_3y_mean",
        window_n_year = 3L,
        n_locations = dplyr::n_distinct(d_fit$adm_cd),
        n_valid = 0L,
        n_early = dplyr::n_distinct(d_fit$adm_cd),
        n_late = dplyr::n_distinct(d_fit$adm_cd),
        kernel = as.character(cfg$gwr_delta_kernel[[1]]),
        adaptive = isTRUE(cfg$gwr_delta_adaptive),
        bw_obs_n = nrow(d_fit),
        status = "not_estimated",
        message = message
      )
  })
}

if (!isTRUE(cfg$run_gwr_delta)) {
  append_log(cfg$logs$model_run, "- GWR delta quarterly appendix skipped (run_gwr_delta = FALSE)")
} else {
  if (!file.exists(cfg$paths$panel_main)) {
    stop("[ERROR] panel_main missing for quarterly GWR delta appendix.", call. = FALSE)
  }

  panel <- read_panel_main_view("gwr_delta") |>
    dplyr::mutate(adm_cd = as.character(adm_cd))
  outcomes <- intersect(cfg$gwr_delta_outcomes, names(panel))
  resident_focals <- intersect(cfg$gwr_delta_main_exposure_vars, names(panel))
  floating_focals <- intersect(cfg$gwr_delta_floating_exposure_vars, names(panel))
  control_candidates <- intersect(gwr_delta_control_candidate_cols(), names(panel))
  assert_gtwr_control_vector_current(
    control_candidates,
    context = "05_run_gwr_delta",
    allowed_controls = gwr_delta_control_candidate_cols()
  )

  main_tbl <- if (length(outcomes) > 0L && length(resident_focals) > 0L) {
    build_deferred_rows(panel, outcomes, resident_focals, gwr_family = "resident", control_candidates = control_candidates)
  } else {
    empty_gwr_delta_main_tbl()
  }
  floating_tbl <- if (isTRUE(cfg$run_gwr_delta_floating_sidecar) && length(outcomes) > 0L && length(floating_focals) > 0L) {
    build_deferred_rows(panel, outcomes, floating_focals, gwr_family = "floating", control_candidates = control_candidates)
  } else {
    empty_gwr_delta_main_tbl()
  }

  controls_tbl <- dplyr::bind_rows(
    if (nrow(main_tbl) > 0L) {
      main_tbl |>
        dplyr::transmute(
          gwr_family,
          outcome,
          focal_var,
          optional_candidates = collapse_chr(control_candidates),
          selected_controls = optional_candidates,
          base_n_obs = bw_obs_n,
          base_n_units = n_locations,
          selection_status = "quarterly_deferred",
          window_scope,
          window_n_year,
          status,
          message
        )
    },
    if (nrow(floating_tbl) > 0L) {
      floating_tbl |>
        dplyr::transmute(
          gwr_family,
          outcome,
          focal_var,
          optional_candidates = collapse_chr(control_candidates),
          selected_controls = optional_candidates,
          base_n_obs = bw_obs_n,
          base_n_units = n_locations,
          selection_status = "quarterly_deferred",
          window_scope,
          window_n_year,
          status,
          message
        )
    }
  )
  assert_gtwr_controls_trace_current(
    controls_tbl,
    context = "05_run_gwr_delta controls trace",
    allowed_controls = control_candidates,
    control_cols = c("optional_candidates", "selected_controls")
  )

  write_csv_safe(main_tbl, cfg$paths$gwr_delta_main_models)
  write_csv_safe(empty_gwr_delta_local_tbl(), cfg$paths$gwr_delta_local_coefficients)
  write_csv_safe(floating_tbl, cfg$paths$gwr_delta_floating_models)
  write_csv_safe(empty_gwr_delta_local_tbl(), cfg$paths$gwr_delta_floating_local_coefficients)
  write_csv_safe(controls_tbl, cfg$paths$gwr_delta_controls_used)

  append_log(
    cfg$logs$model_run,
    sprintf(
      "- GWR delta quarterly appendix emitted deferred bundle: resident_rows=%d, floating_rows=%d",
      nrow(main_tbl),
      nrow(floating_tbl)
    )
  )
}
