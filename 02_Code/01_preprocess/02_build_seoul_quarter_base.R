#==============================================================================
# Script    : 02_build_seoul_quarter_base.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build Seoul commercial raw-integrated wide outputs and the
#             canonical quarterly base panel for 2019-2025 impact analysis.
# Author    : Codex
# Created   : 2026-02-28
# Type      : panel_building
# Inputs    : Seoul commercial service raw csv files by source type
# Outputs   : seoul_raw_integrated_wide.parquet,
#             seoul_raw_review.parquet,
#             seoul_quarter_base.parquet, panel_quarter_aggregation_qc.csv
# DependsOn : 02_Code/R/utils_io.R, 02_Code/R/utils_qc.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# This Seoul Commercial Service branch publishes two layers:
# 1) seoul_raw_integrated_wide / seoul_raw_review: inspectable source-level raw layers
# 2) seoul_quarter_base: analysis-ready quarterly base panel for later auxiliary joins
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
load_project_packages()
ensure_dirs(cfg$required_dirs)

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 02_build_seoul_quarter_base", timestamp()))

## 0-1. Resolve output and raw-source contracts --------------------------------

# The quarter base, raw review companion, raw integrated layer, and aggregation
# QC file are a matched output set. Their paths are resolved through `cfg` before
# any raw data is read so downstream scripts consume the canonical registry names.
quarter_base_path <- value_or(cfg$paths$quarter_base, file.path(cfg$dir_analysis, "seoul_quarter_base.parquet"))
quarter_aggregation_qc_path <- value_or(
  cfg$logs$panel_quarter_aggregation_qc,
  file.path(cfg$dir_logs, "panel_quarter_aggregation_qc.csv")
)

seoul_root <- file.path(cfg$dir_raw, "02_Seoul_Commercial_District_ Administrative Dong")
if (!dir.exists(seoul_root)) {
  stop("[ERROR] Seoul commercial raw directory not found", call. = FALSE)
}

# The former long raw integration artifact is outside the current wide-only
# publication contract, so remove it early instead of leaving a stale alternative
# for manual consumers to discover later.
if (file.exists(cfg$paths$seoul_raw_integrated_long)) {
  removed <- isTRUE(file.remove(cfg$paths$seoul_raw_integrated_long))
  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Removed legacy Seoul raw long file for wide-only contract: %s (removed=%s)",
      basename(cfg$paths$seoul_raw_integrated_long),
      removed
    )
  )
}


#==============================================================================
# 1. Seoul Commercial Harmonization Helpers
#==============================================================================

# These helpers identify Seoul commercial raw files by source type, standardize
# them to the common adm_cd/year/quarter keys, and build source-specific working
# tables reused by the review and base layers.
# The helper layer deliberately keeps a buffer between raw CSV files and the
# analysis panel so source-specific schema differences are absorbed before
# publication.
source_var_map <- list(
  sales = c(
    "당월_매출_금액" = "total_sales_raw",
    "당월_매출_건수" = "sales_count_raw",
    "연령대_60_이상_매출_금액" = "age60_sales_amount_raw",
    "시간대_00~06_매출_금액" = "sales_time_00_06_raw",
    "시간대_06~11_매출_금액" = "sales_time_06_11_raw",
    "시간대_11~14_매출_금액" = "sales_time_11_14_raw",
    "시간대_14~17_매출_금액" = "sales_time_14_17_raw",
    "시간대_17~21_매출_금액" = "sales_time_17_21_raw",
    "시간대_21~24_매출_금액" = "sales_time_21_24_raw"
  ),
  store = c(
    "점포_수" = "total_store_count_raw",
    "개업_점포_수" = "opening_store_count_raw",
    "폐업_점포_수" = "closure_store_count_raw"
  ),
  floating = c(
    "총_유동인구_수" = "floating_pop_raw",
    "연령대_60_이상_유동인구_수" = "age60_floating_pop_raw",
    "시간대_00_06_유동인구_수" = "floating_time_00_06_raw",
    "시간대_06_11_유동인구_수" = "floating_time_06_11_raw",
    "시간대_11_14_유동인구_수" = "floating_time_11_14_raw",
    "시간대_14_17_유동인구_수" = "floating_time_14_17_raw",
    "시간대_17_21_유동인구_수" = "floating_time_17_21_raw",
    "시간대_21_24_유동인구_수" = "floating_time_21_24_raw"
  ),
  resident = c(
    "총_상주인구_수" = "resident_pop_raw",
    "연령대_60_이상_상주인구_수" = "age60_resident_pop_raw",
    "총_가구_수" = "total_household_commercial_raw"
  ),
  worker = c(
    "총_직장_인구_수" = "worker_pop_raw",
    "연령대_60_이상_직장_인구_수" = "age60_worker_pop_raw"
  ),
  income = c(
    "월_평균_소득_금액" = "income_level_raw",
    "지출_총금액" = "spend_total_raw"
  ),
  facility = c(
    "집객시설_수" = "facility_count_raw",
    "종합병원_수" = "hospital_general_raw",
    "일반_병원_수" = "hospital_regular_raw",
    "백화점_수" = "mall_department_raw",
    "슈퍼마켓_수" = "mall_super_raw",
    "지하철_역_수" = "subway_station_count_raw",
    "버스_정거장_수" = "bus_stop_count_raw"
  ),
  apartment = c(
    "아파트_단지_수" = "apartment_complex_count_raw",
    "아파트_평균_시가" = "apartment_mean_price_raw"
  ),
  change = c(
    "상권_변화_지표" = "commercial_change_index_code_raw",
    "상권_변화_지표_명" = "commercial_change_index_name_raw",
    "운영_영업_개월_평균" = "operating_months_avg_raw",
    "폐업_영업_개월_평균" = "closure_months_avg_raw",
    "서울_운영_영업_개월_평균" = "seoul_operating_months_avg_raw"
  )
)

## 1-1. Source discovery and key normalization ----------------------------------

read_seoul_csv <- function(path, ...) {
  readr::read_csv(
    path,
    locale = readr::locale(encoding = "CP949"),
    show_col_types = FALSE,
    ...
  )
}

safe_num <- function(x) {
  suppressWarnings(as.numeric(x))
}

sum_or_na <- function(x) {
  x_num <- safe_num(x)
  if (length(x_num) == 0L || all(is.na(x_num))) return(NA_real_)
  sum(x_num, na.rm = TRUE)
}

quarter_stability_score <- function(x, expected_quarters = 4L) {
  x_num <- safe_num(x)
  x_obs <- x_num[is.finite(x_num)]
  if (length(x_obs) != expected_quarters) return(NA_real_)

  x_mean <- mean(x_obs)
  if (!is.finite(x_mean) || x_mean <= 0) return(NA_real_)

  x_cv <- stats::sd(x_obs) / x_mean
  if (!is.finite(x_cv)) return(NA_real_)
  -log1p(x_cv)
}

rolling_quarter_stability <- function(x, expected_quarters = 4L) {
  x_num <- safe_num(x)
  out <- rep(NA_real_, length(x_num))
  if (length(x_num) < expected_quarters) return(out)
  for (i in seq_along(x_num)) {
    start <- i - expected_quarters + 1L
    if (start < 1L) next
    out[[i]] <- quarter_stability_score(x_num[start:i], expected_quarters = expected_quarters)
  }
  out
}

normalize_structural_zero_count <- function(x, active_ref) {
  x_num <- safe_num(x)
  active_num <- safe_num(active_ref)
  dplyr::if_else(!is.na(active_num), tidyr::replace_na(x_num, 0), NA_real_)
}

extract_year_from_filename <- function(path) {
  base <- basename(path)
  y <- stringr::str_extract(base, "\\d{4}(?=년)")
  if (is.na(y)) y <- stringr::str_extract(base, "\\d{4}")
  suppressWarnings(as.integer(y))
}

infer_source_type <- function(cols) {
  if (all(c("당월_매출_금액", "서비스_업종_코드") %in% cols)) return("sales")
  if (all(c("점포_수", "서비스_업종_코드") %in% cols)) return("store")
  if ("총_유동인구_수" %in% cols) return("floating")
  if ("총_상주인구_수" %in% cols) return("resident")
  if ("총_직장_인구_수" %in% cols) return("worker")
  if ("월_평균_소득_금액" %in% cols) return("income")
  if ("집객시설_수" %in% cols) return("facility")
  if ("아파트_단지_수" %in% cols) return("apartment")
  if ("상권_변화_지표" %in% cols) return("change")
  "unknown"
}

