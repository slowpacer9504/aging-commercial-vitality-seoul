#==============================================================================
# Script    : 03_run_gtwr_age_band.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run age-band quarterly GTWR sidecars for resident and floating
#             age-share exposures when enabled.
# Author    : Codex
# Created   : 2026-04-22
# Status    : OPTIONAL_SIDECAR
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, registered_resident_population.parquet,
#             seoul_raw_integrated_wide.parquet, administrative boundary
# Outputs   : gtwr_age_band_models_*.csv, gtwr_age_band_local_beta_panel_*.csv,
#             gtwr_age_band_local_coefficients_*.csv,
#             gtwr_age_band_controls_used_*.csv,
#             gtwr_age_band_frozen_spec_*.csv
# DependsOn : 02_build_seoul_quarter_base.R,
#             05_build_registered_resident_population.R,
#             07_build_vitality_index.R, utils_gtwr_main.R
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
source(here::here("02_Code", "R", "utils_age_mix.R"))
source(here::here("02_Code", "R", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 03_run_gtwr_age_band", timestamp()))

empty_age_band_summary_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_main_tbl(),
    list(domain = character(), age_band = character(), same_domain_total_control = character())
  )
}

empty_age_band_local_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_local_tbl(),
    list(domain = character(), age_band = character(), same_domain_total_control = character())
  )
}

empty_age_band_panel_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_local_beta_panel_tbl(),
    list(domain = character(), age_band = character(), same_domain_total_control = character())
  )
}

empty_age_band_controls_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_controls_used_tbl(),
    list(
      required_controls = character(),
      global_usable_optional_controls = character(),
      final_scope_usable_optional_controls = character(),
      selected_optional_controls = character(),
      domain = character(),
      age_band = character(),
      same_domain_total_control = character()
    )
  )
}

empty_age_band_frozen_tbl <- function() {
  add_gtwr_constant_cols(
    empty_gtwr_frozen_spec_tbl(),
    list(domain = character(), age_band = character(), same_domain_total_control = character())
  )
}

