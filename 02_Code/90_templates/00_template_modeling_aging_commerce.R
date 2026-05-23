#==============================================================================
# Script    : 00_template_modeling_aging_commerce.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Project-specific template for quarterly TWFE, residual Moran's I,
#             SPDM, and robustness analysis on adm_cd x yq panel data.
# Author    : <AUTHOR>
# Created   : 2026-04-22
# Type      : panel_modeling
# Inputs    : panel_main.parquet, boundary_2020.gpkg, W_queen.rds
# Outputs   : TWFE/SPDM tables, coef plots, robustness summaries, logs
# DependsOn : 07_build_vitality_index.R, 01_build_spatial_weights.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# 이 템플릿은 현재 프로젝트의 quarterly modeling 코드가 어떤 구조를 가져야 하는가를
# 보여 주는 학습용 뼈대다. active contract는 `adm_cd x yq`, contemporaneous quarterly timing,
# TWFE FE `adm_cd + yq`, 그리고 resident-only SPDM main specification이다.

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
      "[ERROR] 필요한 패키지가 설치되어 있지 않습니다: %s",
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
# 1. Helper functions
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
      sprintf("[ERROR] 필요한 컬럼이 없습니다: %s", paste(missing_cols, collapse = ", ")),
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
# 2. Data loading
#==============================================================================

if (!file.exists(path_panel_main)) {
  stop(sprintf("[ERROR] 패널 파일이 없습니다: %s", path_panel_main), call. = FALSE)
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
  "age60_resident_share",
  "age60_floating_share",
  "age60_sales_share"
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
# 3. TWFE example
#==============================================================================

twfe_models <- build_twfe_suite(
  data = panel_main,
  outcomes = existing_outcomes,
  exposures = intersect("age60_resident_share", existing_exposures),
  controls = existing_controls
)

if (length(twfe_models) == 0L) {
  stop("[ERROR] 실행 가능한 TWFE 모형이 없습니다. outcome/exposure 변수를 점검하세요.", call. = FALSE)
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
# 4. Residual Moran example
#==============================================================================

# 실제 메인 스크립트에서는 common sample 정렬과 W ordering alignment를 먼저 확정해야 한다.
# 여기서는 quarterly contract에서 `by_yq` diagnostics를 어떻게 남기는지의 패턴만 보여 준다.
#
# if (file.exists(path_w_queen) && "fitstat" %in% getNamespaceExports("fixest")) {
#   w_queen <- readRDS(path_w_queen)
#   panel_main$resid_m2 <- residuals(twfe_models[[1L]])
#   moran_by_yq <- compute_residual_moran_by_yq(panel_main, "resid_m2", w_queen)
#   write_csv_safe(moran_by_yq, path_twfe_residual_moran_by_yq)
# }

#==============================================================================
# 5. SPDM and robustness reminders
#==============================================================================

# SPDM template rule:
# - main exposure는 `age60_resident_share`
# - quarterly panel time index는 `yq`
# - true SDM은 `W y`, `X`, `W X`를 함께 포함한다.
# - `W X`는 quarterly panel에서 직접 생성하고 Durbin placeholder에 의존하지 않는다.
# - 보고 중심은 coefficient가 아니라 `direct / indirect / total effects`
# - SDM impact는 `S = (I - rho W)^(-1)`와 `S(beta I + theta W)` 행렬식으로 계산한다.
# - W robustness는 별도 family로 분리한다.

# Robustness template rule:
# - canonical shared panel은 동시점 변수만 가진다.
# - outcome-definition, sample window, W-Moran 민감도를 분리해 기록한다.

#==============================================================================
# 6. Template reminders
#==============================================================================

# - active modeling contract는 `adm_cd x yq`다.
# - FE는 `adm_cd + yq`로 고정한다.
# - `year`, `quarter`, `yq`, `quarter_index` are canonical active modeling keys.
# - GTWR는 optional local sidecar이며 main causal estimator가 아니다.
# - GTWR lean control은 규모·지가 통제, extended control은 대중교통 접근성 composite와 직장인구를 추가한다.
