#==============================================================================
# Script    : 05_run_spdm_family_comparison_sidecar.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Rebuild the main Queen SPDM sample/control contract and run the
#             appendix TWFE/SLX/SAR/SDM/SEM/SDEM/SARAR-SAC/GNS family
#             comparison on that fixed contract.
# Author    : Codex
# Created   : 2026-03-30
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, W_queen.rds, spdm_main_diagnostics.csv,
#             spdm_controls_used.csv
# Outputs   : spdm_family_models.csv, spdm_family_comparison.csv
# DependsOn : 01_build_spatial_weights.R, 02_run_spdm_main.R
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spdm.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 05_run_spdm_family_comparison_sidecar", timestamp()))


#==============================================================================
# 0. Helpers
#==============================================================================

family_order <- c("twfe_common", get_main_spatial_families())

build_family_impact_message <- function(family, base_message = NA_character_) {
  family <- normalize_spatial_family(family)
  notes <- stats::na.omit(c(
    if (is.na(base_message)) NA_character_ else as.character(base_message),
    if (identical(family, "sem")) {
      "impacts not applicable for SEM spatial-error-only family"
    } else if (family %in% c("slx", "sdem")) {
      "WX-only effects: direct=beta, indirect=theta, total=beta_plus_theta"
    } else if (identical(family, "gns")) {
      "GNS effects: Wy + WX + spatial error; impacts use SDM matrix mean-effect form"
    } else {
      NA_character_
    }
  ))
  if (length(notes) == 0L) return(NA_character_)
  paste(notes, collapse = " | ")
}

split_collapsed_controls <- function(x) {
  if (length(x) == 0L || all(is.na(x))) return(character())
  vals <- unlist(strsplit(as.character(x[[1]]), ";", fixed = TRUE), use.names = FALSE)
  vals <- trimws(vals)
  vals[!is.na(vals) & nzchar(vals)]
}

selected_controls_from_main_contract <- function(controls_tbl, spec_id) {
  rows <- controls_tbl |>
    dplyr::filter(spec_id == !!spec_id, selected %in% TRUE)
  if (nrow(rows) == 0L) return(character())
  rows |>
    dplyr::arrange(control_order) |>
    dplyr::pull(control_var) |>
    unique()
}

build_failed_family_model_row <- function(spec_id,
                                          outcome,
                                          exposure,
                                          family,
                                          n_units,
                                          n_periods,
                                          n_obs,
                                          sample_min_yq,
                                          sample_max_yq,
                                          w_type,
                                          message) {
  spdm_empty_coef_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      status = "failed",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
      model_family = family,
      w_type = w_type,
      message = as.character(message)
    )
}

build_failed_family_comparison_row <- function(spec_id,
                                               outcome,
                                               exposure,
                                               family,
                                               selected_controls,
                                               n_units,
                                               n_periods,
                                               n_obs,
                                               sample_min_yq,
                                               sample_max_yq,
                                               w_type,
                                               message,
                                               impacts_status = "failed") {
  build_spdm_family_comparison_row(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    family = family,
    w_type = w_type,
    status = "failed",
    impacts_status = impacts_status,
    n_units = n_units,
    n_periods = n_periods,
    n_obs = n_obs,
    sample_min_yq = sample_min_yq,
    sample_max_yq = sample_max_yq,
    selected_controls = selected_controls,
    focal_term = exposure,
    message = message
  )
}

finalize_family_outputs <- function(family_tbl, family_models_tbl) {
  list(
    family = family_tbl |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, exposure, spec_id, match(family, family_order)),
    family_models = family_models_tbl |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, exposure, spec_id, match(model_family, family_order), term)
  )
}

build_contract_fail_result <- function(spec_id,
                                       outcome,
                                       exposure,
                                       selected_controls,
                                       n_units = NA_integer_,
                                       n_periods = NA_integer_,
                                       n_obs = NA_integer_,
                                       sample_min_yq = NA_character_,
                                       sample_max_yq = NA_character_,
                                       message,
                                       w_type) {
  list(
    family = purrr::map_dfr(family_order, function(family) {
      build_failed_family_comparison_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        family = family,
        selected_controls = selected_controls,
        n_units = n_units,
        n_periods = n_periods,
        n_obs = n_obs,
        sample_min_yq = sample_min_yq,
        sample_max_yq = sample_max_yq,
        w_type = w_type,
        impacts_status = if (identical(family, "twfe_common")) "not_applicable" else "failed",
        message = message
      )
    }),
    family_models = purrr::map_dfr(family_order, function(family) {
      build_failed_family_model_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        family = family,
        n_units = n_units,
        n_periods = n_periods,
        n_obs = n_obs,
        sample_min_yq = sample_min_yq,
        sample_max_yq = sample_max_yq,
        w_type = w_type,
        message = message
      )
    })
  )
}


