#==============================================================================
# Script    : 02_run_twfe_interaction_models.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the supplementary/manual TWFE COVID interaction appendix and
#             export coefficient, diagnostic, and linear-combination summaries.
# Author    : Codex
# Created   : 2026-03-30
# Status    : ANNUAL_APPENDIX / manual sidecar outside canonical workflow
# Type      : panel_modeling
# Inputs    : panel_main.parquet, twfe_main_controls_used.csv
# Outputs   : twfe_interaction_models.csv, twfe_interaction_controls_used.csv,
#             twfe_interaction_diagnostics.csv,
#             twfe_interaction_effect_summary.csv
# DependsOn : 02_Code/03_models/01_run_twfe_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 02_run_twfe_interaction_models", timestamp()))

if (!file.exists(cfg$paths$panel_main)) stop("[ERROR] panel_main missing", call. = FALSE)
panel <- read_panel_main_view("twfe")
if ("covid_period" %in% names(panel)) {
  panel$covid_period <- suppressWarnings(as.numeric(panel$covid_period))
}


#==============================================================================
# 1. Resolve Interaction Contract
#==============================================================================

outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = value_or(cfg$twfe_interaction_outcomes, value_or(cfg$twfe_main_outcomes, c(
    "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability", "vitality_index_base"
  ))),
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome
exposure_base <- value_or(cfg$twfe_main_exposure_vars, c("age60_resident_share"))
exposures <- intersect(exposure_base, names(panel))
exposures <- exposures[vapply(exposures, function(v) sum(is.finite(panel[[v]])) > 100, logical(1))]

main_control_contract <- load_twfe_main_control_contracts(outcomes)
assert_twfe_main_controls_current(main_control_contract$screen, context = "02_run_twfe_interaction_models")
ctrl_screen <- main_control_contract$screen |>
  dplyr::mutate(control_source = "twfe_main_controls_used")
control_contracts <- main_control_contract$contracts
controls_by_outcome <- stats::setNames(
  lapply(control_contracts, `[[`, "usable_controls"),
  names(control_contracts)
)

interaction_specs <- dplyr::bind_rows(
  if ("covid_period" %in% names(panel)) tibble::tibble(spec = "m4", interaction_family = "covid_period")
)

if (length(outcomes) == 0 || length(exposures) == 0 || nrow(interaction_specs) == 0L) {
  stop("[ERROR] No valid outcomes/exposures/interactions for TWFE interaction models", call. = FALSE)
}

write_csv_safe(ctrl_screen, cfg$paths$twfe_interaction_controls_used)

build_model_name <- function(outcome, exposure, spec) {
  paste(outcome, exposure, spec, sep = "__")
}

infer_covid_baseline_label <- function(sample_year, sample_covid) {
  sample_year <- suppressWarnings(as.integer(sample_year))
  sample_covid <- suppressWarnings(as.numeric(sample_covid))
  covid_start <- min(cfg$covid_years)
  covid_end <- max(cfg$covid_years)
  non_covid_year <- sample_year[!is.na(sample_year) & !is.na(sample_covid) & sample_covid == 0]
  if (length(non_covid_year) == 0L) return("non_covid_in_sample")
  if (all(non_covid_year < covid_start)) return("pre_covid")
  if (all(non_covid_year > covid_end)) return("post_covid")
  if (any(non_covid_year < covid_start) && any(non_covid_year > covid_end)) return("non_covid_mixed_sample")
  "non_covid_in_sample"
}

build_interaction_effect_defs <- function(model, exposure, interaction_family, coef_terms) {
  d <- value_or(model$data, data.frame())

  baseline_label <- infer_covid_baseline_label(d$year, d$covid_period)
  covid_hits <- coef_terms[
    grepl(exposure, coef_terms, fixed = TRUE) &
      grepl("covid_period", coef_terms, fixed = TRUE)
  ]
  covid_term <- if (length(covid_hits) > 0L) covid_hits[[1]] else paste0(exposure, ":covid_period")
  effect_defs <- list(
    stats::setNames(1, exposure),
    covid_period = stats::setNames(c(1, 1), c(exposure, covid_term))
  )
  names(effect_defs)[[1]] <- baseline_label
  list(
    effect_defs = effect_defs,
    effect_label_definition = sprintf(
      "covid_period denotes realized sample observations within %s to %s; %s denotes realized non-COVID observations outside that window.",
      min(cfg$covid_years),
      max(cfg$covid_years),
      baseline_label
    )
  )
}

