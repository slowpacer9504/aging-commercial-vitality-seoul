#==============================================================================
# Script    : 04_run_gwr_delta.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Emit a deferred quarterly GWR-delta appendix bundle using the
#             active 2019Q4-2025Q4 analysis horizon metadata.
# Author    : Junghyun Pyo (Assisted by Codex)
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

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 04_run_gwr_delta", timestamp()))

#==============================================================================
# 1. Helper Functions
#==============================================================================

# Deferred GWR-delta outputs preserve the appendix contract even when local
# early-late estimation is intentionally inactive.
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
    sample_min_yq = character(),
    sample_max_yq = character(),
    early_start_yq = character(),
    early_end_yq = character(),
    late_start_yq = character(),
    late_end_yq = character(),
    early_n_quarter = integer(),
    late_n_quarter = integer(),
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
    sample_min_yq = character(),
    sample_max_yq = character(),
    early_start_yq = character(),
    early_end_yq = character(),
    late_start_yq = character(),
    late_end_yq = character(),
    early_n_quarter = integer(),
    late_n_quarter = integer(),
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
    sample_min_yq = character(),
    sample_max_yq = character(),
    early_start_yq = character(),
    early_end_yq = character(),
    late_start_yq = character(),
    late_end_yq = character(),
    early_n_quarter = integer(),
    late_n_quarter = integer(),
    status = character(),
    message = character()
  )
}

resolve_gwr_delta_window_meta <- function() {
  # Derive early and late windows from the active quarterly analysis sequence so
  # appendix metadata cannot drift back to annual timing.
  q_seq <- cfg$analysis_quarter_sequence
  if (is.null(q_seq) || nrow(q_seq) == 0L || !"yq" %in% names(q_seq) || !"year" %in% names(q_seq)) {
    stop("[ERROR] cfg$analysis_quarter_sequence is required for GWR delta metadata.", call. = FALSE)
  }

  q_seq <- q_seq |>
    dplyr::mutate(
      year = suppressWarnings(as.integer(.data$year)),
      quarter_index = if ("quarter_index" %in% names(q_seq)) {
        suppressWarnings(as.integer(.data$quarter_index))
      } else {
        dplyr::row_number()
      },
      yq = as.character(.data$yq)
    ) |>
    dplyr::filter(!is.na(.data$year), !is.na(.data$quarter_index), !is.na(.data$yq), nzchar(.data$yq)) |>
    dplyr::arrange(.data$quarter_index)

  if (nrow(q_seq) == 0L) {
    stop("[ERROR] Active analysis quarter sequence is empty for GWR delta metadata.", call. = FALSE)
  }

  window_n_year <- suppressWarnings(as.integer(cfg$gwr_delta_window_years[[1L]]))
  if (length(window_n_year) == 0L || !is.finite(window_n_year) || window_n_year < 1L) {
    window_n_year <- 3L
  }

  analysis_years <- sort(unique(q_seq$year))
  early_years <- utils::head(analysis_years, min(window_n_year, length(analysis_years)))
  late_years <- utils::tail(analysis_years, min(window_n_year, length(analysis_years)))
  early_q <- q_seq |>
    dplyr::filter(.data$year %in% early_years) |>
    dplyr::arrange(.data$quarter_index)
  late_q <- q_seq |>
    dplyr::filter(.data$year %in% late_years) |>
    dplyr::arrange(.data$quarter_index)

  list(
    sample_min_yq = q_seq$yq[[1L]],
    sample_max_yq = q_seq$yq[[nrow(q_seq)]],
    early_start_year = early_years[[1L]],
    early_end_year = early_years[[length(early_years)]],
    late_start_year = late_years[[1L]],
    late_end_year = late_years[[length(late_years)]],
    early_start_yq = early_q$yq[[1L]],
    early_end_yq = early_q$yq[[nrow(early_q)]],
    late_start_yq = late_q$yq[[1L]],
    late_end_yq = late_q$yq[[nrow(late_q)]],
    early_n_quarter = nrow(early_q),
    late_n_quarter = nrow(late_q),
    early_yq = early_q$yq,
    late_yq = late_q$yq,
    window_n_year = window_n_year,
    window_scope = "active_analysis_early_late_deferred"
  )
}

