#!/usr/bin/env Rscript

#==============================================================================
# Script    : 01_build_living_population_inflow.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build quarterly external inflow population from Seoul Living
#             Population monthly ZIP sources without extracting raw CSV files.
# Author    : Codex
# Created   : 2026-05-01
# Type      : panel_building
# Inputs    : seoul_quarter_base.parquet, INNER_PEOPLE_YYYYMM.zip,
#             METRO_PEOPLE_YYYYMM.zip
# Outputs   : living_population_external_inflow.parquet,
#             living_population_inflow_manifest.csv,
#             living_population_inflow_qc.csv
# DependsOn : 02_build_seoul_quarter_base.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
load_project_packages(extra = "data.table")

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 01_build_living_population_inflow", timestamp()))

quarter_base_path <- value_or(cfg$paths$quarter_base, file.path(cfg$dir_analysis, "seoul_quarter_base.parquet"))
if (!file.exists(quarter_base_path)) {
  stop("[ERROR] seoul_quarter_base.parquet is required before living-population inflow build", call. = FALSE)
}
if (!dir.exists(cfg$dir_living_population_inner)) {
  stop(sprintf("[ERROR] Living population inner raw directory not found: %s", cfg$dir_living_population_inner), call. = FALSE)
}
if (!dir.exists(cfg$dir_living_population_metro)) {
  stop(sprintf("[ERROR] Living population metro raw directory not found: %s", cfg$dir_living_population_metro), call. = FALSE)
}
if (Sys.which("unzip") == "") stop("[ERROR] shell command not found: unzip", call. = FALSE)
if (Sys.which("zipinfo") == "") stop("[ERROR] shell command not found: zipinfo", call. = FALSE)

base_quarter <- arrow::read_parquet(quarter_base_path, col_select = c("adm_cd", "year", "quarter", "yq", "quarter_index")) |>
  tibble::as_tibble() |>
  standardize_keys() |>
  dplyr::distinct(adm_cd, year, quarter, yq, quarter_index) |>
  dplyr::arrange(adm_cd, year, quarter)
validate_panel_keys(base_quarter, c("adm_cd", "yq"))


#==============================================================================
# 1. Runtime Helpers
#==============================================================================

parse_hours <- function(x) {
  x <- trimws(as.character(x[[1]]))
  if (!nzchar(x)) x <- "0-23"

  pieces <- trimws(unlist(strsplit(x, ",", fixed = TRUE)))
  hours <- integer(0)
  for (piece in pieces[nzchar(pieces)]) {
    if (grepl("^[0-9]{1,2}-[0-9]{1,2}$", piece)) {
      bounds <- as.integer(strsplit(piece, "-", fixed = TRUE)[[1]])
      hours <- c(hours, seq.int(bounds[[1]], bounds[[2]]))
    } else {
      hours <- c(hours, as.integer(piece))
    }
  }

  hours <- sort(unique(hours))
  if (length(hours) == 0L || any(!is.finite(hours)) || any(hours < 0L | hours > 23L)) {
    stop(sprintf("[ERROR] invalid LIVING_POP_HOURS: %s", x), call. = FALSE)
  }
  hours
}

parse_sample_months <- function(x) {
  x <- trimws(as.character(x[[1]]))
  if (!nzchar(x)) return(character(0))
  months <- trimws(unlist(strsplit(x, ",", fixed = TRUE)))
  months <- months[nzchar(months)]
  bad <- months[!grepl("^[0-9]{6}$", months)]
  if (length(bad) > 0L) {
    stop(sprintf("[ERROR] invalid LIVING_POP_SAMPLE_MONTHS values: %s", paste(bad, collapse = ", ")), call. = FALSE)
  }
  sort(unique(months))
}

sample_tag_path <- function(path, sample_months) {
  if (length(sample_months) == 0L) return(path)
  ext <- tools::file_ext(path)
  stem <- tools::file_path_sans_ext(basename(path))
  tag <- paste(sample_months, collapse = "_")
  file.path(dirname(path), sprintf("%s_sample_%s.%s", stem, tag, ext))
}

extract_year_month <- function(path, prefix) {
  out <- sub(sprintf("^%s_([0-9]{6})[.]zip$", prefix), "\\1", basename(path))
  ifelse(grepl("^[0-9]{6}$", out), out, NA_character_)
}

