#==============================================================================
# Script    : utils_qc.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Centralize column, key, and missingness checks so that all
#             scripts enforce the same panel-data contracts.
# Author    : Codex
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
  # 데이터셋 contract의 가장 기본 검증이다. 기대한 컬럼이 하나라도
  # 없으면 downstream 처리를 계속하지 않고 즉시 중단한다.
  # 대부분의 스크립트가 raw source 직후와 save 직전에 이 함수를 써서,
  # schema drift를 최대한 앞단에서 잡는다.
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
  # raw source마다 행정동 코드/연도/분기 컬럼명이 달라서, 초기에
  # `adm_cd`, `year`, `quarter`로 맞춰두면 이후 join 코드가 단순해진다.
  # 이 함수는 이름 표준화와 타입 표준화를 같이 수행한다.
  # 즉 컬럼명만 바꾸는 것이 아니라, `adm_cd` padding과
  # `year/quarter` 정수화까지 한 번에 끝낸다.
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
  # raw provenance 단계에서만 year-quarter 문자열이 필요할 때 쓰는 helper다.
  # active annual panel/QC/reporting contract에서는 이 키를 사용하지 않는다.
  sprintf("%dQ%d", as.integer(year), as.integer(quarter))
}


#==============================================================================
# 3. Panel Quality Checks
#==============================================================================

validate_panel_keys <- function(df, keys = c("adm_cd", "year")) {
  # active canonical panel은 `adm_cd-year` 유일키를 가져야 한다.
  # 중복이 있으면 회귀 표본이 조용히 늘어나거나 집계가 틀어질 수 있다.
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
  # raw quarterly staging을 점검할 때만 쓰는 별도 helper다.
  validate_panel_keys(df, keys = keys)
}

summarize_missing <- function(df) {
  # 어떤 변수가 얼마나 비어 있는지 공통 형식으로 요약하는 helper다.
  # 이 결과는 QC csv나 로그 본문으로 바로 저장하기 좋은 long table 형태다.
  tibble::tibble(
    variable = names(df),
    n_missing = vapply(df, function(x) sum(is.na(x)), numeric(1)),
    pct_missing = vapply(df, function(x) mean(is.na(x)), numeric(1))
  ) |>
    dplyr::arrange(dplyr::desc(pct_missing), dplyr::desc(n_missing))
}
