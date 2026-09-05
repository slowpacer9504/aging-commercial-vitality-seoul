#==============================================================================
# Script    : 00_template_preprocessing_aging_commerce.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Project-specific template for quarterly preprocessing, harmonization,
#             and panel construction under the 2020 Seoul administrative-dong rule.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-04-22
# Type      : panel_building
# Inputs    : <RAW_INPUT_FILES>
# Outputs   : <OUTPUT_PANEL_FILES>
# DependsOn : 02_Code/00_setup/config.R (optional)
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# This template shows the expected structure for new quarterly preprocessing
# scripts. The core contract is `adm_cd x yq`, contemporaneous quarterly timing,
# and quarterly raw publication as the active panel's base time unit.

## 0-1. Load config, packages, and shared utilities ----------------------------
# Every canonical preprocessing script opens exactly this way. Sourcing the
# shared utilities rather than redefining their helpers locally is a contract,
# not a convenience: because each script loads its sources into one environment,
# a local copy of a shared helper silently shadows the real one for that whole
# script and the two definitions then drift apart unnoticed
# (r_code_style_guide.md section 10).
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
source(here::here("02_Code", "99_utils", "utils_qc.R"))
source(here::here("02_Code", "99_utils", "utils_transform.R"))

load_project_packages()

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
# 1. IO Helpers
#==============================================================================

# IO helpers are not defined here. `read_csv_kr()`, `write_csv_safe()`,
# `write_parquet_safe()`, and `save_rds_safe()` all come from utils_io.R, which
# section 0-1 sources.
#
# This section used to carry local copies, and each was weaker than the shared
# one in a way that would have travelled into every script written from this
# template. The local writers wrote straight to the destination, so an
# interrupted run left a partial file that the next step would read as valid;
# the shared writers stage to a temporary file in the same directory and promote
# it only after the write succeeds. The local reader defaulted to UTF-8, which
# mangles the CP949 Korean public-data CSVs under 01_Data/01_Raw_Data without
# raising.

#==============================================================================
# 2. Validation Helpers
#==============================================================================

# `assert_required_cols()` and `validate_panel_keys()` come from utils_qc.R, and
# `safe_log1p()` from utils_transform.R. The local copies that used to sit here
# were removed for the reason given in section 1, and one of them had already
# drifted: it defaulted the panel key to `c("adm_cd", "year")`, the retired
# annual contract, where the shared helper defaults to the active `c("adm_cd",
# "yq")`.

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

summarize_missingness <- function(df, vars = names(df)) {
  tibble::tibble(variable = vars) |>
    dplyr::mutate(
      n_missing = purrr::map_int(variable, ~ sum(is.na(df[[.x]]))),
      pct_missing = purrr::map_dbl(variable, ~ mean(is.na(df[[.x]])))
    ) |>
    dplyr::arrange(dplyr::desc(pct_missing), dplyr::desc(n_missing))
}

#==============================================================================
# 3. Quarterly Aggregation Helpers
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
# 4. Example Preprocessing Flow
#==============================================================================

# The following block is an example pattern, not runnable production code. It
# shows the object order and contracts expected in quarterly preprocessing.

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
# 5. Template Reminders
#==============================================================================

# - Active publication key is `adm_cd x yq`.
# - Quarterly raw sources enter the active panel through quarterly publication helpers.
# - Additive flows and level/share variables are not aggregated with the same helper.
# - The canonical shared panel keeps only the contemporaneous quarterly contract.
# - legacy shift/lead overlays are excluded unless explicitly reopened as appendix diagnostics.
