#==============================================================================
# Script    : 03_run_twfe_age_mix_experiment.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run an appendix TWFE sidecar that replaces the resident-only
#             age60 exposure with grouped resident age-population vectors.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-03-29
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : panel_modeling
# Inputs    : panel_main.parquet, registered_resident_population.parquet
# Outputs   : twfe_age_mix_experiment_models.csv,
#             twfe_age_mix_experiment_controls_used.csv,
#             twfe_age_mix_experiment_diagnostics.csv
# DependsOn : 02_Code/01_preprocess/02_build_seoul_quarter_base.R,
#             02_Code/01_preprocess/05_build_registered_resident_population.R,
#             02_Code/01_preprocess/07_build_vitality_index.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# This appendix sidecar does not replace the main TWFE specification. It keeps
# `panel_main` unchanged and compares youth, middle-age, and older resident log
# population stocks from the registered-resident source.
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
source(here::here("02_Code", "99_utils", "utils_model.R"))
source(here::here("02_Code", "99_utils", "utils_qc.R"))
source(here::here("02_Code", "99_utils", "utils_age_mix.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 03_run_twfe_age_mix_experiment", timestamp()))

{

if (!file.exists(cfg$paths$panel_main) ||
    !file.exists(cfg$paths$registered_resident_population)) {
  stop("[ERROR] Required inputs for TWFE age-mix experiment missing", call. = FALSE)
}

panel <- read_panel_main_view("twfe")


summarize_family_qc <- function(panel_family, family_rec) {
  domain <- family_rec$domain[[1]]
  model_family <- family_rec$model_family[[1]]
  same_domain_total_control <- family_rec$same_domain_total_control[[1]]
  composition_cols <- family_rec$share_cols[[1]]
  diagnostic_cols <- unique(c(family_rec$exposure_vars[[1]], composition_cols))

  share_mat <- as.matrix(panel_family[, intersect(composition_cols, names(panel_family)), drop = FALSE])
  share_complete <- if (ncol(share_mat) == 0L) rep(FALSE, nrow(panel_family)) else apply(share_mat, 1L, function(x) all(is.finite(x)))
  share_dev <- if (any(share_complete)) {
    abs(rowSums(share_mat[share_complete, , drop = FALSE]) - 1)
  } else {
    numeric(0)
  }

  finite_counts <- setNames(
    as.list(vapply(diagnostic_cols, function(v) sum(is.finite(panel_family[[v]])), integer(1))),
    paste0("finite_n__", diagnostic_cols)
  )

  tibble::tibble(
    model_family = model_family,
    domain = domain,
    exposure_scale = family_rec$exposure_scale[[1]],
    omitted_reference = family_rec$omitted_reference[[1]],
    reference_population = family_rec$reference_population[[1]],
    same_domain_total_control = same_domain_total_control,
    same_domain_total_control_dropped = FALSE,
    share_sum_mean_abs_dev = if (length(share_dev) > 0L) mean(share_dev) else NA_real_,
    share_sum_max_abs_dev = if (length(share_dev) > 0L) max(share_dev) else NA_real_
  ) |>
    dplyr::bind_cols(tibble::as_tibble(finite_counts))
}

build_model_name <- function(model_family, outcome) {
  paste(model_family, outcome, "m2", sep = "__")
}


#==============================================================================
# 2. Resolve Inputs and Build Domain-Specific Age-Mix Panels
#==============================================================================

# Use all grouped resident log-population exposures together while retaining the
# lagged total resident scale control from the main TWFE contract.
outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = value_or(cfg$twfe_age_mix_outcomes, cfg$twfe_main_outcomes),
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome

family_registry <- resolve_age_mix_family_registry("resident", exposure_mode = "resident_log_population")

main_control_contract <- load_twfe_main_control_contracts(outcomes)
assert_twfe_main_controls_current(main_control_contract$screen, context = "03_run_twfe_age_mix_experiment")
main_ctrl_screen <- main_control_contract$screen |>
  dplyr::mutate(control_source = "twfe_main_controls_used")
main_control_contracts <- main_control_contract$contracts
main_controls_by_outcome <- stats::setNames(
  lapply(main_control_contracts, `[[`, "usable_controls"),
  names(main_control_contracts)
)

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
  family_qc[[ii]] <- summarize_family_qc(family_panel, family_rec)
}
family_qc <- dplyr::bind_rows(family_qc)

