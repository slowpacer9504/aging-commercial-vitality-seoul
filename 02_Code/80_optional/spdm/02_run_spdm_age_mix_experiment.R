#==============================================================================
# Script    : 02_run_spdm_age_mix_experiment.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run an appendix SPDM sidecar that replaces the resident-only
#             age60 exposure with domain-specific age-mix share vectors for
#             resident and floating populations.
# Author    : Codex
# Created   : 2026-03-30
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, registered_resident_population.parquet,
#             seoul_raw_integrated_wide.parquet, W_queen.rds
# Outputs   : spdm_age_mix_experiment_models.csv,
#             spdm_age_mix_experiment_impacts.csv,
#             spdm_age_mix_experiment_controls_used.csv,
#             spdm_age_mix_experiment_diagnostics.csv
# DependsOn : 02_build_seoul_quarter_base.R,
#             05_build_registered_resident_population.R,
#             01_build_spatial_weights.R, 02_run_spdm_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spdm.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
source(here::here("02_Code", "R", "utils_age_mix.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 02_run_spdm_age_mix_experiment", timestamp()))

{

if (!file.exists(cfg$paths$panel_main) ||
    !file.exists(cfg$paths$registered_resident_population) ||
    !file.exists(cfg$paths$seoul_raw_integrated_wide) ||
    !file.exists(cfg$paths$w_queen)) {
  stop("[ERROR] Required inputs for SPDM age-mix experiment missing", call. = FALSE)
}


summarize_family_qc <- function(panel_family, domain, model_family, same_domain_total_control) {
  share_cols <- sprintf("%s_%s_share", c("age20", "age30", "age40", "age50", "age60plus"), domain)

  share_mat <- as.matrix(panel_family[, intersect(share_cols, names(panel_family)), drop = FALSE])
  share_complete <- if (ncol(share_mat) == 0L) rep(FALSE, nrow(panel_family)) else apply(share_mat, 1L, function(x) all(is.finite(x)))
  share_dev <- if (any(share_complete)) {
    abs(rowSums(share_mat[share_complete, , drop = FALSE]) - 1)
  } else {
    numeric(0)
  }

  finite_counts <- setNames(
    as.list(vapply(share_cols, function(v) sum(is.finite(panel_family[[v]])), integer(1))),
    paste0("finite_n__", share_cols)
  )

  tibble::tibble(
    model_family = model_family,
    domain = domain,
    exposure_scale = "share",
    omitted_reference = "age60plus",
    reference_population = "age20_to_60plus",
    same_domain_total_control = same_domain_total_control,
    share_sum_mean_abs_dev = if (length(share_dev) > 0L) mean(share_dev) else NA_real_,
    share_sum_max_abs_dev = if (length(share_dev) > 0L) max(share_dev) else NA_real_
  ) |>
    dplyr::bind_cols(tibble::as_tibble(finite_counts))
}

build_model_name <- function(model_family, outcome) {
  paste(model_family, outcome, "sdm", sep = "__")
}

same_control_retained <- function(selected_controls, target_control) {
  if (is.na(target_control) || !nzchar(target_control)) return(FALSE)
  if (is.na(selected_controls) || !nzchar(selected_controls)) return(FALSE)
  target_control %in% strsplit(as.character(selected_controls), ";", fixed = TRUE)[[1]]
}

compute_impacts_status <- function(impacts_tbl) {
  if (nrow(impacts_tbl) == 0L || !"status" %in% names(impacts_tbl)) return("failed")
  sts <- unique(stats::na.omit(as.character(impacts_tbl$status)))
  if (length(sts) == 0L) return("failed")
  if (identical(sort(sts), "success")) return("success")
  if (any(sts == "success")) return("partial_failed")
  sts[[1]]
}


#==============================================================================
# 2. Resolve Inputs and Build Domain-Specific Age-Mix Panels
#==============================================================================

panel <- read_panel_main_view("spdm")
panel$adm_cd <- as.character(panel$adm_cd)

outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = value_or(cfg$spdm_age_mix_outcomes, cfg$spdm_main_outcomes),
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome

if (length(outcomes) == 0L) {
  stop("[ERROR] No valid outcomes for SPDM age-mix experiment", call. = FALSE)
}

control_candidates <- spdm_main_control_candidate_cols()
assert_spdm_main_controls_current(
  tibble::tibble(control = control_candidates, selected = TRUE),
  context = "02_run_spdm_age_mix_experiment",
  control_col = "control",
  selected_col = "selected"
)

family_registry <- resolve_age_mix_family_registry(c("resident", "floating"))

family_panels <- list()
family_qc <- vector("list", nrow(family_registry))

for (ii in seq_len(nrow(family_registry))) {
  family_rec <- family_registry[ii, ]
  domain_df <- build_domain_age_shares(
    source_value = family_rec$source_type[[1]],
    domain = family_rec$domain[[1]],
    quarterly_step = family_rec$quarterly_step[[1]],
    raw_cols = family_rec$raw_cols[[1]],
    asof_col = family_rec$asof_col[[1]]
  )
  family_panel <- add_current_age_shares(panel, domain_df, family_rec$domain[[1]])

  family_panels[[family_rec$model_family[[1]]]] <- family_panel
  family_qc[[ii]] <- summarize_family_qc(
    family_panel,
    domain = family_rec$domain[[1]],
    model_family = family_rec$model_family[[1]],
    same_domain_total_control = family_rec$same_domain_total_control[[1]]
  )
}
family_qc <- dplyr::bind_rows(family_qc)

family_contracts <- tidyr::crossing(
  family_registry |>
    dplyr::mutate(
      requested_controls_list = purrr::map(
        same_domain_total_control,
        ~ c(.x, setdiff(control_candidates, .x))
      )
    ) |>
    dplyr::select(
      model_family,
      domain,
      exposure_vars,
      requested_exposures,
      omitted_reference_var,
      same_domain_total_control,
      requested_controls_list
    ),
  outcome = outcomes
) |>
  dplyr::left_join(outcome_registry, by = "outcome") |>
  dplyr::mutate(
    control_screen = purrr::pmap(
      list(model_family, outcome, requested_controls_list),
      function(model_family, outcome, requested_controls_list) {
        select_outcome_controls_with_details(
          family_panels[[model_family]],
          outcome = outcome,
          candidates = requested_controls_list,
          min_finite = 500L
        )
      }
    ),
    usable_controls_list = purrr::map(
      control_screen,
      ~ .x |>
        dplyr::filter(selected) |>
        dplyr::pull(control)
    ),
    requested_controls = purrr::map_chr(requested_controls_list, collapse_chr),
    usable_controls = purrr::map_chr(usable_controls_list, collapse_chr)
  )

family_overlap_meta <- purrr::map2_dfr(
  family_contracts$outcome,
  family_contracts$exposure_vars,
  ~ resolve_floating_overlap_spec_meta(.x, .y) |>
    dplyr::select(skip_reason, skip_message, skip_spec)
)

family_contracts <- dplyr::bind_cols(
  family_contracts,
  family_overlap_meta
)

spec_registry <- family_contracts |>
  dplyr::left_join(
    family_qc,
    by = c("model_family", "domain", "same_domain_total_control")
  ) |>
  dplyr::mutate(
    model_name = build_model_name(model_family, outcome),
    spec_id = sprintf("S%02d", dplyr::row_number())
  ) |>
  dplyr::arrange(outcome_order, model_family)


#==============================================================================
# 3. Estimate Domain-Specific Age-Mix SPDM Models
#==============================================================================

lw <- readRDS(cfg$paths$w_queen)
w_ids <- attr(lw$neighbours, "region.id")
if (is.null(w_ids)) {
  stop("[ERROR] region.id missing in W_queen", call. = FALSE)
}
w_ids <- as.character(w_ids)

run_one_spec <- function(spec_row) {
  family_panel <- family_panels[[spec_row$model_family[[1]]]]
  exposure_vars <- spec_row$exposure_vars[[1]]
  exposure_label <- spec_row$requested_exposures[[1]]
  requested_controls <- spec_row$requested_controls_list[[1]]
  usable_controls <- spec_row$usable_controls_list[[1]]

  if (isTRUE(spec_row$skip_spec[[1]])) {
    skip_message <- spec_row$skip_message[[1]]

    skipped_coefs <- spdm_empty_coef_tbl() |>
      dplyr::add_row(
        spec_id = spec_row$spec_id[[1]],
        outcome = spec_row$outcome[[1]],
        exposure = exposure_label,
        term = NA_character_,
        status = "not_estimated",
        model_family = "sdm",
        w_type = "queen",
        message = skip_message
      )

    skipped_impacts <- dplyr::bind_rows(lapply(exposure_vars, function(focal_var) {
      spdm_empty_impacts_tbl() |>
        dplyr::add_row(
          spec_id = spec_row$spec_id[[1]],
          outcome = spec_row$outcome[[1]],
          exposure = exposure_label,
          focal_var = focal_var,
          status = "not_estimated",
          model_family = "sdm",
          w_type = "queen",
          sim_R = as.integer(value_or(cfg$spdm_impact_sim_R, 1000L)),
          sim_method = as.character(value_or(cfg$spdm_impact_sim_type, "mult")),
          message = skip_message
        )
    }))

    skipped_controls <- build_spdm_control_rows(
      spec_id = spec_row$spec_id[[1]],
      outcome = spec_row$outcome[[1]],
      exposure = exposure_label,
      requested_controls = requested_controls,
      usable_controls = usable_controls,
      balanced_controls = character(),
      selected_controls = character(),
      status = "not_estimated",
      message = skip_message,
      model_family = "sdm",
      w_type = "queen"
    )

    skipped_diag <- build_spdm_diagnostics_row(
      spec_id = spec_row$spec_id[[1]],
      outcome = spec_row$outcome[[1]],
      exposure = exposure_label,
      model_family = "sdm",
      w_type = "queen",
      status = "not_estimated",
      n_units = NA_integer_,
      n_periods = NA_integer_,
      n_obs = NA_integer_,
      sample_min_yq = NA_character_,
      sample_max_yq = NA_character_,
      selected_controls = character(),
      impacts_status = "not_estimated",
      message = skip_message
    )

    return(list(
      coefs = skipped_coefs,
      impacts = skipped_impacts,
      controls = skipped_controls,
      diagnostics = skipped_diag
    ))
  }

  prep <- prepare_spdm_spec(
    panel = family_panel,
    outcome = spec_row$outcome[[1]],
    exposure = exposure_vars,
    lw = lw,
    w_ids = w_ids,
    requested_controls = requested_controls,
    usable_controls = usable_controls,
    model_family = "sdm"
  )

  if (!identical(prep$status, "success") || is.null(prep$mod)) {
    failed_coefs <- spdm_empty_coef_tbl() |>
      dplyr::add_row(
        spec_id = spec_row$spec_id[[1]],
        outcome = spec_row$outcome[[1]],
        exposure = exposure_label,
        status = "failed",
        model_family = "sdm",
        w_type = "queen",
        message = prep$message
      )

    failed_impacts <- dplyr::bind_rows(lapply(exposure_vars, function(focal_var) {
      spdm_empty_impacts_tbl() |>
        dplyr::add_row(
          spec_id = spec_row$spec_id[[1]],
          outcome = spec_row$outcome[[1]],
          exposure = exposure_label,
          focal_var = focal_var,
          status = "failed",
          model_family = "sdm",
          w_type = "queen",
          sim_R = as.integer(value_or(cfg$spdm_impact_sim_R, 1000L)),
          sim_method = as.character(value_or(cfg$spdm_impact_sim_type, "mult")),
          message = prep$message
        )
    }))

    failed_controls <- build_spdm_control_rows(
      spec_id = spec_row$spec_id[[1]],
      outcome = spec_row$outcome[[1]],
      exposure = exposure_label,
      requested_controls = requested_controls,
      usable_controls = usable_controls,
      balanced_controls = prep$balanced_controls,
      selected_controls = prep$selected_controls,
      status = "failed",
      message = prep$message,
      model_family = "sdm",
      w_type = "queen"
    )

    failed_diag <- build_spdm_diagnostics_row(
      spec_id = spec_row$spec_id[[1]],
      outcome = spec_row$outcome[[1]],
      exposure = exposure_label,
      model_family = "sdm",
      w_type = "queen",
      status = "failed",
      n_units = prep$n_units,
      n_periods = prep$n_periods,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      selected_controls = prep$selected_controls,
      impacts_status = "failed",
      message = prep$message
    )

    return(list(
      coefs = failed_coefs,
      impacts = failed_impacts,
      controls = failed_controls,
      diagnostics = failed_diag
    ))
  }

  coef_tbl <- extract_spdm_coef_table(
    mod = prep$mod,
    spec_id = spec_row$spec_id[[1]],
    outcome = spec_row$outcome[[1]],
    exposure = exposure_label,
    n_units = prep$n_units,
    n_periods = prep$n_periods,
    n_obs = prep$n_obs,
    sample_min_yq = prep$sample_min_yq,
    sample_max_yq = prep$sample_max_yq,
    model_family = "sdm",
    w_type = "queen",
    message = prep$message
  )

  impact_tbl <- dplyr::bind_rows(lapply(exposure_vars, function(focal_var) {
    compute_spdm_impacts_row(
      spec_id = spec_row$spec_id[[1]],
      outcome = spec_row$outcome[[1]],
      exposure = exposure_label,
      focal_var = focal_var,
      mod = prep$mod,
      lw_sub = prep$lw_sub,
      n_periods = prep$n_periods,
      n_units = prep$n_units,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "sdm",
      w_type = "queen",
      sim_R = as.integer(value_or(cfg$spdm_impact_sim_R, 1000L)),
      sim_method = as.character(value_or(cfg$spdm_impact_sim_type, "mult")),
      empirical = isTRUE(value_or(cfg$spdm_impact_empirical, FALSE)),
      message = prep$message
    )$row
  }))

  controls_tbl <- build_spdm_control_rows(
    spec_id = spec_row$spec_id[[1]],
    outcome = spec_row$outcome[[1]],
    exposure = exposure_label,
    requested_controls = requested_controls,
    usable_controls = usable_controls,
    balanced_controls = prep$balanced_controls,
    selected_controls = prep$selected_controls,
    status = "success",
    message = prep$message,
    model_family = "sdm",
    w_type = "queen"
  )

  spatial_param <- extract_spdm_spatial_param(prep$mod)
  fit_stats <- extract_spdm_fit_stats(prep$mod)
  diag_tbl <- build_spdm_diagnostics_row(
    spec_id = spec_row$spec_id[[1]],
    outcome = spec_row$outcome[[1]],
    exposure = exposure_label,
    model_family = "sdm",
    w_type = "queen",
    status = "success",
    n_units = prep$n_units,
    n_periods = prep$n_periods,
    n_obs = prep$n_obs,
    sample_min_yq = prep$sample_min_yq,
    sample_max_yq = prep$sample_max_yq,
    selected_controls = prep$selected_controls,
    spatial_param_name = spatial_param$spatial_param_name,
    spatial_param_estimate = spatial_param$spatial_param_estimate,
    spatial_param_se = spatial_param$spatial_param_se,
    spatial_param_p = spatial_param$spatial_param_p,
    logLik = fit_stats$logLik,
    AIC = fit_stats$AIC,
    BIC = fit_stats$BIC,
    impacts_status = compute_impacts_status(impact_tbl),
    message = prep$message
  )

  list(
    coefs = coef_tbl,
    impacts = impact_tbl,
    controls = controls_tbl,
    diagnostics = diag_tbl
  )
}

results <- purrr::map(split(spec_registry, spec_registry$spec_id), run_one_spec)

spec_meta <- spec_registry |>
  dplyr::transmute(
    spec_id,
    model_name,
    age_mix_family = model_family,
    domain,
    requested_exposures,
    exposure_scale,
    omitted_reference,
    reference_population,
    same_domain_total_control,
    share_sum_mean_abs_dev,
    share_sum_max_abs_dev,
    dplyr::pick(dplyr::starts_with("finite_n__")),
    outcome_group,
    outcome_order
  )

diagnostics_tbl <- dplyr::bind_rows(purrr::map(results, "diagnostics")) |>
  dplyr::left_join(spec_meta, by = "spec_id") |>
  dplyr::mutate(
    same_domain_total_control_dropped = !mapply(same_control_retained, selected_controls, same_domain_total_control)
  ) |>
  dplyr::select(
    spec_id, model_name, model_family_spdm = model_family, age_mix_family, domain, outcome, outcome_group, outcome_order,
    exposure, requested_exposures, exposure_scale, omitted_reference, reference_population,
    same_domain_total_control, same_domain_total_control_dropped,
    status, n_units, n_periods, n_obs, sample_min_yq, sample_max_yq,
    selected_controls, spatial_param_name, spatial_param_estimate, spatial_param_se, spatial_param_p,
    logLik, AIC, BIC, impacts_status,
    share_sum_mean_abs_dev, share_sum_max_abs_dev, dplyr::starts_with("finite_n__"),
    message
  ) |>
  dplyr::arrange(outcome_order, age_mix_family, spec_id)

diag_drop_meta <- diagnostics_tbl |>
  dplyr::select(spec_id, same_domain_total_control_dropped)

models_tbl <- dplyr::bind_rows(purrr::map(results, "coefs")) |>
  dplyr::left_join(spec_meta, by = "spec_id") |>
  dplyr::left_join(diag_drop_meta, by = "spec_id") |>
  dplyr::select(
    spec_id, model_name, model_family_spdm = model_family, age_mix_family, domain, outcome, outcome_group, outcome_order,
    exposure, requested_exposures, term, estimate, std.error, statistic, p.value,
    status, n_units, n_periods, n_obs, sample_min_yq, sample_max_yq,
    exposure_scale, omitted_reference, reference_population,
    same_domain_total_control, same_domain_total_control_dropped,
    share_sum_mean_abs_dev, share_sum_max_abs_dev, message
  ) |>
  dplyr::arrange(outcome_order, age_mix_family, spec_id, term)

impacts_tbl <- dplyr::bind_rows(purrr::map(results, "impacts")) |>
  dplyr::left_join(spec_meta, by = "spec_id") |>
  dplyr::left_join(diag_drop_meta, by = "spec_id") |>
  dplyr::select(
    spec_id, model_name, model_family_spdm = model_family, age_mix_family, domain, outcome, outcome_group, outcome_order,
    exposure, requested_exposures, focal_var,
    direct, direct_se, direct_z, direct_p, direct_ci_low, direct_ci_high,
    indirect, indirect_se, indirect_z, indirect_p, indirect_ci_low, indirect_ci_high,
    total, total_se, total_z, total_p, total_ci_low, total_ci_high,
    status, n_units, n_periods, n_obs, sample_min_yq, sample_max_yq,
    exposure_scale, omitted_reference, reference_population,
    same_domain_total_control, same_domain_total_control_dropped,
    sim_R, sim_method, share_sum_mean_abs_dev, share_sum_max_abs_dev, message
  ) |>
  dplyr::arrange(outcome_order, age_mix_family, spec_id, focal_var)

controls_tbl <- dplyr::bind_rows(purrr::map(results, "controls")) |>
  dplyr::left_join(spec_meta, by = "spec_id") |>
  dplyr::left_join(diag_drop_meta, by = "spec_id") |>
  dplyr::select(
    spec_id, model_name, model_family_spdm = model_family, age_mix_family, domain, outcome, outcome_group, outcome_order,
    exposure, requested_exposures, control_var, control_order,
    requested, usable, balanced_candidate, selected,
    exposure_scale, omitted_reference, reference_population,
    same_domain_total_control, same_domain_total_control_dropped,
    status, w_type, share_sum_mean_abs_dev, share_sum_max_abs_dev, message
  ) |>
  dplyr::arrange(outcome_order, age_mix_family, spec_id, control_order)

write_csv_safe(models_tbl, cfg$paths$spdm_age_mix_experiment_models)
write_csv_safe(impacts_tbl, cfg$paths$spdm_age_mix_experiment_impacts)
write_csv_safe(controls_tbl, cfg$paths$spdm_age_mix_experiment_controls_used)
write_csv_safe(diagnostics_tbl, cfg$paths$spdm_age_mix_experiment_diagnostics)

append_log(
  cfg$logs$model_run,
  sprintf(
    "- SPDM age-mix specs attempted: %d (success=%d, skipped=%d, failed=%d)",
    nrow(spec_registry),
    sum(diagnostics_tbl$status == "success", na.rm = TRUE),
    sum(diagnostics_tbl$status == "not_estimated", na.rm = TRUE),
    sum(!diagnostics_tbl$status %in% c("success", "not_estimated"), na.rm = TRUE)
  )
)

}
