#==============================================================================
# Script    : 06_run_gtwr_experiment.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Emit an annual GTWR experiment registry and deferred result
#             bundle for manual appendix comparisons.
# Author    : Codex
# Created   : 2026-04-22
# Status    : ANNUAL_APPENDIX / manual sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet
# Outputs   : gtwr_experiment_registry_*.csv, gtwr_experiment_main_models_*.csv,
#             gtwr_experiment_controls_used_*.csv,
#             gtwr_experiment_ranked_candidates_*.csv,
#             gtwr_experiment_local_beta_panel_*.csv,
#             gtwr_experiment_local_coefficients_*.csv
# DependsOn : 01_run_gtwr_main.R
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 06_run_gtwr_experiment", timestamp()))

split_tokens <- function(x) {
  x <- trimws(as.character(value_or(x, "")[[1]]))
  if (!nzchar(x)) {
    return(character())
  }
  toks <- unlist(strsplit(x, "[,;|[:space:]]+"))
  toks[nzchar(toks)]
}

parse_num_tokens <- function(x, default) {
  toks <- split_tokens(x)
  vals <- suppressWarnings(as.numeric(toks))
  vals <- vals[is.finite(vals)]
  if (length(vals) == 0L) default else vals
}

build_variants <- function() {
  bw_approaches <- split_tokens(cfg$gtwr_experiment_bw_approaches)
  if (length(bw_approaches) == 0L) bw_approaches <- "CV"
  lamda_grid <- parse_num_tokens(cfg$gtwr_experiment_lamda_grid, default = 0.05)
  ksi_grid <- parse_num_tokens(cfg$gtwr_experiment_ksi_grid, default = 0)
  min_st_bw_grid <- parse_num_tokens(cfg$gtwr_experiment_min_st_bw_grid, default = 120)
  control_strategies <- split_tokens(cfg$gtwr_experiment_control_strategies)
  if (length(control_strategies) == 0L) control_strategies <- "baseline"

  tidyr::expand_grid(
    bw_approach = bw_approaches,
    lamda = lamda_grid,
    ksi = ksi_grid,
    min_st_bw = min_st_bw_grid,
    control_strategy = control_strategies
  ) |>
    dplyr::mutate(
      control_set_id = cfg$gtwr_control_set_token(cfg$gtwr_control_set),
      use_configured_control_set = TRUE,
      experiment_id = sprintf("annual_exp_%03d", dplyr::row_number()),
      is_baseline_variant = dplyr::row_number() == 1L
    ) |>
    dplyr::relocate(experiment_id, .before = 1)
}

empty_summary_tbl <- function() {
  tibble::tibble(
    method = character(),
    outcome = character(),
    focal_var = character(),
    exposure = character(),
    target_year = integer(),
    estimate_type = character(),
    earliest_year = integer(),
    latest_year = integer(),
    window_scope = character(),
    n_locations = integer(),
    n_valid = integer(),
    mean_beta = numeric(),
    sd_beta = numeric(),
    p25_beta = numeric(),
    p50_beta = numeric(),
    p75_beta = numeric(),
    share_positive = numeric(),
    st_bw = numeric(),
    global_gw_r2 = numeric(),
    global_gw_r2_adj = numeric(),
    global_edf = numeric(),
    collinearity_warn_n = integer(),
    collinearity_warn_share = numeric(),
    max_local_cn = numeric(),
    max_local_vif = numeric(),
    control_set = character(),
    fit_scope = character(),
    recent_year_n = integer(),
    location_frac = numeric(),
    location_n = integer(),
    n_obs_fit = integer(),
    bw_obs_n = integer(),
    bw_source = character(),
    control_origin = character(),
    bandwidth_origin = character(),
    frozen_spec_status = character(),
    frozen_spec_reason = character(),
    elapsed_sec = numeric(),
    status = character(),
    message = character(),
    control_set_id = character(),
    use_configured_control_set = logical(),
    experiment_id = character(),
    bw_approach = character(),
    lamda = numeric(),
    ksi = numeric(),
    min_st_bw = numeric(),
    st_bw_raw = numeric(),
    st_bw_used = numeric(),
    st_bw_floor_applied = logical(),
    control_strategy = character(),
    is_baseline_variant = logical()
  )
}