build_deferred_rows <- function(panel, outcomes, focal_vars, gwr_family, control_candidates, window_meta) {
  # Emit one metadata-rich deferred row per outcome/exposure pair, including
  # support counts for the active horizon and early/late windows.
  purrr::map2_dfr(outcomes, focal_vars[rep(1L, length(outcomes))], function(outcome, focal_var) {
    vars <- unique(c("adm_cd", "year", "yq", outcome, focal_var, control_candidates))
    d_fit <- panel |>
      dplyr::select(dplyr::all_of(intersect(vars, names(panel)))) |>
      tidyr::drop_na()

    message <- if (nrow(d_fit) < 400L || dplyr::n_distinct(d_fit$adm_cd) < 30L) {
      "quarterly_gwr_delta_deferred: insufficient active-horizon support for early-late local comparison"
    } else {
      "quarterly_gwr_delta_deferred: appendix local delta estimation is not activated; active-horizon metadata preserved"
    }

    empty_gwr_delta_main_tbl() |>
      dplyr::add_row(
        gwr_family = gwr_family,
        method = "GWmodel::gwr.basic",
        outcome = outcome,
        focal_var = focal_var,
        exposure = focal_var,
        estimate_type = "late_window_minus_early_window",
        early_start_year = window_meta$early_start_year,
        early_end_year = window_meta$early_end_year,
        late_start_year = window_meta$late_start_year,
        late_end_year = window_meta$late_end_year,
        sample_min_yq = window_meta$sample_min_yq,
        sample_max_yq = window_meta$sample_max_yq,
        early_start_yq = window_meta$early_start_yq,
        early_end_yq = window_meta$early_end_yq,
        late_start_yq = window_meta$late_start_yq,
        late_end_yq = window_meta$late_end_yq,
        early_n_quarter = window_meta$early_n_quarter,
        late_n_quarter = window_meta$late_n_quarter,
        window_scope = window_meta$window_scope,
        window_n_year = window_meta$window_n_year,
        n_locations = dplyr::n_distinct(d_fit$adm_cd),
        n_valid = 0L,
        n_early = d_fit |>
          dplyr::filter(.data$yq %in% window_meta$early_yq) |>
          dplyr::pull(.data$adm_cd) |>
          dplyr::n_distinct(),
        n_late = d_fit |>
          dplyr::filter(.data$yq %in% window_meta$late_yq) |>
          dplyr::pull(.data$adm_cd) |>
          dplyr::n_distinct(),
        kernel = as.character(cfg$gwr_delta_kernel[[1]]),
        adaptive = isTRUE(cfg$gwr_delta_adaptive),
        bw_obs_n = nrow(d_fit),
        status = "not_estimated",
        message = message
      )
  })
}

#==============================================================================
# 2. Publish Deferred GWR-Delta Bundle
#==============================================================================

{
  # Read the current GWR-delta view and publish resident/floating deferred
  # bundles plus a controls trace for appendix review.
  if (!file.exists(cfg$paths$panel_main)) {
    stop("[ERROR] panel_main missing for quarterly GWR delta appendix.", call. = FALSE)
  }

  panel <- read_panel_main_view("gwr_delta") |>
    dplyr::mutate(adm_cd = as.character(adm_cd))
  window_meta <- resolve_gwr_delta_window_meta()
  outcomes <- intersect(cfg$gwr_delta_outcomes, names(panel))
  resident_focals <- intersect(cfg$gwr_delta_main_exposure_vars, names(panel))
  floating_focals <- intersect(cfg$gwr_delta_floating_exposure_vars, names(panel))
  control_candidates <- intersect(gwr_delta_control_candidate_cols(), names(panel))
  assert_gtwr_control_vector_current(
    control_candidates,
    context = "04_run_gwr_delta",
    allowed_controls = gwr_delta_control_candidate_cols()
  )

  main_tbl <- if (length(outcomes) > 0L && length(resident_focals) > 0L) {
    build_deferred_rows(panel, outcomes, resident_focals, gwr_family = "resident", control_candidates = control_candidates, window_meta = window_meta)
  } else {
    empty_gwr_delta_main_tbl()
  }
  floating_tbl <- if (length(outcomes) > 0L && length(floating_focals) > 0L) {
    build_deferred_rows(panel, outcomes, floating_focals, gwr_family = "floating", control_candidates = control_candidates, window_meta = window_meta)
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
          sample_min_yq,
          sample_max_yq,
          early_start_yq,
          early_end_yq,
          late_start_yq,
          late_end_yq,
          early_n_quarter,
          late_n_quarter,
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
          sample_min_yq,
          sample_max_yq,
          early_start_yq,
          early_end_yq,
          late_start_yq,
          late_end_yq,
          early_n_quarter,
          late_n_quarter,
          status,
          message
        )
    }
  )
  assert_gtwr_controls_trace_current(
    controls_tbl,
    context = "04_run_gwr_delta controls trace",
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
