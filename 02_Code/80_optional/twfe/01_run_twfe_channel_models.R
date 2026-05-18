#==============================================================================
# Script    : 01_run_twfe_channel_models.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the supplementary/manual TWFE channel appendix and export
#             compact coefficient tables under the shared main-control contract.
# Author    : Codex
# Created   : 2026-03-30
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : panel_modeling
# Inputs    : panel_main.parquet, twfe_main_controls_used.csv
# Outputs   : twfe_channel_models.csv, twfe_channel_controls_used.csv
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

append_log(cfg$logs$model_run, sprintf("\n## [%s] 01_run_twfe_channel_models", timestamp()))

if (!file.exists(cfg$paths$panel_main)) stop("[ERROR] panel_main missing", call. = FALSE)
panel <- read_panel_main_view("twfe")


#==============================================================================
# 1. Resolve TWFE Channel Contract
#==============================================================================

outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = value_or(cfg$twfe_channel_outcomes, value_or(cfg$twfe_main_outcomes, c(
    "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability", "vitality_index_base"
  ))),
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome
main_exposure <- intersect(
  value_or(cfg$twfe_main_exposure_vars, c("age60_resident_share")),
  names(panel)
)
channel_vars <- intersect(
  value_or(cfg$twfe_channel_vars, "age60_floating_share"),
  names(panel)
)
main_control_contract <- load_twfe_main_control_contracts(outcomes)
assert_twfe_main_controls_current(main_control_contract$screen, context = "01_run_twfe_channel_models")
main_ctrl_screen <- main_control_contract$screen |>
  dplyr::mutate(
    equation_type = "y_with_channels",
    control_source = "twfe_main_controls_used"
  )
main_control_contracts <- main_control_contract$contracts
main_controls_by_outcome <- stats::setNames(
  lapply(main_control_contracts, `[[`, "usable_controls"),
  names(main_control_contracts)
)

# The mediator equation (`x_to_m`) has `age60_floating_share` as its outcome,
# which is not part of the main TWFE outcome contract. It therefore uses the
# controls selected in every main TWFE outcome contract, rather than running a
# separate mediator-specific control screen.
main_control_lists <- lapply(main_controls_by_outcome, function(x) {
  x <- unique(as.character(value_or(x, character())))
  x[!is.na(x) & nzchar(x)]
})
common_main_controls <- if (length(main_control_lists) > 0L) {
  Reduce(intersect, main_control_lists)
} else {
  character()
}

if (length(channel_vars) > 0L && length(common_main_controls) == 0L) {
  stop("[ERROR] No common inherited TWFE main controls available for TWFE channel mediator equation", call. = FALSE)
}

mediator_ctrl_template <- main_ctrl_screen |>
  dplyr::group_by(control) |>
  dplyr::slice(1) |>
  dplyr::ungroup() |>
  dplyr::select(-dplyr::any_of(c("outcome", "equation_type", "control_source")))

mediator_ctrl_screen <- if (length(channel_vars) == 0L) {
  main_ctrl_screen[0, ]
} else {
  purrr::map_dfr(channel_vars, function(m_var) {
    mediator_ctrl_template |>
      dplyr::mutate(outcome = m_var, .before = 1)
  }) |>
    dplyr::mutate(
      selected = control %in% common_main_controls,
      reason = dplyr::if_else(
        selected,
        "inherited_from_twfe_main_common_controls",
        "not_in_twfe_main_common_controls"
      ),
      equation_type = "x_to_m",
      control_source = "twfe_main_controls_used"
    )
}

mediator_controls_by_outcome <- stats::setNames(
  rep(list(common_main_controls), length(channel_vars)),
  channel_vars
)
controls_by_outcome <- c(main_controls_by_outcome, mediator_controls_by_outcome)
ctrl_screen <- dplyr::bind_rows(main_ctrl_screen, mediator_ctrl_screen)
channel_spec_registry <- dplyr::bind_cols(
  outcome_registry,
  resolve_floating_overlap_spec_meta(
    outcome_registry$outcome,
    rep(list(unique(c(main_exposure, channel_vars))), length.out = nrow(outcome_registry))
  ) |>
    dplyr::select(skip_reason, skip_message, skip_spec)
) |>
  dplyr::mutate(equation_type = "y_with_channels")

ctrl_screen <- ctrl_screen |>
  dplyr::mutate(
    equation_type = dplyr::if_else(outcome %in% channel_vars, "x_to_m", "y_with_channels")
  ) |>
  dplyr::left_join(
    channel_spec_registry |>
      dplyr::select(outcome, equation_type, skip_reason, skip_message, skip_spec),
    by = c("outcome", "equation_type")
  ) |>
  dplyr::mutate(
    spec_status = dplyr::case_when(
      equation_type == "x_to_m" ~ "success",
      dplyr::coalesce(skip_spec, FALSE) ~ "not_estimated",
      TRUE ~ "success"
    ),
    spec_reason = dplyr::if_else(equation_type == "y_with_channels", skip_reason, NA_character_),
    spec_message = dplyr::if_else(equation_type == "y_with_channels", skip_message, NA_character_)
  )

