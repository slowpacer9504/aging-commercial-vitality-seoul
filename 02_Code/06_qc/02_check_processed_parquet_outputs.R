#==============================================================================
# Script    : 02_check_processed_parquet_outputs.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Audit processed parquet outputs for readability, schema coverage,
#             key integrity, and quarterly-contract compliance.
# Author    : Codex
# Created   : 2026-02-28
# Type      : qc
# Inputs    : all parquet files under 01_Data/03_Processed_Data
# Outputs   : processed_parquet_inventory.csv, processed_parquet_schema.csv,
#             processed_parquet_missing_summary.csv,
#             processed_parquet_qc_checks.csv
# DependsOn : manual post-run QC step
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
load_project_packages()
ensure_dirs(cfg$required_dirs)

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 02_check_processed_parquet_outputs", timestamp()))

out_inventory <- file.path(cfg$dir_logs, "processed_parquet_inventory.csv")
out_schema <- file.path(cfg$dir_logs, "processed_parquet_schema.csv")
out_missing <- file.path(cfg$dir_logs, "processed_parquet_missing_summary.csv")
out_checks <- file.path(cfg$dir_logs, "processed_parquet_qc_checks.csv")

processed_root <- cfg$dir_processed
parquet_paths <- list.files(processed_root, recursive = TRUE, full.names = TRUE, pattern = "[.]parquet$")
parquet_paths <- parquet_paths[!grepl("[.]DS_Store$", parquet_paths)]
parquet_paths <- sort(unique(parquet_paths))


#==============================================================================
# 1. Helpers
#==============================================================================

add_check <- function(id, pass = NULL, detail = "", status = NULL) {
  st <- status
  if (is.null(st)) st <- if (isTRUE(pass)) "PASS" else "FAIL"
  tibble::tibble(
    created_at = timestamp(),
    check_id = as.character(id),
    status = as.character(st),
    detail = as.character(detail)
  )
}

safe_nrow <- function(df) {
  out <- suppressWarnings(as.integer(nrow(df)))
  ifelse(is.na(out), NA_integer_, out)
}

safe_ncol <- function(df) {
  out <- suppressWarnings(as.integer(ncol(df)))
  ifelse(is.na(out), NA_integer_, out)
}

safe_schema <- function(df, file_path) {
  tibble::tibble(
    file_path = file_path,
    column_name = names(df),
    column_class = vapply(df, function(x) paste(class(x), collapse = "|"), character(1))
  )
}

safe_missing_summary <- function(df, file_path) {
  n <- nrow(df)
  miss <- vapply(df, function(x) sum(is.na(x)), numeric(1))
  tibble::tibble(
    file_path = file_path,
    variable = names(df),
    non_missing_n = as.integer(n - miss),
    missing_n = as.integer(miss),
    missing_share = if (is.finite(n) && n > 0) miss / n else NA_real_
  )
}

profile_one <- function(path) {
  rel <- fs::path_rel(path, start = processed_root)
  top <- stringr::str_split_fixed(rel, "/", 2)[1]

  info <- file.info(path)
  base_info <- tibble::tibble(
    file_path = path,
    rel_path = rel,
    tier = top,
    size_bytes = suppressWarnings(as.numeric(info$size[[1]])),
    mtime = as.character(info$mtime[[1]])
  )

  obj <- tryCatch(
    arrow::read_parquet(path) |> tibble::as_tibble(),
    error = function(e) e
  )

  if (inherits(obj, "error")) {
    inv <- base_info |>
      dplyr::mutate(
        read_status = "FAIL",
        n_rows = NA_integer_,
        n_cols = NA_integer_,
        has_adm_cd = FALSE,
        has_year = FALSE,
        has_quarter = FALSE,
        has_yq = FALSE,
        error_message = as.character(obj$message)
      )
    return(list(inventory = inv, schema = tibble::tibble(), missing = tibble::tibble(), data = NULL))
  }

  inv <- base_info |>
    dplyr::mutate(
      read_status = "PASS",
      n_rows = safe_nrow(obj),
      n_cols = safe_ncol(obj),
      has_adm_cd = "adm_cd" %in% names(obj),
      has_year = "year" %in% names(obj),
      has_quarter = "quarter" %in% names(obj),
      has_yq = "yq" %in% names(obj),
      error_message = NA_character_
    )

  list(
    inventory = inv,
    schema = safe_schema(obj, path),
    missing = safe_missing_summary(obj, path),
    data = obj
  )
}