derive_service_cs_group <- function(code) {
  code <- as.character(code)
  dplyr::case_when(
    stringr::str_starts(code, "CS1") ~ "cs1",
    stringr::str_starts(code, "CS2") ~ "cs2",
    stringr::str_starts(code, "CS3") ~ "cs3",
    TRUE ~ "other"
  )
}

# Source scanning is not just file listing; it defines the raw branch domain.
# Classifying files as sales, store, facility, and related source types
# determines later review outputs and base aggregation scope, so unknown sources
# must surface early.
scan_seoul_sources <- function(root_dir) {
  files <- list.files(root_dir, recursive = TRUE, full.names = TRUE, pattern = "[.]csv$")
  files <- files[!grepl("[.]DS_Store$", files)]
  if (length(files) == 0) stop("[ERROR] No CSV files found in Seoul raw directory", call. = FALSE)

  purrr::map_dfr(files, function(path) {
    cols <- names(read_seoul_csv(path, n_max = 0))
    tibble::tibble(
      file = path,
      source_type = infer_source_type(cols),
      file_declared_year = extract_year_from_filename(path),
      n_cols = length(cols)
    )
  }) |>
    dplyr::arrange(source_type, file_declared_year, file)
}

## 1-2. Key and publication validation helpers ---------------------------------

assert_no_dup_keys <- function(df, keys, label) {
  assert_required_cols(df, keys, name = label)
  dup_n <- df |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(n > 1L) |>
    nrow()
  if (dup_n > 0) {
    stop(sprintf("[ERROR] %s duplicated keys: %d", label, dup_n), call. = FALSE)
  }
}

assert_unique_raw_keys <- function(df, label, include_service = FALSE) {
  keys <- c("기준_년분기_코드", "행정동_코드")
  if (include_service && "서비스_업종_코드" %in% names(df)) {
    keys <- c(keys, "서비스_업종_코드")
  }
  assert_no_dup_keys(df, keys, label)
}

prepare_key_cols <- function(df) {
  assert_required_cols(df, c("기준_년분기_코드", "행정동_코드"), name = "seoul_raw")

  quarter_code_raw <- as.character(df[["기준_년분기_코드"]])
  year <- suppressWarnings(as.integer(substr(quarter_code_raw, 1, 4)))
  quarter <- suppressWarnings(as.integer(substr(quarter_code_raw, 5, 5)))

  df2 <- df |>
    dplyr::mutate(
      adm_cd = as.character(.data[["행정동_코드"]]),
      year = year,
      quarter = quarter,
      quarter_code_raw = quarter_code_raw
    )

  standardize_keys(df2)
}