add_age_band_payload_metadata <- function(payload, job) {
  metadata <- list(
    domain = job$domain,
    age_band = job$age_band,
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

if (!isTRUE(cfg$run_gtwr_age_band_sidecar)) {
  append_log(cfg$logs$model_run, "- GTWR age-band quarterly sidecar skipped by run flag")
} else {
  if (!file.exists(cfg$paths$panel_main) ||
      !file.exists(cfg$paths$registered_resident_population) ||
      !file.exists(cfg$paths$seoul_raw_integrated_wide)) {
    stop("[ERROR] Required inputs missing for GTWR age-band quarterly sidecar.", call. = FALSE)
  }
  if (!requireNamespace("GWmodel", quietly = TRUE)) {
    stop("[ERROR] GWmodel package is required for GTWR age-band sidecar.", call. = FALSE)
  }
  if (!requireNamespace("sp", quietly = TRUE)) {
    stop("[ERROR] sp package is required for GTWR age-band sidecar.", call. = FALSE)
  }

  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  panel_base <- read_panel_main_view("gtwr") |>
    dplyr::mutate(adm_cd = as.character(adm_cd))

  outcome_registry <- resolve_model_outcomes(
    panel_base,
    requested_outcomes = cfg$gtwr_main_outcomes,
    include_robustness = FALSE
  )
  outcomes <- outcome_registry$outcome
  age_band_labels <- intersect(
    as.character(value_or(cfg$gtwr_age_band_labels, c("age20", "age30", "age40", "age50"))),
    c("age20", "age30", "age40", "age50")
  )
  family_registry <- resolve_age_mix_family_registry(
    value_or(cfg$gtwr_age_band_domains, c("resident", "floating"))
  )
  control_candidates <- gtwr_main_control_candidate_cols()
  assert_gtwr_control_vector_current(control_candidates, context = "03_run_gtwr_age_band")
  missing_control_cols <- setdiff(control_candidates, names(panel_base))
  if (length(missing_control_cols) > 0L) {
    stop(
      sprintf(
        "[ERROR] GTWR age-band sidecar %s control set is missing required panel columns: %s.",
        control_set,
        paste(missing_control_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  summary_path <- cfg$get_gtwr_age_band_models_path(control_set)
  local_path <- cfg$get_gtwr_age_band_local_path(control_set)
  panel_path <- cfg$get_gtwr_age_band_panel_path(control_set)
  controls_path <- cfg$get_gtwr_age_band_controls_used_path(control_set)
  frozen_path <- cfg$get_gtwr_age_band_frozen_spec_path(control_set)

  if (length(outcomes) == 0L || length(age_band_labels) == 0L || nrow(family_registry) == 0L) {
    write_csv_safe(empty_age_band_summary_tbl(), summary_path)
    write_csv_safe(empty_age_band_local_tbl(), local_path)
    write_csv_safe(empty_age_band_panel_tbl(), panel_path)
    write_csv_safe(empty_age_band_controls_tbl(), controls_path)
    write_csv_safe(empty_age_band_frozen_tbl(), frozen_path)
    append_log(cfg$logs$model_run, "- GTWR age-band quarterly sidecar skipped: missing quarterly outcomes or valid age-band registry")
  } else {
    cache_dir <- cfg$get_gtwr_age_band_spec_cache_dir(control_set)
    bw_cache_dir <- cfg$get_gtwr_age_band_bw_cache_dir(control_set)
    ensure_dirs(cache_dir)
    ensure_dirs(bw_cache_dir)
    if (isTRUE(cfg$gtwr_refresh_spec_cache)) {
      unlink(list.files(cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
    }
    if (isTRUE(cfg$gtwr_refresh_bw_cache)) {
      unlink(list.files(bw_cache_dir, pattern = "[.]rds$", full.names = TRUE), force = TRUE)
    }

    family_panels <- lapply(seq_len(nrow(family_registry)), function(ii) {
      rec <- family_registry[ii, ]
      domain <- rec$domain[[1]]
      domain_df <- build_domain_age_shares(
        source_value = rec$source_type[[1]],
        domain = domain,
        quarterly_step = rec$quarterly_step[[1]],
        raw_cols = rec$raw_cols[[1]],
        asof_col = rec$asof_col[[1]]
      )
      list(
        domain = domain,
        same_domain_total_control = rec$same_domain_total_control[[1]],
        panel = add_current_age_shares(panel_base, domain_df, domain)
      )
    })

    run_family_ctx <- function(family_ctx) {
      domain <- family_ctx$domain
      family_panel <- family_ctx$panel
      panel_xy <- prepare_gtwr_points(family_panel)

      spec_grid <- tidyr::crossing(
        age_band = age_band_labels,
        outcome = outcomes
      ) |>
        dplyr::mutate(
          domain = .env$domain,
          focal_var = sprintf("%s_%s_share", .data$age_band, .env$domain)
        ) |>
        dplyr::filter(.data$focal_var %in% names(family_panel)) |>
        dplyr::left_join(outcome_registry, by = "outcome") |>
        dplyr::arrange(.data$age_band, .data$outcome_order, .data$focal_var)

      if (nrow(spec_grid) == 0L) return(list())

      jobs <- purrr::pmap(
        list(spec_grid$outcome, spec_grid$age_band, spec_grid$focal_var),
        function(outcome, age_band, focal_var) {
          required_controls <- clean_gtwr_control_vector(family_ctx$same_domain_total_control)
          optional_controls <- setdiff(control_candidates, required_controls)
          selected_controls <- intersect(unique(c(required_controls, optional_controls)), names(family_panel))
          cache_context <- sprintf("age_band_%s_%s", domain, age_band)
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
            domain = domain,
            age_band = age_band,
            required_controls = required_controls,
            optional_controls = optional_controls,
            control_candidates = unique(c(required_controls, control_candidates)),
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

      cached_jobs <- Filter(function(job) isTRUE(job$cached), jobs)
      pending_jobs <- Filter(function(job) !isTRUE(job$cached), jobs)
      workers <- resolve_gtwr_worker_count(length(pending_jobs))

      append_log(
        cfg$logs$model_run,
        paste0(
          "- GTWR age-band sidecar family execution: domain=", domain,
          ", specs=", length(jobs),
          ", cached=", length(cached_jobs),
          ", pending=", length(pending_jobs),
          ", workers=", workers
        )
      )

      pending_results <- run_gtwr_pending_jobs(pending_jobs, workers, panel_xy = panel_xy)
      pending_errors <- purrr::keep(pending_results, ~ inherits(.x, "try-error"))
      if (length(pending_errors) > 0L) {
        stop(
          sprintf("[ERROR] %d GTWR age-band sidecar worker(s) failed for domain=%s before writing cache.", length(pending_errors), domain),
          call. = FALSE
        )
      }

      purrr::map(jobs, function(job) {
        payload <- read_gtwr_spec_cache(job$cache_path, job$signature)
        if (is.null(payload) && is_valid_gtwr_payload(job$payload)) payload <- job$payload
        if (is.null(payload)) {
          stop(
            sprintf(
              "[ERROR] GTWR age-band sidecar cache missing after execution: domain=%s, age_band=%s, outcome=%s, focal=%s, path=%s.",
              job$domain,
              job$age_band,
              job$outcome,
              job$focal_var,
              job$cache_path
            ),
            call. = FALSE
          )
        }
        add_age_band_payload_metadata(payload, job)
      })
    }

    spec_results <- purrr::flatten(purrr::map(family_panels, run_family_ctx))

    summary_tbl_raw <- dplyr::bind_rows(purrr::map(spec_results, "summary"))
    summary_tbl <- if (nrow(summary_tbl_raw) == 0L) {
      empty_age_band_summary_tbl()
    } else {
      summary_tbl_raw |>
        annotate_outcomes(include_robustness = FALSE) |>
        dplyr::arrange(.data$domain, .data$age_band, .data$outcome_order, .data$focal_var)
    }
    local_tbl <- dplyr::bind_rows(purrr::map(spec_results, "local"))
    panel_tbl <- dplyr::bind_rows(purrr::map(spec_results, "panel"))
    controls_tbl_raw <- dplyr::bind_rows(purrr::map(spec_results, "controls"))
    controls_tbl <- if (nrow(controls_tbl_raw) == 0L) {
      empty_age_band_controls_tbl()
    } else {
      controls_tbl_raw |>
        annotate_outcomes(include_robustness = FALSE) |>
        repair_gtwr_controls_trace() |>
        dplyr::arrange(.data$domain, .data$age_band, .data$outcome_order, .data$focal_var)
    }
    assert_gtwr_controls_trace_current(
      controls_tbl,
      context = "03_run_gtwr_age_band controls trace",
      allowed_controls = control_candidates
    )
    frozen_tbl <- dplyr::bind_rows(purrr::map(spec_results, "frozen")) |>
      dplyr::arrange(.data$domain, .data$age_band, .data$outcome, .data$focal_var)

    write_csv_safe(if (nrow(summary_tbl) == 0L) empty_age_band_summary_tbl() else summary_tbl, summary_path)
    write_csv_safe(if (nrow(local_tbl) == 0L) empty_age_band_local_tbl() else local_tbl, local_path)
    write_csv_safe(if (nrow(panel_tbl) == 0L) empty_age_band_panel_tbl() else panel_tbl, panel_path)
    write_csv_safe(if (nrow(controls_tbl) == 0L) empty_age_band_controls_tbl() else controls_tbl, controls_path)
    write_csv_safe(if (nrow(frozen_tbl) == 0L) empty_age_band_frozen_tbl() else frozen_tbl, frozen_path)

    append_log(
      cfg$logs$model_run,
      sprintf(
        "- GTWR age-band quarterly sidecar completed: control_set=%s, specs=%d, statuses=%s",
        control_set,
        nrow(summary_tbl),
        paste(unique(summary_tbl$status), collapse = "|")
      )
    )
  }
}