dup_count <- function(df, keys) {
  if (is.null(df) || !all(keys %in% names(df))) return(NA_integer_)
  df |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(n > 1L) |>
    nrow() |>
    as.integer()
}

range_check <- function(df, y_min_target = cfg$short_start, y_max_target = cfg$short_end) {
  if (is.null(df)) {
    return(list(pass = FALSE, detail = "data missing"))
  }
  if ("yq" %in% names(df)) {
    observed <- sort(unique(stats::na.omit(as.character(df$yq))))
    expected <- sort(unique(as.character(cfg$quarter_sequence$yq)))
    return(list(
      pass = identical(observed, expected),
      detail = sprintf(
        "observed_yq=%s; expected_yq=%s",
        if (length(observed) == 0L) "none" else paste(observed, collapse = ", "),
        paste(expected, collapse = ", ")
      )
    ))
  }
  if (!"year" %in% names(df)) {
    return(list(pass = FALSE, detail = "year/yq column missing"))
  }
  years <- sort(unique(stats::na.omit(as.integer(df$year))))
  expected <- y_min_target:y_max_target
  list(
    pass = identical(years, expected),
    detail = sprintf(
      "observed_years=%s; expected_years=%s",
      if (length(years) == 0L) "none" else paste(years, collapse = ", "),
      paste(expected, collapse = ", ")
    )
  )
}

quarterly_contract_check <- function(df, name) {
  if (is.null(df)) {
    return(list(
      range = list(pass = FALSE, detail = sprintf("%s missing", name)),
      dup = list(pass = FALSE, detail = sprintf("%s missing", name)),
      time_cols = list(pass = FALSE, detail = sprintf("%s missing", name))
    ))
  }

  period_range <- range_check(df)
  dup_n <- dup_count(df, c("adm_cd", "yq"))
  missing_time_cols <- setdiff(c("year", "quarter", "yq", "quarter_index"), names(df))
  list(
    range = list(pass = period_range$pass, detail = sprintf("%s %s", name, period_range$detail)),
    dup = list(pass = !is.na(dup_n) && dup_n == 0L, detail = sprintf("%s dup(adm_cd,yq)=%s", name, dup_n)),
    time_cols = list(
      pass = length(missing_time_cols) == 0L,
      detail = sprintf(
        "%s missing quarterly time cols=%s",
        name,
        if (length(missing_time_cols) == 0L) "none" else paste(missing_time_cols, collapse = ", ")
      )
    )
  )
}

get_df <- function(name, data_map) {
  x <- data_map[[name]]
  if (is.null(x)) return(NULL)
  x
}


#==============================================================================
# 2. Collect Inventory and Schema
#==============================================================================

profiles <- purrr::map(parquet_paths, profile_one)
inventory <- dplyr::bind_rows(purrr::map(profiles, "inventory"))
schema_tbl <- dplyr::bind_rows(purrr::map(profiles, "schema"))
missing_tbl <- dplyr::bind_rows(purrr::map(profiles, "missing"))
data_map <- rlang::set_names(
  purrr::map(profiles, "data"),
  nm = vapply(parquet_paths, function(p) basename(p), character(1))
)