if (length(outcomes) == 0L) {
  stop("[ERROR] No valid outcomes for TWFE age-mix experiment", call. = FALSE)
}

family_contracts <- tidyr::crossing(
  family_registry |>
    dplyr::select(
      model_family,
      domain,
      exposure_vars,
      omitted_reference_var,
      requested_exposures,
      same_domain_total_control
    ),
  outcome = outcomes
) |>
  dplyr::left_join(outcome_registry, by = "outcome") |>
  dplyr::mutate(
    requested_controls_list = purrr::map(
      outcome,
      function(outcome) {
        inherited <- unique(as.character(value_or(main_controls_by_outcome[[outcome]], character())))
        inherited <- inherited[!is.na(inherited) & nzchar(inherited)]
        inherited
      }
    ),
    control_screen = purrr::map(
      outcome,
      function(outcome_nm) {
        main_ctrl_screen |>
          dplyr::filter(.data$outcome == .env$outcome_nm) |>
          dplyr::select(-dplyr::any_of("outcome"))
      }
    ),
    selected_controls = requested_controls_list,
    requested_controls = purrr::map_chr(requested_controls_list, collapse_chr),
    selected_controls_chr = purrr::map_chr(selected_controls, collapse_chr)
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
) |>
  dplyr::mutate(
    same_domain_total_control_dropped = !purrr::map2_lgl(
      same_domain_total_control,
      selected_controls,
      ~ {
        control_nm <- unique(as.character(value_or(.x, character())))
        control_nm <- control_nm[!is.na(control_nm) & nzchar(control_nm)]
        # No requested same-domain total control means nothing was dropped.
        if (length(control_nm) == 0L) return(TRUE)
        all(control_nm %in% .y)
      }
    )
  )

control_screen_expanded <- family_contracts |>
  dplyr::select(
    model_family,
    domain,
    same_domain_total_control,
    outcome,
    outcome_group,
    outcome_order,
    skip_spec,
    skip_reason,
    skip_message,
    control_screen
  ) |>
  tidyr::unnest(control_screen) |>
  dplyr::rename(control_var = control, selected_main = selected, control_reason = reason) |>
  dplyr::mutate(
    selected = selected_main,
    spec_status = dplyr::if_else(skip_spec, "not_estimated", "success"),
    spec_reason = skip_reason,
    spec_message = skip_message
  ) |>
  dplyr::select(
    model_family, domain, same_domain_total_control, outcome, outcome_group, outcome_order,
    control_var, selected, control_reason, spec_status, spec_reason, spec_message, dplyr::everything()
  ) |>
  dplyr::arrange(outcome_order, model_family, control_var)
write_csv_safe(control_screen_expanded, cfg$paths$twfe_age_mix_experiment_controls_used)


#==============================================================================
# 3. Estimate Domain-Specific M2 Models
#==============================================================================

# Estimate domain-specific M2 models with the grouped resident log-population
# exposures and the lagged resident scale control.
spec_registry <- family_contracts |>
  dplyr::left_join(
    family_qc |>
      dplyr::select(-same_domain_total_control_dropped),
    by = c("model_family", "domain", "same_domain_total_control")
  ) |>
  dplyr::mutate(
    spec = "m2",
    model_name = build_model_name(model_family, outcome)
  ) |>
  dplyr::arrange(outcome_order, model_family)

mods <- list()
for (ii in seq_len(nrow(spec_registry))) {
  spec_row <- spec_registry[ii, ]
  if (isTRUE(spec_row$skip_spec[[1]])) {
    next
  }

  fit <- run_twfe_multi(
    family_panels[[spec_row$model_family[[1]]]],
    outcome = spec_row$outcome[[1]],
    exposures = spec_row$exposure_vars[[1]],
    controls = spec_row$selected_controls[[1]]
  )
  if (!is.null(fit)) {
    mods[[spec_row$model_name[[1]]]] <- fit
  }
}

age_mix_success <- if (length(mods) == 0L) {
  tibble::tibble()
} else {
  tidy_models(mods) |>
    dplyr::mutate(status = "success", message = NA_character_)
}

failed_specs <- spec_registry |>
  dplyr::filter(!skip_spec & !model_name %in% names(mods))

