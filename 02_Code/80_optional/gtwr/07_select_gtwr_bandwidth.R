#==============================================================================
# Script    : 07_select_gtwr_bandwidth.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run explicit bw.gtwr bandwidth selection diagnostics for the
#             resident-only quarterly GTWR main sidecar.
# Author    : Codex
# Created   : 2026-05-20
# Type      : spatial_panel_modeling_diagnostic
# Inputs    : panel_main.parquet, administrative boundary
# Outputs   : gtwr_bandwidth_selection_<control_set>.csv,
#             gtwr_bandwidth_cache/<control_set>/main/*.rds
# DependsOn : 01_run_gtwr_main.R, utils_gtwr_main.R
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
source(here::here("02_Code", "R", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 07_select_gtwr_bandwidth", timestamp()))

empty_gtwr_bandwidth_selection_tbl <- function() {
  tibble::tibble(
    method = character(),
    outcome = character(),
    focal_var = character(),
    exposure = character(),
    control_set = character(),
    bandwidth_strategy = character(),
    bandwidth_scope = character(),
    bandwidth_periods = character(),
    st_bw = numeric(),
    bw_raw = numeric(),
    bw_source = character(),
    bw_obs_n = integer(),
    n_obs_fit = integer(),
    n_locations = integer(),
    n_periods = integer(),
    approach = character(),
    kernel = character(),
    adaptive = logical(),
    lamda = numeric(),
    ksi = numeric(),
    status = character(),
    message = character()
  )
}

build_gtwr_bandwidth_selection_row <- function(outcome,
                                               focal_var,
                                               control_set,
                                               bandwidth_strategy,
                                               bandwidth_scope,
                                               bandwidth_periods,
                                               st_bw,
                                               bw_raw,
                                               bw_source,
                                               bw_obs_n,
                                               n_obs_fit,
                                               n_locations,
                                               n_periods,
                                               status,
                                               message) {
  empty_gtwr_bandwidth_selection_tbl() |>
    dplyr::add_row(
      method = "GWmodel::bw.gtwr",
      outcome = outcome,
      focal_var = focal_var,
      exposure = focal_var,
      control_set = control_set,
      bandwidth_strategy = bandwidth_strategy,
      bandwidth_scope = bandwidth_scope,
      bandwidth_periods = paste(as.character(bandwidth_periods), collapse = ";"),
      st_bw = suppressWarnings(as.numeric(st_bw)),
      bw_raw = suppressWarnings(as.numeric(bw_raw)),
      bw_source = bw_source,
      bw_obs_n = suppressWarnings(as.integer(bw_obs_n)),
      n_obs_fit = suppressWarnings(as.integer(n_obs_fit)),
      n_locations = suppressWarnings(as.integer(n_locations)),
      n_periods = suppressWarnings(as.integer(n_periods)),
      approach = cfg$gtwr_bw_approach,
      kernel = cfg$gtwr_kernel,
      adaptive = isTRUE(cfg$gtwr_adaptive),
      lamda = suppressWarnings(as.numeric(cfg$gtwr_lamda)),
      ksi = suppressWarnings(as.numeric(cfg$gtwr_ksi)),
      status = status,
      message = message
    )
}

run_gtwr_bandwidth_selection_job <- function(job, panel_xy, bw_cache_dir) {
  rhs_vars <- unique(c(job$focal_var, job$selected_controls))
  vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "time_id", "x", "y", job$outcome, rhs_vars))
  d_fit <- panel_xy |>
    dplyr::select(dplyr::all_of(vars)) |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(c(job$outcome, rhs_vars, "x", "y")), ~ suppressWarnings(as.numeric(.x)))
    ) |>
    tidyr::drop_na() |>
    dplyr::arrange(.data$time_id, .data$adm_cd)

  period_meta <- gtwr_period_meta(d_fit)
  n_obs_fit <- nrow(d_fit)
  n_locations <- dplyr::n_distinct(d_fit$adm_cd)
  bandwidth_strategy <- as.character(cfg$gtwr_bandwidth_strategy[[1]])
  bandwidth_scope <- if (identical(bandwidth_strategy, "anchor_quarter_bw_gtwr")) {
    sprintf("anchor_quarter_%s", cfg$gtwr_bw_anchor_yq)
  } else {
    "full_panel"
  }
  bandwidth_periods <- if (identical(bandwidth_strategy, "anchor_quarter_bw_gtwr")) {
    cfg$gtwr_bw_anchor_yq
  } else {
    sort(unique(as.character(d_fit$yq)))
  }

  min_required_obs <- max(400L, length(rhs_vars) + 30L)
  if (n_obs_fit < min_required_obs ||
      n_locations < cfg$gtwr_control_min_units ||
      period_meta$n_periods < cfg$spdm_min_periods) {
    return(build_gtwr_bandwidth_selection_row(
      outcome = job$outcome,
      focal_var = job$focal_var,
      control_set = job$control_set,
      bandwidth_strategy = bandwidth_strategy,
      bandwidth_scope = bandwidth_scope,
      bandwidth_periods = bandwidth_periods,
      st_bw = resolve_fixed_gtwr_st_bw(n_obs_fit, rhs_vars),
      bw_raw = NA_real_,
      bw_source = "not_estimated",
      bw_obs_n = NA_integer_,
      n_obs_fit = n_obs_fit,
      n_locations = n_locations,
      n_periods = period_meta$n_periods,
      status = "not_estimated",
      message = "quarterly_gtwr_bandwidth_selection_deferred: insufficient complete-case sample"
    ))
  }

  st_dmat <- build_gtwr_st_dmat(d_fit)
  formula_obj <- stats::reformulate(rhs_vars, response = job$outcome)
  selection <- resolve_gtwr_st_bw(
    d_fit = d_fit,
    formula_obj = formula_obj,
    rhs_vars = rhs_vars,
    outcome = job$outcome,
    focal_var = job$focal_var,
    selected_controls = job$selected_controls,
    control_set = job$control_set,
    st_dmat = st_dmat,
    cache_context = "main",
    bw_cache_dir = bw_cache_dir
  )

  source <- as.character(selection$bw_source[[1]])
  status <- if (startsWith(source, "bw.gtwr")) "success" else "not_estimated"
  message <- if (identical(status, "success")) {
    "bw_gtwr_bandwidth_selection_completed"
  } else {
    "bw_gtwr_bandwidth_selection_fell_back_to_fixed_bandwidth"
  }

  build_gtwr_bandwidth_selection_row(
    outcome = job$outcome,
    focal_var = job$focal_var,
    control_set = job$control_set,
    bandwidth_strategy = bandwidth_strategy,
    bandwidth_scope = bandwidth_scope,
    bandwidth_periods = bandwidth_periods,
    st_bw = selection$st_bw,
    bw_raw = selection$bw_raw,
    bw_source = source,
    bw_obs_n = selection$bw_obs_n,
    n_obs_fit = n_obs_fit,
    n_locations = n_locations,
    n_periods = period_meta$n_periods,
    status = status,
    message = message
  )
}