empty_local_tbl <- function() {
  tibble::tibble(
    adm_cd = character(),
    outcome = character(),
    focal_var = character(),
    estimate = numeric(),
    earliest_estimate = numeric(),
    latest_estimate = numeric(),
    estimate_type = character(),
    earliest_year = integer(),
    latest_year = integer(),
    window_scope = character(),
    status = character(),
    message = character(),
    n_obs = integer(),
    n_eff = integer(),
    target_year = integer(),
    method = character(),
    control_set = character(),
    fit_scope = character(),
    recent_year_n = integer(),
    location_frac = numeric(),
    location_n = integer(),
    bw_obs_n = integer(),
    bw_source = character(),
    control_set_id = character(),
    use_configured_control_set = logical(),
    experiment_id = character(),
    bw_approach = character(),
    lamda = numeric(),
    ksi = numeric(),
    min_st_bw = numeric(),
    st_bw_raw = numeric(),
    st_bw_used = numeric(),
    st_bw_floor_applied = logical(),
    control_strategy = character(),
    is_baseline_variant = logical()
  )
}

empty_panel_tbl <- function() {
  tibble::tibble(
    adm_cd = character(),
    year = integer(),
    time_id = integer(),
    outcome = character(),
    focal_var = character(),
    estimate = numeric(),
    estimate_type = character(),
    window_scope = character(),
    status = character(),
    message = character(),
    n_obs = integer(),
    n_eff = integer(),
    target_year = integer(),
    method = character(),
    control_set = character(),
    fit_scope = character(),
    recent_year_n = integer(),
    location_frac = numeric(),
    location_n = integer(),
    bw_obs_n = integer(),
    bw_source = character(),
    control_set_id = character(),
    use_configured_control_set = logical(),
    experiment_id = character(),
    bw_approach = character(),
    lamda = numeric(),
    ksi = numeric(),
    min_st_bw = numeric(),
    st_bw_raw = numeric(),
    st_bw_used = numeric(),
    st_bw_floor_applied = logical(),
    control_strategy = character(),
    is_baseline_variant = logical()
  )
}

empty_controls_tbl <- function() {
  tibble::tibble(
    outcome = character(),
    focal_var = character(),
    required_controls = character(),
    optional_candidates = character(),
    global_usable_optional_controls = character(),
    final_scope_usable_optional_controls = character(),
    selected_controls = character(),
    selected_optional_controls = character(),
    base_n_obs = integer(),
    base_n_units = integer(),
    selected_n_obs = integer(),
    selected_n_units = integer(),
    retention_ratio = numeric(),
    retention_floor = numeric(),
    selection_status = character(),
    selection_strategy = character(),
    control_set = character(),
    fit_scope = character(),
    recent_year_n = integer(),
    location_frac = numeric(),
    location_n = integer(),
    bw_obs_n = integer(),
    bw_source = character(),
    control_origin = character(),
    bandwidth_origin = character(),
    frozen_spec_status = character(),
    frozen_spec_reason = character(),
    finite_n_final_scope = character(),
    zero_share_final_scope = character(),
    sd_final_scope = character(),
    zero_share_warn_controls = character(),
    status = character(),
    message = character(),
    control_set_id = character(),
    use_configured_control_set = logical(),
    experiment_id = character(),
    bw_approach = character(),
    lamda = numeric(),
    ksi = numeric(),
    min_st_bw = numeric(),
    control_strategy = character(),
    is_baseline_variant = logical()
  )
}

summarize_sample <- function(panel, vars) {
  d <- panel |>
    dplyr::select(dplyr::all_of(intersect(vars, names(panel)))) |>
    tidyr::drop_na()

  list(
    n_obs_fit = nrow(d),
    n_units = dplyr::n_distinct(d$adm_cd),
    n_periods = dplyr::n_distinct(d$year),
    sample_min_year = if (nrow(d) > 0L) suppressWarnings(as.integer(min(d$year, na.rm = TRUE))) else NA_integer_,
    sample_max_year = if (nrow(d) > 0L) suppressWarnings(as.integer(max(d$year, na.rm = TRUE))) else NA_integer_
  )
}