list_monthly_zips <- function(dir, prefix, years, sample_months = character(0)) {
  files <- list.files(dir, pattern = sprintf("^%s_[0-9]{6}[.]zip$", prefix), full.names = TRUE)
  if (length(files) == 0L) return(character(0))

  year_month <- extract_year_month(files, prefix)
  year <- suppressWarnings(as.integer(substr(year_month, 1, 4)))
  keep <- !is.na(year_month) & year %in% years
  if (length(sample_months) > 0L) keep <- keep & year_month %in% sample_months
  files[keep][order(year_month[keep])]
}

zip_members <- function(zip_path) {
  cmd <- sprintf("zipinfo -1 %s", shQuote(zip_path))
  out <- tryCatch(system(cmd, intern = TRUE), error = function(e) character(0))
  out[grepl("[.]csv$", out, ignore.case = TRUE)]
}

build_unzip_cmd <- function(zip_path, member_name, encoding_from = "UTF-8") {
  unzip_cmd <- sprintf("unzip -p %s %s", shQuote(zip_path), shQuote(member_name))
  encoding_from <- toupper(trimws(encoding_from))
  if (encoding_from %in% c("", "UTF-8", "UTF8")) return(unzip_cmd)
  sprintf("%s | iconv -f %s -t UTF-8", unzip_cmd, shQuote(encoding_from))
}

encoding_candidates <- function(encoding_from) {
  enc <- toupper(trimws(as.character(encoding_from[[1]])))
  if (!nzchar(enc)) enc <- "UTF-8"
  unique(c(enc, "UTF-8", "CP949", "EUC-KR"))
}

normalize_living_pop_colname <- function(x) {
  x <- iconv(as.character(x), from = "", to = "UTF-8", sub = "")
  x[is.na(x)] <- ""
  x <- enc2utf8(x)
  x <- gsub("\ufeff", "", x, fixed = TRUE)
  x <- gsub("[\"']", "", x)
  x <- gsub("^\\?+", "", x)
  x <- gsub("^[^[:alnum:]가-힣_]+|[^[:alnum:]가-힣_]+$", "", x, perl = TRUE)
  trimws(x)
}

living_pop_col_aliases <- list(
  "기준일ID" = c("기준일ID", "stdr_de_id"),
  "시간대구분" = c("시간대구분", "tmzon_pd_se"),
  "행정동코드" = c("행정동코드", "adstrd_code_se"),
  "거주지 자치구 코드" = c("거주지 자치구 코드", "mlng_resdnc_code_se"),
  "대도시권거주지코드" = c("대도시권거주지코드", "metro_resdnc_code_se"),
  "총생활인구수" = c("총생활인구수", "tot_lvpop_co")
)

get_living_pop_aliases <- function(col) {
  aliases <- living_pop_col_aliases[[col]]
  if (is.null(aliases)) aliases <- col
  unique(c(col, aliases))
}

resolve_living_pop_columns <- function(actual_cols, usecols) {
  normalized_actual <- normalize_living_pop_colname(actual_cols)
  matched_idx <- vapply(usecols, function(expected_col) {
    normalized_aliases <- normalize_living_pop_colname(get_living_pop_aliases(expected_col))
    hit <- match(normalized_aliases, normalized_actual)
    hit <- hit[!is.na(hit)]
    if (length(hit) == 0L) NA_integer_ else hit[[1L]]
  }, integer(1))

  list(
    selected = actual_cols[matched_idx[!is.na(matched_idx)]],
    canonical = usecols[!is.na(matched_idx)],
    missing = usecols[is.na(matched_idx)]
  )
}

read_member_selected <- function(zip_path, member_name, usecols, encoding_from) {
  errors <- character(0)

  for (enc in encoding_candidates(encoding_from)) {
    cmd <- build_unzip_cmd(zip_path, member_name, enc)

    header <- tryCatch(
      suppressWarnings(
        data.table::fread(
          cmd = cmd,
          nrows = 0L,
          encoding = "UTF-8",
          showProgress = FALSE
        )
      ),
      error = function(e) e
    )

    if (inherits(header, "error")) {
      errors <- c(errors, sprintf("%s header: %s", enc, header$message))
      next
    }

    col_map <- resolve_living_pop_columns(names(header), usecols)
    if (length(col_map$missing) > 0L) {
      errors <- c(
        errors,
        sprintf("%s: missing columns [%s]", enc, paste(col_map$missing, collapse = ", "))
      )
      next
    }

    col_classes <- stats::setNames(rep("character", length(col_map$selected)), col_map$selected)
    dt <- tryCatch(
      suppressWarnings(
        data.table::fread(
          cmd = cmd,
          select = col_map$selected,
          colClasses = col_classes,
          encoding = "UTF-8",
          showProgress = FALSE
        )
      ),
      error = function(e) e
    )

    if (inherits(dt, "error")) {
      errors <- c(errors, sprintf("%s: %s", enc, dt$message))
      next
    }

    data.table::setnames(dt, col_map$selected, col_map$canonical)
    return(list(data = dt, encoding_used = enc, error = NULL))
  }

  list(
    data = NULL,
    encoding_used = NA_character_,
    error = paste(errors, collapse = " | ")
  )
}

