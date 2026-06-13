#==============================================================================
# Script    : 00_template_modeling_aging_commerce.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Project-specific template for quarterly TWFE, residual Moran's I,
#             SPDM, and robustness analysis on adm_cd x yq panel data.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-04-22
# Type      : panel_modeling
# Inputs    : panel_main.parquet, boundary_2020.gpkg, W_queen.rds
# Outputs   : TWFE/SPDM tables, coef plots, robustness summaries, logs
# DependsOn : 07_build_vitality_index.R, 01_build_spatial_weights.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# This template shows the expected structure for quarterly modeling scripts. The
# active contract is `adm_cd x yq`, lagged quarterly timing for main exposure
# and controls, TWFE fixed effects `adm_cd + yq`, and the resident-only SPDM main
# specification.

## 0-1. Load packages ----------------------------------------------------------
required_packages <- c(
  "arrow", "broom", "cli", "dplyr", "fixest", "fs", "ggplot2", "here",
  "modelsummary", "purrr", "readr", "rlang", "spdep", "splm",
  "stringr", "tibble", "tidyr"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0L) {
  stop(
    sprintf(
      "[ERROR] Required packages are not installed: %s",
      paste(missing_packages, collapse = ", ")
    ),
    call. = FALSE
  )
}

invisible(lapply(required_packages, library, character.only = TRUE))
options(scipen = 999)
options(modelsummary_format_numeric_latex = "plain")

## 0-2. Define paths -----------------------------------------------------------
dir_panel <- here::here("01_Data", "03_Processed_Data", "03_Panel")
dir_tables <- here::here("03_Output", "01_Tables")
dir_figures <- here::here("03_Output", "02_Figures")
dir_logs <- here::here("03_Output", "04_Logs")
fs::dir_create(c(dir_tables, dir_figures, dir_logs))

path_panel_main <- fs::path(dir_panel, "panel_main.parquet")
path_w_queen <- fs::path(dir_panel, "W_queen.rds")
path_twfe_csv <- fs::path(dir_tables, "twfe_main_models.csv")
path_twfe_html <- fs::path(dir_tables, "twfe_main_models.html")
path_twfe_plot <- fs::path(dir_figures, "twfe_main_coefplot.png")
path_twfe_residual_moran_by_yq <- fs::path(dir_tables, "twfe_main_residual_moran_by_yq.csv")
path_spdm_csv <- fs::path(dir_tables, "spdm_main_models.csv")
path_spdm_impacts <- fs::path(dir_tables, "spdm_impacts.csv")
path_robustness_csv <- fs::path(dir_tables, "robustness_summary.csv")
path_model_log <- fs::path(dir_logs, "model_run_log.md")

#==============================================================================
# 1. Helper Functions
#==============================================================================

append_log_line <- function(text, path) {
  fs::dir_create(fs::path_dir(path))
  cat(text, file = path, append = TRUE, sep = "\n")
}

write_csv_safe <- function(df, path, ...) {
  fs::dir_create(fs::path_dir(path))
  readr::write_csv(df, file = path, ...)
  cli::cli_alert_success("Saved CSV: {path}")
}

