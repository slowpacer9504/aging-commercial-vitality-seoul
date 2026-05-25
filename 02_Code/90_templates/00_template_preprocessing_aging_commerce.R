#==============================================================================
# Script    : 00_template_preprocessing_aging_commerce.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Project-specific template for quarterly preprocessing, harmonization,
#             and panel construction under the 2020 Seoul administrative-dong rule.
# Author    : <AUTHOR>
# Created   : 2026-04-22
# Type      : panel_building
# Inputs    : <RAW_INPUT_FILES>
# Outputs   : <OUTPUT_PANEL_FILES>
# DependsOn : 02_Code/00_setup/config.R (optional)
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# 이 템플릿은 분기 패널 preprocessing 스크립트를 새로 만들 때 따라야 하는
# 기본 골격을 보여 준다. 핵심 계약은 `adm_cd x yq`, contemporaneous quarterly timing,
# 그리고 "분기 raw는 active panel의 기본 시간 단위로 발행한다"는 점이다.

## 0-1. Load packages ----------------------------------------------------------
required_packages <- c(
  "arrow", "cli", "dplyr", "fs", "here", "janitor",
  "purrr", "readr", "readxl", "rlang", "sf",
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
options(dplyr.summarise.inform = FALSE)

## 0-2. Load shared config (optional) ------------------------------------------
config_path <- here::here("02_Code", "00_setup", "config.R")
if (file.exists(config_path)) {
  source(config_path)
}

## 0-3. Project constants ------------------------------------------------------
target_crs <- if (exists("target_crs", inherits = FALSE)) target_crs else 5179
boundary_year <- if (exists("boundary_year", inherits = FALSE)) boundary_year else 2020
short_panel_start_year <- if (exists("cfg", inherits = FALSE) && is.environment(cfg)) cfg$short_start else 2019L
short_panel_end_year <- if (exists("cfg", inherits = FALSE) && is.environment(cfg)) cfg$short_end else 2025L
short_panel_years <- seq.int(short_panel_start_year, short_panel_end_year)
covid_start_yq <- if (exists("cfg", inherits = FALSE) && is.environment(cfg)) cfg$covid_start_yq else "2020Q1"
covid_end_yq <- if (exists("cfg", inherits = FALSE) && is.environment(cfg)) cfg$covid_end_yq else "2022Q2"

## 0-4. Define paths -----------------------------------------------------------
dir_raw <- here::here("01_Data", "01_Raw_Data")
dir_boundary <- here::here("01_Data", "02_Boundary")
dir_processed <- here::here("01_Data", "03_Processed_Data")
dir_intermediate <- fs::path(dir_processed, "01_Intermediate")
dir_analysis_ready <- fs::path(dir_processed, "02_Analysis_Ready")
dir_panel <- fs::path(dir_processed, "03_Panel")
dir_output <- here::here("03_Output")
dir_logs <- fs::path(dir_output, "04_Logs")

fs::dir_create(c(dir_intermediate, dir_analysis_ready, dir_panel, dir_logs))

#==============================================================================
# 1. IO helpers
#==============================================================================

read_csv_kr <- function(path, encoding = "UTF-8", show_col_types = FALSE, ...) {
  readr::read_csv(
    file = path,
    locale = readr::locale(encoding = encoding),
    show_col_types = show_col_types,
    ...
  )
}

write_csv_safe <- function(df, path, ...) {
  fs::dir_create(fs::path_dir(path))
  readr::write_csv(df, file = path, ...)
  cli::cli_alert_success("Saved CSV: {path}")
}

write_parquet_safe <- function(df, path, ...) {
  fs::dir_create(fs::path_dir(path))
  arrow::write_parquet(df, sink = path, ...)
  cli::cli_alert_success("Saved Parquet: {path}")
}

#==============================================================================
# 2. Validation helpers
#==============================================================================

assert_required_cols <- function(df, required_cols, df_name = deparse(substitute(df))) {
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s에 필요한 컬럼이 없습니다: %s",
        df_name,
        paste(missing_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

standardize_panel_keys <- function(df) {
  rename_map <- c(
    "adm_cd" = "adm_cd",
    "adm_code" = "adm_cd",
    "adm_dong_cd" = "adm_cd",
    "adm_dong_code" = "adm_cd",
    "year" = "year",
    "yr" = "year",
    "quarter" = "quarter",
    "qtr" = "quarter"
  )

  original_names <- names(df)
  replacement_names <- rename_map[original_names]
  replacement_names[is.na(replacement_names)] <- original_names[is.na(replacement_names)]
  names(df) <- replacement_names

  if ("adm_cd" %in% names(df)) {
    df <- df |>
      dplyr::mutate(adm_cd = stringr::str_pad(as.character(adm_cd), width = 10, side = "left", pad = "0"))
  }

  if ("year" %in% names(df)) {
    df <- df |>
      dplyr::mutate(year = as.integer(year))
  }

  if ("quarter" %in% names(df)) {
    df <- df |>
      dplyr::mutate(quarter = as.integer(quarter))
  }

  df
}

validate_panel_keys <- function(df, key_cols = c("adm_cd", "year")) {
  assert_required_cols(df, key_cols)

  dup_n <- df |>
    dplyr::count(dplyr::across(dplyr::all_of(key_cols)), name = "n") |>
    dplyr::filter(n > 1L) |>
    nrow()

  if (dup_n > 0L) {
    stop(sprintf("[ERROR] 중복 키가 %d건 존재합니다.", dup_n), call. = FALSE)
  }

  cli::cli_alert_success("중복 키 0건 확인")
  invisible(TRUE)
}

summarize_missingness <- function(df, vars = names(df)) {
  tibble::tibble(variable = vars) |>
    dplyr::mutate(
      n_missing = purrr::map_int(variable, ~ sum(is.na(df[[.x]]))),
      pct_missing = purrr::map_dbl(variable, ~ mean(is.na(df[[.x]])))
    ) |>
    dplyr::arrange(dplyr::desc(pct_missing), dplyr::desc(n_missing))
}

safe_log1p <- function(x) {
  if (!is.numeric(x)) {
    stop("[ERROR] safe_log1p()는 numeric 벡터만 허용합니다.", call. = FALSE)
  }
  log1p(pmax(x, 0))
}

#==============================================================================
# 3. Annualization helpers
#==============================================================================

weighted_mean_or_na <- function(x, w = NULL) {
  keep <- !is.na(x)
  if (!is.null(w)) {
    keep <- keep & !is.na(w)
  }

  if (!any(keep)) {
    return(NA_real_)
  }

  x <- x[keep]

  if (is.null(w)) {
    return(mean(x))
  }

  w <- w[keep]
  if (sum(w) <= 0) {
    return(mean(x))
  }

  stats::weighted.mean(x, w = w)
}

quarterize_flow <- function(df, value_cols, group_cols = c("adm_cd", "year", "quarter", "yq")) {
  assert_required_cols(df, c(group_cols, value_cols))

  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) |>
    dplyr::summarise(
      dplyr::across(
        dplyr::all_of(value_cols),
        ~ sum(.x, na.rm = TRUE),
        .names = "{.col}"
      ),
      .groups = "drop"
    )
}

quarterize_level <- function(df, value_cols, weight_col = NULL, group_cols = c("adm_cd", "year", "quarter", "yq")) {
  assert_required_cols(df, c(group_cols, value_cols))
  if (!is.null(weight_col)) {
    assert_required_cols(df, weight_col)
  }

  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) |>
    dplyr::summarise(
      dplyr::across(
        dplyr::all_of(value_cols),
        ~ weighted_mean_or_na(.x, if (is.null(weight_col)) NULL else .data[[weight_col]]),
        .names = "{.col}"
      ),
      .groups = "drop"
    )
}

#==============================================================================
# 4. Example preprocessing flow
#==============================================================================

# 아래는 실제 실행 코드가 아니라, quarterly preprocessing 스크립트에서
# 어떤 순서로 객체를 만들고 어떤 계약을 지켜야 하는지 보여 주는 예시다.

## 4-1. Read and clean raw source ----------------------------------------------
# df_raw_quarterly <- read_csv_kr(fs::path(dir_raw, "seoul_sales_quarterly.csv")) |>
#   janitor::clean_names() |>
#   standardize_panel_keys()
#
# assert_required_cols(df_raw_quarterly, c("adm_cd", "year", "quarter", "sales_amount", "sales_count"))

## 4-2. Publish quarterly flow and level sources --------------------------------
# quarterly_sales <- quarterize_flow(
#   df = df_raw_quarterly,
#   value_cols = c("sales_amount", "sales_count")
# )
#
# quarterly_floating <- quarterize_level(
#   df = df_raw_quarterly,
#   value_cols = c("floating_pop", "age60_floating_share"),
#   weight_col = "floating_pop"
# )

## 4-3. Read annual or static source directly ----------------------------------
# df_raw_annual <- read_csv_kr(fs::path(dir_raw, "seoul_resident_annual.csv")) |>
#   janitor::clean_names() |>
#   standardize_panel_keys() |>
#   dplyr::select(adm_cd, year, resident_pop, age60_resident_share)

## 4-4. Build quarterly panel grid ------------------------------------------------
# panel_grid <- tidyr::expand_grid(
#   adm_cd = sort(unique(df_raw_annual$adm_cd)),
#   cfg$quarter_sequence
# )

## 4-5. Join quarterly and year/static sources ---------------------------------
# panel_base <- panel_grid |>
#   dplyr::left_join(quarterly_sales, by = c("adm_cd", "year", "quarter", "yq")) |>
#   dplyr::left_join(quarterly_floating, by = c("adm_cd", "year", "quarter", "yq")) |>
#   dplyr::left_join(df_raw_annual, by = c("adm_cd", "year"))
#
# validate_panel_keys(panel_base)

## 4-6. Add shared quarterly transforms -------------------------------------------
# panel_base <- panel_base |>
#   dplyr::mutate(
#     covid_period = dplyr::if_else(
#       yq >= covid_start_yq & yq <= covid_end_yq,
#       1L,
#       0L
#     ),
#     ln_total_sales = safe_log1p(sales_amount),
#     ln_floating_pop = safe_log1p(floating_pop),
#     ln_external_inflow_pop = safe_log1p(external_inflow_pop),
#     ln_resident_pop = safe_log1p(resident_pop)
#   )

## 4-7. Publish quarterly outputs -------------------------------------------------
# path_quarter_base <- fs::path(dir_analysis_ready, "seoul_quarter_base.parquet")
# path_panel_merged <- fs::path(dir_panel, "panel_merged_base.parquet")
# path_panel_pre <- fs::path(dir_panel, "panel_main_pre_vitality.parquet")
# path_agg_qc <- fs::path(dir_logs, "panel_quarter_aggregation_qc.csv")
#
# write_parquet_safe(panel_base, path_quarter_base)
# write_parquet_safe(panel_base, path_panel_merged)
# write_parquet_safe(panel_base, path_panel_pre)
# write_csv_safe(summarize_missingness(panel_base), path_agg_qc)

#==============================================================================
# 5. Template reminders
#==============================================================================

# - active publication key는 `adm_cd x yq`다.
# - 분기 raw는 quarterly publication helper를 거쳐 active panel에 남긴다.
# - additive flow와 level-share를 같은 함수로 집계하지 않는다.
# - canonical shared panel은 동시점 quarterly contract만 유지한다.
# - legacy shift/lead overlays are excluded unless explicitly reopened as appendix diagnostics.
