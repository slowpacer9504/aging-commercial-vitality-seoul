#==============================================================================
# Script    : 01_run_spdm_w_robustness.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Re-estimate the resident-only main SPDM under Queen, Rook, kNN6,
#             and kNN8 to check W sensitivity using the same SDM contract.
# Author    : Codex
# Created   : 2026-03-29
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, W_queen.rds, W_rook.rds, W_knn6.rds, W_knn8.rds
# Outputs   : spdm_w_robustness_models.csv, spdm_w_robustness_impacts.csv,
#             spdm_w_robustness_controls_used.csv,
#             spdm_w_robustness_diagnostics.csv
# DependsOn : 01_build_spatial_weights.R, 02_run_spdm_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spdm.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 01_run_spdm_w_robustness", timestamp()))

if (!file.exists(cfg$paths$panel_main)) {
  stop("[ERROR] Missing panel_main for SPDM W robustness", call. = FALSE)
}

panel <- read_panel_main_view("spdm")
panel$adm_cd <- as.character(panel$adm_cd)

outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = value_or(cfg$spdm_main_outcomes, c(
    "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability", "vitality_index_base"
  )),
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome
exposure_base <- if (!is.null(cfg$spdm_main_exposure_vars) && length(cfg$spdm_main_exposure_vars) > 0) {
  cfg$spdm_main_exposure_vars
} else {
  c("age60_resident_share")
}
exposures <- intersect(exposure_base, names(panel))

control_candidates <- spdm_main_control_candidate_cols()
control_screen <- resolve_outcome_control_screen(
  panel,
  outcomes = outcomes,
  candidates = control_candidates,
  min_finite = 500L
)
assert_spdm_main_controls_current(
  control_screen,
  context = "01_run_spdm_w_robustness",
  control_col = "control",
  selected_col = "selected"
)
control_contracts <- resolve_outcome_control_contracts(control_screen, outcomes = outcomes)

impact_sim_R <- as.integer(value_or(cfg$spdm_impact_sim_R, 1000L))
impact_sim_type <- as.character(value_or(cfg$spdm_impact_sim_type, "mult"))
impact_empirical <- isTRUE(value_or(cfg$spdm_impact_empirical, FALSE))
w_types <- unique(c(value_or(cfg$default_w, "queen"), value_or(cfg$alt_w, c("rook", "knn6", "knn8"))))


#==============================================================================
# 1. Helpers
#==============================================================================

resolve_w_path <- function(w_type) {
  cfg$paths[[paste0("w_", w_type)]]
}

finalize_outputs <- function(out_coef, out_imp, out_ctrl, out_diag) {
  list(
    coefs = out_coef |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, w_type, exposure, spec_id, term),
    impacts = out_imp |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, w_type, exposure, spec_id, focal_var),
    controls = out_ctrl |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, w_type, exposure, spec_id, control_order),
    diagnostics = out_diag |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, w_type, exposure, spec_id)
  )
}

build_fail_result <- function(spec_id,
                              outcome,
                              exposure,
                              w_type,
                              message,
                              requested_controls,
                              usable_controls,
                              balanced_controls = character(),
                              selected_controls = character(),
                              n_units = NA_integer_,
                              n_periods = NA_integer_,
                              n_obs = NA_integer_,
                              sample_min_year = NA_integer_,
                              sample_max_year = NA_integer_) {
  controls_out <- build_spdm_control_rows(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    requested_controls = requested_controls,
    usable_controls = usable_controls,
    balanced_controls = balanced_controls,
    selected_controls = selected_controls,
    status = "failed",
    message = message,
    model_family = "sdm",
    w_type = w_type
  )

  impacts_out <- spdm_empty_impacts_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = exposure,
      status = "failed",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = sample_min_year,
      sample_max_year = sample_max_year,
      model_family = "sdm",
      w_type = w_type,
      sim_R = impact_sim_R,
      sim_method = impact_sim_type,
      message = as.character(message)
    )

  coefs_out <- spdm_empty_coef_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      status = "failed",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = sample_min_year,
      sample_max_year = sample_max_year,
      model_family = "sdm",
      w_type = w_type,
      message = as.character(message)
    )

  diag_out <- build_spdm_diagnostics_row(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    model_family = "sdm",
    w_type = w_type,
    status = "failed",
    n_units = n_units,
    n_periods = n_periods,
    n_obs = n_obs,
    sample_min_year = sample_min_year,
    sample_max_year = sample_max_year,
    selected_controls = selected_controls,
    impacts_status = "failed",
    message = message
  )

  list(coefs = coefs_out, impacts = impacts_out, controls = controls_out, diagnostics = diag_out)
}