read_source_selected <- function(path, source_type, file_declared_year = NA_integer_) {
  raw <- read_seoul_csv(path)
  assert_required_cols(raw, c("기준_년분기_코드", "행정동_코드"), name = sprintf("%s raw", source_type))
  assert_unique_raw_keys(raw, sprintf("%s raw (%s)", source_type, basename(path)), include_service = source_type %in% c("sales", "store"))

  out <- prepare_key_cols(raw)
  if (!is.na(file_declared_year) && any(!is.na(out$year) & out$year != file_declared_year)) {
    stop(
      sprintf(
        "[ERROR] %s file-year mismatch (%s): declared=%d, observed years=%s",
        source_type,
        basename(path),
        file_declared_year,
        paste(sort(unique(out$year)), collapse = ",")
      ),
      call. = FALSE
    )
  }

  map <- source_var_map[[source_type]]
  if (is.null(map)) {
    stop(sprintf("[ERROR] source variable map not found: %s", source_type), call. = FALSE)
  }

  missing_raw_cols <- setdiff(names(map), names(out))
  if (length(missing_raw_cols) > 0) {
    stop(
      sprintf(
        "[ERROR] %s missing raw columns (%s): %s",
        source_type,
        basename(path),
        paste(missing_raw_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  service_code <- if ("서비스_업종_코드" %in% names(out)) as.character(out[["서비스_업종_코드"]]) else rep(NA_character_, nrow(out))

  # The selected layer preserves common source identifiers alongside extra raw
  # columns, letting review outputs keep source traces while base builders reuse
  # shared keys directly.
  selected <- out |>
    dplyr::transmute(
      source_type = source_type,
      source_file = basename(path),
      adm_cd,
      year,
      quarter,
      quarter_code_raw,
      service_industry_code = dplyr::na_if(trimws(service_code), "")
    )

  raw_extra <- out |>
    dplyr::select(-dplyr::any_of(c(
      "adm_cd", "year", "quarter", "quarter_code_raw",
      "기준_년분기_코드", "행정동_코드", "서비스_업종_코드"
    )))

  dplyr::bind_cols(selected, raw_extra)
}

## 1-3. Source working-layer and metric helpers --------------------------------

build_working_source_df <- function(df, source_type) {
  out <- df |>
    dplyr::filter(source_type == !!source_type)

  if (nrow(out) == 0L) {
    return(out)
  }

  map <- source_var_map[[source_type]]
  if (is.null(map)) {
    stop(sprintf("[ERROR] source variable map not found: %s", source_type), call. = FALSE)
  }

  missing_raw_cols <- setdiff(names(map), names(out))
  if (length(missing_raw_cols) > 0) {
    stop(
      sprintf(
        "[ERROR] %s missing raw columns in wide-only layer: %s",
        source_type,
        paste(missing_raw_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  for (raw_col in names(map)) {
    std_col <- unname(map[[raw_col]])
    out[[std_col]] <- out[[raw_col]]
  }

  # Sales and store sources need the service-code axis for composition metrics,
  # so keep both the original service label and the higher-level CS group.
  if (source_type %in% c("sales", "store")) {
    service_name <- if ("서비스_업종_코드_명" %in% names(out)) {
      as.character(out[["서비스_업종_코드_명"]])
    } else {
      rep(NA_character_, nrow(out))
    }

    out <- out |>
      dplyr::mutate(
        service_industry_code = as.character(service_industry_code),
        service_industry_name = service_name,
        service_cs_group = derive_service_cs_group(service_industry_code)
      )
  }

  out
}

calc_shannon_entropy <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & x > 0]
  if (length(x) == 0) return(NA_real_)
  p <- x / sum(x)
  -sum(p * log(p))
}

# SeMAS dayparts have irregular widths, so time-persistence entropy uses
# width-adjusted normalized entropy rather than plain 6-bin Shannon entropy.
calc_interval_entropy <- function(x, interval_hours, normalize = TRUE) {
  x <- as.numeric(x)
  interval_hours <- as.numeric(interval_hours)

  if (length(x) != length(interval_hours)) {
    stop("[ERROR] interval entropy requires matching x/interval_hours lengths", call. = FALSE)
  }

  keep <- is.finite(x) & is.finite(interval_hours) & interval_hours > 0
  if (!any(keep)) return(NA_real_)

  x <- pmax(x[keep], 0)
  interval_hours <- interval_hours[keep]
  total <- sum(x, na.rm = TRUE)
  total_hours <- sum(interval_hours, na.rm = TRUE)
  if (!is.finite(total) || total <= 0 || !is.finite(total_hours) || total_hours <= 0) {
    return(NA_real_)
  }

  pos <- x > 0
  p <- x[pos] / total
  entropy <- -sum(p * log(p / interval_hours[pos]))
  if (!isTRUE(normalize)) return(entropy)

  out <- entropy / log(total_hours)
  if (!is.finite(out)) return(NA_real_)
  pmin(pmax(out, 0), 1)
}

semas_daypart_suffixes_all <- c("00_06", "06_11", "11_14", "14_17", "17_21", "21_24")
semas_daypart_hours_all <- c(6, 5, 3, 3, 4, 3)
semas_daypart_suffixes_06_24 <- semas_daypart_suffixes_all[-1]
semas_daypart_hours_06_24 <- semas_daypart_hours_all[-1]

## 1-4. Quarter publication and review helpers ---------------------------------

first_present_value <- function(x) {
  idx <- which(value_present(x))
  if (length(idx) == 0) return(x[NA_integer_][1])
  x[idx[[1]]]
}

collapse_unique_present <- function(x) {
  vals <- x[value_present(x)]
  vals <- unique(as.character(vals))
  if (length(vals) == 0L) return(NA_character_)
  paste(vals, collapse = " | ")
}

pick_preferred_present <- function(x) {
  vals <- x[value_present(x)]
  vals <- unique(as.character(vals))
  if (length(vals) == 0L) return(NA_character_)

  # Prefer display strings without replacement characters when duplicates differ only by rendering.
  q_count <- stringr::str_count(vals, stringr::fixed("?"))
  vals[[order(q_count, vals)[[1]]]]
}

value_present <- function(x) {
  if (is.numeric(x)) {
    is.finite(x)
  } else {
    !is.na(x) & trimws(as.character(x)) != ""
  }
}

has_any_value_row <- function(df, value_cols) {
  if (nrow(df) == 0 || length(value_cols) == 0) return(logical(0))
  Reduce("|", lapply(value_cols, function(cc) value_present(df[[cc]])))
}

pick_first_present_value <- function(x) {
  present <- value_present(x)
  if (!any(present)) {
    if (is.character(x)) return(NA_character_)
    if (is.integer(x)) return(NA_integer_)
    return(NA_real_)
  }
  x[present][[1]]
}

publish_values_by_quarter <- function(df, value_cols, availability_col = NULL) {
  value_cols <- intersect(value_cols, names(df))
  out <- df |>
    dplyr::group_by(adm_cd, year, quarter) |>
    dplyr::summarise(
      dplyr::across(dplyr::all_of(value_cols), pick_first_present_value),
      .groups = "drop"
    ) |>
    dplyr::arrange(adm_cd, year, quarter)

  if (!is.null(availability_col)) {
    out[[availability_col]] <- as.integer(has_any_value_row(out, value_cols))
  }

  out
}

summarize_year_source_qc <- function(df, vars, source_name, aggregation_rule) {
  vars <- intersect(vars, names(df))
  if (nrow(df) == 0L || length(vars) == 0L) {
    return(tibble::tibble(
      source = character(0),
      yq = character(0),
      aggregation_rule = character(0),
      observed_adm_n = integer(0),
      row_n = integer(0),
      observed_share = numeric(0)
    ))
  }

  observed <- Reduce("|", lapply(vars, function(vn) value_present(df[[vn]])))
  if (!"yq" %in% names(df) && all(c("year", "quarter") %in% names(df))) {
    df$yq <- make_yq(df$year, df$quarter)
  }

  df |>
    dplyr::mutate(.observed = observed) |>
    dplyr::group_by(yq) |>
    dplyr::summarise(
      source = source_name,
      aggregation_rule = aggregation_rule,
      observed_adm_n = sum(.observed, na.rm = TRUE),
      row_n = dplyr::n(),
      observed_share = observed_adm_n / pmax(row_n, 1L),
      .groups = "drop"
    ) |>
    dplyr::select(source, yq, aggregation_rule, observed_adm_n, row_n, observed_share)
}

add_missing_numeric_cols <- function(df, cols, fill = 0) {
  for (cc in cols) {
    if (!cc %in% names(df)) df[[cc]] <- fill
  }
  df
}

relocate_after_if_present <- function(df, cols, after_col) {
  if (!after_col %in% names(df)) return(df)
  cols <- intersect(cols, names(df))
  if (length(cols) == 0L) return(df)
  dplyr::relocate(df, dplyr::all_of(cols), .after = dplyr::all_of(after_col))
}

detect_review_keep_cols <- function(df, drop_cols = character(0), always_keep_cols = character(0)) {
  keep <- names(df)[vapply(df, function(x) any(value_present(x)), logical(1))]
  keep <- union(keep, intersect(always_keep_cols, names(df)))
  setdiff(keep, drop_cols)
}

summarise_review_source <- function(
    df,
    group_keys,
    prefix,
    sum_numeric_cols = FALSE,
    collapse_cols = character(0),
    first_cols = character(0),
    drop_cols = character(0),
    always_keep_cols = character(0)
) {
  # Review summaries do not keep every raw row. They compress each group key with
  # the appropriate sum, first-present-value, or unique-value rule so the output
  # stays readable for manual inspection.
  keep_cols <- detect_review_keep_cols(
    df,
    drop_cols = unique(c(group_keys, drop_cols)),
    always_keep_cols = always_keep_cols
  )
  if (length(keep_cols) == 0L) {
    return(df |>
      dplyr::distinct(dplyr::across(dplyr::all_of(group_keys))) |>
      dplyr::arrange(dplyr::across(dplyr::all_of(group_keys))))
  }

  summary_exprs <- lapply(keep_cols, function(cc) {
    if (cc %in% collapse_cols) {
      rlang::expr(collapse_unique_present(.data[[!!cc]]))
    } else if (cc %in% first_cols) {
      rlang::expr(first_present_value(.data[[!!cc]]))
    } else if (isTRUE(sum_numeric_cols) && is.numeric(df[[cc]])) {
      rlang::expr(sum_or_na(.data[[!!cc]]))
    } else {
      rlang::expr(first_present_value(.data[[!!cc]]))
    }
  })
  names(summary_exprs) <- paste0(prefix, "__", keep_cols)

  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_keys))) |>
    dplyr::summarise(!!!summary_exprs, .groups = "drop") |>
    dplyr::arrange(dplyr::across(dplyr::all_of(group_keys)))
}

collect_source_header_cols <- function(source_scan, source_type) {
  files <- source_scan |>
    dplyr::filter(source_type == !!source_type) |>
    dplyr::pull(file)

  if (length(files) == 0L) return(character(0))

  unique(unlist(lapply(files, function(path) names(read_seoul_csv(path, n_max = 0))), use.names = FALSE))
}

build_review_keep_cols <- function(source_scan, source_type) {
  raw_cols <- setdiff(
    collect_source_header_cols(source_scan, source_type),
    c(
      "기준_년분기_코드", "행정동_코드", "행정동_코드_명",
      "서비스_업종_코드", "서비스_업종_코드_명"
    )
  )
  meta_cols <- c("source_file")
  if (source_type %in% c("sales", "store")) {
    meta_cols <- c(meta_cols, "service_industry_code", "service_industry_name")
  }

  unique(c(meta_cols, raw_cols))
}

build_adm_name_lookup <- function(df) {
  if (!"행정동_코드_명" %in% names(df)) {
    return(tibble::tibble(adm_cd = sort(unique(df$adm_cd)), adm_nm = NA_character_, adm_nm_variant_n = 0L))
  }

  df |>
    dplyr::transmute(adm_cd, adm_nm = as.character(.data[["행정동_코드_명"]])) |>
    dplyr::filter(value_present(adm_nm)) |>
    dplyr::group_by(adm_cd) |>
    dplyr::summarise(
      adm_nm = pick_preferred_present(adm_nm),
      adm_nm_variant_n = dplyr::n_distinct(adm_nm),
      .groups = "drop"
    )
}

log_extreme_summary <- function(df, col) {
  if (!col %in% names(df)) return(invisible(NULL))
  x <- safe_num(df[[col]])
  x <- x[is.finite(x)]
  if (length(x) == 0) {
    append_log(cfg$logs$data_qc, sprintf("- %s extremes: no finite values", col))
    return(invisible(NULL))
  }

  q99 <- suppressWarnings(as.numeric(stats::quantile(x, probs = 0.99, na.rm = TRUE, names = FALSE)))
  q999 <- suppressWarnings(as.numeric(stats::quantile(x, probs = 0.999, na.rm = TRUE, names = FALSE)))
  append_log(
    cfg$logs$data_qc,
    sprintf("- %s extremes: max=%.3f q99=%.3f q999=%.3f", col, max(x), q99, q999)
  )
}

## 1-5. Staged output helpers ---------------------------------------------------

build_stage_output_path <- function(path) {
  dir <- fs::path_dir(path)
  ext <- tools::file_ext(path)
  stem <- tools::file_path_sans_ext(basename(path))
  stamp <- paste0(Sys.getpid(), "_", format(Sys.time(), "%Y%m%d%H%M%OS6"))
  fileext <- if (nzchar(ext)) paste0(".", ext, ".stage") else ".stage"
  fs::dir_create(dir)
  tempfile(pattern = paste0(".", stem, "_", stamp, "_"), tmpdir = dir, fileext = fileext)
}

stage_output_write <- function(final_path, writer) {
  staged_path <- build_stage_output_path(final_path)
  writer(staged_path)
  staged_path
}

promote_staged_outputs <- function(staged_outputs) {
  # Review and base outputs are a matched file set, so staged promotion is handled
  # atomically. This prevents partial refreshes and allows the previous canonical
  # set to be restored when publication fails mid-run.
  staged_paths <- vapply(staged_outputs, function(x) x$staged_path, character(1))
  backup_paths <- stats::setNames(rep("", length(staged_outputs)), names(staged_outputs))
  promoted <- character(0)

  on.exit({
    leftover <- staged_paths[file.exists(staged_paths)]
    if (length(leftover) > 0) unlink(leftover)
    backup_leftover <- backup_paths[nzchar(backup_paths) & file.exists(backup_paths)]
    if (length(backup_leftover) > 0) unlink(backup_leftover)
  }, add = TRUE)

  for (nm in names(staged_outputs)) {
    final_path <- staged_outputs[[nm]]$final_path
    staged_path <- staged_outputs[[nm]]$staged_path

    if (file.exists(final_path)) {
      backup_paths[[nm]] <- build_stage_output_path(final_path)
      atomic_rename(final_path, backup_paths[[nm]])
    }

    tryCatch(
      {
        atomic_rename(staged_path, final_path)
      },
      error = function(e) {
        if (file.exists(final_path)) unlink(final_path)
        if (nzchar(backup_paths[[nm]]) && file.exists(backup_paths[[nm]])) {
          atomic_rename(backup_paths[[nm]], final_path)
        }

        for (rollback_nm in rev(promoted)) {
          rollback_final <- staged_outputs[[rollback_nm]]$final_path
          rollback_backup <- backup_paths[[rollback_nm]]
          if (file.exists(rollback_final)) unlink(rollback_final)
          if (nzchar(rollback_backup) && file.exists(rollback_backup)) {
            atomic_rename(rollback_backup, rollback_final)
          }
        }

        stop(e$message, call. = FALSE)
      }
    )

    promoted <- c(promoted, nm)
    if (nzchar(backup_paths[[nm]]) && file.exists(backup_paths[[nm]])) {
      unlink(backup_paths[[nm]])
      backup_paths[[nm]] <- ""
    }
  }

  invisible(promoted)
}

#==============================================================================
# 2. Scan Raw Files and Build Wide Output
#==============================================================================

# Scan the full raw folder first and assign a source_type to every file. Unknown
# sources stop the run because they may signal a source-periodicity change.
# Seoul commercial raw files mix split-year sales/store files with single-file
# multi-year sources, so coverage is judged by parsed quarter codes rather than
# by file counts alone.
source_scan <- scan_seoul_sources(seoul_root)

# Review-column rules are derived from discovered source headers. This keeps the
# human-readable companion aligned with the current raw schema while preventing
# raw-only identifiers from leaking into the canonical quarter base.
review_keep_cols_map <- setNames(
  lapply(sort(unique(source_scan$source_type)), function(st) build_review_keep_cols(source_scan, st)),
  sort(unique(source_scan$source_type))
)
review_drop_cols_map <- setNames(
  lapply(sort(unique(source_scan$source_type)), function(st) {
    unique(c(
      "source_type", "service_cs_group", "quarter_code_raw", "기준_년분기_코드", "행정동_코드", "행정동_코드_명",
      "서비스_업종_코드", "서비스_업종_코드_명",
      if (!is.null(source_var_map[[st]])) unname(source_var_map[[st]]) else character(0)
    ))
  }),
  sort(unique(source_scan$source_type))
)

unknown_sources <- source_scan |>
  dplyr::filter(source_type == "unknown")
if (nrow(unknown_sources) > 0) {
  stop(
    sprintf(
      "[ERROR] Unknown Seoul source files detected: %s",
      paste(basename(unknown_sources$file), collapse = ", ")
    ),
    call. = FALSE
  )
}

type_counts <- source_scan |>
  dplyr::count(source_type, name = "n_files") |>
  dplyr::arrange(source_type)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Seoul source file types: %s",
    paste(sprintf("%s=%d", type_counts$source_type, type_counts$n_files), collapse = ", ")
  )
)

required_source_types <- c("sales", "store", "floating", "resident", "worker", "income", "facility", "apartment", "change")
missing_required_source_types <- setdiff(required_source_types, unique(source_scan$source_type))
if (length(missing_required_source_types) > 0L) {
  stop(
    sprintf(
      "[ERROR] Missing required Seoul source types: %s",
      paste(missing_required_source_types, collapse = ", ")
    ),
    call. = FALSE
  )
}

selected_list <- vector("list", nrow(source_scan))

# raw_integrated_wide is an inspectable integration layer that preserves as many
# source-specific raw columns as possible. It does not yet collapse sales, store,
# floating, and other sources into one row.
for (ii in seq_len(nrow(source_scan))) {
  rec <- source_scan[ii, ]
  selected <- read_source_selected(
    path = rec$file[[1]],
    source_type = rec$source_type[[1]],
    file_declared_year = rec$file_declared_year[[1]]
  )
  selected_list[[ii]] <- selected
}

raw_integrated_wide <- dplyr::bind_rows(selected_list) |>
  dplyr::arrange(source_type, adm_cd, year, quarter, service_industry_code)

adm_name_lookup <- build_adm_name_lookup(raw_integrated_wide)

# The working-source map is the handoff from "raw but standardized" rows to
# source-specific builders. Each table keeps one source type but shares the same
# `adm_cd`, `year`, and `quarter` contract.
working_source_map <- setNames(
  lapply(sort(unique(source_scan$source_type)), function(st) build_working_source_df(raw_integrated_wide, st)),
  sort(unique(source_scan$source_type))
)

# Enforce uniqueness before aggregation so duplicated raw rows cannot silently
# inflate sales, store, or population quantities.
for (st in sort(unique(raw_integrated_wide$source_type))) {
  keys <- c("adm_cd", "year", "quarter")
  if (st %in% c("sales", "store")) keys <- c(keys, "service_industry_code")
  assert_no_dup_keys(raw_integrated_wide |> dplyr::filter(source_type == st), keys, sprintf("%s raw integrated wide", st))
}

# The published raw layer must stay inside the configured panel-build horizon.
# Out-of-range quarters indicate either source drift or quarter-code parsing
# failure and should not flow into later panel joins.
invalid_year_quarter_n <- raw_integrated_wide |>
  dplyr::filter(
    is.na(year) | is.na(quarter) |
      year < cfg$short_start | year > cfg$short_end |
      quarter < 1L | quarter > 4L |
      (year == cfg$short_end & quarter > cfg$short_end_quarter)
  ) |>
  nrow()
if (invalid_year_quarter_n > 0) {
  stop(sprintf("[ERROR] Invalid year/quarter rows in Seoul raw integrated wide: %d", invalid_year_quarter_n), call. = FALSE)
}

# Terminal-year coverage is checked source-by-source because mixed raw layouts
# can otherwise hide a partially updated source behind files from other types.
terminal_year_coverage <- raw_integrated_wide |>
  dplyr::filter(!is.na(year), !is.na(quarter), year == cfg$short_end) |>
  dplyr::distinct(source_type, quarter) |>
  dplyr::group_by(source_type) |>
  dplyr::summarise(
    quarter_n = dplyr::n_distinct(quarter),
    quarters_present = paste(sort(unique(quarter)), collapse = ","),
    .groups = "drop"
  ) |>
  dplyr::arrange(source_type)

append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Seoul source terminal-year quarter coverage: %s",
    paste(
      sprintf("%s={%s}", terminal_year_coverage$source_type, terminal_year_coverage$quarters_present),
      collapse = ", "
    )
  )
)