build_message <- function(meta, experiment_id) {
  if (meta$n_obs_fit < 400L || meta$n_units < 30L || meta$n_periods < cfg$spdm_min_periods) {
    sprintf(
      "annual_gtwr_experiment_deferred: insufficient annual support for %s after contemporaneous complete-case filtering",
      experiment_id
    )
  } else {
    sprintf(
      "annual_gtwr_experiment_deferred: %s preserved as manual annual experiment metadata but not estimated",
      experiment_id
    )
  }
}

if (!isTRUE(cfg$run_gtwr_experiment_sidecar)) {
  append_log(cfg$logs$model_run, "- GTWR experiment annual sidecar skipped by run flag")
} else {
  if (!file.exists(cfg$paths$panel_main)) {
    stop("[ERROR] panel_main missing for GTWR experiment annual sidecar.", call. = FALSE)
  }

  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  panel <- read_panel_main_view("gtwr") |>
    dplyr::mutate(adm_cd = as.character(adm_cd))

  requested_outcomes <- split_tokens(cfg$gtwr_experiment_outcomes)
  base_outcomes <- if (length(requested_outcomes) > 0L) requested_outcomes else cfg$gtwr_main_outcomes
  outcomes <- intersect(base_outcomes, names(panel))
  focal_vars <- intersect(cfg$gtwr_main_exposure_vars, names(panel))
  control_candidates <- intersect(gtwr_main_control_candidate_cols(), names(panel))
  assert_gtwr_control_vector_current(control_candidates, context = "06_run_gtwr_experiment")
  variants <- build_variants()

  summary_path <- cfg$get_gtwr_experiment_main_models_path(control_set)
  local_path <- cfg$get_gtwr_experiment_local_path(control_set)
  panel_path <- cfg$get_gtwr_experiment_panel_path(control_set)
  controls_path <- cfg$get_gtwr_experiment_controls_used_path(control_set)
  state_controls_path <- cfg$get_gtwr_experiment_state_controls_used_path(control_set)
  registry_path <- cfg$get_gtwr_experiment_registry_path(control_set)
  ranked_path <- cfg$get_gtwr_experiment_ranked_candidates_path(control_set)

  registry_tbl <- variants |>
    dplyr::mutate(
      control_set = control_set,
      status = "annual_deferred",
      message = "manual annual experiment registry; local estimation not activated"
    )

  if (length(outcomes) == 0L || length(focal_vars) == 0L || nrow(variants) == 0L) {
    write_csv_safe(empty_summary_tbl(), summary_path)
    write_csv_safe(empty_local_tbl(), local_path)
    write_csv_safe(empty_panel_tbl(), panel_path)
    write_csv_safe(empty_controls_tbl(), controls_path)
    write_csv_safe(empty_controls_tbl(), state_controls_path)
    write_csv_safe(registry_tbl, registry_path)
    write_csv_safe(tibble::tibble(), ranked_path)
    append_log(cfg$logs$model_run, "- GTWR experiment annual sidecar skipped: missing annual outcomes, resident exposure, or variants")
  } else {
    spec_rows <- tidyr::crossing(
      outcome = outcomes,
      focal_var = focal_vars,
      variants
    ) |>
      dplyr::mutate(
        outcome_order = match(outcome, outcomes)
      ) |>
      dplyr::rowwise() |>
      dplyr::do({
        spec <- .
        vars <- unique(c("adm_cd", "year", spec$outcome, spec$focal_var, control_candidates))
        meta <- summarize_sample(panel, vars)
        message <- build_message(meta, spec$experiment_id)

        summary_row <- empty_summary_tbl() |>
          dplyr::add_row(
            method = "GWmodel::gtwr",
            outcome = spec$outcome,
            focal_var = spec$focal_var,
            exposure = spec$focal_var,
            target_year = meta$sample_max_year,
            estimate_type = "latest_minus_earliest",
            earliest_year = meta$sample_min_year,
            latest_year = meta$sample_max_year,
            window_scope = "annual_full_window",
            n_locations = meta$n_units,
            n_valid = 0L,
            control_set = control_set,
            fit_scope = "annual_deferred",
            recent_year_n = meta$n_periods,
            location_frac = 1,
            location_n = meta$n_units,
            n_obs_fit = meta$n_obs_fit,
            control_origin = "annual_screened",
            bandwidth_origin = "deferred",
            frozen_spec_status = "annual_deferred",
            frozen_spec_reason = "manual_appendix_not_estimated",
            status = "not_estimated",
            message = message,
            control_set_id = spec$control_set_id,
            use_configured_control_set = spec$use_configured_control_set,
            experiment_id = spec$experiment_id,
            bw_approach = spec$bw_approach,
            lamda = spec$lamda,
            ksi = spec$ksi,
            min_st_bw = spec$min_st_bw,
            control_strategy = spec$control_strategy,
            is_baseline_variant = spec$is_baseline_variant
          )

        controls_row <- empty_controls_tbl() |>
          dplyr::add_row(
            outcome = spec$outcome,
            focal_var = spec$focal_var,
            required_controls = NA_character_,
            optional_candidates = collapse_chr(control_candidates),
            global_usable_optional_controls = collapse_chr(control_candidates),
            final_scope_usable_optional_controls = collapse_chr(control_candidates),
            selected_controls = collapse_chr(control_candidates),
            selected_optional_controls = collapse_chr(control_candidates),
            base_n_obs = meta$n_obs_fit,
            base_n_units = meta$n_units,
            selected_n_obs = meta$n_obs_fit,
            selected_n_units = meta$n_units,
            retention_ratio = 1,
            retention_floor = 1,
            selection_status = "annual_deferred",
            selection_strategy = spec$control_strategy,
            control_set = control_set,
            fit_scope = "annual_deferred",
            recent_year_n = meta$n_periods,
            location_frac = 1,
            location_n = meta$n_units,
            control_origin = "annual_screened",
            bandwidth_origin = "deferred",
            frozen_spec_status = "annual_deferred",
            frozen_spec_reason = "manual_appendix_not_estimated",
            status = "not_estimated",
            message = message,
            control_set_id = spec$control_set_id,
            use_configured_control_set = spec$use_configured_control_set,
            experiment_id = spec$experiment_id,
            bw_approach = spec$bw_approach,
            lamda = spec$lamda,
            ksi = spec$ksi,
            min_st_bw = spec$min_st_bw,
            control_strategy = spec$control_strategy,
            is_baseline_variant = spec$is_baseline_variant
          )

        tibble::tibble(
          summary = list(summary_row),
          controls = list(controls_row)
        )
      }) |>
      dplyr::ungroup()

    summary_tbl <- dplyr::bind_rows(spec_rows$summary) |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, experiment_id, focal_var)
    controls_tbl <- dplyr::bind_rows(spec_rows$controls) |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, experiment_id, focal_var)
    assert_gtwr_controls_trace_current(
      controls_tbl,
      context = "06_run_gtwr_experiment controls trace",
      allowed_controls = control_candidates
    )
    ranked_tbl <- summary_tbl |>
      dplyr::mutate(
        rank_order = dplyr::row_number(),
        rank_score = NA_real_
      ) |>
      dplyr::select(
        control_set, outcome, focal_var, experiment_id, control_set_id,
        bw_approach, lamda, ksi, min_st_bw, control_strategy,
        status, message, rank_order, rank_score
      )

    write_csv_safe(summary_tbl, summary_path)
    write_csv_safe(empty_local_tbl(), local_path)
    write_csv_safe(empty_panel_tbl(), panel_path)
    write_csv_safe(controls_tbl, controls_path)
    write_csv_safe(controls_tbl, state_controls_path)
    write_csv_safe(registry_tbl, registry_path)
    write_csv_safe(ranked_tbl, ranked_path)

    append_log(
      cfg$logs$model_run,
      sprintf(
        "- GTWR experiment annual sidecar emitted deferred bundle: control_set=%s, specs=%d, variants=%d",
        control_set,
        nrow(summary_tbl),
        nrow(registry_tbl)
      )
    )
  }
}