clean_code <- function(x, width) {
  x <- trimws(as.character(x))
  x <- sub("[.]0$", "", x)
  x[!nzchar(x)] <- NA_character_
  stringr::str_pad(x, width = width, side = "left", pad = "0")
}

normalize_pop <- function(x, suppressed_value) {
  x_chr <- gsub(",", "", trimws(as.character(x)), fixed = TRUE)
  out <- suppressWarnings(as.numeric(x_chr))
  out[!is.finite(out)] <- suppressed_value
  out
}

make_empty_member_manifest <- function(dataset, zip_path, member_name, year_month, status, error_message = "") {
  data.table::data.table(
    dataset = dataset,
    file_path = zip_path,
    member_name = member_name,
    year_month = year_month,
    encoding_used = NA_character_,
    status = status,
    rows_read = NA_integer_,
    rows_used = NA_integer_,
    n_slots = NA_integer_,
    n_days = NA_integer_,
    month_success_days = NA_integer_,
    month_expected_days = NA_integer_,
    month_coverage_flag = NA_character_,
    error_message = error_message
  )
}

days_in_year_month <- function(year_month) {
  ym <- as.character(year_month[[1]])
  if (!grepl("^[0-9]{6}$", ym)) return(NA_integer_)
  year <- as.integer(substr(ym, 1, 4))
  month <- as.integer(substr(ym, 5, 6))
  if (!is.finite(year) || !is.finite(month) || month < 1L || month > 12L) return(NA_integer_)
  next_year <- if (month == 12L) year + 1L else year
  next_month <- if (month == 12L) 1L else month + 1L
  as.integer(as.Date(sprintf("%04d-%02d-01", next_year, next_month)) - as.Date(sprintf("%04d-%02d-01", year, month)))
}

classify_month_coverage <- function(n_days, expected_days) {
  if (!is.finite(n_days) || n_days <= 0L) return("missing_month")
  if (!is.finite(expected_days) || expected_days <= 0L) return("unknown_expected_days")
  if (n_days >= expected_days) return("complete_month")
  if (n_days >= 20L) return("partial_month_ge20_days")
  if (n_days >= 10L) return("partial_month_10_19_days")
  "partial_month_1_9_days"
}

aggregate_member <- function(zip_path, member_name, dataset, usecols, hours, suppressed_value, encoding_from) {
  year_month <- sub(".*_([0-9]{6}).*", "\\1", basename(zip_path))
  read_out <- read_member_selected(zip_path, member_name, usecols, encoding_from)

  if (!is.null(read_out$error)) {
    return(list(
      result = NULL,
      manifest = make_empty_member_manifest(dataset, zip_path, member_name, year_month, "error", read_out$error)
    ))
  }

  dt <- read_out$data
  rows_read <- nrow(dt)
  data.table::setnames(dt, usecols, c("date_id", "hour", "adm_cd_raw", "origin_code", "pop"))
  dt[, hour := suppressWarnings(as.integer(hour))]
  dt <- dt[hour %in% hours]
  n_days <- data.table::uniqueN(dt$date_id)
  n_slots <- data.table::uniqueN(dt[, paste0(date_id, "_", sprintf("%02d", hour))])

  if (nrow(dt) == 0L || n_slots == 0L) {
    return(list(
      result = NULL,
      manifest = data.table::data.table(
        dataset = dataset,
        file_path = zip_path,
        member_name = member_name,
        year_month = year_month,
        encoding_used = read_out$encoding_used,
        status = "skipped",
        rows_read = rows_read,
        rows_used = 0L,
        n_slots = 0L,
        n_days = 0L,
        month_success_days = NA_integer_,
        month_expected_days = NA_integer_,
        month_coverage_flag = NA_character_,
        error_message = "no rows after hour filter"
      )
    ))
  }

  dt[, adm_cd_8 := clean_code(adm_cd_raw, 8)]
  dt[, adm_cd := clean_code(adm_cd_raw, 10)]
  dt[, year := suppressWarnings(as.integer(substr(date_id, 1, 4)))]
  dt[, year_month := year_month]
  dt[, pop := normalize_pop(pop, suppressed_value)]

  if (identical(dataset, "inner")) {
    dt[, target_sgg := substr(adm_cd_8, 1, 5)]
    dt[, origin_sgg := clean_code(origin_code, 5)]
    dt <- dt[!is.na(origin_sgg) & origin_sgg != target_sgg]
  }

  rows_used <- nrow(dt)
  if (rows_used == 0L) {
    result <- NULL
  } else {
    result <- dt[
      ,
      .(pop_sum = sum(pop, na.rm = TRUE)),
      by = .(year, year_month, adm_cd)
    ]
  }

  list(
    result = result,
    manifest = data.table::data.table(
      dataset = dataset,
      file_path = zip_path,
      member_name = member_name,
      year_month = year_month,
      encoding_used = read_out$encoding_used,
      status = "success",
      rows_read = rows_read,
      rows_used = rows_used,
      n_slots = n_slots,
      n_days = n_days,
      month_success_days = NA_integer_,
      month_expected_days = NA_integer_,
      month_coverage_flag = NA_character_,
      error_message = ""
    )
  )
}