missing_terminal_quarters <- terminal_year_coverage |>
  dplyr::filter(source_type %in% required_source_types, quarter_n < cfg$short_end_quarter)
if (nrow(missing_terminal_quarters) > 0L) {
  stop(
    sprintf(
      "[ERROR] Terminal-year raw coverage incomplete for Seoul source types: %s",
      paste(
        sprintf("%s={%s}", missing_terminal_quarters$source_type, missing_terminal_quarters$quarters_present),
        collapse = ", "
      )
    ),
    call. = FALSE
  )
}

#==============================================================================
# 3. Build Source Components for Quarter Base
#==============================================================================

# This section converts each source-specific working table into `adm_cd x
# year x quarter` components. Flow variables are summed, level/snapshot variables
# keep their source-quarter meaning, and derived shares are calculated before the
# final multi-source join.
sales_major_cols <- paste0("sales_", c("cs1", "cs2", "cs3"))
sales_share_cols <- paste0("sales_share_", c("cs1", "cs2", "cs3"))
store_major_cols <- paste0("store_", c("cs1", "cs2", "cs3"))
store_share_cols <- paste0("store_share_", c("cs1", "cs2", "cs3"))
sales_time_cols <- c(
  "sales_time_00_06_raw", "sales_time_06_11_raw", "sales_time_11_14_raw",
  "sales_time_14_17_raw", "sales_time_17_21_raw", "sales_time_21_24_raw"
)
floating_time_cols <- c(
  "floating_time_00_06_raw", "floating_time_06_11_raw", "floating_time_11_14_raw",
  "floating_time_14_17_raw", "floating_time_17_21_raw", "floating_time_21_24_raw"
)

