#==============================================================================
# Script    : utils_qc.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Centralize column, key, and missingness checks so that all
#             scripts enforce the same panel-data contracts.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-02-28
# Type      : utility
# Inputs    : data frames and expected column/key definitions
# Outputs   : validation side effects or summary tables
# DependsOn : dplyr, stringr, tibble
#==============================================================================

#==============================================================================
# 1. Schema Validation
#==============================================================================

assert_required_cols <- function(df, cols, name = deparse(substitute(df))) {
  # Enforce the most basic dataset contract before downstream joins or models
  # can silently operate on a drifted schema.
  miss <- setdiff(cols, names(df))
  if (length(miss) > 0) {
    stop(sprintf("[ERROR] %s missing columns: %s", name, paste(miss, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}


#==============================================================================
# 2. Key Standardization
#==============================================================================

standardize_keys <- function(df) {
  # Raw sources use slightly different administrative code aliases. Normalize
  # them early so all joins operate on one canonical key set.
  # This helper standardizes both names and types, including `adm_cd` padding
  # and integer year/quarter fields.
  nm <- names(df)
  map <- c(
    adm_cd = "adm_cd", adm_code = "adm_cd", admdong_cd = "adm_cd", dong_cd = "adm_cd",
    std_dong_cd = "adm_cd", year = "year", quarter = "quarter", qtr = "quarter"
  )
  new_nm <- map[nm]
  new_nm[is.na(new_nm)] <- nm[is.na(new_nm)]
  names(df) <- new_nm

  if ("adm_cd" %in% names(df)) {
    df$adm_cd <- stringr::str_pad(as.character(df$adm_cd), width = 10, side = "left", pad = "0")
  }
  if ("year" %in% names(df)) df$year <- suppressWarnings(as.integer(df$year))
  if ("quarter" %in% names(df)) df$quarter <- suppressWarnings(as.integer(df$quarter))
  df
}

make_yq <- function(year, quarter) {
  # active quarterly panel key helper.
  sprintf("%dQ%d", as.integer(year), as.integer(quarter))
}


#==============================================================================
# 3. Panel Quality Checks
#==============================================================================

validate_panel_keys <- function(df, keys = c("adm_cd", "yq")) {
  # The active canonical panel must have unique keys; duplicates would inflate
  # model samples or distort grouped summaries.
  assert_required_cols(df, keys)
  dups <- df |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(n > 1)

  if (nrow(dups) > 0) {
    stop(sprintf("[ERROR] duplicated panel keys: %d", nrow(dups)), call. = FALSE)
  }
  invisible(TRUE)
}

validate_quarter_panel_keys <- function(df, keys = c("adm_cd", "year", "quarter")) {
  # quarterly staging and active quarterly panel helper.
  validate_panel_keys(df, keys = keys)
}

summarize_missing <- function(df) {
  # Return missingness in a long, export-ready format for QC CSVs and logs.
  tibble::tibble(
    variable = names(df),
    n_missing = vapply(df, function(x) sum(is.na(x)), numeric(1)),
    pct_missing = vapply(df, function(x) mean(is.na(x)), numeric(1))
  ) |>
    dplyr::arrange(dplyr::desc(pct_missing), dplyr::desc(n_missing))
}