run_w_spec <- function(spec_id,
                       outcome,
                       exposure,
                       w_type,
                       panel,
                       requested_controls,
                       usable_controls) {
  w_path <- resolve_w_path(w_type)
  if (is.null(w_path) || !file.exists(w_path)) {
    return(build_fail_result(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      w_type = w_type,
      message = sprintf("missing_w_file:%s", w_type),
      requested_controls = requested_controls,
      usable_controls = usable_controls
    ))
  }

  lw <- readRDS(w_path)
  w_ids <- attr(lw$neighbours, "region.id")
  if (is.null(w_ids)) {
    return(build_fail_result(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      w_type = w_type,
      message = "region.id missing in W",
      requested_controls = requested_controls,
      usable_controls = usable_controls
    ))
  }
  w_ids <- as.character(w_ids)

  prep <- prepare_spdm_spec(
    panel = panel,
    outcome = outcome,
    exposure = exposure,
    lw = lw,
    w_ids = w_ids,
    requested_controls = requested_controls,
    usable_controls = usable_controls,
    model_family = "sdm"
  )

  if (!identical(prep$status, "success") || is.null(prep$mod)) {
    return(build_fail_result(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      w_type = w_type,
      message = prep$message,
      requested_controls = requested_controls,
      usable_controls = usable_controls,
      balanced_controls = prep$balanced_controls,
      selected_controls = prep$selected_controls,
      n_units = prep$n_units,
      n_periods = prep$n_periods,
      n_obs = prep$n_obs,
      sample_min_year = prep$sample_min_year,
      sample_max_year = prep$sample_max_year
    ))
  }

  coef_tbl <- extract_spdm_coef_table(
    mod = prep$mod,
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    n_units = prep$n_units,
    n_periods = prep$n_periods,
    n_obs = prep$n_obs,
    sample_min_year = prep$sample_min_year,
    sample_max_year = prep$sample_max_year,
    model_family = "sdm",
    w_type = w_type,
    message = prep$message
  )

  impacts_res <- compute_spdm_impacts_row(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    focal_var = exposure,
    mod = prep$mod,
    lw_sub = prep$lw_sub,
    n_periods = prep$n_periods,
    n_units = prep$n_units,
    n_obs = prep$n_obs,
    sample_min_year = prep$sample_min_year,
    sample_max_year = prep$sample_max_year,
    model_family = "sdm",
    w_type = w_type,
    sim_R = impact_sim_R,
    sim_method = impact_sim_type,
    empirical = impact_empirical,
    seed = cfg$esda_seed,
    message = prep$message
  )

  controls_out <- build_spdm_control_rows(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    requested_controls = requested_controls,
    usable_controls = usable_controls,
    balanced_controls = prep$balanced_controls,
    selected_controls = prep$selected_controls,
    status = "success",
    message = prep$message,
    model_family = "sdm",
    w_type = w_type
  )

  spatial_param <- extract_spdm_spatial_param(prep$mod)
  fit_stats <- extract_spdm_fit_stats(prep$mod)
  wx_terms <- value_or(attr(prep$mod, "spdm_wx_terms", exact = TRUE), character())
  sdm_implementation <- value_or(attr(prep$mod, "spdm_implementation", exact = TRUE), NA_character_)
  impact_method <- if (nrow(impacts_res$row) > 0L) {
    value_or(impacts_res$row$sim_method[[1]], NA_character_)
  } else {
    NA_character_
  }
  diag_out <- build_spdm_diagnostics_row(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    model_family = "sdm",
    w_type = w_type,
    status = "success",
    n_units = prep$n_units,
    n_periods = prep$n_periods,
    n_obs = prep$n_obs,
    sample_min_year = prep$sample_min_year,
    sample_max_year = prep$sample_max_year,
    selected_controls = prep$selected_controls,
    spatial_lagged_terms = collapse_chr(wx_terms),
    n_wx_terms = length(wx_terms),
    sdm_implementation = sdm_implementation,
    impact_method = impact_method,
    spatial_param_name = spatial_param$spatial_param_name,
    spatial_param_estimate = spatial_param$spatial_param_estimate,
    spatial_param_se = spatial_param$spatial_param_se,
    spatial_param_p = spatial_param$spatial_param_p,
    logLik = fit_stats$logLik,
    AIC = fit_stats$AIC,
    BIC = fit_stats$BIC,
    impacts_status = impacts_res$status,
    message = impacts_res$message
  )

  list(
    coefs = coef_tbl,
    impacts = impacts_res$row,
    controls = controls_out,
    diagnostics = diag_out
  )
}