## 3-1. Sales and store activity components ------------------------------------

# Sales and store sources carry a service-industry axis. Collapse that axis only
# after preserving CS-group composition, time concentration, age-60 sales share,
# opening/closure rates, and diversity diagnostics.
sales_raw <- working_source_map[["sales"]]
if (nrow(sales_raw) == 0) stop("[ERROR] sales source is empty", call. = FALSE)
assert_required_cols(
  sales_raw,
  c(
    "adm_cd", "year", "quarter", "service_industry_code",
    "total_sales_raw", "sales_count_raw", "age60_sales_amount_raw",
    sales_time_cols
  ),
  name = "sales_raw"
)
assert_no_dup_keys(sales_raw, c("adm_cd", "year", "quarter", "service_industry_code"), "sales_raw")
unexpected_sales_major <- setdiff(unique(stats::na.omit(as.character(sales_raw$service_cs_group))), c("cs1", "cs2", "cs3"))
if (length(unexpected_sales_major) > 0) {
  stop(
    sprintf(
      "[ERROR] Unexpected sales service_cs_group in raw data: %s",
      paste(unexpected_sales_major, collapse = ", ")
    ),
    call. = FALSE
  )
}

sales_major <- sales_raw |>
  # sales_major is an intermediate CS-group layer. Keep it separate from
  # total_sales so industry composition and total volume can be checked
  # independently.
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    service_cs_group,
    sales_amount = safe_num(total_sales_raw)
  ) |>
  dplyr::group_by(adm_cd, year, quarter, service_cs_group) |>
  dplyr::summarise(value = sum(sales_amount, na.rm = TRUE), .groups = "drop") |>
  dplyr::mutate(var_name = paste0("sales_", service_cs_group)) |>
  dplyr::select(adm_cd, year, quarter, var_name, value) |>
  tidyr::pivot_wider(names_from = var_name, values_from = value, values_fill = 0)

sales_time_entropy <- sales_raw |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    sales_time_00_06 = safe_num(sales_time_00_06_raw),
    sales_time_06_11 = safe_num(sales_time_06_11_raw),
    sales_time_11_14 = safe_num(sales_time_11_14_raw),
    sales_time_14_17 = safe_num(sales_time_14_17_raw),
    sales_time_17_21 = safe_num(sales_time_17_21_raw),
    sales_time_21_24 = safe_num(sales_time_21_24_raw)
  ) |>
  dplyr::group_by(adm_cd, year, quarter) |>
  dplyr::summarise(
    sales_time_00_06 = sum(sales_time_00_06, na.rm = TRUE),
    sales_time_06_11 = sum(sales_time_06_11, na.rm = TRUE),
    sales_time_11_14 = sum(sales_time_11_14, na.rm = TRUE),
    sales_time_14_17 = sum(sales_time_14_17, na.rm = TRUE),
    sales_time_17_21 = sum(sales_time_17_21, na.rm = TRUE),
    sales_time_21_24 = sum(sales_time_21_24, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    sales_time_entropy = calc_interval_entropy(
      c_across(dplyr::all_of(paste0("sales_time_", semas_daypart_suffixes_all))),
      semas_daypart_hours_all
    ),
    sales_time_entropy_06_24 = calc_interval_entropy(
      c_across(dplyr::all_of(paste0("sales_time_", semas_daypart_suffixes_06_24))),
      semas_daypart_hours_06_24
    )
  ) |>
  dplyr::ungroup() |>
  dplyr::select(adm_cd, year, quarter, sales_time_entropy, sales_time_entropy_06_24)

sales_q <- sales_raw |>
  # sales_q collapses the service-industry axis to dong-quarter totals and
  # age-60 sales. Shares are calculated here so downstream models do not need to
  # re-aggregate raw service rows.
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    total_sales = safe_num(total_sales_raw),
    sales_count = safe_num(sales_count_raw),
    age60_sales_amount = safe_num(age60_sales_amount_raw)
  ) |>
  dplyr::group_by(adm_cd, year, quarter) |>
  dplyr::summarise(
    total_sales = sum(total_sales, na.rm = TRUE),
    sales_count = sum(sales_count, na.rm = TRUE),
    age60_sales_amount = sum(age60_sales_amount, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(sales_major, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(sales_time_entropy, by = c("adm_cd", "year", "quarter")) |>
  add_missing_numeric_cols(sales_major_cols, fill = 0) |>
  dplyr::mutate(
    age60_sales_share = dplyr::if_else(total_sales > 0, age60_sales_amount / total_sales, NA_real_),
    sales_share_cs1 = dplyr::if_else(total_sales > 0, sales_cs1 / total_sales, NA_real_),
    sales_share_cs2 = dplyr::if_else(total_sales > 0, sales_cs2 / total_sales, NA_real_),
    sales_share_cs3 = dplyr::if_else(total_sales > 0, sales_cs3 / total_sales, NA_real_)
  ) |>
  dplyr::arrange(adm_cd, year, quarter) |>
  dplyr::group_by(adm_cd) |>
  dplyr::mutate(sales_quarter_stability = rolling_quarter_stability(total_sales)) |>
  dplyr::ungroup()

store_raw <- working_source_map[["store"]]
if (nrow(store_raw) == 0) stop("[ERROR] store source is empty", call. = FALSE)
assert_required_cols(
  store_raw,
  c("adm_cd", "year", "quarter", "service_industry_code", "total_store_count_raw", "opening_store_count_raw", "closure_store_count_raw"),
  name = "store_raw"
)
assert_no_dup_keys(store_raw, c("adm_cd", "year", "quarter", "service_industry_code"), "store_raw")
unexpected_store_major <- setdiff(unique(stats::na.omit(as.character(store_raw$service_cs_group))), c("cs1", "cs2", "cs3"))
if (length(unexpected_store_major) > 0) {
  stop(
    sprintf(
      "[ERROR] Unexpected store service_cs_group in raw data: %s",
      paste(unexpected_store_major, collapse = ", ")
    ),
    call. = FALSE
  )
}

store_major <- store_raw |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    service_cs_group,
    store_count = safe_num(total_store_count_raw)
  ) |>
  dplyr::group_by(adm_cd, year, quarter, service_cs_group) |>
  dplyr::summarise(value = sum(store_count, na.rm = TRUE), .groups = "drop") |>
  dplyr::mutate(var_name = paste0("store_", service_cs_group)) |>
  dplyr::select(adm_cd, year, quarter, var_name, value) |>
  tidyr::pivot_wider(names_from = var_name, values_from = value, values_fill = 0)

store_entropy <- store_raw |>
  # diversity_index is based on the store-count distribution by service industry,
  # so store counts must be aggregated by service industry before Shannon entropy
  # is calculated.
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    service_industry_code = as.character(service_industry_code),
    store_count = safe_num(total_store_count_raw)
  ) |>
  dplyr::group_by(adm_cd, year, quarter, service_industry_code) |>
  dplyr::summarise(store_count = sum(store_count, na.rm = TRUE), .groups = "drop_last") |>
  dplyr::summarise(diversity_index = calc_shannon_entropy(store_count), .groups = "drop")

store_q <- store_raw |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    total_store_count = safe_num(total_store_count_raw),
    opening_store_count = safe_num(opening_store_count_raw),
    closure_store_count = safe_num(closure_store_count_raw)
  ) |>
  dplyr::group_by(adm_cd, year, quarter) |>
  dplyr::summarise(
    total_store_count = sum(total_store_count, na.rm = TRUE),
    opening_store_count = sum(opening_store_count, na.rm = TRUE),
    closure_store_count = sum(closure_store_count, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(store_entropy, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(store_major, by = c("adm_cd", "year", "quarter")) |>
  add_missing_numeric_cols(store_major_cols, fill = 0) |>
  dplyr::mutate(
    opening_rate = dplyr::if_else(total_store_count > 0, opening_store_count / total_store_count, NA_real_),
    closure_rate = dplyr::if_else(total_store_count > 0, closure_store_count / total_store_count, NA_real_),
    instability_index = closure_rate - opening_rate,
    store_share_cs1 = dplyr::if_else(total_store_count > 0, store_cs1 / total_store_count, NA_real_),
    store_share_cs2 = dplyr::if_else(total_store_count > 0, store_cs2 / total_store_count, NA_real_),
    store_share_cs3 = dplyr::if_else(total_store_count > 0, store_cs3 / total_store_count, NA_real_)
  )

## 3-2. Population and source-quarter snapshot components ----------------------

# Non-sales sources already publish at the administrative-dong quarter level.
# Keep quarterly snapshot/level semantics here; source-specific as-of or lag
# treatment happens later when the shared panel is assembled.
floating_raw <- working_source_map[["floating"]]
assert_required_cols(
  floating_raw,
  c("adm_cd", "year", "quarter", "floating_pop_raw", "age60_floating_pop_raw", floating_time_cols),
  name = "floating_raw"
)

floating_q <- floating_raw |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    floating_pop = safe_num(floating_pop_raw),
    age60_floating_pop = safe_num(age60_floating_pop_raw),
    floating_time_00_06 = safe_num(floating_time_00_06_raw),
    floating_time_06_11 = safe_num(floating_time_06_11_raw),
    floating_time_11_14 = safe_num(floating_time_11_14_raw),
    floating_time_14_17 = safe_num(floating_time_14_17_raw),
    floating_time_17_21 = safe_num(floating_time_17_21_raw),
    floating_time_21_24 = safe_num(floating_time_21_24_raw)
  ) |>
  dplyr::group_by(adm_cd, year, quarter) |>
  dplyr::summarise(
    floating_pop = sum(floating_pop, na.rm = TRUE),
    age60_floating_pop = sum(age60_floating_pop, na.rm = TRUE),
    floating_time_00_06 = sum(floating_time_00_06, na.rm = TRUE),
    floating_time_06_11 = sum(floating_time_06_11, na.rm = TRUE),
    floating_time_11_14 = sum(floating_time_11_14, na.rm = TRUE),
    floating_time_14_17 = sum(floating_time_14_17, na.rm = TRUE),
    floating_time_17_21 = sum(floating_time_17_21, na.rm = TRUE),
    floating_time_21_24 = sum(floating_time_21_24, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    floating_time_entropy = calc_interval_entropy(
      c_across(dplyr::all_of(paste0("floating_time_", semas_daypart_suffixes_all))),
      semas_daypart_hours_all
    ),
    floating_time_entropy_06_24 = calc_interval_entropy(
      c_across(dplyr::all_of(paste0("floating_time_", semas_daypart_suffixes_06_24))),
      semas_daypart_hours_06_24
    ),
    age60_floating_share = dplyr::if_else(floating_pop > 0, age60_floating_pop / floating_pop, NA_real_)
  ) |>
  dplyr::ungroup()
floating_q <- floating_q |>
  dplyr::arrange(adm_cd, year, quarter) |>
  dplyr::group_by(adm_cd) |>
  dplyr::mutate(floating_quarter_stability = rolling_quarter_stability(floating_pop)) |>
  dplyr::ungroup()
assert_no_dup_keys(floating_q, c("adm_cd", "year", "quarter"), "floating_q")

resident_source <- working_source_map[["resident"]] |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    total_household_commercial = safe_num(total_household_commercial_raw)
  )
resident_q <- publish_values_by_quarter(
  resident_source,
  c("total_household_commercial")
)

worker_source <- working_source_map[["worker"]] |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    worker_pop = safe_num(worker_pop_raw),
    age60_worker_pop = safe_num(age60_worker_pop_raw)
  )
worker_q <- publish_values_by_quarter(worker_source, c("worker_pop", "age60_worker_pop"))

income_source <- working_source_map[["income"]] |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    income_level = safe_num(income_level_raw),
    spend_total = safe_num(spend_total_raw)
  )
