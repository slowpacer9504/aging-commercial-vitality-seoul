#==============================================================================
# Script    : 03_run_gtwr_sector_share.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the sector-share quarterly GTWR optional sidecar with separate
#             resident-only and floating-only exposure families.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-04-22
# Status    : QUARTERLY_OPTIONAL / manual GTWR sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, administrative boundary
# Outputs   : gtwr_sector_share_models_*.csv,
#             gtwr_sector_share_local_beta_panel_*.csv,
#             gtwr_sector_share_local_coefficients_*.csv,
#             gtwr_sector_share_controls_used_*.csv,
#             gtwr_sector_share_frozen_spec_*.csv
# DependsOn : 03_run_spdm_sector_share_experiment.R, utils_gtwr_main.R
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

append_log(cfg$logs$model_run, sprintf("\n## [%s] 03_run_gtwr_sector_share", timestamp()))

#==============================================================================
# 1. Helper Functions
#==============================================================================

empty_sector_share_summary_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_main_tbl(),
    list(exposure_family = character(), same_domain_total_control = character())
  )
}

empty_sector_share_local_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_local_tbl(),
    list(exposure_family = character(), same_domain_total_control = character())
  )
}

empty_sector_share_panel_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_local_beta_panel_tbl(),
    list(exposure_family = character(), same_domain_total_control = character())
  )
}

empty_sector_share_controls_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_controls_used_tbl(),
    list(
      required_controls = character(),
      global_usable_optional_controls = character(),
      final_scope_usable_optional_controls = character(),
      selected_optional_controls = character(),
      exposure_family = character(),
      same_domain_total_control = character()
    )
  )
}

empty_sector_share_frozen_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_frozen_spec_tbl(),
    list(exposure_family = character(), same_domain_total_control = character())
  )
}

add_sector_share_payload_metadata <- function(payload, job) {
  metadata <- list(
    exposure_family = job$exposure_family,
    same_domain_total_control = collapse_chr(job$required_controls)
  )
  payload <- add_gtwr_payload_metadata(payload, metadata)
  payload$controls <- add_gtwr_constant_cols(
    payload$controls,
    list(
      required_controls = collapse_chr(job$required_controls),
      global_usable_optional_controls = collapse_chr(job$optional_controls),
      final_scope_usable_optional_controls = collapse_chr(job$optional_controls),
      selected_optional_controls = collapse_chr(setdiff(job$selected_controls, job$required_controls))
    )
  )
  payload
}

#==============================================================================
# 2. Run Sector-Share GTWR Sidecar
#==============================================================================