assert_required_cols <- function(df, required_cols) {
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(
      sprintf("[ERROR] Required columns are missing: %s", paste(missing_cols, collapse = ", ")),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

build_twfe_formula <- function(outcome, exposure, controls = NULL, interaction_var = NULL) {
  rhs_terms <- exposure

  if (!is.null(controls) && length(controls) > 0L) {
    rhs_terms <- c(rhs_terms, controls)
  }

  if (!is.null(interaction_var) && nzchar(interaction_var)) {
    rhs_terms <- c(rhs_terms, sprintf("%s:%s", exposure, interaction_var))
  }

  stats::as.formula(
    sprintf("%s ~ %s | adm_cd + yq", outcome, paste(rhs_terms, collapse = " + "))
  )
}

run_twfe_model <- function(data, outcome, exposure, controls = NULL, interaction_var = NULL) {
  fixest::feols(
    fml = build_twfe_formula(outcome, exposure, controls, interaction_var),
    data = data,
    cluster = ~ adm_cd
  )
}

build_twfe_suite <- function(data, outcomes, exposures, controls = NULL) {
  results <- list()

  for (outcome in outcomes) {
    for (exposure in exposures) {
      key_prefix <- paste(outcome, exposure, sep = "__")

      results[[paste0(key_prefix, "__m1")]] <- run_twfe_model(
        data = data,
        outcome = outcome,
        exposure = exposure,
        controls = NULL
      )

      results[[paste0(key_prefix, "__m2")]] <- run_twfe_model(
        data = data,
        outcome = outcome,
        exposure = exposure,
        controls = controls
      )

      if ("covid_period" %in% names(data)) {
        results[[paste0(key_prefix, "__m4")]] <- run_twfe_model(
          data = data,
          outcome = outcome,
          exposure = exposure,
          controls = controls,
          interaction_var = "covid_period"
        )
      }
    }
  }

  results
}

compute_residual_moran_by_yq <- function(data, residual_col, w_listw) {
  assert_required_cols(data, c("adm_cd", "yq", residual_col))

  data |>
    dplyr::filter(!is.na(.data[[residual_col]])) |>
    dplyr::group_by(yq) |>
    dplyr::group_modify(function(df_yq, ...) {
      if (nrow(df_yq) < 2L) {
        return(tibble::tibble(moran_i = NA_real_, p_value = NA_real_))
      }

      mt <- spdep::moran.test(df_yq[[residual_col]], listw = w_listw, zero.policy = TRUE)

      tibble::tibble(
        moran_i = unname(mt$estimate[["Moran I statistic"]]),
        p_value = mt$p.value
      )
    }) |>
    dplyr::ungroup()
}

#==============================================================================
# 2. Data Loading
#==============================================================================

if (!file.exists(path_panel_main)) {
  stop(sprintf("[ERROR] Panel file is missing: %s", path_panel_main), call. = FALSE)
}

panel_main <- arrow::read_parquet(path_panel_main) |>
  tibble::as_tibble()

assert_required_cols(panel_main, c("adm_cd", "year"))

outcomes_main <- c(
  "vitality_sub_economic",
  "vitality_sub_social",
  "vitality_sub_temporal",
  "vitality_sub_stability",
  "vitality_index_base"
)

exposures_main <- c(
  "lag4_age60_resident_share"
)

controls_structural <- c(
  "lag4_ln_resident_pop",
  "lag4_ln_land_price_adjusted",
  "lag4_transit_accessibility",
  "lag4_ln_workplace_worker_pop"
)

controls_gtwr_lean <- c(
  "lag4_ln_resident_pop",
  "lag4_ln_land_price_adjusted"
)

controls_gtwr_extended <- c(
  controls_gtwr_lean,
  "lag4_transit_accessibility",
  "lag4_ln_workplace_worker_pop"
)

existing_outcomes <- intersect(outcomes_main, names(panel_main))
existing_exposures <- intersect(exposures_main, names(panel_main))
existing_controls <- intersect(controls_structural, names(panel_main))

append_log_line(sprintf("- Existing outcomes: %s", paste(existing_outcomes, collapse = ", ")), path_model_log)
append_log_line(sprintf("- Existing exposures: %s", paste(existing_exposures, collapse = ", ")), path_model_log)
append_log_line(sprintf("- Existing controls: %s", paste(existing_controls, collapse = ", ")), path_model_log)

#==============================================================================
# 3. TWFE Example
#==============================================================================

twfe_models <- build_twfe_suite(
  data = panel_main,
  outcomes = existing_outcomes,
  exposures = intersect("lag4_age60_resident_share", existing_exposures),
  controls = existing_controls
)

if (length(twfe_models) == 0L) {
  stop("[ERROR] No estimable TWFE model is available. Check outcome/exposure variables.", call. = FALSE)
}

modelsummary::modelsummary(
  twfe_models,
  output = path_twfe_html,
  stars = TRUE,
  fmt = 3
)

twfe_tidy <- purrr::imap_dfr(
  twfe_models,
  ~ broom::tidy(.x, conf.int = TRUE) |>
    dplyr::mutate(model_id = .y, .before = 1)
)

write_csv_safe(twfe_tidy, path_twfe_csv)

#==============================================================================
# 4. Residual Moran Example
#==============================================================================

# Real main scripts must first lock the common sample and W ordering alignment.
# This example only shows the pattern for quarterly `by_yq` diagnostics.
#
# if (file.exists(path_w_queen) && "fitstat" %in% getNamespaceExports("fixest")) {
#   w_queen <- readRDS(path_w_queen)
#   panel_main$resid_m2 <- residuals(twfe_models[[1L]])
#   moran_by_yq <- compute_residual_moran_by_yq(panel_main, "resid_m2", w_queen)
#   write_csv_safe(moran_by_yq, path_twfe_residual_moran_by_yq)
# }

#==============================================================================
# 5. SPDM and Robustness Reminders
#==============================================================================

# SPDM template rule:
# - Main exposure is `lag4_age60_resident_share`.
# - Quarterly panel time index is `yq`.
# - True SDM includes `W y`, `X`, and `W X` together.
# - `W X` includes `W lag4_age60_resident_share` and W-lagged controls built
#   directly on the quarterly panel, not via a Durbin placeholder.
# - Reporting centers on `direct / indirect / total effects`, not coefficients.
# - SDM impacts use `S = (I - rho W)^(-1)` and `S(beta I + theta W)`.
# - W robustness is kept as a separate family.

# Robustness template rule:
# - The canonical shared panel keeps contemporaneous variables only.
# - Outcome-definition, sample-window, and W-Moran sensitivities are recorded separately.

#==============================================================================
# 6. Template Reminders
#==============================================================================

# - Active modeling contract is `adm_cd x yq`.
# - Fixed effects are locked to `adm_cd + yq`.
# - `year`, `quarter`, `yq`, `quarter_index` are canonical active modeling keys.
# - GTWR is an optional local sidecar, not the main causal estimator.
# - GTWR lean controls cover scale and land value; extended controls add transit
#   accessibility and workplace population.
