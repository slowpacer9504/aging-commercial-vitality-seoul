#==============================================================================
# Script    : 07_run_gtwr_bandwidth_sensitivity.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run fixed-bandwidth grid sensitivity for the resident-only
#             quarterly GTWR main sidecar.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-05-20
# Status    : QUARTERLY_DIAGNOSTIC / manual GTWR diagnostic outside canonical workflow
# Type      : spatial_panel_modeling_diagnostic
# Inputs    : panel_main.parquet, gtwr_main_models_<control_set>.csv,
#             gtwr_local_coefficients_<control_set>.csv
# Outputs   : gtwr_bandwidth_sensitivity_<control_set>.csv,
#             gtwr_bandwidth_sensitivity_cache/<control_set>/main/*.rds
# DependsOn : 03_run_gtwr_main.R, utils_gtwr_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
source(here::here("02_Code", "R", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 07_run_gtwr_bandwidth_sensitivity", timestamp()))

#==============================================================================
# 1. Run Bandwidth Sensitivity Diagnostic
#==============================================================================

{
  # This sidecar treats bandwidth values as fixed perturbations around the main
  # GTWR run, so baseline summary/local outputs must already exist.
  cfg$gtwr_bandwidth_strategy <- "fixed"
  if (!file.exists(cfg$paths$panel_main)) {
    stop("[ERROR] panel_main missing for GTWR bandwidth sensitivity.", call. = FALSE)
  }
  if (!requireNamespace("GWmodel", quietly = TRUE)) {
    stop("[ERROR] GWmodel package is required for GTWR bandwidth sensitivity.", call. = FALSE)
  }
  if (!requireNamespace("sp", quietly = TRUE)) {
    stop("[ERROR] sp package is required for GTWR bandwidth sensitivity.", call. = FALSE)
  }

  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  summary_path <- cfg$get_gtwr_main_models_path(control_set)
  local_path <- cfg$get_gtwr_local_coefficients_path(control_set)
  bandwidth_sensitivity_path <- cfg$get_gtwr_bandwidth_sensitivity_path(control_set)
  if (!file.exists(summary_path) || !file.exists(local_path)) {
    stop(
      sprintf(
        "[ERROR] Baseline GTWR outputs are required before bandwidth sensitivity. Run 02_Code/03_models/03_run_gtwr_main.R first. Missing: %s",
        paste(c(summary_path, local_path)[!file.exists(c(summary_path, local_path))], collapse = ", ")
      ),
      call. = FALSE
    )
  }

  summary_tbl <- readr::read_csv(summary_path, show_col_types = FALSE)
  local_tbl <- readr::read_csv(local_path, show_col_types = FALSE)
  if (nrow(summary_tbl) == 0L || nrow(local_tbl) == 0L) {
    stop("[ERROR] Baseline GTWR outputs are empty; run 03_run_gtwr_main.R successfully before bandwidth sensitivity.", call. = FALSE)
  }

  panel <- read_panel_main_view("gtwr") |>
    dplyr::mutate(adm_cd = as.character(adm_cd))
  outcome_registry <- resolve_model_outcomes(
    panel,
    requested_outcomes = cfg$gtwr_main_outcomes,
    include_robustness = FALSE
  )
  outcomes <- intersect(outcome_registry$outcome, unique(summary_tbl$outcome))
  focal_vars <- intersect(cfg$gtwr_main_exposure_vars, unique(summary_tbl$focal_var))
  control_candidates <- gtwr_main_control_candidate_cols()
  assert_gtwr_control_vector_current(control_candidates, context = "07_run_gtwr_bandwidth_sensitivity")
  missing_control_cols <- setdiff(control_candidates, names(panel))
  if (length(missing_control_cols) > 0L) {
    stop(
      sprintf(
        "[ERROR] GTWR bandwidth sensitivity %s control set is missing required panel columns: %s.",
        control_set,
        paste(missing_control_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  if (length(outcomes) == 0L || length(focal_vars) == 0L) {
    write_csv_safe(empty_gtwr_bandwidth_sensitivity_tbl(), bandwidth_sensitivity_path)
    append_log(cfg$logs$model_run, "- GTWR bandwidth sensitivity skipped: no baseline main specs match current config")
  } else {
    # Refit only non-baseline bandwidths and prepend the baseline row so the
    # output table can be plotted or reviewed as one complete sensitivity grid.
    panel_xy <- prepare_gtwr_points(panel)
    spec_grid <- tidyr::crossing(
      outcome = outcomes,
      focal_var = focal_vars
    ) |>
      dplyr::left_join(outcome_registry, by = "outcome") |>
      dplyr::arrange(.data$outcome_order, .data$focal_var)

    baseline_latest_tbl <- local_tbl |>
      dplyr::filter(.data$status == "success", is.finite(.data$estimate)) |>
      dplyr::transmute(
        adm_cd = as.character(.data$adm_cd),
        outcome,
        focal_var,
        main_estimate = suppressWarnings(as.numeric(.data$estimate))
      )
    baseline_st_bw <- suppressWarnings(as.integer(cfg$gtwr_st_bw))
    bandwidth_grid <- parse_gtwr_numeric_grid(
      cfg$gtwr_bandwidth_sensitivity_grid,
      default = baseline_st_bw
    )
    bandwidth_grid <- suppressWarnings(as.integer(round(bandwidth_grid)))
    bandwidth_grid <- sort(unique(bandwidth_grid[is.finite(bandwidth_grid) & bandwidth_grid >= 30L]))
    bandwidth_grid <- sort(unique(c(baseline_st_bw, bandwidth_grid)))
    nonbaseline_bandwidth_grid <- bandwidth_grid[bandwidth_grid != baseline_st_bw]

    bandwidth_cache_dir <- cfg$get_gtwr_bandwidth_sensitivity_cache_dir(control_set)
    ensure_dirs(bandwidth_cache_dir)
    if (isTRUE(cfg$gtwr_refresh_bandwidth_sensitivity_cache)) {
      unlink(list.files(bandwidth_cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
    }

    bandwidth_grid_tbl <- tidyr::crossing(
      outcome = spec_grid$outcome,
      focal_var = spec_grid$focal_var,
      st_bw = nonbaseline_bandwidth_grid
    ) |>
      dplyr::left_join(spec_grid |> dplyr::select(outcome, focal_var, outcome_order), by = c("outcome", "focal_var")) |>
      dplyr::arrange(.data$outcome_order, .data$focal_var, .data$st_bw)

    bandwidth_jobs <- purrr::pmap(
      list(bandwidth_grid_tbl$outcome, bandwidth_grid_tbl$focal_var, bandwidth_grid_tbl$st_bw),
      function(outcome, focal_var, st_bw) {
        selected_controls <- control_candidates
        signature <- build_gtwr_bandwidth_sensitivity_signature(
          outcome = outcome,
          focal_var = focal_var,
          selected_controls = selected_controls,
          control_set = control_set,
          st_bw = st_bw,
          baseline_st_bw = baseline_st_bw,
          lamda = cfg$gtwr_lamda,
          ksi = cfg$gtwr_ksi
        )
        cache_path <- get_gtwr_bandwidth_sensitivity_cache_path(
          cache_dir = bandwidth_cache_dir,
          outcome = outcome,
          focal_var = focal_var,
          st_bw = st_bw,
          lamda = cfg$gtwr_lamda,
          ksi = cfg$gtwr_ksi
        )
        cached_payload <- if (isTRUE(cfg$gtwr_resume_specs) && !isTRUE(cfg$gtwr_refresh_bandwidth_sensitivity_cache)) {
          read_gtwr_bandwidth_sensitivity_cache(cache_path, signature)
        } else {
          NULL
        }
        list(
          outcome = outcome,
          focal_var = focal_var,
          control_candidates = control_candidates,
          selected_controls = selected_controls,
          control_set = control_set,
          st_bw = st_bw,
          baseline_st_bw = baseline_st_bw,
          baseline_latest = baseline_latest_tbl,
          signature = signature,
          cache_path = cache_path,
          cached = !is.null(cached_payload),
          payload = cached_payload
        )
      }
    )

    bandwidth_cached_jobs <- Filter(function(job) isTRUE(job$cached), bandwidth_jobs)
    bandwidth_pending_jobs <- Filter(function(job) !isTRUE(job$cached), bandwidth_jobs)
    bandwidth_workers <- resolve_gtwr_worker_count(length(bandwidth_pending_jobs))

    append_log(
      cfg$logs$model_run,
      paste0(
        "- GTWR bandwidth sensitivity execution: control_set=", control_set,
        ", baseline_st_bw=", baseline_st_bw,
        ", bandwidth_grid=", paste(bandwidth_grid, collapse = "|"),
        ", specs=", length(bandwidth_jobs),
        ", cached=", length(bandwidth_cached_jobs),
        ", pending=", length(bandwidth_pending_jobs),
        ", workers=", bandwidth_workers,
        ", cache_dir=", bandwidth_cache_dir
      )
    )

    bandwidth_pending_results <- run_gtwr_bandwidth_sensitivity_pending_jobs(
      bandwidth_pending_jobs,
      bandwidth_workers
    )
    bandwidth_pending_errors <- purrr::keep(bandwidth_pending_results, ~ inherits(.x, "try-error"))
    if (length(bandwidth_pending_errors) > 0L) {
      stop(
        sprintf("[ERROR] %d GTWR bandwidth sensitivity worker(s) failed before writing cache. Re-run 07_run_gtwr_bandwidth_sensitivity.R to continue remaining sensitivity specs.", length(bandwidth_pending_errors)),
        call. = FALSE
      )
    }

    bandwidth_results <- purrr::map(bandwidth_jobs, function(job) {
      payload <- read_gtwr_bandwidth_sensitivity_cache(job$cache_path, job$signature)
      if (!is.null(payload)) return(payload)
      if (is_valid_gtwr_bandwidth_sensitivity_payload(job$payload)) return(job$payload)
      stop(
        sprintf(
          "[ERROR] GTWR bandwidth sensitivity cache missing after execution: outcome=%s, focal=%s, st_bw=%s, path=%s. Re-run 07_run_gtwr_bandwidth_sensitivity.R to continue.",
          job$outcome,
          job$focal_var,
          as.character(job$st_bw),
          job$cache_path
        ),
        call. = FALSE
      )
    })

    bandwidth_sensitivity_tbl <- dplyr::bind_rows(
      build_gtwr_bandwidth_baseline_rows(summary_tbl),
      dplyr::bind_rows(bandwidth_results)
    ) |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(.data$outcome_order, .data$focal_var, .data$st_bw) |>
      dplyr::select(dplyr::all_of(names(empty_gtwr_bandwidth_sensitivity_tbl())))
    write_csv_safe(bandwidth_sensitivity_tbl, bandwidth_sensitivity_path)

    append_log(
      cfg$logs$model_run,
      paste0(
        "- GTWR bandwidth sensitivity completed: control_set=", control_set,
        ", specs=", nrow(bandwidth_sensitivity_tbl),
        ", statuses=", paste(unique(bandwidth_sensitivity_tbl$status), collapse = "|"),
        ", output=", basename(bandwidth_sensitivity_path)
      )
    )
  }
}