process_zips <- function(files, dataset, usecols, hours, suppressed_value, encoding_from) {
  result_list <- list()
  manifest_list <- list()

  for (i in seq_along(files)) {
    zip_path <- files[[i]]
    members <- zip_members(zip_path)
    if (length(members) == 0L) {
      manifest_list[[length(manifest_list) + 1L]] <- make_empty_member_manifest(
        dataset,
        zip_path,
        NA_character_,
        extract_year_month(zip_path, if (identical(dataset, "inner")) "INNER_PEOPLE" else "METRO_PEOPLE"),
        "error",
        "no csv members in zip"
      )
      next
    }

    message(sprintf("[%s] zip %d/%d: %s (%d daily CSV)", dataset, i, length(files), basename(zip_path), length(members)))
    for (member_name in members) {
      out <- aggregate_member(
        zip_path = zip_path,
        member_name = member_name,
        dataset = dataset,
        usecols = usecols,
        hours = hours,
        suppressed_value = suppressed_value,
        encoding_from = encoding_from
      )
      if (!is.null(out$result) && nrow(out$result) > 0L) {
        result_list[[length(result_list) + 1L]] <- out$result
      }
      manifest_list[[length(manifest_list) + 1L]] <- out$manifest
    }
  }

  result <- if (length(result_list) == 0L) {
    data.table::data.table(year = integer(), year_month = character(), adm_cd = character(), pop_sum = numeric())
  } else {
    data.table::rbindlist(result_list, fill = TRUE)[
      ,
      .(pop_sum = sum(pop_sum, na.rm = TRUE)),
      by = .(year, year_month, adm_cd)
    ]
  }

  manifest <- if (length(manifest_list) == 0L) {
    data.table::data.table(
      dataset = character(), file_path = character(), member_name = character(),
      year_month = character(), encoding_used = character(), status = character(),
      rows_read = integer(), rows_used = integer(), n_slots = integer(),
      n_days = integer(), month_success_days = integer(), month_expected_days = integer(),
      month_coverage_flag = character(),
      error_message = character()
    )
  } else {
    data.table::rbindlist(manifest_list, fill = TRUE)
  }

  if (nrow(manifest) > 0L) {
    month_coverage <- manifest[
      ,
      .(
        month_success_days = sum(n_days[status == "success"], na.rm = TRUE),
        month_expected_days = days_in_year_month(year_month[[1L]])
      ),
      by = .(dataset, year_month)
    ]
    month_coverage[
      ,
      month_coverage_flag := mapply(classify_month_coverage, month_success_days, month_expected_days)
    ]
    manifest[, c("month_success_days", "month_expected_days", "month_coverage_flag") := NULL]
    manifest <- merge(manifest, month_coverage, by = c("dataset", "year_month"), all.x = TRUE)
    data.table::setcolorder(
      manifest,
      c(
        "dataset", "file_path", "member_name", "year_month", "encoding_used", "status",
        "rows_read", "rows_used", "n_slots", "n_days",
        "month_success_days", "month_expected_days", "month_coverage_flag",
        "error_message"
      )
    )
  }

  list(result = result, manifest = manifest)
}

