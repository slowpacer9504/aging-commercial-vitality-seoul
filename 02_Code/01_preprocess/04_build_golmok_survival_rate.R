#==============================================================================
# Script    : 04_build_golmok_survival_rate.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Download Seoul Commercial District Service new-enterprise
#             survival-rate JSON and publish an adm_cd-year annual layer.
# Author    : Codex
# Created   : 2026-05-04
# Type      : preprocessing
# Inputs    : Seoul Commercial District Service selectSurvivalRate JSON,
#             seoul_year_base.parquet
# Outputs   : golmok_survival_rate.parquet,
#             golmok_survival_all_levels.parquet,
#             golmok_survival_rate_qc.csv
# DependsOn : 02_build_seoul_year_base.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
load_project_packages(extra = c("httr", "jsonlite"))
ensure_dirs(cfg$required_dirs)

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 04_build_golmok_survival_rate", timestamp()))

if (!file.exists(cfg$paths$year_base)) {
  stop(sprintf("[ERROR] Missing required input: %s", cfg$paths$year_base), call. = FALSE)
}


#==============================================================================
# 1. Helpers
#==============================================================================

to_num <- function(x) {
  x <- as.character(x)
  x[x %in% c("", "-", "NA", "NaN", "null", "NULL")] <- NA_character_
  x <- gsub(",", "", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

get_col <- function(df, col) {
  if (col %in% names(df)) return(df[[col]])
  rep(NA_character_, nrow(df))
}

make_block <- function(df, prefix, year_value) {
  tibble::tibble(
    cd = as.character(get_col(df, "CD")),
    nm = as.character(get_col(df, "NM")),
    gubun = as.character(get_col(df, "GUBUN")),
    year = as.integer(year_value),
    survival_1y = to_num(get_col(df, paste0(prefix, "_1Y"))),
    survival_1y_survived = to_num(get_col(df, paste0(prefix, "_1Y_MOL"))),
    survival_1y_cohort = to_num(get_col(df, paste0(prefix, "_1Y_DEN"))),
    survival_3y = to_num(get_col(df, paste0(prefix, "_3Y"))),
    survival_3y_survived = to_num(get_col(df, paste0(prefix, "_3Y_MOL"))),
    survival_3y_cohort = to_num(get_col(df, paste0(prefix, "_3Y_DEN"))),
    survival_5y = to_num(get_col(df, paste0(prefix, "_5Y"))),
    survival_5y_survived = to_num(get_col(df, paste0(prefix, "_5Y_MOL"))),
    survival_5y_cohort = to_num(get_col(df, paste0(prefix, "_5Y_DEN")))
  )
}

parse_survival_response <- function(df, base_year) {
  dplyr::bind_rows(
    make_block(df, "FIRST", base_year - 2L),
    make_block(df, "SECOND", base_year - 1L),
    make_block(df, "THIRD", base_year)
  )
}

json_to_tibble <- function(txt, raw_path) {
  x <- jsonlite::fromJSON(txt, flatten = TRUE)
  if (is.data.frame(x)) return(tibble::as_tibble(x))

  if (is.list(x)) {
    df_idx <- which(vapply(x, is.data.frame, logical(1)))
    if (length(df_idx) >= 1L) return(tibble::as_tibble(x[[df_idx[[1L]]]]))
  }

  stop(sprintf("[ERROR] Could not parse survival JSON as a table: %s", raw_path), call. = FALSE)
}

fetch_survival_rate <- function(base_year, quarter = cfg$golmok_survival_quarter) {
  stdr_mn_cd <- sprintf("%d%02d", as.integer(base_year), as.integer(quarter) * 3L)
  raw_path <- file.path(
    cfg$dir_golmok_survival_json,
    sprintf("survival_%d_q%d.json", as.integer(base_year), as.integer(quarter))
  )

  headers <- c(
    "Content-Type" = "application/x-www-form-urlencoded; charset=UTF-8",
    "Accept" = "application/json, text/javascript, */*; q=0.01",
    "Origin" = "https://golmok.seoul.go.kr",
    "Referer" = "https://golmok.seoul.go.kr/stateArea.do",
    "X-Requested-With" = "XMLHttpRequest",
    "User-Agent" = "Mozilla/5.0"
  )
  if (nzchar(cfg$golmok_survival_cookie)) {
    headers <- c(headers, "Cookie" = cfg$golmok_survival_cookie)
  }

  form_body <- list(
    stdrYyCd = as.character(base_year),
    stdrSlctQu = "sameQu",
    stdrQuCd = as.character(quarter),
    stdrMnCd = stdr_mn_cd,
    selectTerm = "quarter",
    svcIndutyCdL = "CS000000",
    svcIndutyCdM = "all",
    stdrSigngu = "11",
    selectInduty = "1",
    infoCategory = "survival"
  )

  message(sprintf("[golmok_survival] requesting base_year=%d quarter=%d", base_year, quarter))
  resp <- httr::POST(
    cfg$golmok_survival_endpoint,
    httr::add_headers(.headers = headers),
    body = form_body,
    encode = "form"
  )

  status <- httr::status_code(resp)
  txt <- httr::content(resp, as = "text", encoding = "UTF-8")
  write_txt_safe(txt, raw_path)

  if (status < 200L || status >= 300L) {
    stop(sprintf("[ERROR] Survival request failed: base_year=%d status=%d raw=%s", base_year, status, raw_path), call. = FALSE)
  }
  if (!grepl("^\\s*(\\[|\\{)", txt)) {
    stop(sprintf("[ERROR] Survival endpoint did not return JSON: base_year=%d raw=%s", base_year, raw_path), call. = FALSE)
  }

  parsed <- json_to_tibble(txt, raw_path)
  list(
    data = parse_survival_response(parsed, as.integer(base_year)),
    manifest = tibble::tibble(
      base_year = as.integer(base_year),
      quarter = as.integer(quarter),
      raw_json_path = raw_path,
      http_status = as.integer(status),
      source_rows = nrow(parsed),
      parsed_rows = nrow(parsed) * 3L,
      status = "success"
    )
  )
}

write_txt_safe <- function(txt, path) {
  with_atomic_write(path, function(tmp) writeLines(txt, tmp, useBytes = TRUE))
}

validate_survival_rates <- function(df) {
  validate_panel_keys(df, c("adm_cd", "year"))
  forbidden_cols <- intersect(c("quarter", "yq"), names(df))
  if (length(forbidden_cols) > 0L) {
    stop(sprintf("[ERROR] survival annual layer has forbidden columns: %s", paste(forbidden_cols, collapse = ", ")), call. = FALSE)
  }

  rate_cols <- intersect(c("survival_1y", "survival_3y", "survival_5y"), names(df))
  out_of_range <- vapply(
    rate_cols,
    function(v) sum(is.finite(df[[v]]) & (df[[v]] < 0 | df[[v]] > 100)),
    integer(1)
  )
  if (any(out_of_range > 0L)) {
    stop(
      sprintf(
        "[ERROR] survival rate out of 0-100 range: %s",
        paste(sprintf("%s=%d", names(out_of_range), out_of_range), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

ratio_diff <- function(df, rate_col, survived_col, cohort_col) {
  if (!all(c(rate_col, survived_col, cohort_col) %in% names(df))) return(NA_real_)
  valid <- is.finite(df[[rate_col]]) & is.finite(df[[survived_col]]) & is.finite(df[[cohort_col]]) & df[[cohort_col]] > 0
  if (!any(valid)) return(NA_real_)
  max(abs(df[[rate_col]][valid] - round(100 * df[[survived_col]][valid] / df[[cohort_col]][valid], 1)), na.rm = TRUE)
}

write_qc <- function(survival_dong, request_manifest, source_mode) {
  expected_rows <- nrow(arrow::read_parquet(cfg$paths$year_base, col_select = tidyselect::all_of(c("adm_cd", "year"))))
  qc <- tibble::tibble(
    run_ts = timestamp(),
    source_mode = source_mode,
    rows = nrow(survival_dong),
    expected_rows = expected_rows,
    adm_n = dplyr::n_distinct(survival_dong$adm_cd),
    year_min = suppressWarnings(min(survival_dong$year, na.rm = TRUE)),
    year_max = suppressWarnings(max(survival_dong$year, na.rm = TRUE)),
    key_dup_n = survival_dong |>
      dplyr::count(adm_cd, year, name = "n") |>
      dplyr::filter(n > 1L) |>
      nrow(),
    survival_3y_missing_n = sum(is.na(survival_dong$survival_3y)),
    survival_3y_out_of_range_n = sum(is.finite(survival_dong$survival_3y) & (survival_dong$survival_3y < 0 | survival_dong$survival_3y > 100)),
    survival_3y_cohort_lt10_n = sum(is.finite(survival_dong$survival_3y_cohort) & survival_dong$survival_3y_cohort < 10),
    survival_3y_cohort_lt30_n = sum(is.finite(survival_dong$survival_3y_cohort) & survival_dong$survival_3y_cohort < 30),
    max_abs_diff_1y = ratio_diff(survival_dong, "survival_1y", "survival_1y_survived", "survival_1y_cohort"),
    max_abs_diff_3y = ratio_diff(survival_dong, "survival_3y", "survival_3y_survived", "survival_3y_cohort"),
    max_abs_diff_5y = ratio_diff(survival_dong, "survival_5y", "survival_5y_survived", "survival_5y_cohort"),
    request_success_n = sum(request_manifest$status == "success", na.rm = TRUE),
    raw_json_n = sum(file.exists(request_manifest$raw_json_path))
  )
  write_csv_safe(qc, cfg$logs$golmok_survival_rate_qc)
  qc
}


#==============================================================================
# 2. Reuse Existing Output When Allowed
#==============================================================================

skip_survival_build <- FALSE
if (file.exists(cfg$paths$golmok_survival_rate) && !isTRUE(cfg$golmok_survival_force_rebuild)) {
  survival_reused <- arrow::read_parquet(cfg$paths$golmok_survival_rate) |>
    tibble::as_tibble() |>
    standardize_keys()
  validate_survival_rates(survival_reused)
  reused_raw_json <- list.files(cfg$dir_golmok_survival_json, full.names = TRUE, pattern = "[.]json$")
  reused_manifest <- if (length(reused_raw_json) == 0L) {
    tibble::tibble(status = character(0), raw_json_path = character(0))
  } else {
    tibble::tibble(status = rep("success", length(reused_raw_json)), raw_json_path = reused_raw_json)
  }
  qc <- write_qc(
    survival_reused,
    reused_manifest,
    "reused"
  )
  append_log(
    cfg$logs$data_qc,
    sprintf("- Golmok survival layer reused: %s (rows=%d, missing_3y=%d)", basename(cfg$paths$golmok_survival_rate), nrow(survival_reused), qc$survival_3y_missing_n)
  )
  message(sprintf("[DONE] reused %s rows=%d", basename(cfg$paths$golmok_survival_rate), nrow(survival_reused)))
  skip_survival_build <- TRUE
}


#==============================================================================
# 3. Fetch, Parse, Align to Annual Panel, and Publish
#==============================================================================

if (!isTRUE(skip_survival_build)) {
  requests <- purrr::map(cfg$golmok_survival_base_years, fetch_survival_rate)
  request_manifest <- dplyr::bind_rows(purrr::map(requests, "manifest"))
  survival_all <- dplyr::bind_rows(purrr::map(requests, "data")) |>
    dplyr::mutate(
      cd = stringr::str_trim(cd),
      nm = stringr::str_trim(nm),
      gubun = stringr::str_trim(gubun)
    )

  write_parquet_safe(survival_all, cfg$paths$golmok_survival_all_levels)

  survival_dong <- survival_all |>
    dplyr::filter(year %in% cfg$golmok_survival_study_years, stringr::str_length(cd) == 8L) |>
    dplyr::transmute(
      adm_cd = stringr::str_pad(cd, width = 10, side = "left", pad = "0"),
      year,
      survival_area_name = nm,
      survival_area_gubun = gubun,
      survival_1y,
      survival_1y_survived,
      survival_1y_cohort,
      survival_3y,
      survival_3y_survived,
      survival_3y_cohort,
      survival_5y,
      survival_5y_survived,
      survival_5y_cohort
    ) |>
    dplyr::arrange(adm_cd, year)

  if (nrow(survival_dong) == 0L) {
    gubun_summary <- survival_all |>
      dplyr::count(gubun, code_length = stringr::str_length(cd), name = "n") |>
      dplyr::arrange(gubun, code_length)
    stop(
      sprintf(
        "[ERROR] No dong-level survival rows detected. Code-length summary: %s",
        paste(sprintf("%s/%s=%d", gubun_summary$gubun, gubun_summary$code_length, gubun_summary$n), collapse = "; ")
      ),
      call. = FALSE
    )
  }

  validate_survival_rates(survival_dong)

  year_base_keys <- arrow::read_parquet(cfg$paths$year_base, col_select = tidyselect::all_of(c("adm_cd", "year"))) |>
    tibble::as_tibble() |>
    standardize_keys() |>
    dplyr::distinct(adm_cd, year)
  validate_panel_keys(year_base_keys, c("adm_cd", "year"))

  survival_panel <- year_base_keys |>
    dplyr::left_join(survival_dong, by = c("adm_cd", "year")) |>
    dplyr::arrange(adm_cd, year)

  validate_survival_rates(survival_panel)

  missing_3y <- sum(is.na(survival_panel$survival_3y))
  if (missing_3y > 0L) {
    message(sprintf("[WARN] survival_3y missing after panel alignment: %d rows; retained as NA and logged in QC", missing_3y))
  }

  diff_3y <- ratio_diff(survival_panel, "survival_3y", "survival_3y_survived", "survival_3y_cohort")
  if (is.finite(diff_3y) && diff_3y > 0.2) {
    stop(sprintf("[ERROR] survival_3y ratio check failed: max abs diff=%.3f", diff_3y), call. = FALSE)
  }

  write_parquet_safe(survival_panel, cfg$paths$golmok_survival_rate)
  qc <- write_qc(survival_panel, request_manifest, "fetched")

  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Golmok survival layer published: %s (rows=%d, adm_n=%d, years=%d-%d, survival_3y_missing=%d)",
      basename(cfg$paths$golmok_survival_rate),
      nrow(survival_panel),
      dplyr::n_distinct(survival_panel$adm_cd),
      min(survival_panel$year, na.rm = TRUE),
      max(survival_panel$year, na.rm = TRUE),
      qc$survival_3y_missing_n
    )
  )

  message(sprintf("[DONE] golmok survival annual layer rows=%d", nrow(survival_panel)))
}
