#==============================================================================
# Script    : 08_run_gtwr_lamda_sensitivity.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run lamda grid sensitivity for the resident-only quarterly GTWR
#             main sidecar.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-05-20
# Status    : QUARTERLY_DIAGNOSTIC / manual GTWR diagnostic outside canonical workflow
# Type      : spatial_panel_modeling_diagnostic
# Inputs    : panel_main.parquet, gtwr_main_models_<control_set>.csv,
#             gtwr_local_coefficients_<control_set>.csv
# Outputs   : gtwr_lamda_sensitivity_<control_set>.csv,
#             gtwr_lamda_sensitivity_cache/<control_set>/main/*.rds
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

append_log(cfg$logs$model_run, sprintf("\n## [%s] 08_run_gtwr_lamda_sensitivity", timestamp()))

#==============================================================================
# 1. Run Lamda Sensitivity Diagnostic
#==============================================================================

{
  # Lamda sensitivity holds the main GTWR bandwidth rule fixed and perturbs the
  # spatiotemporal distance parameter around the baseline local-beta surface.
  cfg$gtwr_bandwidth_strategy <- "fixed"
  if (!file.exists(cfg$paths$panel_main)) {
    stop("[ERROR] panel_main missing for GTWR lamda sensitivity.", call. = FALSE)
  }
  if (!requireNamespace("GWmodel", quietly = TRUE)) {
    stop("[ERROR] GWmodel package is required for GTWR lamda sensitivity.", call. = FALSE)
  }
  if (!requireNamespace("sp", quietly = TRUE)) {
    stop("[ERROR] sp package is required for GTWR lamda sensitivity.", call. = FALSE)
  }

  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  summary_path <- cfg$get_gtwr_main_models_path(control_set)
  local_path <- cfg$get_gtwr_local_coefficients_path(control_set)
  lamda_sensitivity_path <- cfg$get_gtwr_lamda_sensitivity_path(control_set)
  if (!file.exists(summary_path) || !file.exists(local_path)) {
    stop(
      sprintf(
        "[ERROR] Baseline GTWR outputs are required before lamda sensitivity. Run 02_Code/03_models/03_run_gtwr_main.R first. Missing: %s",
        paste(c(summary_path, local_path)[!file.exists(c(summary_path, local_path))], collapse = ", ")
      ),
      call. = FALSE
    )
  }

  summary_tbl <- readr::read_csv(summary_path, show_col_types = FALSE)
  local_tbl <- readr::read_csv(local_path, show_col_types = FALSE)
  if (nrow(summary_tbl) == 0L || nrow(local_tbl) == 0L) {
    stop("[ERROR] Baseline GTWR outputs are empty; run 03_run_gtwr_main.R successfully before lamda sensitivity.", call. = FALSE)
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
  assert_gtwr_control_vector_current(control_candidates, context = "08_run_gtwr_lamda_sensitivity")
  missing_control_cols <- setdiff(control_candidates, names(panel))
  if (length(missing_control_cols) > 0L) {
    stop(
      sprintf(
        "[ERROR] GTWR lamda sensitivity %s control set is missing required panel columns: %s.",
        control_set,
        paste(missing_control_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  if (length(outcomes) == 0L || length(focal_vars) == 0L) {
    write_csv_safe(empty_gtwr_lamda_sensitivity_tbl(), lamda_sensitivity_path)
    append_log(cfg$logs$model_run, "- GTWR lamda sensitivity skipped: no baseline main specs match current config")
  } else {
    # Refit non-baseline lamda values and append a baseline reuse row so every
    # outcome/exposure has a complete comparison family.
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
    lamda_grid <- parse_gtwr_numeric_grid(
      cfg$gtwr_lamda_sensitivity_grid,
      default = suppressWarnings(as.numeric(cfg$gtwr_lamda))
    )
    baseline_lamda <- suppressWarnings(as.numeric(cfg$gtwr_lamda))
    lamda_grid <- sort(unique(c(baseline_lamda, lamda_grid)))
    nonbaseline_lamda_grid <- lamda_grid[!vapply(
      lamda_grid,
      function(x) isTRUE(all.equal(x, baseline_lamda, tolerance = 1e-12)),
      logical(1)
    )]

    lamda_cache_dir <- cfg$get_gtwr_lamda_sensitivity_cache_dir(control_set)
    ensure_dirs(lamda_cache_dir)
    if (isTRUE(cfg$gtwr_refresh_lamda_sensitivity_cache)) {
      unlink(list.files(lamda_cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
    }

    sensitivity_grid <- tidyr::crossing(
      outcome = spec_grid$outcome,
      focal_var = spec_grid$focal_var,
      lamda = nonbaseline_lamda_grid
    ) |>
      dplyr::left_join(spec_grid |> dplyr::select(outcome, focal_var, outcome_order), by = c("outcome", "focal_var")) |>
      dplyr::arrange(.data$outcome_order, .data$focal_var, .data$lamda)

    sensitivity_jobs <- purrr::pmap(
      list(sensitivity_grid$outcome, sensitivity_grid$focal_var, sensitivity_grid$lamda),
      function(outcome, focal_var, lamda) {
        selected_controls <- control_candidates
        signature <- build_gtwr_lamda_sensitivity_signature(
          outcome = outcome,
          focal_var = focal_var,
          selected_controls = selected_controls,
          control_set = control_set,
          lamda = lamda,
          ksi = cfg$gtwr_ksi
        )
        cache_path <- get_gtwr_lamda_sensitivity_cache_path(
          cache_dir = lamda_cache_dir,
          outcome = outcome,
          focal_var = focal_var,
          lamda = lamda,
          ksi = cfg$gtwr_ksi
        )
        cached_payload <- if (isTRUE(cfg$gtwr_resume_specs) && !isTRUE(cfg$gtwr_refresh_lamda_sensitivity_cache)) {
          read_gtwr_lamda_sensitivity_cache(cache_path, signature)
        } else {
          NULL
        }
        list(
          outcome = outcome,
          focal_var = focal_var,
          control_candidates = control_candidates,
          selected_controls = selected_controls,
          control_set = control_set,
          lamda = lamda,
          ksi = cfg$gtwr_ksi,
          baseline_latest = baseline_latest_tbl,
          signature = signature,
          cache_path = cache_path,
          cached = !is.null(cached_payload),
          payload = cached_payload
        )
      }
    )

    sensitivity_cached_jobs <- Filter(function(job) isTRUE(job$cached), sensitivity_jobs)
    sensitivity_pending_jobs <- Filter(function(job) !isTRUE(job$cached), sensitivity_jobs)
    sensitivity_workers <- resolve_gtwr_worker_count(length(sensitivity_pending_jobs))

    append_log(
      cfg$logs$model_run,
      paste0(
        "- GTWR lamda sensitivity execution: control_set=", control_set,
        ", baseline_lamda=", baseline_lamda,
        ", lamda_grid=", paste(lamda_grid, collapse = "|"),
        ", specs=", length(sensitivity_jobs),
        ", cached=", length(sensitivity_cached_jobs),
        ", pending=", length(sensitivity_pending_jobs),
        ", workers=", sensitivity_workers,
        ", cache_dir=", lamda_cache_dir
      )
    )

    sensitivity_pending_results <- run_gtwr_lamda_sensitivity_pending_jobs(
      sensitivity_pending_jobs,
      sensitivity_workers
    )
    sensitivity_pending_errors <- purrr::keep(sensitivity_pending_results, ~ inherits(.x, "try-error"))
    if (length(sensitivity_pending_errors) > 0L) {
      stop(
        sprintf("[ERROR] %d GTWR lamda sensitivity worker(s) failed before writing cache. Re-run 08_run_gtwr_lamda_sensitivity.R to continue remaining sensitivity specs.", length(sensitivity_pending_errors)),
        call. = FALSE
      )
    }

    sensitivity_results <- purrr::map(sensitivity_jobs, function(job) {
      payload <- read_gtwr_lamda_sensitivity_cache(job$cache_path, job$signature)
      if (!is.null(payload)) return(payload)
      if (is_valid_gtwr_lamda_sensitivity_payload(job$payload)) return(job$payload)
      stop(
        sprintf(
          "[ERROR] GTWR lamda sensitivity cache missing after execution: outcome=%s, focal=%s, lamda=%s, path=%s. Re-run 08_run_gtwr_lamda_sensitivity.R to continue.",
          job$outcome,
          job$focal_var,
          as.character(job$lamda),
          job$cache_path
        ),
        call. = FALSE
      )
    })

    lamda_sensitivity_tbl <- dplyr::bind_rows(
      build_gtwr_lamda_baseline_rows(summary_tbl),
      dplyr::bind_rows(sensitivity_results)
    ) |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(.data$outcome_order, .data$focal_var, .data$lamda) |>
      dplyr::select(dplyr::all_of(names(empty_gtwr_lamda_sensitivity_tbl())))
    write_csv_safe(lamda_sensitivity_tbl, lamda_sensitivity_path)

    append_log(
      cfg$logs$model_run,
      paste0(
        "- GTWR lamda sensitivity completed: control_set=", control_set,
        ", specs=", nrow(lamda_sensitivity_tbl),
        ", statuses=", paste(unique(lamda_sensitivity_tbl$status), collapse = "|"),
        ", output=", basename(lamda_sensitivity_path)
      )
    )
  }
}