if (!file.exists(cfg$paths$panel_main)) {
  stop("[ERROR] panel_main missing for GTWR bandwidth selection.", call. = FALSE)
}
if (!requireNamespace("GWmodel", quietly = TRUE)) {
  stop("[ERROR] GWmodel package is required for GTWR bandwidth selection.", call. = FALSE)
}
if (!requireNamespace("sp", quietly = TRUE)) {
  stop("[ERROR] sp package is required for GTWR bandwidth selection.", call. = FALSE)
}
if (identical(cfg$gtwr_bandwidth_strategy, "fixed")) {
  stop(
    "[ERROR] 07_select_gtwr_bandwidth.R requires GTWR_BANDWIDTH_STRATEGY=full_panel_bw_gtwr or anchor_quarter_bw_gtwr.",
    call. = FALSE
  )
}

control_set <- normalize_control_set_main(cfg$gtwr_control_set)
selection_path <- cfg$get_gtwr_bandwidth_selection_path(control_set)
panel <- read_panel_main_view("gtwr") |>
  dplyr::mutate(adm_cd = as.character(adm_cd))

outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = cfg$gtwr_main_outcomes,
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome
focal_vars <- intersect(cfg$gtwr_main_exposure_vars, names(panel))
control_candidates <- gtwr_main_control_candidate_cols()
assert_gtwr_control_vector_current(control_candidates, context = "07_select_gtwr_bandwidth")
missing_control_cols <- setdiff(control_candidates, names(panel))
if (length(missing_control_cols) > 0L) {
  stop(
    sprintf(
      "[ERROR] GTWR bandwidth selection %s control set is missing required panel columns: %s.",
      control_set,
      paste(missing_control_cols, collapse = ", ")
    ),
    call. = FALSE
  )
}

