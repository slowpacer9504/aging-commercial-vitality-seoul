#==============================================================================
# Script    : 01_run_gtwr_main.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the resident-only quarterly GTWR optional sidecar and overwrite
#             the configured output bundle on each active execution.
# Author    : Codex
# Created   : 2026-03-27
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, administrative boundary
# Outputs   : gtwr_main_models_<control_set>.csv,
#             gtwr_local_beta_panel_<control_set>.csv,
#             gtwr_local_coefficients_<control_set>.csv,
#             gtwr_controls_used_<control_set>.csv,
#             gtwr_main_frozen_spec_<control_set>.csv,
#             gtwr_lamda_sensitivity_<control_set>.csv,
#             gtwr_bandwidth_sensitivity_<control_set>.csv
# DependsOn : 01_run_twfe_main.R, utils_gtwr_main.R
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

append_log(cfg$logs$model_run, sprintf("\n## [%s] 01_run_gtwr_main", timestamp()))

#==============================================================================
# 1. Resident-Only Quarterly GTWR Contract
#==============================================================================

if (!isTRUE(cfg$run_gtwr)) {
  append_log(cfg$logs$model_run, "- GTWR main skipped (run_gtwr = FALSE)")
} else {
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
  assert_gtwr_control_vector_current(control_candidates, context = "01_run_gtwr_main")
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
  lamda_sensitivity_path <- cfg$get_gtwr_lamda_sensitivity_path(control_set)
  bandwidth_sensitivity_path <- cfg$get_gtwr_bandwidth_sensitivity_path(control_set)

  if (length(outcomes) == 0L || length(focal_vars) == 0L) {
    write_csv_safe(empty_gtwr_main_tbl(), summary_path)
    write_csv_safe(empty_gtwr_local_tbl(), local_path)
    write_csv_safe(empty_gtwr_local_beta_panel_tbl(), panel_path)
    write_csv_safe(empty_gtwr_controls_used_tbl(), controls_path)
    write_csv_safe(empty_gtwr_frozen_spec_tbl(), frozen_path)
    write_csv_safe(empty_gtwr_lamda_sensitivity_tbl(), lamda_sensitivity_path)
    write_csv_safe(empty_gtwr_bandwidth_sensitivity_tbl(), bandwidth_sensitivity_path)
    append_log(cfg$logs$model_run, "- GTWR main skipped: missing quarterly outcomes or resident exposure")
  } else {
    panel_xy <- prepare_gtwr_points(panel)
    cache_dir <- cfg$get_gtwr_main_spec_cache_dir(control_set)
    bw_cache_dir <- cfg$get_gtwr_main_bw_cache_dir(control_set)
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
        "- GTWR main spec execution: control_set=", control_set,
        ", controls={", paste(control_candidates, collapse = "|"), "}",
        ", specs=", length(spec_jobs),
        ", cached=", length(cached_jobs),
        ", pending=", length(pending_jobs),
        ", workers=", workers,
        ", resume=", isTRUE(cfg$gtwr_resume_specs),
        ", refresh_cache=", isTRUE(cfg$gtwr_refresh_spec_cache),
        ", bw_strategy=", cfg$gtwr_bandwidth_strategy,
        ", bw_anchor_yq=", cfg$gtwr_bw_anchor_yq,
        ", bw_approach=", cfg$gtwr_bw_approach,
        ", refresh_bw_cache=", isTRUE(cfg$gtwr_refresh_bw_cache),
        ", cache_dir=", cache_dir
      )
    )

    pending_results <- run_gtwr_pending_jobs(pending_jobs, workers, panel_xy = panel_xy)
    pending_errors <- purrr::keep(pending_results, ~ inherits(.x, "try-error"))
    if (length(pending_errors) > 0L) {
      stop(
        sprintf("[ERROR] %d GTWR spec worker(s) failed before writing cache. Re-run 80_optional/gtwr/01_run_gtwr_main.R to continue remaining specs.", length(pending_errors)),
        call. = FALSE
      )
    }

    spec_results <- purrr::map(spec_jobs, function(job) {
      payload <- read_gtwr_spec_cache(job$cache_path, job$signature)
      if (!is.null(payload)) return(payload)
      if (is_valid_gtwr_payload(job$payload)) return(job$payload)
      stop(
        sprintf(
          "[ERROR] GTWR spec cache missing after execution: outcome=%s, focal=%s, path=%s. Re-run 80_optional/gtwr/01_run_gtwr_main.R to continue remaining specs.",
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
      context = "01_run_gtwr_main controls trace",
      allowed_controls = control_candidates
    )
    frozen_tbl <- dplyr::bind_rows(purrr::map(spec_results, "frozen"))

    write_csv_safe(summary_tbl, summary_path)
    write_csv_safe(if (nrow(local_tbl) == 0L) empty_gtwr_local_tbl() else local_tbl, local_path)
    write_csv_safe(if (nrow(panel_tbl) == 0L) empty_gtwr_local_beta_panel_tbl() else panel_tbl, panel_path)
    write_csv_safe(controls_tbl, controls_path)
    write_csv_safe(frozen_tbl, frozen_path)

    baseline_latest_tbl <- local_tbl |>
      dplyr::filter(.data$status == "success", is.finite(.data$estimate)) |>
      dplyr::transmute(
        adm_cd,
        outcome,
        focal_var,
        main_estimate = suppressWarnings(as.numeric(.data$estimate))
      )

    if (isTRUE(cfg$run_gtwr_lamda_sensitivity)) {
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
          sprintf("[ERROR] %d GTWR lamda sensitivity worker(s) failed before writing cache. Re-run 80_optional/gtwr/01_run_gtwr_main.R to continue remaining sensitivity specs.", length(sensitivity_pending_errors)),
          call. = FALSE
        )
      }

      sensitivity_results <- purrr::map(sensitivity_jobs, function(job) {
        payload <- read_gtwr_lamda_sensitivity_cache(job$cache_path, job$signature)
        if (!is.null(payload)) return(payload)
        if (is_valid_gtwr_lamda_sensitivity_payload(job$payload)) return(job$payload)
        stop(
          sprintf(
            "[ERROR] GTWR lamda sensitivity cache missing after execution: outcome=%s, focal=%s, lamda=%s, path=%s. Re-run 80_optional/gtwr/01_run_gtwr_main.R to continue.",
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
    } else {
      write_csv_safe(empty_gtwr_lamda_sensitivity_tbl(), lamda_sensitivity_path)
      append_log(cfg$logs$model_run, "- GTWR lamda sensitivity skipped (RUN_GTWR_LAMDA_SENSITIVITY=FALSE)")
    }

    if (isTRUE(cfg$run_gtwr_bandwidth_sensitivity)) {
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
          sprintf("[ERROR] %d GTWR bandwidth sensitivity worker(s) failed before writing cache. Re-run 80_optional/gtwr/01_run_gtwr_main.R to continue remaining sensitivity specs.", length(bandwidth_pending_errors)),
          call. = FALSE
        )
      }

      bandwidth_results <- purrr::map(bandwidth_jobs, function(job) {
        payload <- read_gtwr_bandwidth_sensitivity_cache(job$cache_path, job$signature)
        if (!is.null(payload)) return(payload)
        if (is_valid_gtwr_bandwidth_sensitivity_payload(job$payload)) return(job$payload)
        stop(
          sprintf(
            "[ERROR] GTWR bandwidth sensitivity cache missing after execution: outcome=%s, focal=%s, st_bw=%s, path=%s. Re-run 80_optional/gtwr/01_run_gtwr_main.R to continue.",
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
    } else {
      write_csv_safe(empty_gtwr_bandwidth_sensitivity_tbl(), bandwidth_sensitivity_path)
      append_log(cfg$logs$model_run, "- GTWR bandwidth sensitivity skipped (RUN_GTWR_BANDWIDTH_SENSITIVITY=FALSE)")
    }

    append_log(
      cfg$logs$model_run,
      paste0(
        "- GTWR main quarterly sidecar completed: control_set=", control_set,
        ", specs=", nrow(summary_tbl),
        ", statuses=", paste(unique(summary_tbl$status), collapse = "|"),
        ", outputs={", basename(summary_path), ",", basename(panel_path), ",", basename(local_path), ",", basename(controls_path), ",", basename(frozen_path), ",", basename(lamda_sensitivity_path), ",", basename(bandwidth_sensitivity_path), "}"
      )
    )
  }
}