build_effect_summary <- function(model_name, spec, interaction_family, model, outcome, exposure) {
  coef_tbl <- broom::tidy(model) |>
    dplyr::select(term, estimate, std.error, statistic, p.value)
  coef_named <- stats::setNames(coef_tbl$estimate, coef_tbl$term)
  vc <- tryCatch(stats::vcov(model), error = function(e) NULL)
  vc_names <- if (!is.null(vc)) rownames(vc) else character()
  if (!is.null(vc) && (is.null(vc_names) || all(is.na(vc_names)) || all(vc_names == "")) && nrow(vc) == nrow(coef_tbl)) {
    rownames(vc) <- coef_tbl$term
    colnames(vc) <- coef_tbl$term
  }

  effect_info <- build_interaction_effect_defs(model, exposure, interaction_family, coef_tbl$term)

  purrr::imap_dfr(effect_info$effect_defs, function(weights, effect_label) {
    terms <- names(weights)
    source_terms <- paste(terms, collapse = " + ")
    if (length(setdiff(terms, names(coef_named))) > 0L || is.null(vc) || !all(terms %in% rownames(vc))) {
      return(tibble::tibble(
        model_name = model_name,
        spec = spec,
        interaction_family = interaction_family,
        outcome = outcome,
        exposure = exposure,
        effect_label = effect_label,
        estimate = NA_real_,
        std.error = NA_real_,
        statistic = NA_real_,
        p.value = NA_real_,
        inference_scope = "not_available",
        effect_label_definition = effect_info$effect_label_definition,
        source_terms = source_terms,
        status = "failed",
        message = "delta-method terms unavailable"
      ))
    }

    weight_vec <- as.numeric(weights)
    coef_vec <- as.numeric(coef_named[terms])
    vc_sub <- as.matrix(vc[terms, terms, drop = FALSE])
    est <- sum(weight_vec * coef_vec)
    se <- sqrt(drop(t(weight_vec) %*% vc_sub %*% weight_vec))
    stat <- if (is.finite(se) && se > 0) est / se else NA_real_
    p_val <- if (is.finite(stat)) 2 * stats::pnorm(abs(stat), lower.tail = FALSE) else NA_real_

    tibble::tibble(
      model_name = model_name,
      spec = spec,
      interaction_family = interaction_family,
      outcome = outcome,
      exposure = exposure,
      effect_label = effect_label,
      estimate = est,
      std.error = se,
      statistic = stat,
      p.value = p_val,
      inference_scope = "coefficient_delta_method",
      effect_label_definition = effect_info$effect_label_definition,
      source_terms = source_terms,
      status = "success",
      message = NA_character_
    )
  })
}

build_interaction_diag <- function(model_name, spec, interaction_family, model) {
  meta <- value_or(model$twfe_meta, list())
  d <- value_or(model$data, data.frame())
  has_sample <- nrow(d) > 0L
  tibble::tibble(
    model_name = model_name,
    outcome = value_or(meta$outcome, NA_character_),
    exposure = value_or(meta$exposure, NA_character_),
    spec = spec,
    interaction_family = interaction_family,
    status = "success",
    nobs = suppressWarnings(as.integer(value_or(meta$nobs, stats::nobs(model)))),
    initial_nobs = suppressWarnings(as.integer(value_or(meta$initial_nobs, NA_integer_))),
    requested_controls = collapse_chr(value_or(meta$requested_controls, character(0))),
    retained_controls = collapse_chr(value_or(meta$retained_controls, character(0))),
    dropped_collinear_controls = collapse_chr(value_or(meta$dropped_collinear_controls, character(0))),
    dropped_collinear_terms = collapse_chr(value_or(meta$dropped_collinear_terms, character(0))),
    sample_min_year = if (has_sample) min(as.character(d$year), na.rm = TRUE) else NA_character_,
    sample_max_year = if (has_sample) max(as.character(d$year), na.rm = TRUE) else NA_character_,
    n_covid_obs = if (has_sample && "covid_period" %in% names(d)) as.integer(sum(d$covid_period == 1, na.rm = TRUE)) else NA_integer_,
    n_non_covid_obs = if (has_sample && "covid_period" %in% names(d)) as.integer(sum(d$covid_period == 0, na.rm = TRUE)) else NA_integer_
  )
}