if (nrow(inventory) == 0L) {
  inventory <- tibble::tibble(
    file_path = character(0),
    rel_path = character(0),
    tier = character(0),
    size_bytes = numeric(0),
    mtime = character(0),
    read_status = character(0),
    n_rows = integer(0),
    n_cols = integer(0),
    has_adm_cd = logical(0),
    has_year = logical(0),
    has_quarter = logical(0),
    has_yq = logical(0),
    error_message = character(0)
  )
}

if (nrow(schema_tbl) == 0L) {
  schema_tbl <- tibble::tibble(file_path = character(0), column_name = character(0), column_class = character(0))
}

if (nrow(missing_tbl) == 0L) {
  missing_tbl <- tibble::tibble(
    file_path = character(0),
    variable = character(0),
    non_missing_n = integer(0),
    missing_n = integer(0),
    missing_share = numeric(0)
  )
}


#==============================================================================
# 3. Run Core Checks
#==============================================================================

checks <- list()

checks[[length(checks) + 1L]] <- add_check(
  "P01",
  pass = nrow(inventory) > 0L,
  detail = sprintf("parquet files found=%d under %s", nrow(inventory), processed_root)
)

read_fail_n <- sum(inventory$read_status == "FAIL", na.rm = TRUE)
checks[[length(checks) + 1L]] <- add_check("P02", pass = read_fail_n == 0L, detail = sprintf("read failures=%d", read_fail_n))

core_files <- c(
  "seoul_raw_integrated_wide.parquet",
  "seoul_raw_review.parquet",
  "seoul_quarter_base.parquet",
  "adm_region_lookup.parquet",
  "aux_covariates.parquet",
  "registered_resident_population.parquet",
  "golmok_survival_rate.parquet",
  "walk_betweenness_local800_len_v1.parquet",
  "medical_source_preagg.parquet",
  "mall_source_preagg.parquet",
  "senior_source_preagg.parquet",
  "bus_stop_source_preagg.parquet",
  "subway_station_source_preagg.parquet",
  "panel_merged_base.parquet",
  "panel_main_pre_vitality.parquet",
  "panel_main.parquet",
  "vitality_components.parquet"
)

for (ii in seq_along(core_files)) {
  nm <- core_files[[ii]]
  cnt <- sum(basename(inventory$file_path) == nm, na.rm = TRUE)
  checks[[length(checks) + 1L]] <- add_check(
    sprintf("PCF%02d", ii),
    pass = cnt == 1L,
    detail = sprintf("%s count=%d", nm, cnt)
  )
}

obsolete_panel_cnt <- sum(basename(inventory$file_path) %in% basename(cfg$obsolete_panel_paths), na.rm = TRUE)
checks[[length(checks) + 1L]] <- add_check(
  "P18A",
  status = if (obsolete_panel_cnt == 0L) "PASS" else "WARN",
  detail = sprintf("obsolete slim-panel files count=%d", obsolete_panel_cnt)
)

df_seoul_raw_wide <- get_df("seoul_raw_integrated_wide.parquet", data_map)
if (!is.null(df_seoul_raw_wide)) {
  raw_has_time <- all(c("year", "quarter") %in% names(df_seoul_raw_wide))
  raw_range <- range_check(df_seoul_raw_wide)
  raw_dup_n <- dup_count(df_seoul_raw_wide, c("adm_cd", "year", "quarter", "source_type", "service_industry_code"))

  checks[[length(checks) + 1L]] <- add_check(
    "P23A",
    pass = raw_has_time,
    detail = sprintf("seoul_raw_integrated_wide has year/quarter=%s", raw_has_time)
  )
  checks[[length(checks) + 1L]] <- add_check(
    "P23B",
    pass = raw_range$pass,
    detail = sprintf("seoul_raw_integrated_wide %s", raw_range$detail)
  )
  checks[[length(checks) + 1L]] <- add_check(
    "P23C",
    pass = !is.na(raw_dup_n) && raw_dup_n == 0L,
    detail = sprintf("seoul_raw_integrated_wide dup(adm_cd,year,quarter,source_type,service_industry_code)=%s", raw_dup_n)
  )
}