finalize_dataset <- function(base_quarter, aggregate, manifest, dataset, mean_col, slots_col, months_col) {
  years <- sort(unique(base_quarter$year))
  month_tbl <- manifest[
    status == "success",
    .(
      quarter = ceiling(as.integer(substr(year_month, 5, 6)) / 3),
      n_slots_month = sum(n_slots, na.rm = TRUE),
      n_days_month = unique(month_success_days)[[1L]],
      coverage_flag = unique(month_coverage_flag)[[1L]]
    ),
    by = .(year = as.integer(substr(year_month, 1, 4)), year_month)
  ][year %in% years]

  base_dt <- data.table::as.data.table(base_quarter)
  adm_grid <- unique(base_dt[, .(adm_cd)])
  adm_grid[, join_key := 1L]
  month_grid <- month_tbl[, .(year, quarter, year_month, n_slots_month, n_days_month, coverage_flag)]
  month_grid[, join_key := 1L]
  observed_month_grid <- merge(
    adm_grid,
    month_grid,
    by = "join_key",
    allow.cartesian = TRUE
  )[, join_key := NULL]
  monthly <- merge(observed_month_grid, aggregate, by = c("year", "year_month", "adm_cd"), all.x = TRUE)
  monthly[is.na(pop_sum) & is.finite(n_slots_month) & n_slots_month > 0, pop_sum := 0]
  monthly[
    ,
    monthly_mean := data.table::fifelse(
      is.finite(n_slots_month) & n_slots_month > 0,
      pop_sum / n_slots_month,
      NA_real_
    )
  ]
  quarterly <- monthly[
    ,
    .(
      quarter_mean = mean(monthly_mean[is.finite(monthly_mean)], na.rm = TRUE)
    ),
    by = .(year, quarter, adm_cd)
  ]
  quarterly[!is.finite(quarter_mean), quarter_mean := NA_real_]

  slot_tbl <- month_tbl[
    ,
    .(
      n_slots = sum(n_slots_month, na.rm = TRUE),
      n_months = data.table::uniqueN(year_month)
    ),
    by = .(year, quarter)
  ]

  out <- merge(base_dt, quarterly, by = c("year", "quarter", "adm_cd"), all.x = TRUE)
  out <- merge(out, slot_tbl, by = c("year", "quarter"), all.x = TRUE)
  out[, (mean_col) := quarter_mean]
  out[, (slots_col) := n_slots]
  out[, (months_col) := n_months]
  out[, c("quarter_mean", "n_slots", "n_months") := NULL]
  out[]
}


#==============================================================================
# 2. Build Quarterly External Inflow
#==============================================================================

hours <- parse_hours(cfg$living_pop_hours)
sample_months <- parse_sample_months(cfg$living_pop_sample_months)

output_path <- sample_tag_path(cfg$paths$living_population_external_inflow, sample_months)
manifest_path <- sample_tag_path(cfg$logs$living_population_inflow_manifest, sample_months)
qc_path <- sample_tag_path(cfg$logs$living_population_inflow_qc, sample_months)

reuse_existing_output <- file.exists(output_path) && !isTRUE(cfg$living_pop_force_rebuild)

if (reuse_existing_output) {
  append_log(cfg$logs$data_qc, sprintf("- Reusing existing living-population inflow output: %s", basename(output_path)))
  message(sprintf("[SKIP] Existing output reused: %s", output_path))
}

