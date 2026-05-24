#==============================================================================
# Script    : 04_run_twfe_vitality_component_models.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run an appendix TWFE sidecar using vitality component variables
#             as outcomes.
# Author    : Codex
# Created   : 2026-05-24
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : panel_modeling
# Inputs    : panel_main.parquet
# Outputs   : twfe_vitality_component_models.csv,
#             twfe_vitality_component_controls_used.csv,
#             twfe_vitality_component_diagnostics.csv
# DependsOn : 02_Code/01_preprocess/07_build_vitality_index.R,
#             02_Code/03_models/01_run_twfe_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 04_run_twfe_vitality_component_models", timestamp()))

if (!file.exists(cfg$paths$panel_main)) {
  stop("[ERROR] Required inputs for TWFE vitality component sidecar missing", call. = FALSE)
}

panel <- read_panel_main_view("twfe")

build_model_name <- function(outcome, exposure, spec) {
  paste(outcome, exposure, spec, sep = "__")
}


#==============================================================================
# 1. Resolve Estimation Inputs
#==============================================================================

component_outcomes <- value_or(cfg$vitality_component_appendix_outcomes, character())
outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = component_outcomes,
  include_robustness = TRUE
)
outcomes <- outcome_registry$outcome

exposure_base <- if (!is.null(cfg$twfe_main_exposure_vars) && length(cfg$twfe_main_exposure_vars) > 0) {
  cfg$twfe_main_exposure_vars
} else {
  c("age60_resident_share")
}
exposures <- intersect(exposure_base, names(panel))
exposures <- exposures[vapply(exposures, function(v) sum(is.finite(panel[[v]])) > 100, logical(1))]

control_candidates <- value_or(cfg$twfe_main_control_cols, c(
  "lag4_ln_resident_pop", "lag4_ln_land_price_adjusted", "lag4_transit_accessibility",
  "lag4_ln_workplace_worker_pop"
))
control_screen <- resolve_outcome_control_screen(
  panel,
  outcomes = outcomes,
  candidates = control_candidates,
  min_finite = 500L,
  fe_aware = TRUE
)
control_contracts <- resolve_outcome_control_contracts(control_screen, outcomes = outcomes)
controls_by_outcome <- stats::setNames(
  lapply(control_contracts, `[[`, "usable_controls"),
  names(control_contracts)
)

if (length(outcomes) == 0L || length(exposures) == 0L) {
  stop("[ERROR] No valid outcomes/exposures for TWFE vitality component sidecar", call. = FALSE)
}

write_csv_safe(control_screen, cfg$paths$twfe_vitality_component_controls_used)


#==============================================================================
# 2. Estimate TWFE Component Models
#==============================================================================

available_specs <- c("m1", "m2")
spec_registry <- tidyr::crossing(
  outcome = outcomes,
  exposure = exposures,
  spec = available_specs
) |>
  dplyr::left_join(outcome_registry, by = "outcome") |>
  dplyr::arrange(outcome_order, exposure, spec) |>
  dplyr::mutate(
    model_name = build_model_name(outcome, exposure, spec),
    interaction_var = NA_character_,
    requested_controls = purrr::map_chr(
      seq_len(dplyr::n()),
      ~ if (spec[[.x]] == "m1") NA_character_ else collapse_chr(controls_by_outcome[[outcome[[.x]]]])
    )
  )

mods <- list()
for (y in outcomes) {
  for (x in exposures) {
    key <- paste(y, x, sep = "__")

    m1 <- run_twfe(panel, y, x, controls = NULL)
    m2 <- run_twfe(panel, y, x, controls = controls_by_outcome[[y]])
    if (!is.null(m1)) mods[[paste0(key, "__m1")]] <- m1
    if (!is.null(m2)) mods[[paste0(key, "__m2")]] <- m2
  }
}

if (length(mods) == 0L) {
  stop("[ERROR] No estimable TWFE vitality component models", call. = FALSE)
}

component_tidy <- tidy_models(mods) |>
  annotate_outcomes(include_robustness = TRUE) |>
  dplyr::arrange(outcome_order, exposure, model_name, term)
write_csv_safe(component_tidy, cfg$paths$twfe_vitality_component_models)

model_diag_success <- summarize_model_diagnostics(mods)
model_diag <- spec_registry |>
  dplyr::left_join(model_diag_success, by = "model_name", suffix = c("_expected", "")) |>
  dplyr::transmute(
    model_name,
    outcome = dplyr::coalesce(outcome, outcome_expected),
    outcome_group,
    outcome_order,
    exposure = dplyr::coalesce(exposure, exposure_expected),
    spec,
    status = dplyr::coalesce(status, "failed"),
    nobs,
    initial_nobs,
    requested_controls = dplyr::coalesce(requested_controls, requested_controls_expected),
    retained_controls,
    dropped_collinear_controls,
    dropped_collinear_terms,
    interaction_var = dplyr::coalesce(interaction_var, interaction_var_expected),
    message = dplyr::if_else(status == "success", NA_character_, "estimation returned NULL", missing = "estimation returned NULL")
  )
write_csv_safe(model_diag, cfg$paths$twfe_vitality_component_diagnostics)

append_log(
  cfg$logs$model_run,
  sprintf(
    "- TWFE vitality component specs attempted: %d (success=%d, failed=%d)",
    nrow(spec_registry),
    sum(model_diag$status == "success", na.rm = TRUE),
    sum(model_diag$status != "success", na.rm = TRUE)
  )
)