income_q <- publish_values_by_quarter(income_source, c("income_level", "spend_total"))

facility_source <- working_source_map[["facility"]] |>
  dplyr::mutate(
    facility_count = safe_num(facility_count_raw),
    hospital_general_count = normalize_structural_zero_count(hospital_general_raw, facility_count),
    hospital_regular_count = normalize_structural_zero_count(hospital_regular_raw, facility_count),
    mall_department_count = normalize_structural_zero_count(mall_department_raw, facility_count),
    mall_super_count = normalize_structural_zero_count(mall_super_raw, facility_count),
    subway_station_count = normalize_structural_zero_count(subway_station_count_raw, facility_count),
    bus_stop_count = normalize_structural_zero_count(bus_stop_count_raw, facility_count)
  ) |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    facility_count,
    hospital_count = hospital_general_count + hospital_regular_count,
    mall_count = mall_department_count + mall_super_count,
    subway_station_count,
    bus_stop_count
  )
facility_q <- publish_values_by_quarter(
  facility_source,
  c("facility_count", "hospital_count", "mall_count", "subway_station_count", "bus_stop_count"),
  availability_col = "facility_available"
)

apartment_source <- working_source_map[["apartment"]] |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    apartment_complex_count = safe_num(apartment_complex_count_raw),
    apartment_mean_price = safe_num(apartment_mean_price_raw)
  )
apartment_q <- publish_values_by_quarter(
  apartment_source,
  c("apartment_complex_count", "apartment_mean_price"),
  availability_col = "apartment_available"
)

change_source <- working_source_map[["change"]] |>
  dplyr::transmute(
    adm_cd,
    year,
    quarter,
    commercial_change_index_code = as.character(commercial_change_index_code_raw),
    commercial_change_index_name = as.character(commercial_change_index_name_raw),
    operating_months_avg = safe_num(operating_months_avg_raw),
    closure_months_avg = safe_num(closure_months_avg_raw),
    seoul_operating_months_avg = safe_num(seoul_operating_months_avg_raw)
  )
change_q <- publish_values_by_quarter(
  change_source,
  c(
    "commercial_change_index_code", "commercial_change_index_name",
    "operating_months_avg", "closure_months_avg", "seoul_operating_months_avg"
  )
) |>
  dplyr::mutate(
    operating_months_rel_seoul = operating_months_avg - seoul_operating_months_avg
  )

## 3-3. Assemble quarter base and review companion -----------------------------

# Floating population is the preferred base universe because it is the widest
# quarterly population source, but the final grid keeps any adm_cd appearing in
# other required Seoul commercial sources and logs that expansion.
adm_base <- sort(unique(floating_q$adm_cd))
adm_pool <- sort(unique(c(
  adm_base,
  sales_q$adm_cd,
  store_q$adm_cd,
  resident_q$adm_cd,
  worker_q$adm_cd,
  income_q$adm_cd,
  facility_q$adm_cd,
  apartment_q$adm_cd,
  change_q$adm_cd
)))

extra_adm <- setdiff(adm_pool, adm_base)
if (length(extra_adm) > 0) {
  append_log(cfg$logs$data_qc, sprintf("- Extra adm_cd beyond floating quarterly base: %d", length(extra_adm)))
}

panel_quarter_grid <- tidyr::expand_grid(
  adm_cd = adm_pool,
  cfg$quarter_sequence
) |>
  dplyr::arrange(adm_cd, year, quarter)