if (!reuse_existing_output) {
  years_target <- sort(unique(base_quarter$year))
  inner_files <- list_monthly_zips(cfg$dir_living_population_inner, "INNER_PEOPLE", years_target, sample_months)
  metro_files <- list_monthly_zips(cfg$dir_living_population_metro, "METRO_PEOPLE", years_target, sample_months)

  if (length(inner_files) == 0L) stop("[ERROR] no INNER_PEOPLE zip files found for requested years", call. = FALSE)
  if (length(metro_files) == 0L) stop("[ERROR] no METRO_PEOPLE zip files found for requested years", call. = FALSE)

  inner_usecols <- c("기준일ID", "시간대구분", "행정동코드", "거주지 자치구 코드", "총생활인구수")
  metro_usecols <- c("기준일ID", "시간대구분", "행정동코드", "대도시권거주지코드", "총생활인구수")

  inner_out <- process_zips(
    files = inner_files,
    dataset = "inner",
    usecols = inner_usecols,
    hours = hours,
    suppressed_value = cfg$living_pop_suppressed_value,
    encoding_from = cfg$living_pop_encoding
  )
  metro_out <- process_zips(
    files = metro_files,
    dataset = "metro",
    usecols = metro_usecols,
    hours = hours,
    suppressed_value = cfg$living_pop_suppressed_value,
    encoding_from = cfg$living_pop_encoding
  )

  inner_quarter <- finalize_dataset(
    base_quarter,
    inner_out$result,
    inner_out$manifest,
    "inner",
    "inner_external_inflow_pop",
    "inner_n_slots",
    "inner_n_months"
  )
  metro_quarter <- finalize_dataset(
    base_quarter,
    metro_out$result,
    metro_out$manifest,
    "metro",
    "metro_external_inflow_pop",
    "metro_n_slots",
    "metro_n_months"
  )

  external <- dplyr::left_join(
    tibble::as_tibble(inner_quarter),
    tibble::as_tibble(metro_quarter),
    by = c("adm_cd", "year", "quarter", "yq", "quarter_index")
  ) |>
    dplyr::mutate(
      external_inflow_pop = dplyr::if_else(
        is.finite(inner_external_inflow_pop) & is.finite(metro_external_inflow_pop),
        inner_external_inflow_pop + metro_external_inflow_pop,
        NA_real_
      )
    ) |>
    dplyr::select(
      adm_cd, year, quarter, yq, quarter_index,
      inner_external_inflow_pop, metro_external_inflow_pop, external_inflow_pop,
      inner_n_slots, metro_n_slots, inner_n_months, metro_n_months
    ) |>
    dplyr::arrange(adm_cd, year, quarter)

  validate_panel_keys(external, c("adm_cd", "yq"))

  manifest <- data.table::rbindlist(list(inner_out$manifest, metro_out$manifest), fill = TRUE) |>
    tibble::as_tibble()

  qc <- external |>
    tidyr::pivot_longer(
      cols = c(inner_external_inflow_pop, metro_external_inflow_pop, external_inflow_pop),
      names_to = "variable",
      values_to = "value"
    ) |>
    dplyr::group_by(variable, yq) |>
    dplyr::summarise(
      row_n = dplyr::n(),
      finite_n = sum(is.finite(value)),
      missing_n = sum(!is.finite(value)),
      mean_value = if (any(is.finite(value))) mean(value[is.finite(value)]) else NA_real_,
      min_value = if (any(is.finite(value))) min(value[is.finite(value)]) else NA_real_,
      max_value = if (any(is.finite(value))) max(value[is.finite(value)]) else NA_real_,
      .groups = "drop"
    )

  if (length(sample_months) == 0L) {
    external_coverage_fail <- qc |>
      dplyr::filter(.data$variable == "external_inflow_pop", .data$finite_n < .data$row_n)
    month_coverage_fail <- external |>
      dplyr::group_by(yq) |>
      dplyr::summarise(
        inner_n_months = max(inner_n_months, na.rm = TRUE),
        metro_n_months = max(metro_n_months, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::filter(.data$inner_n_months < 3L | .data$metro_n_months < 3L)

    if (nrow(external_coverage_fail) > 0L || nrow(month_coverage_fail) > 0L) {
      write_csv_safe(manifest, manifest_path)
      write_csv_safe(qc, qc_path)
      stop(
        sprintf(
          "[ERROR] Living-population external inflow has incomplete quarterly coverage: finite={%s}; months={%s}",
          if (nrow(external_coverage_fail) == 0L) {
            "none"
          } else {
            paste(
              sprintf(
                "%s finite=%d/%d",
                external_coverage_fail$yq,
                external_coverage_fail$finite_n,
                external_coverage_fail$row_n
              ),
              collapse = "; "
            )
          },
          if (nrow(month_coverage_fail) == 0L) {
            "none"
          } else {
            paste(
              sprintf(
                "%s inner_months=%d metro_months=%d",
                month_coverage_fail$yq,
                month_coverage_fail$inner_n_months,
                month_coverage_fail$metro_n_months
              ),
              collapse = "; "
            )
          }
        ),
        call. = FALSE
      )
    }
  }

  write_parquet_safe(external, output_path)
  write_csv_safe(manifest, manifest_path)
  write_csv_safe(qc, qc_path)

  append_log(cfg$logs$data_qc, sprintf("- Living-population inflow output: %s (rows=%d)", basename(output_path), nrow(external)))
  append_log(cfg$logs$data_qc, sprintf("- Living-population manifest: %s (rows=%d)", basename(manifest_path), nrow(manifest)))
  append_log(cfg$logs$data_qc, sprintf("- Living-population QC: %s (rows=%d)", basename(qc_path), nrow(qc)))
  message(sprintf("[DONE] living population external inflow rows=%d", nrow(external)))
}