quarterly_targets <- c(
  "seoul_quarter_base.parquet",
  "aux_covariates.parquet",
  "registered_resident_population.parquet",
  "golmok_survival_rate.parquet",
  "panel_merged_base.parquet",
  "panel_main_pre_vitality.parquet",
  "panel_main.parquet",
  "vitality_components.parquet"
)

for (ii in seq_along(quarterly_targets)) {
  nm <- quarterly_targets[[ii]]
  checks_set <- quarterly_contract_check(get_df(nm, data_map), nm)
  checks[[length(checks) + 1L]] <- add_check(sprintf("PQY%02dA", ii), pass = checks_set$range$pass, detail = checks_set$range$detail)
  checks[[length(checks) + 1L]] <- add_check(sprintf("PQY%02dB", ii), pass = checks_set$dup$pass, detail = checks_set$dup$detail)
  checks[[length(checks) + 1L]] <- add_check(sprintf("PQY%02dC", ii), pass = checks_set$time_cols$pass, detail = checks_set$time_cols$detail)
}

df_adm_region_lookup <- get_df("adm_region_lookup.parquet", data_map)
if (!is.null(df_adm_region_lookup)) {
  adm_region_checks <- summarise_adm_region_lookup_qc(df_adm_region_lookup) |>
    dplyr::mutate(check_id = paste0("PAR_", .data$check_id))
  for (ii in seq_len(nrow(adm_region_checks))) {
    checks[[length(checks) + 1L]] <- add_check(
      adm_region_checks$check_id[[ii]],
      status = adm_region_checks$status[[ii]],
      detail = adm_region_checks$detail[[ii]]
    )
  }
}

df_panel_main <- get_df("panel_main.parquet", data_map)
if (!is.null(df_panel_main)) {
  required_cols <- c("age60_resident_share", "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability", "vitality_index_base")
  missing_cols <- setdiff(required_cols, names(df_panel_main))
  forbidden_temporal_cols <- grep("(_l[0-9]+$|_f[0-9]+$|_yoy$)", names(df_panel_main), value = TRUE)

  checks[[length(checks) + 1L]] <- add_check(
    "PAY06A",
    pass = length(missing_cols) == 0L,
    detail = sprintf("panel_main missing quarterly canonical cols=%s", if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "))
  )
  checks[[length(checks) + 1L]] <- add_check(
    "PAY06B",
    pass = length(forbidden_temporal_cols) == 0L,
    detail = sprintf("panel_main forbidden temporal cols=%s", if (length(forbidden_temporal_cols) == 0L) "none" else paste(forbidden_temporal_cols, collapse = ", "))
  )
}


#==============================================================================
# 4. Save QC Outputs
#==============================================================================

checks_tbl <- dplyr::bind_rows(checks)

write_csv_safe(inventory, out_inventory)
write_csv_safe(schema_tbl, out_schema)
write_csv_safe(missing_tbl, out_missing)
write_csv_safe(checks_tbl, out_checks)

append_log(cfg$logs$data_qc, sprintf("- Processed parquet inventory: %s (files=%d)", basename(out_inventory), nrow(inventory)))
append_log(cfg$logs$data_qc, sprintf("- Processed parquet schema: %s (rows=%d)", basename(out_schema), nrow(schema_tbl)))
append_log(cfg$logs$data_qc, sprintf("- Processed parquet missing summary: %s (rows=%d)", basename(out_missing), nrow(missing_tbl)))
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Processed parquet QC checks: %s (PASS=%d, FAIL=%d, WARN=%d)",
    basename(out_checks),
    sum(checks_tbl$status == "PASS", na.rm = TRUE),
    sum(checks_tbl$status == "FAIL", na.rm = TRUE),
    sum(checks_tbl$status == "WARN", na.rm = TRUE)
  )
)
