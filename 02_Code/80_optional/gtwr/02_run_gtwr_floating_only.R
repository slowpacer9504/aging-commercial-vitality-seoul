#==============================================================================
# Script    : 02_run_gtwr_floating_only.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the floating-only annual GTWR optional sidecar when enabled.
# Author    : Codex
# Created   : 2026-04-22
# Status    : OPTIONAL_SIDECAR
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, administrative boundary
# Outputs   : gtwr_floating_models_*.csv, gtwr_floating_local_beta_panel_*.csv,
#             gtwr_floating_local_coefficients_*.csv,
#             gtwr_floating_controls_used_*.csv,
#             gtwr_floating_frozen_spec_*.csv
# DependsOn : 01_run_gtwr_main.R, utils_gtwr_main.R
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
source(here::here("02_Code", "R", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 02_run_gtwr_floating_only", timestamp()))

if (!isTRUE(cfg$run_gtwr_floating_sidecar)) {
  append_log(cfg$logs$model_run, "- GTWR floating-only annual sidecar skipped by run flag")
} else {
  if (!file.exists(cfg$paths$panel_main)) {
    stop("[ERROR] panel_main missing for GTWR floating-only sidecar.", call. = FALSE)
  }
  if (!requireNamespace("GWmodel", quietly = TRUE)) {
    stop("[ERROR] GWmodel package is required for GTWR floating-only sidecar.", call. = FALSE)
  }
  if (!requireNamespace("sp", quietly = TRUE)) {
    stop("[ERROR] sp package is required for GTWR floating-only sidecar.", call. = FALSE)
  }

  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  panel <- read_panel_main_view("gtwr") |>
    dplyr::mutate(adm_cd = as.character(adm_cd))

  outcome_registry <- resolve_model_outcomes(
    panel,
    requested_outcomes = cfg$gtwr_main_outcomes,
    include_robustness = FALSE
  )
  outcomes <- outcome_registry$outcome
  focal_vars <- intersect(cfg$gtwr_floating_exposure_vars, names(panel))
  control_candidates <- gtwr_main_control_candidate_cols()
  assert_gtwr_control_vector_current(control_candidates, context = "02_run_gtwr_floating_only")
  missing_control_cols <- setdiff(control_candidates, names(panel))
  if (length(missing_control_cols) > 0L) {
    stop(
      sprintf(
        "[ERROR] GTWR floating sidecar %s control set is missing required panel columns: %s.",
        control_set,
        paste(missing_control_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  summary_path <- cfg$get_gtwr_floating_models_path(control_set)
  local_path <- cfg$get_gtwr_floating_local_path(control_set)
  panel_path <- cfg$get_gtwr_floating_local_beta_panel_path(control_set)
  controls_path <- cfg$get_gtwr_floating_controls_used_path(control_set)
  frozen_path <- cfg$get_gtwr_floating_frozen_spec_path(control_set)

  if (length(outcomes) == 0L || length(focal_vars) == 0L) {
    write_csv_safe(empty_gtwr_main_tbl(), summary_path)
    write_csv_safe(empty_gtwr_local_tbl(), local_path)
    write_csv_safe(empty_gtwr_local_beta_panel_tbl(), panel_path)
    write_csv_safe(empty_gtwr_controls_used_tbl(), controls_path)
    write_csv_safe(empty_gtwr_frozen_spec_tbl(), frozen_path)
    append_log(cfg$logs$model_run, "- GTWR floating-only annual sidecar skipped: missing annual outcomes or floating exposure")
  } else {
    panel_xy <- prepare_gtwr_points(panel)
    cache_dir <- cfg$get_gtwr_floating_spec_cache_dir(control_set)
    bw_cache_dir <- cfg$get_gtwr_floating_bw_cache_dir(control_set)
    ensure_dirs(cache_dir)
    ensure_dirs(bw_cache_dir)
    if (isTRUE(cfg$gtwr_refresh_spec_cache)) {
      unlink(list.files(cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
    }
    if (isTRUE(cfg$gtwr_refresh_bw_cache)) {
      unlink(list.files(bw_cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
    }

    spec_grid <- tidyr::crossing(
      outcome = outcomes,
      focal_var = focal_vars
    ) |>
      dplyr::left_join(outcome_registry, by = "outcome") |>
      dplyr::arrange(.data$outcome_order, .data$focal_var)

    cache_context <- "floating"
    spec_jobs <- purrr::pmap(
      list(spec_grid$outcome, spec_grid$focal_var),
      function(outcome, focal_var) {
        selected_controls <- control_candidates
        signature <- build_gtwr_spec_signature(
          outcome = outcome,
          focal_var = focal_var,
          selected_controls = selected_controls,
          control_set = control_set,
          cache_context = cache_context
        )
        cache_path <- get_gtwr_spec_cache_path(cache_dir, outcome, focal_var)
        cached_payload <- if (isTRUE(cfg$gtwr_resume_specs) && !isTRUE(cfg$gtwr_refresh_spec_cache)) {
          read_gtwr_spec_cache(cache_path, signature)
        } else {
          NULL
        }
        list(
          outcome = outcome,
          focal_var = focal_var,
          control_candidates = control_candidates,
          selected_controls = selected_controls,
          control_set = control_set,
          cache_context = cache_context,
          bw_cache_dir = bw_cache_dir,
          signature = signature,
          cache_path = cache_path,
          cached = !is.null(cached_payload),
          payload = cached_payload
        )
      }
    )

    cached_jobs <- Filter(function(job) isTRUE(job$cached), spec_jobs)
    pending_jobs <- Filter(function(job) !isTRUE(job$cached), spec_jobs)
    workers <- resolve_gtwr_worker_count(length(pending_jobs))

    append_log(
      cfg$logs$model_run,
      paste0(
        "- GTWR floating-only sidecar execution: control_set=", control_set,
        ", controls={", paste(control_candidates, collapse = "|"), "}",
        ", specs=", length(spec_jobs),
        ", cached=", length(cached_jobs),
        ", pending=", length(pending_jobs),
        ", workers=", workers,
        ", cache_dir=", cache_dir
      )
    )

    pending_results <- run_gtwr_pending_jobs(pending_jobs, workers, panel_xy = panel_xy)
    pending_errors <- purrr::keep(pending_results, ~ inherits(.x, "try-error"))
    if (length(pending_errors) > 0L) {
      stop(
        sprintf("[ERROR] %d GTWR floating sidecar worker(s) failed before writing cache. Re-run 02_run_gtwr_floating_only.R to continue remaining specs.", length(pending_errors)),
        call. = FALSE
      )
    }

    spec_results <- purrr::map(spec_jobs, function(job) {
      payload <- read_gtwr_spec_cache(job$cache_path, job$signature)
      if (!is.null(payload)) return(payload)
      if (is_valid_gtwr_payload(job$payload)) return(job$payload)
      stop(
        sprintf(
          "[ERROR] GTWR floating sidecar cache missing after execution: outcome=%s, focal=%s, path=%s.",
          job$outcome,
          job$focal_var,
          job$cache_path
        ),
        call. = FALSE
      )
    })

    summary_tbl <- dplyr::bind_rows(purrr::map(spec_results, "summary")) |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(.data$outcome_order, .data$focal_var)
    local_tbl <- dplyr::bind_rows(purrr::map(spec_results, "local"))
    panel_tbl <- dplyr::bind_rows(purrr::map(spec_results, "panel"))
    controls_tbl <- dplyr::bind_rows(purrr::map(spec_results, "controls")) |>
      annotate_outcomes(include_robustness = FALSE) |>
      repair_gtwr_controls_trace() |>
      dplyr::arrange(.data$outcome_order, .data$focal_var)
    assert_gtwr_controls_trace_current(
      controls_tbl,
      context = "02_run_gtwr_floating_only controls trace",
      allowed_controls = control_candidates
    )
    frozen_tbl <- dplyr::bind_rows(purrr::map(spec_results, "frozen"))

    write_csv_safe(summary_tbl, summary_path)
    write_csv_safe(if (nrow(local_tbl) == 0L) empty_gtwr_local_tbl() else local_tbl, local_path)
    write_csv_safe(if (nrow(panel_tbl) == 0L) empty_gtwr_local_beta_panel_tbl() else panel_tbl, panel_path)
    write_csv_safe(if (nrow(controls_tbl) == 0L) empty_gtwr_controls_used_tbl() else controls_tbl, controls_path)
    write_csv_safe(if (nrow(frozen_tbl) == 0L) empty_gtwr_frozen_spec_tbl() else frozen_tbl, frozen_path)

    append_log(
      cfg$logs$model_run,
      sprintf(
        "- GTWR floating-only annual sidecar completed: control_set=%s, specs=%d, statuses=%s",
        control_set,
        nrow(summary_tbl),
        paste(unique(summary_tbl$status), collapse = "|")
      )
    )
  }
}