age_mix_placeholders <- dplyr::bind_rows(
  spec_registry |>
    dplyr::filter(skip_spec) |>
    dplyr::transmute(
      model_name,
      outcome,
      exposure = requested_exposures,
      nobs = NA_integer_,
      initial_nobs = NA_integer_,
      requested_controls,
      retained_controls = selected_controls_chr,
      dropped_collinear_controls = NA_character_,
      dropped_collinear_terms = NA_character_,
      interaction_var = NA_character_,
      term = NA_character_,
      estimate = NA_real_,
      std.error = NA_real_,
      statistic = NA_real_,
      p.value = NA_real_,
      status = "not_estimated",
      message = skip_message
    ),
  failed_specs |>
    dplyr::transmute(
      model_name,
      outcome,
      exposure = requested_exposures,
      nobs = NA_integer_,
      initial_nobs = NA_integer_,
      requested_controls,
      retained_controls = selected_controls_chr,
      dropped_collinear_controls = NA_character_,
      dropped_collinear_terms = NA_character_,
      interaction_var = NA_character_,
      term = NA_character_,
      estimate = NA_real_,
      std.error = NA_real_,
      statistic = NA_real_,
      p.value = NA_real_,
      status = "failed",
      message = "estimation returned NULL"
    )
)

age_mix_tidy <- dplyr::bind_rows(age_mix_success, age_mix_placeholders) |>
  dplyr::left_join(
    spec_registry |>
      dplyr::select(
        model_name,
        model_family,
        domain,
        requested_exposures,
        exposure_scale,
        omitted_reference,
        reference_population,
        same_domain_total_control,
        same_domain_total_control_dropped,
        share_sum_mean_abs_dev,
        share_sum_max_abs_dev
      ),
    by = "model_name"
  ) |>
  annotate_outcomes(include_robustness = FALSE) |>
  dplyr::arrange(outcome_order, model_family, model_name, term)
write_csv_safe(age_mix_tidy, cfg$paths$twfe_age_mix_experiment_models)

model_diag_success <- summarize_model_diagnostics(mods)
model_diag <- spec_registry |>
  dplyr::left_join(model_diag_success, by = "model_name", suffix = c("_expected", "")) |>
  dplyr::transmute(
    model_name,
    model_family,
    domain,
    outcome = dplyr::coalesce(outcome, outcome_expected),
    outcome_group,
    outcome_order,
    spec,
    status = dplyr::case_when(
      skip_spec ~ "not_estimated",
      !is.na(status) ~ status,
      TRUE ~ "failed"
    ),
    nobs,
    initial_nobs,
    requested_exposures,
    exposure_scale,
    omitted_reference,
    reference_population,
    same_domain_total_control,
    same_domain_total_control_dropped,
    share_sum_mean_abs_dev,
    share_sum_max_abs_dev,
    requested_controls = dplyr::coalesce(requested_controls, requested_controls_expected),
    retained_controls = dplyr::coalesce(retained_controls, selected_controls_chr),
    dropped_collinear_controls,
    dropped_collinear_terms,
    message = dplyr::case_when(
      skip_spec ~ skip_message,
      !model_name %in% names(mods) ~ "estimation returned NULL",
      TRUE ~ NA_character_
    ),
    dplyr::pick(dplyr::starts_with("finite_n__"))
  ) |>
  dplyr::arrange(outcome_order, model_family)
write_csv_safe(model_diag, cfg$paths$twfe_age_mix_experiment_diagnostics)

family_control_summary <- family_contracts |>
  dplyr::distinct(model_family, requested_controls, same_domain_total_control) |>
  dplyr::transmute(
    family_summary = sprintf(
      "%s(exposure=resident_log_population; controls=%s; retained_total=%s)",
      model_family,
      requested_controls,
      same_domain_total_control
    )
  ) |>
  dplyr::pull(family_summary) |>
  paste(collapse = " | ")

append_log(
  cfg$logs$model_run,
  sprintf(
    "- TWFE age-mix experiment specs: success=%d, skipped=%d, failed=%d (families=%d, outcomes=%d, exposure_scale=log_population, %s)",
    sum(model_diag$status == "success", na.rm = TRUE),
    sum(model_diag$status == "not_estimated", na.rm = TRUE),
    sum(model_diag$status == "failed", na.rm = TRUE),
    nrow(family_registry),
    length(outcomes),
    family_control_summary
  )
)
}