review_panel_grid <- tidyr::expand_grid(
  adm_cd = adm_pool,
  year = cfg$short_start:cfg$short_end,
  quarter = 1:4
) |>
  dplyr::filter(!(year == cfg$short_end & quarter > cfg$short_end_quarter))

# Service CS groups are retained in the review companion so source-level sales
# and store rows can be inspected without polluting the canonical quarter base
# with a service-industry dimension.
service_cs_group_levels <- sort(unique(c(as.character(sales_raw$service_cs_group), as.character(store_raw$service_cs_group))))
service_cs_group_levels <- service_cs_group_levels[!is.na(service_cs_group_levels) & trimws(service_cs_group_levels) != ""]
if (length(service_cs_group_levels) == 0L) service_cs_group_levels <- c("cs1", "cs2", "cs3")

# The review table is a source-audit companion. It keeps source-prefixed fields
# and selected raw metadata for inspection, while preserving unique
# `adm_cd-year-quarter-service_cs_group` keys.
sales_review_raw <- summarise_review_source(
  df = sales_raw,
  group_keys = c("adm_cd", "year", "quarter", "service_cs_group"),
  prefix = "sales",
  sum_numeric_cols = TRUE,
  collapse_cols = c("service_industry_code", "service_industry_name", "서비스_업종_코드", "서비스_업종_코드_명"),
  first_cols = c("source_type", "source_file", "quarter_code_raw", "기준_년분기_코드", "행정동_코드", "행정동_코드_명"),
  drop_cols = review_drop_cols_map[["sales"]],
  always_keep_cols = review_keep_cols_map[["sales"]]
)
assert_no_dup_keys(sales_review_raw, c("adm_cd", "year", "quarter", "service_cs_group"), "sales_review_raw")

store_review_raw <- summarise_review_source(
  df = store_raw,
  group_keys = c("adm_cd", "year", "quarter", "service_cs_group"),
  prefix = "store",
  sum_numeric_cols = TRUE,
  collapse_cols = c("service_industry_code", "service_industry_name", "서비스_업종_코드", "서비스_업종_코드_명"),
  first_cols = c("source_type", "source_file", "quarter_code_raw", "기준_년분기_코드", "행정동_코드", "행정동_코드_명"),
  drop_cols = review_drop_cols_map[["store"]],
  always_keep_cols = review_keep_cols_map[["store"]]
)
assert_no_dup_keys(store_review_raw, c("adm_cd", "year", "quarter", "service_cs_group"), "store_review_raw")

floating_review_raw <- summarise_review_source(
  df = working_source_map[["floating"]],
  group_keys = c("adm_cd", "year", "quarter"),
  prefix = "floating",
  drop_cols = review_drop_cols_map[["floating"]],
  always_keep_cols = review_keep_cols_map[["floating"]]
)
assert_no_dup_keys(floating_review_raw, c("adm_cd", "year", "quarter"), "floating_review_raw")

resident_review_raw <- summarise_review_source(
  df = working_source_map[["resident"]],
  group_keys = c("adm_cd", "year", "quarter"),
  prefix = "resident",
  drop_cols = review_drop_cols_map[["resident"]],
  always_keep_cols = review_keep_cols_map[["resident"]]
)
assert_no_dup_keys(resident_review_raw, c("adm_cd", "year", "quarter"), "resident_review_raw")

worker_review_raw <- summarise_review_source(
  df = working_source_map[["worker"]],
  group_keys = c("adm_cd", "year", "quarter"),
  prefix = "worker",
  drop_cols = review_drop_cols_map[["worker"]],
  always_keep_cols = review_keep_cols_map[["worker"]]
)
assert_no_dup_keys(worker_review_raw, c("adm_cd", "year", "quarter"), "worker_review_raw")

income_review_raw <- summarise_review_source(
  df = working_source_map[["income"]],
  group_keys = c("adm_cd", "year", "quarter"),
  prefix = "income",
  drop_cols = review_drop_cols_map[["income"]],
  always_keep_cols = review_keep_cols_map[["income"]]
)
assert_no_dup_keys(income_review_raw, c("adm_cd", "year", "quarter"), "income_review_raw")

facility_review_raw <- summarise_review_source(
  df = working_source_map[["facility"]],
  group_keys = c("adm_cd", "year", "quarter"),
  prefix = "facility",
  drop_cols = review_drop_cols_map[["facility"]],
  always_keep_cols = review_keep_cols_map[["facility"]]
)
assert_no_dup_keys(facility_review_raw, c("adm_cd", "year", "quarter"), "facility_review_raw")

apartment_review_raw <- summarise_review_source(
  df = working_source_map[["apartment"]],
  group_keys = c("adm_cd", "year", "quarter"),
  prefix = "apartment",
  drop_cols = review_drop_cols_map[["apartment"]],
  always_keep_cols = review_keep_cols_map[["apartment"]]
)
assert_no_dup_keys(apartment_review_raw, c("adm_cd", "year", "quarter"), "apartment_review_raw")

change_review_raw <- summarise_review_source(
  df = working_source_map[["change"]],
  group_keys = c("adm_cd", "year", "quarter"),
  prefix = "change",
  drop_cols = review_drop_cols_map[["change"]],
  always_keep_cols = review_keep_cols_map[["change"]]
)
assert_no_dup_keys(change_review_raw, c("adm_cd", "year", "quarter"), "change_review_raw")