{
  if (!file.exists(cfg$paths$panel_main)) {
    stop("[ERROR] panel_main missing for GTWR sector-share quarterly sidecar.", call. = FALSE)
  }
  if (!requireNamespace("GWmodel", quietly = TRUE)) {
    stop("[ERROR] GWmodel package is required for GTWR sector-share sidecar.", call. = FALSE)
  }
  if (!requireNamespace("sp", quietly = TRUE)) {
    stop("[ERROR] sp package is required for GTWR sector-share sidecar.", call. = FALSE)
  }

  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  cfg$gtwr_bandwidth_strategy <- "fixed"
  panel <- read_panel_main_view("gtwr", extra_cols = cfg$gtwr_sector_share_outcomes) |>
    dplyr::mutate(adm_cd = as.character(adm_cd))

  outcomes <- intersect(cfg$gtwr_sector_share_outcomes, names(panel))
  control_candidates <- gtwr_main_control_candidate_cols()
  assert_gtwr_control_vector_current(control_candidates, context = "03_run_gtwr_sector_share")
  missing_control_cols <- setdiff(control_candidates, names(panel))
  if (length(missing_control_cols) > 0L) {
    stop(
      sprintf(
        "[ERROR] GTWR sector-share sidecar %s control set is missing required panel columns: %s.",
        control_set,
        paste(missing_control_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  family_registry <- tibble::tibble(
    exposure_family = c("resident_only", "floating_only"),
    focal_var = c("age60_resident_share", "age60_floating_share"),
    same_domain_total_control = c("ln_resident_pop", NA_character_)
  ) |>
    dplyr::filter(.data$focal_var %in% names(panel))

  summary_path <- cfg$get_gtwr_sector_share_models_path(control_set)
  local_path <- cfg$get_gtwr_sector_share_local_path(control_set)
  panel_path <- cfg$get_gtwr_sector_share_panel_path(control_set)
  controls_path <- cfg$get_gtwr_sector_share_controls_used_path(control_set)
  frozen_path <- cfg$get_gtwr_sector_share_frozen_spec_path(control_set)

  if (length(outcomes) == 0L || nrow(family_registry) == 0L) {
    write_csv_safe(empty_sector_share_summary_tbl(), summary_path)
    write_csv_safe(empty_sector_share_local_tbl(), local_path)
    write_csv_safe(empty_sector_share_panel_tbl(), panel_path)
    write_csv_safe(empty_sector_share_controls_tbl(), controls_path)
    write_csv_safe(empty_sector_share_frozen_tbl(), frozen_path)
    append_log(cfg$logs$model_run, "- GTWR sector-share quarterly sidecar skipped: missing sector-share outcomes or quarterly exposure families")
  } else {
    panel_xy <- prepare_gtwr_points(panel)
    cache_dir <- cfg$get_gtwr_sector_share_spec_cache_dir(control_set)
    ensure_dirs(cache_dir)
    if (isTRUE(cfg$gtwr_refresh_spec_cache)) {
      unlink(list.files(cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
    }

    spec_grid <- tidyr::crossing(
      outcome = outcomes,
      family_row = seq_len(nrow(family_registry))
    ) |>
      dplyr::mutate(
        exposure_family = family_registry$exposure_family[.data$family_row],
        focal_var = family_registry$focal_var[.data$family_row],
        same_domain_total_control = family_registry$same_domain_total_control[.data$family_row],
        outcome_order = match(.data$outcome, .env$outcomes)
      ) |>
      dplyr::arrange(.data$exposure_family, .data$outcome_order, .data$outcome, .data$focal_var)

    spec_jobs <- purrr::pmap(
      list(
        spec_grid$outcome,
        spec_grid$exposure_family,
        spec_grid$focal_var,
        spec_grid$same_domain_total_control
      ),
      function(outcome, exposure_family, focal_var, same_domain_total_control) {
        required_controls <- clean_gtwr_control_vector(same_domain_total_control)
        optional_controls <- setdiff(control_candidates, required_controls)
        selected_controls <- intersect(unique(c(required_controls, optional_controls)), names(panel))
        cache_context <- sprintf("sector_share_%s", exposure_family)
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
          exposure_family = exposure_family,
          required_controls = required_controls,
          optional_controls = optional_controls,
          control_candidates = unique(c(required_controls, control_candidates)),
          selected_controls = selected_controls,
          control_set = control_set,
          cache_context = cache_context,
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
        "- GTWR sector-share sidecar execution: control_set=", control_set,
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
        sprintf("[ERROR] %d GTWR sector-share sidecar worker(s) failed before writing cache.", length(pending_errors)),
        call. = FALSE
      )
    }

    spec_results <- purrr::map(spec_jobs, function(job) {
      payload <- read_gtwr_spec_cache(job$cache_path, job$signature)
      if (is.null(payload) && is_valid_gtwr_payload(job$payload)) payload <- job$payload
      if (is.null(payload)) {
        stop(
          sprintf(
            "[ERROR] GTWR sector-share sidecar cache missing after execution: family=%s, outcome=%s, focal=%s, path=%s.",
            job$exposure_family,
            job$outcome,
            job$focal_var,
            job$cache_path
          ),
          call. = FALSE
        )
      }
      add_sector_share_payload_metadata(payload, job)
    })

    summary_tbl <- dplyr::bind_rows(purrr::map(spec_results, "summary")) |>
      dplyr::mutate(outcome_group = "sector_share", outcome_order = match(.data$outcome, outcomes)) |>
      dplyr::arrange(.data$exposure_family, .data$outcome_order, .data$outcome, .data$focal_var)
    local_tbl <- dplyr::bind_rows(purrr::map(spec_results, "local"))
    panel_tbl <- dplyr::bind_rows(purrr::map(spec_results, "panel"))
    controls_tbl <- dplyr::bind_rows(purrr::map(spec_results, "controls")) |>
      dplyr::mutate(outcome_group = "sector_share", outcome_order = match(.data$outcome, outcomes)) |>
      repair_gtwr_controls_trace() |>
      dplyr::arrange(.data$exposure_family, .data$outcome_order, .data$outcome, .data$focal_var)
    assert_gtwr_controls_trace_current(
      controls_tbl,
      context = "03_run_gtwr_sector_share controls trace",
      allowed_controls = control_candidates
    )
    frozen_tbl <- dplyr::bind_rows(purrr::map(spec_results, "frozen")) |>
      dplyr::arrange(.data$exposure_family, .data$outcome, .data$focal_var)

    write_csv_safe(if (nrow(summary_tbl) == 0L) empty_sector_share_summary_tbl() else summary_tbl, summary_path)
    write_csv_safe(if (nrow(local_tbl) == 0L) empty_sector_share_local_tbl() else local_tbl, local_path)
    write_csv_safe(if (nrow(panel_tbl) == 0L) empty_sector_share_panel_tbl() else panel_tbl, panel_path)
    write_csv_safe(if (nrow(controls_tbl) == 0L) empty_sector_share_controls_tbl() else controls_tbl, controls_path)
    write_csv_safe(if (nrow(frozen_tbl) == 0L) empty_sector_share_frozen_tbl() else frozen_tbl, frozen_path)

    append_log(
      cfg$logs$model_run,
      sprintf(
        "- GTWR sector-share quarterly sidecar completed: control_set=%s, specs=%d, statuses=%s",
        control_set,
        nrow(summary_tbl),
        paste(unique(summary_tbl$status), collapse = "|")
      )
    )
  }
}