#==============================================================================
# 1. Load Main Contract
#==============================================================================

if (!file.exists(cfg$paths$panel_main) ||
    !file.exists(cfg$paths$w_queen) ||
    !file.exists(cfg$paths$spdm_main_diagnostics) ||
    !file.exists(cfg$paths$spdm_controls_used)) {
  stop("[ERROR] Missing panel, W, or main SPDM diagnostics/control outputs", call. = FALSE)
}

panel <- read_panel_main_view("spdm")
panel$adm_cd <- as.character(panel$adm_cd)

main_diag <- readr::read_csv(cfg$paths$spdm_main_diagnostics, show_col_types = FALSE) |>
  dplyr::mutate(
    spec_id = as.character(spec_id),
    outcome = as.character(outcome),
    exposure = as.character(exposure),
    model_family = as.character(model_family),
    w_type = as.character(w_type)
  ) |>
  dplyr::filter(model_family == "sdm")

main_controls <- readr::read_csv(cfg$paths$spdm_controls_used, show_col_types = FALSE) |>
  dplyr::mutate(
    spec_id = as.character(spec_id),
    outcome = as.character(outcome),
    exposure = as.character(exposure),
    model_family = as.character(model_family),
    w_type = as.character(w_type),
    control_var = as.character(control_var)
  )

assert_spdm_main_controls_current(
  main_controls,
  context = "05_run_spdm_family_comparison_sidecar",
  control_col = "control_var",
  selected_col = "selected"
)
assert_spdm_main_diagnostics_controls_current(
  main_diag,
  context = "05_run_spdm_family_comparison_sidecar"
)