#==============================================================================
# 2. Estimate Interaction Models
#==============================================================================

spec_registry <- tidyr::crossing(
  outcome = outcomes,
  exposure = exposures,
  interaction_specs
) |>
  dplyr::left_join(outcome_registry, by = "outcome") |>
  dplyr::arrange(outcome_order, exposure, spec) |>
  dplyr::mutate(
    model_name = build_model_name(outcome, exposure, spec),
    requested_controls = purrr::map_chr(outcome, ~ collapse_chr(controls_by_outcome[[.x]]))
  )

mods <- list()
for (i in seq_len(nrow(spec_registry))) {
  row <- spec_registry[i, ]
  model_obj <- run_twfe(
    panel,
    outcome = row$outcome[[1]],
    exposure = row$exposure[[1]],
    controls = controls_by_outcome[[row$outcome[[1]]]],
    interaction = row$interaction_family[[1]]
  )
  if (!is.null(model_obj)) {
    mods[[row$model_name[[1]]]] <- model_obj
  }
}

if (length(mods) == 0L) stop("[ERROR] No estimable TWFE interaction models", call. = FALSE)

twfe_tidy <- tidy_models(mods) |>
  dplyr::left_join(
    spec_registry |>
      dplyr::select(model_name, spec, interaction_family),
    by = "model_name"
  ) |>
  annotate_outcomes(include_robustness = FALSE) |>
  dplyr::arrange(outcome_order, interaction_family, model_name, term)
write_csv_safe(twfe_tidy, cfg$paths$twfe_interaction_models)

diag_success <- purrr::imap_dfr(mods, function(model, model_name) {
  reg_row <- spec_registry |>
    dplyr::filter(model_name == !!model_name) |>
    dplyr::slice(1)
  build_interaction_diag(
    model_name = model_name,
    spec = reg_row$spec[[1]],
    interaction_family = reg_row$interaction_family[[1]],
    model = model
  )
})

diag_tbl <- spec_registry |>
  dplyr::left_join(
    diag_success,
    by = c("model_name", "outcome", "exposure", "spec", "interaction_family"),
    suffix = c("_expected", "")
  ) |>
  dplyr::transmute(
    model_name,
    outcome,
    outcome_group,
    outcome_order,
    exposure,
    spec,
    interaction_family,
    status = dplyr::coalesce(status, "failed"),
    nobs,
    initial_nobs,
    requested_controls = dplyr::coalesce(requested_controls, requested_controls_expected),
    retained_controls,
    dropped_collinear_controls,
    dropped_collinear_terms,
    sample_min_year,
    sample_max_year,
    n_covid_obs,
    n_non_covid_obs
  )
write_csv_safe(diag_tbl, cfg$paths$twfe_interaction_diagnostics)

effect_summary <- purrr::imap_dfr(mods, function(model, model_name) {
  reg_row <- spec_registry |>
    dplyr::filter(model_name == !!model_name) |>
    dplyr::slice(1)
  build_effect_summary(
    model_name = model_name,
    spec = reg_row$spec[[1]],
    interaction_family = reg_row$interaction_family[[1]],
    model = model,
    outcome = reg_row$outcome[[1]],
    exposure = reg_row$exposure[[1]]
  )
}) |>
  annotate_outcomes(include_robustness = FALSE) |>
  dplyr::arrange(outcome_order, interaction_family, model_name, effect_label)
write_csv_safe(effect_summary, cfg$paths$twfe_interaction_effect_summary)

append_log(cfg$logs$model_run, sprintf("- TWFE interaction models: %d/%d", length(mods), nrow(spec_registry)))