if (length(outcomes) == 0L || length(focal_vars) == 0L) {
  write_csv_safe(empty_gtwr_bandwidth_selection_tbl(), selection_path)
  append_log(cfg$logs$model_run, "- GTWR bandwidth selection skipped: missing quarterly outcomes or resident exposure")
} else {
  panel_xy <- prepare_gtwr_points(panel)
  bw_cache_dir <- cfg$get_gtwr_main_bw_cache_dir(control_set)
  ensure_dirs(bw_cache_dir)
  if (isTRUE(cfg$gtwr_refresh_bw_cache)) {
    unlink(list.files(bw_cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
  }

  spec_grid <- tidyr::crossing(
    outcome = outcomes,
    focal_var = focal_vars
  ) |>
    dplyr::left_join(outcome_registry, by = "outcome") |>
    dplyr::arrange(.data$outcome_order, .data$focal_var)

  selection_jobs <- purrr::pmap(
    list(spec_grid$outcome, spec_grid$focal_var),
    function(outcome, focal_var) {
      list(
        outcome = outcome,
        focal_var = focal_var,
        selected_controls = control_candidates,
        control_set = control_set
      )
    }
  )
  workers <- resolve_gtwr_worker_count(length(selection_jobs))

  append_log(
    cfg$logs$model_run,
    paste0(
      "- GTWR bandwidth selection execution: control_set=", control_set,
      ", bw_strategy=", cfg$gtwr_bandwidth_strategy,
      ", bw_anchor_yq=", cfg$gtwr_bw_anchor_yq,
      ", bw_approach=", cfg$gtwr_bw_approach,
      ", specs=", length(selection_jobs),
      ", workers=", workers,
      ", cache_dir=", bw_cache_dir
    )
  )

  selection_results <- if (workers > 1L && !identical(.Platform$OS.type, "windows")) {
    parallel::mclapply(
      selection_jobs,
      run_gtwr_bandwidth_selection_job,
      panel_xy = panel_xy,
      bw_cache_dir = bw_cache_dir,
      mc.cores = workers,
      mc.preschedule = FALSE
    )
  } else {
    lapply(selection_jobs, run_gtwr_bandwidth_selection_job, panel_xy = panel_xy, bw_cache_dir = bw_cache_dir)
  }
  selection_errors <- purrr::keep(selection_results, ~ inherits(.x, "try-error"))
  if (length(selection_errors) > 0L) {
    stop(
      sprintf("[ERROR] %d GTWR bandwidth selection worker(s) failed.", length(selection_errors)),
      call. = FALSE
    )
  }

  selection_tbl <- dplyr::bind_rows(selection_results) |>
    annotate_outcomes(include_robustness = FALSE) |>
    dplyr::arrange(.data$outcome_order, .data$focal_var) |>
    dplyr::select(dplyr::all_of(names(empty_gtwr_bandwidth_selection_tbl())))
  write_csv_safe(selection_tbl, selection_path)

  append_log(
    cfg$logs$model_run,
    paste0(
      "- GTWR bandwidth selection completed: control_set=", control_set,
      ", specs=", nrow(selection_tbl),
      ", statuses=", paste(unique(selection_tbl$status), collapse = "|"),
      ", output=", basename(selection_path)
    )
  )
}