if (nrow(main_diag) == 0L) {
  finalized <- finalize_family_outputs(spdm_empty_family_comparison_tbl(), spdm_empty_coef_tbl())
  write_csv_safe(finalized$family, cfg$paths$spdm_family_comparison)
  write_csv_safe(finalized$family_models, cfg$paths$spdm_family_models)
  append_log(cfg$logs$model_run, "- SPDM family comparison sidecar skipped: no main SPDM diagnostics rows")
} else {
  lw <- readRDS(cfg$paths$w_queen)
  w_ids <- as.character(attr(lw$neighbours, "region.id"))
  if (length(w_ids) == 0L || all(is.na(w_ids))) {
    stop("[ERROR] region.id missing in Queen W", call. = FALSE)
  }
  w_type_main <- as.character(value_or(cfg$default_w, "queen"))


#==============================================================================
# 2. Run Family Comparison on Main Contract
#==============================================================================

run_family_comparison_spec <- function(main_row) {
  family_out <- spdm_empty_family_comparison_tbl()
  family_models_out <- spdm_empty_coef_tbl()
  spec_id <- as.character(main_row$spec_id[[1]])
  outcome <- as.character(main_row$outcome[[1]])
  exposure <- as.character(main_row$exposure[[1]])
  selected_controls <- split_collapsed_controls(main_row$selected_controls)
  selected_controls_from_controls <- selected_controls_from_main_contract(main_controls, spec_id)

  if (length(selected_controls_from_controls) > 0L &&
      !identical(selected_controls_from_controls, selected_controls)) {
    failed <- build_contract_fail_result(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      selected_controls = selected_controls,
      n_units = main_row$n_units[[1]],
      n_periods = main_row$n_periods[[1]],
      n_obs = main_row$n_obs[[1]],
      sample_min_yq = main_row$sample_min_yq[[1]],
      sample_max_yq = main_row$sample_max_yq[[1]],
      message = "main SPDM control contract mismatch between diagnostics and controls output",
      w_type = w_type_main
    )
    family_out <- dplyr::bind_rows(family_out, failed$family)
    family_models_out <- dplyr::bind_rows(family_models_out, failed$family_models)
    return(list(family = family_out, family_models = family_models_out))
  }

  if (!identical(as.character(main_row$status[[1]]), "success")) {
    failed <- build_contract_fail_result(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      selected_controls = selected_controls,
      n_units = main_row$n_units[[1]],
      n_periods = main_row$n_periods[[1]],
      n_obs = main_row$n_obs[[1]],
      sample_min_yq = main_row$sample_min_yq[[1]],
      sample_max_yq = main_row$sample_max_yq[[1]],
      message = paste("main SPDM status:", main_row$status[[1]]),
      w_type = w_type_main
    )
    family_out <- dplyr::bind_rows(family_out, failed$family)
    family_models_out <- dplyr::bind_rows(family_models_out, failed$family_models)
    return(list(family = family_out, family_models = family_models_out))
  }

  prep <- rebuild_main_spdm_sample(
    panel = panel,
    outcome = outcome,
    exposure = exposure,
    selected_controls = selected_controls,
    lw = lw,
    w_ids = w_ids,
    expected_row = main_row,
    context_label = "family comparison sidecar"
  )
  if (!identical(prep$status, "success")) {
    failed <- build_contract_fail_result(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      selected_controls = selected_controls,
      n_units = main_row$n_units[[1]],
      n_periods = main_row$n_periods[[1]],
      n_obs = main_row$n_obs[[1]],
      sample_min_yq = main_row$sample_min_yq[[1]],
      sample_max_yq = main_row$sample_max_yq[[1]],
      message = prep$message,
      w_type = w_type_main
    )
    family_out <- dplyr::bind_rows(family_out, failed$family)
    family_models_out <- dplyr::bind_rows(family_models_out, failed$family_models)
    return(list(family = family_out, family_models = family_models_out))
  }

  twfe_fit <- fit_twfe_common_model(
    pdat = prep$data,
    outcome = outcome,
    exposure = exposure,
    controls = selected_controls
  )
  if (inherits(twfe_fit, "error") || is.null(twfe_fit)) {
    family_models_out <- dplyr::bind_rows(
      family_models_out,
      build_failed_family_model_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        family = "twfe_common",
        n_units = prep$n_units,
        n_periods = prep$n_periods,
        n_obs = prep$n_obs,
        sample_min_yq = prep$sample_min_yq,
        sample_max_yq = prep$sample_max_yq,
        w_type = w_type_main,
        message = if (inherits(twfe_fit, "error")) paste("common twfe error:", twfe_fit$message) else "common twfe unavailable"
      )
    )
    family_out <- dplyr::bind_rows(
      family_out,
      build_failed_family_comparison_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        family = "twfe_common",
        selected_controls = selected_controls,
        n_units = prep$n_units,
        n_periods = prep$n_periods,
        n_obs = prep$n_obs,
        sample_min_yq = prep$sample_min_yq,
        sample_max_yq = prep$sample_max_yq,
        w_type = w_type_main,
        impacts_status = "not_applicable",
        message = if (inherits(twfe_fit, "error")) paste("common twfe error:", twfe_fit$message) else "common twfe unavailable"
      )
    )
  } else {
    twfe_coef_tbl <- extract_twfe_common_coef_table(
      mod = twfe_fit,
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      n_units = prep$n_units,
      n_periods = prep$n_periods,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "twfe_common",
      w_type = w_type_main,
      message = prep$message
    )
    twfe_focal <- extract_focal_term_stats(twfe_coef_tbl, exposure)
    twfe_fit_stats <- extract_twfe_fit_stats(twfe_fit)
    twfe_impacts <- build_spdm_not_applicable_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = exposure,
      n_units = prep$n_units,
      n_periods = prep$n_periods,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "twfe_common",
      w_type = w_type_main,
      message = "impacts not applicable for TWFE"
    )
    family_models_out <- dplyr::bind_rows(family_models_out, twfe_coef_tbl)
    family_out <- dplyr::bind_rows(
      family_out,
      build_spdm_family_comparison_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        family = "twfe_common",
        w_type = w_type_main,
        status = "success",
        impacts_status = "not_applicable",
        n_units = prep$n_units,
        n_periods = prep$n_periods,
        n_obs = prep$n_obs,
        sample_min_yq = prep$sample_min_yq,
        sample_max_yq = prep$sample_max_yq,
        selected_controls = selected_controls,
        focal_term = twfe_focal$focal_term,
        focal_estimate = twfe_focal$focal_estimate,
        focal_se = twfe_focal$focal_se,
        focal_p = twfe_focal$focal_p,
        logLik = twfe_fit_stats$logLik,
        AIC = twfe_fit_stats$AIC,
        BIC = twfe_fit_stats$BIC,
        impacts_row = twfe_impacts,
        message = "impacts not applicable for TWFE"
      )
    )
  }

  for (family in get_main_spatial_families()) {
    mod <- fit_spdm_model(
      pdat = prep$data,
      outcome = outcome,
      exposure = exposure,
      controls = selected_controls,
      lw_sub = prep$lw_sub,
      model_family = family
    )

    if (inherits(mod, "error")) {
      family_models_out <- dplyr::bind_rows(
        family_models_out,
        build_failed_family_model_row(
          spec_id = spec_id,
          outcome = outcome,
          exposure = exposure,
          family = family,
          n_units = prep$n_units,
          n_periods = prep$n_periods,
          n_obs = prep$n_obs,
          sample_min_yq = prep$sample_min_yq,
          sample_max_yq = prep$sample_max_yq,
          w_type = w_type_main,
          message = paste("spml error:", mod$message)
        )
      )
      family_out <- dplyr::bind_rows(
        family_out,
        build_failed_family_comparison_row(
          spec_id = spec_id,
          outcome = outcome,
          exposure = exposure,
          family = family,
          selected_controls = selected_controls,
          n_units = prep$n_units,
          n_periods = prep$n_periods,
          n_obs = prep$n_obs,
          sample_min_yq = prep$sample_min_yq,
          sample_max_yq = prep$sample_max_yq,
          w_type = w_type_main,
          message = paste("spml error:", mod$message)
        )
      )
      next
    }

    coef_tbl <- if (identical(family, "slx")) {
      extract_twfe_common_coef_table(
        mod = mod,
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        n_units = prep$n_units,
        n_periods = prep$n_periods,
        n_obs = prep$n_obs,
        sample_min_yq = prep$sample_min_yq,
        sample_max_yq = prep$sample_max_yq,
        model_family = family,
        w_type = w_type_main,
        message = prep$message
      )
    } else {
      extract_spdm_coef_table(
        mod = mod,
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        n_units = prep$n_units,
        n_periods = prep$n_periods,
        n_obs = prep$n_obs,
        sample_min_yq = prep$sample_min_yq,
        sample_max_yq = prep$sample_max_yq,
        model_family = family,
        w_type = w_type_main,
        message = prep$message
      )
    }
    impacts_message <- build_family_impact_message(family, prep$message)
    impacts_res <- compute_spdm_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = exposure,
      mod = mod,
      lw_sub = prep$lw_sub,
      n_periods = prep$n_periods,
      n_units = prep$n_units,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = family,
      w_type = w_type_main,
      sim_R = as.integer(value_or(cfg$spdm_impact_sim_R, 1000L)),
      sim_method = as.character(value_or(cfg$spdm_impact_sim_type, "mult")),
      empirical = isTRUE(value_or(cfg$spdm_impact_empirical, FALSE)),
      seed = cfg$esda_seed,
      message = impacts_message
    )
    spatial_param <- extract_spdm_spatial_param(mod)
    fit_stats <- extract_spdm_fit_stats(mod)
    focal_stats <- extract_focal_term_stats(coef_tbl, exposure)

    family_models_out <- dplyr::bind_rows(family_models_out, coef_tbl)
    family_out <- dplyr::bind_rows(
      family_out,
      build_spdm_family_comparison_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        family = family,
        w_type = w_type_main,
        status = "success",
        impacts_status = impacts_res$status,
        n_units = prep$n_units,
        n_periods = prep$n_periods,
        n_obs = prep$n_obs,
        sample_min_yq = prep$sample_min_yq,
        sample_max_yq = prep$sample_max_yq,
        selected_controls = selected_controls,
        focal_term = focal_stats$focal_term,
        focal_estimate = focal_stats$focal_estimate,
        focal_se = focal_stats$focal_se,
        focal_p = focal_stats$focal_p,
        lag_param_name = spatial_param$lag_param_name,
        lag_param_estimate = spatial_param$lag_param_estimate,
        lag_param_se = spatial_param$lag_param_se,
        lag_param_p = spatial_param$lag_param_p,
        error_param_name = spatial_param$error_param_name,
        error_param_estimate = spatial_param$error_param_estimate,
        error_param_se = spatial_param$error_param_se,
        error_param_p = spatial_param$error_param_p,
        spatial_param_estimate = spatial_param$spatial_param_estimate,
        spatial_param_p = spatial_param$spatial_param_p,
        logLik = fit_stats$logLik,
        AIC = fit_stats$AIC,
        BIC = fit_stats$BIC,
        impacts_row = impacts_res$row,
        message = impacts_res$message
      )
    )
  }
  list(family = family_out, family_models = family_models_out)
}

  family_results <- run_spdm_optional_spec_jobs(
    split(main_diag, seq_len(nrow(main_diag))),
    run_family_comparison_spec,
    label = "SPDM family-comparison specs"
  )
  family_out <- dplyr::bind_rows(purrr::map(family_results, "family"))
  family_models_out <- dplyr::bind_rows(purrr::map(family_results, "family_models"))

  finalized <- finalize_family_outputs(family_out, family_models_out)
  write_csv_safe(finalized$family, cfg$paths$spdm_family_comparison)
  write_csv_safe(finalized$family_models, cfg$paths$spdm_family_models)

  append_log(
    cfg$logs$model_run,
    sprintf(
      "- SPDM family comparison sidecar completed: %d family rows, %d coefficient rows",
      nrow(finalized$family),
      nrow(finalized$family_models)
    )
  )
}