seoul_raw_review <- review_panel_grid |>
  dplyr::select(adm_cd, year, quarter) |>
  dplyr::left_join(
    adm_name_lookup |>
      dplyr::select(adm_cd, adm_nm),
    by = "adm_cd"
  ) |>
  tidyr::crossing(service_cs_group = service_cs_group_levels) |>
  dplyr::left_join(sales_review_raw, by = c("adm_cd", "year", "quarter", "service_cs_group")) |>
  dplyr::left_join(store_review_raw, by = c("adm_cd", "year", "quarter", "service_cs_group")) |>
  dplyr::left_join(floating_review_raw, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(resident_review_raw, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(worker_review_raw, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(income_review_raw, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(facility_review_raw, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(apartment_review_raw, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(change_review_raw, by = c("adm_cd", "year", "quarter")) |>
  relocate_after_if_present("sales__service_industry_name", "sales__service_industry_code") |>
  relocate_after_if_present("store__service_industry_name", "store__service_industry_code") |>
  dplyr::arrange(adm_cd, year, quarter, service_cs_group)
assert_no_dup_keys(seoul_raw_review, c("adm_cd", "year", "quarter", "service_cs_group"), "seoul_raw_review")

# `out_quarter` is the canonical Seoul commercial base published at `adm_cd-yq`.
# It carries derived quarterly measures only; raw quarter-code/source columns
# remain in the review and raw-integrated artifacts.
out_quarter <- panel_quarter_grid |>
  dplyr::left_join(
    sales_q |>
      dplyr::select(
        adm_cd, year, quarter,
        total_sales, sales_count, age60_sales_amount, age60_sales_share,
        sales_time_entropy, sales_time_entropy_06_24, sales_quarter_stability,
        dplyr::all_of(sales_major_cols), dplyr::all_of(sales_share_cols)
      ),
    by = c("adm_cd", "year", "quarter")
  ) |>
  dplyr::left_join(
    store_q |>
      dplyr::select(
        adm_cd, year, quarter,
        total_store_count, opening_rate, closure_rate, instability_index, diversity_index,
        dplyr::all_of(store_major_cols), dplyr::all_of(store_share_cols)
      ),
    by = c("adm_cd", "year", "quarter")
  ) |>
  dplyr::left_join(
    floating_q |>
      dplyr::select(
        adm_cd, year, quarter,
        floating_pop, age60_floating_pop,
        floating_time_entropy, floating_time_entropy_06_24, floating_quarter_stability,
        age60_floating_share
      ),
    by = c("adm_cd", "year", "quarter")
  ) |>
  dplyr::left_join(resident_q, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(worker_q, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(income_q, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(facility_q, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(apartment_q, by = c("adm_cd", "year", "quarter")) |>
  dplyr::left_join(change_q, by = c("adm_cd", "year", "quarter")) |>
  dplyr::arrange(adm_cd, year, quarter)

#==============================================================================
# 4. Run QC and Save Quarter Base
#==============================================================================

# The quarter base is the first published `adm_cd-yq` commercial panel layer, so
# duplicate keys and raw parser-only columns are treated as hard contract breaks.
validate_panel_keys(out_quarter, c("adm_cd", "yq"))

forbidden_quarter_base_cols <- intersect(c("quarter_code_raw"), names(out_quarter))
if (length(forbidden_quarter_base_cols) > 0L) {
  stop(
    sprintf(
      "[ERROR] seoul_quarter_base still contains raw quarterly columns: %s",
      paste(forbidden_quarter_base_cols, collapse = ", ")
    ),
    call. = FALSE
  )
}

# Diversity can degenerate silently when the service-industry axis collapses or
# store counts are missing. Give it a dedicated QC gate before publishing.
diversity_qc <- dplyr::bind_rows(
  out_quarter |>
    dplyr::group_by(yq) |>
    dplyr::summarise(
      source = "diversity_index",
      aggregation_rule = "quarterly_stock_distribution_entropy",
      observed_adm_n = sum(is.finite(diversity_index)),
      row_n = dplyr::n(),
      observed_share = observed_adm_n / pmax(row_n, 1L),
      unique_n = dplyr::n_distinct(diversity_index[is.finite(diversity_index)]),
      sd_value = suppressWarnings(stats::sd(diversity_index[is.finite(diversity_index)], na.rm = TRUE)),
      min_value = suppressWarnings(min(diversity_index[is.finite(diversity_index)], na.rm = TRUE)),
      max_value = suppressWarnings(max(diversity_index[is.finite(diversity_index)], na.rm = TRUE)),
      .groups = "drop"
    ),
  out_quarter |>
    dplyr::summarise(
      source = "diversity_index",
      yq = NA_character_,
      aggregation_rule = "quarterly_stock_distribution_entropy",
      observed_adm_n = sum(is.finite(diversity_index)),
      row_n = dplyr::n(),
      observed_share = observed_adm_n / pmax(row_n, 1L),
      unique_n = dplyr::n_distinct(diversity_index[is.finite(diversity_index)]),
      sd_value = suppressWarnings(stats::sd(diversity_index[is.finite(diversity_index)], na.rm = TRUE)),
      min_value = suppressWarnings(min(diversity_index[is.finite(diversity_index)], na.rm = TRUE)),
      max_value = suppressWarnings(max(diversity_index[is.finite(diversity_index)], na.rm = TRUE))
    )
)

diversity_overall <- diversity_qc |>
  dplyr::filter(is.na(yq)) |>
  dplyr::slice(1)
diversity_sd <- diversity_overall$sd_value[[1]]
if (!is.finite(diversity_overall$observed_adm_n[[1]]) || diversity_overall$observed_adm_n[[1]] == 0L ||
    diversity_overall$unique_n[[1]] <= 1L ||
    !is.finite(diversity_sd) || diversity_sd <= 1e-8) {
  stop(
    sprintf(
      "[ERROR] diversity_index QC failed: observed=%s unique_n=%s sd=%s",
      diversity_overall$observed_adm_n[[1]],
      diversity_overall$unique_n[[1]],
      diversity_sd
    ),
    call. = FALSE
  )
}

quarter_aggregation_qc <- dplyr::bind_rows(
  summarize_year_source_qc(
    sales_q,
    c("total_sales", "sales_count", "age60_sales_share", "sales_time_entropy", "sales_quarter_stability"),
    "sales_quarter",
    "source_quarter_flow + time_entropy + rolling_4q_stability + quarterly_ratio"
  ),
  summarize_year_source_qc(
    store_q,
    c("total_store_count", "opening_rate", "closure_rate", "diversity_index"),
    "store_quarter",
    "source_quarter_stock_flow + quarterly_diversity"
  ),
  summarize_year_source_qc(
    floating_q,
    c("floating_pop", "age60_floating_share", "floating_time_entropy", "floating_quarter_stability"),
    "floating_quarter",
    "source_quarter_level + time_entropy + rolling_4q_stability"
  ),
  summarize_year_source_qc(
    resident_q,
    c("total_household_commercial"),
    "resident_quarter",
    "source_quarter_snapshot_households_only"
  ),
  summarize_year_source_qc(
    worker_q,
    c("worker_pop", "age60_worker_pop"),
    "worker_quarter",
    "source_quarter_snapshot"
  ),
  summarize_year_source_qc(
    income_q,
    c("income_level", "spend_total"),
    "income_quarter",
    "source_quarter_snapshot"
  ),
  summarize_year_source_qc(
    facility_q,
    c("facility_count", "hospital_count", "mall_count", "bus_stop_count", "subway_station_count"),
    "facility_quarter",
    "source_quarter_snapshot + structural_zero_normalization"
  ),
  summarize_year_source_qc(
    apartment_q,
    c("apartment_complex_count", "apartment_mean_price"),
    "apartment_quarter",
    "source_quarter_snapshot"
  ),
  summarize_year_source_qc(
    change_q,
    c("operating_months_rel_seoul", "commercial_change_index_code"),
    "change_quarter",
    "source_quarter_snapshot_difference"
  ),
  diversity_qc
)

# Stage every member of the output set before promotion. This keeps the quarter
# base, raw review companion, raw integrated layer, and aggregation QC in sync
# even when a write fails halfway through the publish step.
staged_outputs <- list(
  quarter_base = list(
    final_path = quarter_base_path,
    staged_path = stage_output_write(quarter_base_path, function(path) write_parquet_safe(out_quarter, path))
  ),
  seoul_raw_review = list(
    final_path = cfg$paths$seoul_raw_review,
    staged_path = stage_output_write(cfg$paths$seoul_raw_review, function(path) write_parquet_safe(seoul_raw_review, path))
  ),
  seoul_raw_integrated_wide = list(
    final_path = cfg$paths$seoul_raw_integrated_wide,
    staged_path = stage_output_write(cfg$paths$seoul_raw_integrated_wide, function(path) write_parquet_safe(raw_integrated_wide, path))
  ),
  panel_quarter_aggregation_qc = list(
    final_path = quarter_aggregation_qc_path,
    staged_path = stage_output_write(quarter_aggregation_qc_path, function(path) write_csv_safe(quarter_aggregation_qc, path))
  )
)

promote_staged_outputs(staged_outputs)

# The final log records both row-count evidence and special publication rules so
# later audits can distinguish expected source behavior from data drift.
log_extreme_summary(out_quarter, "total_sales")
log_extreme_summary(out_quarter, "total_store_count")
log_extreme_summary(out_quarter, "floating_pop")

append_log(cfg$logs$data_qc, sprintf("- Quarter base rows: %d", nrow(out_quarter)))
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Seoul raw staged publish complete: wide_rows=%d wide_cols=%d raw=%s review=%s quarter=%s aggregation_qc=%s",
    nrow(raw_integrated_wide),
    ncol(raw_integrated_wide),
    basename(cfg$paths$seoul_raw_integrated_wide),
    basename(cfg$paths$seoul_raw_review),
    basename(quarter_base_path),
    basename(quarter_aggregation_qc_path)
  )
)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Seoul raw review companion: rows=%d cols=%d (%s)",
    nrow(seoul_raw_review),
    ncol(seoul_raw_review),
    basename(cfg$paths$seoul_raw_review)
  )
)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Review common-key dedup applied: source-specific source_type/quarter_code_raw/quarter_code_source/adm_code/adm_name removed; canonical adm_nm added (name_variant_adm=%d)",
    sum(adm_name_lookup$adm_nm_variant_n > 1L, na.rm = TRUE)
  )
)
append_log(
  cfg$logs$data_qc,
  paste(
    "- Facility structural-zero normalization applied in quarter base:",
    "missing hospital/mall/subway/bus subcomponent counts within active facility rows are treated as 0"
  )
)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Quarterly diversity QC: %s (observed=%d unique=%d sd=%.6f)",
    basename(quarter_aggregation_qc_path),
    diversity_overall$observed_adm_n[[1]],
    diversity_overall$unique_n[[1]],
    diversity_sd
  )
)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Availability flags (facility/apartment) active rows: %d/%d",
    sum(out_quarter$facility_available == 1L, na.rm = TRUE),
    sum(out_quarter$apartment_available == 1L, na.rm = TRUE)
  )
)