if (length(outcomes) == 0 || length(main_exposure) == 0 || length(channel_vars) == 0) {
  stop("[ERROR] No valid outcomes/resident/channel vars for TWFE channel models", call. = FALSE)
}


#==============================================================================
# 2. Estimate Channel Models
#==============================================================================

mods <- list()
x_var <- main_exposure[[1]]

for (m_var in channel_vars) {
  m <- run_twfe(panel, m_var, x_var, controls = controls_by_outcome[[m_var]])
  if (!is.null(m)) {
    m$channel_meta <- list(
      equation_type = "x_to_m",
      main_exposure = x_var,
      channel_vars = m_var
    )
    mods[[paste("x_to_m", m_var, sep = "__")]] <- m
  }
}

for (y in outcomes) {
  spec_meta <- channel_spec_registry |>
    dplyr::filter(outcome == y) |>
    dplyr::slice(1)
  if (nrow(spec_meta) > 0L && isTRUE(spec_meta$skip_spec[[1]])) {
    next
  }
  m <- run_twfe_multi(panel, y, c(x_var, channel_vars), controls = controls_by_outcome[[y]])
  if (!is.null(m)) {
    m$channel_meta <- list(
      equation_type = "y_with_channels",
      main_exposure = x_var,
      channel_vars = collapse_chr(channel_vars)
    )
    mods[[paste("y_with_channels", y, sep = "__")]] <- m
  }
}

if (length(mods) == 0L) stop("[ERROR] No estimable TWFE channel models", call. = FALSE)

td <- tidy_models(mods) |>
  dplyr::mutate(status = "success", message = NA_character_)
meta_tbl <- purrr::imap_dfr(mods, function(model, model_name) {
  channel_meta <- value_or(model$channel_meta, list())
  tibble::tibble(
    model_name = model_name,
    equation_type = value_or(channel_meta$equation_type, NA_character_),
    main_exposure = value_or(channel_meta$main_exposure, NA_character_),
    channel_vars = value_or(channel_meta$channel_vars, NA_character_)
  )
})

skip_tbl <- channel_spec_registry |>
  dplyr::filter(skip_spec) |>
  dplyr::transmute(
    model_name = paste("y_with_channels", outcome, sep = "__"),
    outcome,
    exposure = collapse_chr(c(x_var, channel_vars)),
    nobs = NA_integer_,
    initial_nobs = NA_integer_,
    requested_controls = purrr::map_chr(outcome, ~ collapse_chr(controls_by_outcome[[.x]])),
    retained_controls = purrr::map_chr(outcome, ~ collapse_chr(controls_by_outcome[[.x]])),
    dropped_collinear_controls = NA_character_,
    dropped_collinear_terms = NA_character_,
    interaction_var = NA_character_,
    term = NA_character_,
    estimate = NA_real_,
    std.error = NA_real_,
    statistic = NA_real_,
    p.value = NA_real_,
    status = "not_estimated",
    message = skip_message,
    equation_type,
    main_exposure = x_var,
    channel_vars = collapse_chr(channel_vars)
  )

td <- dplyr::bind_rows(td, skip_tbl) |>
  dplyr::left_join(meta_tbl, by = "model_name") |>
  dplyr::mutate(
    equation_type = dplyr::coalesce(equation_type.x, equation_type.y),
    main_exposure = dplyr::coalesce(main_exposure.x, main_exposure.y),
    channel_vars = dplyr::coalesce(channel_vars.x, channel_vars.y)
  ) |>
  dplyr::select(-equation_type.x, -equation_type.y, -main_exposure.x, -main_exposure.y, -channel_vars.x, -channel_vars.y) |>
  annotate_outcomes(include_robustness = FALSE) |>
  dplyr::arrange(outcome_order, equation_type, model_name, term) |>
  dplyr::select(
    outcome_group, outcome_order,
    equation_type, main_exposure, channel_vars,
    dplyr::everything()
  )

write_csv_safe(td, cfg$paths$twfe_channel_models)
write_csv_safe(ctrl_screen, cfg$paths$twfe_channel_controls_used)

append_log(
  cfg$logs$model_run,
  sprintf(
    "- TWFE channel models: success=%d, skipped=%d",
    sum(td$status == "success", na.rm = TRUE),
    sum(td$status == "not_estimated", na.rm = TRUE)
  )
)
