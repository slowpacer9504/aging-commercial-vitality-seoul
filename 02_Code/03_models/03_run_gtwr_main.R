#==============================================================================
# Script    : 03_run_gtwr_main.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the resident-only quarterly GTWR optional sidecar and overwrite
#             the configured output bundle on each active execution.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-03-27
# Status    : QUARTERLY_OPTIONAL / manual GTWR sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, administrative boundary
# Outputs   : gtwr_main_models_<control_set>.csv,
#             gtwr_local_beta_panel_<control_set>.csv,
#             gtwr_local_coefficients_<control_set>.csv,
#             gtwr_controls_used_<control_set>.csv,
#             gtwr_main_frozen_spec_<control_set>.csv
# DependsOn : 01_run_twfe_main.R, utils_gtwr_main.R
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

append_log(cfg$logs$model_run, sprintf("\n## [%s] 03_run_gtwr_main", timestamp()))

#==============================================================================
# 1. Resident-Only Quarterly GTWR Contract
#==============================================================================

{
  if (!file.exists(cfg$paths$panel_main)) {
    stop("[ERROR] panel_main missing for GTWR.", call. = FALSE)
  }
  if (!requireNamespace("GWmodel", quietly = TRUE)) {
    stop("[ERROR] GWmodel package is required for actual GTWR estimation.", call. = FALSE)
  }
  if (!requireNamespace("sp", quietly = TRUE)) {
    stop("[ERROR] sp package is required for actual GTWR estimation.", call. = FALSE)
  }

  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  requested_bw_strategy <- cfg$gtwr_bandwidth_strategy
  cfg$gtwr_bandwidth_strategy <- "fixed"
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
  assert_gtwr_control_vector_current(control_candidates, context = "03_run_gtwr_main")
  missing_control_cols <- setdiff(control_candidates, names(panel))
  if (length(missing_control_cols) > 0L) {
    stop(
      sprintf(
        "[ERROR] GTWR %s control set is missing required panel columns: %s. Re-run 06_build_analysis_panel.R and 07_build_vitality_index.R.",
        cfg$gtwr_control_set,
        paste(missing_control_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  summary_path <- cfg$get_gtwr_main_models_path(control_set)
  local_path <- cfg$get_gtwr_local_coefficients_path(control_set)
  panel_path <- cfg$get_gtwr_local_beta_panel_path(control_set)
  controls_path <- cfg$get_gtwr_controls_used_path(control_set)
  frozen_path <- cfg$get_gtwr_main_frozen_spec_path(control_set)

  if (length(outcomes) == 0L || length(focal_vars) == 0L) {
    write_csv_safe(empty_gtwr_main_tbl(), summary_path)
    write_csv_safe(empty_gtwr_local_tbl(), local_path)
    write_csv_safe(empty_gtwr_local_beta_panel_tbl(), panel_path)
    write_csv_safe(empty_gtwr_controls_used_tbl(), controls_path)
    write_csv_safe(empty_gtwr_frozen_spec_tbl(), frozen_path)
    append_log(cfg$logs$model_run, "- GTWR main skipped: missing quarterly outcomes or resident exposure")
  } else {
    panel_xy <- prepare_gtwr_points(panel)
    cache_dir <- cfg$get_gtwr_main_spec_cache_dir(control_set)
    ensure_dirs(cache_dir)
    if (isTRUE(cfg$gtwr_refresh_spec_cache)) {
      unlink(list.files(cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
    }

    spec_grid <- tidyr::crossing(
      outcome = outcomes,
      focal_var = focal_vars
    ) |>
      dplyr::left_join(outcome_registry, by = "outcome") |>
      dplyr::arrange(outcome_order, focal_var)

    spec_jobs <- purrr::pmap(
      list(spec_grid$outcome, spec_grid$focal_var),
      function(outcome, focal_var) {
        selected_controls <- control_candidates
        signature <- build_gtwr_spec_signature(
          outcome = outcome,
          focal_var = focal_var,
          selected_controls = selected_controls,
          control_set = control_set,
          cache_context = "main"
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
          cache_context = "main",
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
        "- GTWR main spec execution: control_set=", control_set,
        ", controls={", paste(control_candidates, collapse = "|"), "}",
        ", specs=", length(spec_jobs),
        ", cached=", length(cached_jobs),
        ", pending=", length(pending_jobs),
        ", workers=", workers,
        ", resume=", isTRUE(cfg$gtwr_resume_specs),
        ", refresh_cache=", isTRUE(cfg$gtwr_refresh_spec_cache),
        ", bw_strategy=fixed",
        ", requested_bw_strategy=", requested_bw_strategy,
        ", cache_dir=", cache_dir
      )
    )

    pending_results <- run_gtwr_pending_jobs(pending_jobs, workers, panel_xy = panel_xy)
    pending_errors <- purrr::keep(pending_results, ~ inherits(.x, "try-error"))
    if (length(pending_errors) > 0L) {
      stop(
        sprintf("[ERROR] %d GTWR spec worker(s) failed before writing cache. Re-run 03_models/03_run_gtwr_main.R to continue remaining specs.", length(pending_errors)),
        call. = FALSE
      )
    }

    spec_results <- purrr::map(spec_jobs, function(job) {
      payload <- read_gtwr_spec_cache(job$cache_path, job$signature)
      if (!is.null(payload)) return(payload)
      if (is_valid_gtwr_payload(job$payload)) return(job$payload)
      stop(
        sprintf(
          "[ERROR] GTWR spec cache missing after execution: outcome=%s, focal=%s, path=%s. Re-run 03_models/03_run_gtwr_main.R to continue remaining specs.",
          job$outcome,
          job$focal_var,
          job$cache_path
        ),
        call. = FALSE
      )
    })

    summary_tbl <- dplyr::bind_rows(purrr::map(spec_results, "summary")) |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, focal_var)
    local_tbl <- dplyr::bind_rows(purrr::map(spec_results, "local"))
    panel_tbl <- dplyr::bind_rows(purrr::map(spec_results, "panel"))
    controls_tbl <- dplyr::bind_rows(purrr::map(spec_results, "controls")) |>
      annotate_outcomes(include_robustness = FALSE) |>
      repair_gtwr_controls_trace() |>
      standardize_gtwr_controls_used_tbl() |>
      dplyr::arrange(outcome_order, focal_var)
    assert_gtwr_controls_trace_current(
      controls_tbl,
      context = "03_run_gtwr_main controls trace",
      allowed_controls = control_candidates
    )
    frozen_tbl <- dplyr::bind_rows(purrr::map(spec_results, "frozen"))

    write_csv_safe(summary_tbl, summary_path)
    write_csv_safe(if (nrow(local_tbl) == 0L) empty_gtwr_local_tbl() else local_tbl, local_path)
    write_csv_safe(if (nrow(panel_tbl) == 0L) empty_gtwr_local_beta_panel_tbl() else panel_tbl, panel_path)
    write_csv_safe(controls_tbl, controls_path)
    write_csv_safe(frozen_tbl, frozen_path)

    append_log(
      cfg$logs$model_run,
      paste0(
        "- GTWR main quarterly sidecar completed: control_set=", control_set,
        ", specs=", nrow(summary_tbl),
        ", statuses=", paste(unique(summary_tbl$status), collapse = "|"),
        ", outputs={", basename(summary_path), ",", basename(panel_path), ",", basename(local_path), ",", basename(controls_path), ",", basename(frozen_path), "}"
      )
    )
  }
}