#==============================================================================
# 2. Run W Robustness Grid
#==============================================================================

if (length(outcomes) == 0L || length(exposures) == 0L) {
  finalized <- finalize_outputs(
    spdm_empty_coef_tbl(),
    spdm_empty_impacts_tbl(),
    spdm_empty_controls_tbl(),
    spdm_empty_diag_tbl()
  )
  write_csv_safe(finalized$coefs, cfg$paths$spdm_w_robustness_models)
  write_csv_safe(finalized$impacts, cfg$paths$spdm_w_robustness_impacts)
  write_csv_safe(finalized$controls, cfg$paths$spdm_w_robustness_controls)
  write_csv_safe(finalized$diagnostics, cfg$paths$spdm_w_robustness_diagnostics)
  append_log(cfg$logs$model_run, "- Skipped: missing SPDM W-robustness outcomes/exposures")
} else {
  spec_grid <- tidyr::crossing(w_type = w_types, outcome = outcomes, exposure = exposures) |>
    dplyr::left_join(outcome_registry, by = "outcome") |>
    dplyr::arrange(outcome_order, w_type, exposure) |>
    dplyr::mutate(spec_id = sprintf("W%02d", dplyr::row_number()))

  res <- purrr::pmap(
    list(spec_grid$spec_id, spec_grid$outcome, spec_grid$exposure, spec_grid$w_type),
    function(spec_id, outcome, exposure, w_type) {
      run_w_spec(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        w_type = w_type,
        panel = panel,
        requested_controls = control_contracts[[outcome]]$requested_controls,
        usable_controls = control_contracts[[outcome]]$usable_controls
      )
    }
  )

  finalized <- finalize_outputs(
    dplyr::bind_rows(purrr::map(res, "coefs")),
    dplyr::bind_rows(purrr::map(res, "impacts")),
    dplyr::bind_rows(purrr::map(res, "controls")),
    dplyr::bind_rows(purrr::map(res, "diagnostics"))
  )

  write_csv_safe(finalized$coefs, cfg$paths$spdm_w_robustness_models)
  write_csv_safe(finalized$impacts, cfg$paths$spdm_w_robustness_impacts)
  write_csv_safe(finalized$controls, cfg$paths$spdm_w_robustness_controls)
  write_csv_safe(finalized$diagnostics, cfg$paths$spdm_w_robustness_diagnostics)

  n_success <- sum(finalized$diagnostics$status == "success", na.rm = TRUE)
  n_fail <- sum(finalized$diagnostics$status != "success", na.rm = TRUE)
  append_log(
    cfg$logs$model_run,
    sprintf("- SPDM W robustness specs attempted: %d (success=%d, failed=%d)", nrow(spec_grid), n_success, n_fail)
  )
}
