#==============================================================================
# Script    : utils_spatial.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide shared helpers for administrative-boundary discovery,
#             geometry loading, and W creation.
# Author    : Codex
# Created   : 2026-02-28
# Type      : utility
# Inputs    : boundary directories, year identifiers, sf objects
# Outputs   : standardized sf objects, mapping tables, listw objects
# DependsOn : sf, janitor, dplyr, stringr, spdep
#==============================================================================

find_commercial_boundary_shp <- function(boundary_dir) {
  # 서울 상권분석서비스 경계는 파일명 변형이 약간 있을 수 있어서,
  # 허용 패턴 후보를 순서대로 시도한다.
  # 첫 번째 매치만 반환하는 이유는 canonical source contract를 유지하려는 것이다.
  # Colab/Linux에서는 Drive sync 과정에서 Unicode normalization(NFC/NFD)이
  # 달라질 수 있어서, basename 기준 + normalization fallback까지 같이 본다.
  patterns <- c(
    "상권분석서비스\\(영역-행정동\\)[.]shp$",
    "상권분석서비스\\(영역-행정동\\).*[.]shp$"
  )

  shp_files <- list.files(
    boundary_dir,
    pattern = "[.]shp$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (length(shp_files) == 0L) return(NA_character_)

  normalize_unicode <- function(x, form = c("NFC", "NFD")) {
    form <- match.arg(form)
    if (!requireNamespace("stringi", quietly = TRUE)) return(x)
    if (identical(form, "NFC")) {
      stringi::stri_trans_nfc(x)
    } else {
      stringi::stri_trans_nfd(x)
    }
  }

  basename_raw <- basename(shp_files)
  candidate_views <- list(
    full_raw = shp_files,
    base_raw = basename_raw,
    full_nfc = normalize_unicode(shp_files, "NFC"),
    base_nfc = normalize_unicode(basename_raw, "NFC"),
    full_nfd = normalize_unicode(shp_files, "NFD"),
    base_nfd = normalize_unicode(basename_raw, "NFD")
  )

  for (ptn in patterns) {
    for (view in candidate_views) {
      hits <- which(grepl(ptn, view))
      if (length(hits) > 0L) return(shp_files[[hits[[1]]]])
    }
  }

  # exact pattern이 깨진 환경에서도 canonical keyword 조합이 보이면
  # 가장 먼저 잡히는 shapefile을 fallback으로 사용한다.
  keyword_views <- unique(c(
    candidate_views$base_raw,
    candidate_views$base_nfc,
    candidate_views$base_nfd
  ))
  keyword_hit <- grepl("상권분석서비스", keyword_views) & grepl("행정동", keyword_views)
  if (any(keyword_hit)) {
    hit_names <- unique(keyword_views[keyword_hit])
    idx <- match(hit_names[[1]], candidate_views$base_raw)
    if (!is.na(idx)) return(shp_files[[idx]])
  }

  NA_character_
}


#==============================================================================
# 1. Boundary Loading and Standardization
#==============================================================================

load_commercial_boundary <- function(boundary_dir, target_crs = 5179L) {
  # short-run quarterly panel과 auxiliary join이 모두 참조하는 기준
  # 행정동 경계를 읽는 canonical loader다.
  # 상권 경계는 이 프로젝트의 최종 분석 단위이므로,
  # 여기서 만든 `adm_cd`가 downstream panel key의 사실상 원점이 된다.
  shp <- find_commercial_boundary_shp(boundary_dir)
  if (is.na(shp)) stop("[ERROR] commercial boundary shapefile not found", call. = FALSE)

  obj <- sf::st_read(shp, quiet = TRUE) |>
    janitor::clean_names()

  if (is.na(sf::st_crs(obj))) {
    sf::st_crs(obj) <- target_crs
  }
  obj <- sf::st_transform(obj, target_crs)

  code_candidates <- c("adstrd_cd", "adm_cd", "adstrdcd", "adstrd_code")
  code_col <- intersect(code_candidates, names(obj))
  if (length(code_col) == 0) stop("[ERROR] commercial boundary code column not found", call. = FALSE)
  code_col <- code_col[[1]]

  obj$adm_cd_raw <- as.character(obj[[code_col]])
  # 원본 코드값도 `adm_cd_raw`로 남겨 두면,
  # 이후 join mismatch나 원천 데이터 검토 시 역추적이 쉽다.
  obj$adm_cd <- stringr::str_pad(obj$adm_cd_raw, width = 10, side = "left", pad = "0")
  obj
}


#==============================================================================
# 2. Administrative Region Lookup
#==============================================================================

seoul_gu_region_lookup <- function() {
  # 서울 5대 권역생활권-25개 자치구 체계는 행정동 경계의 adm_cd 앞 6자리로
  # 안정적으로 식별된다. expected_adm_n은 2020 기준 425개 행정동 계약의 QC용이다.
  tibble::tribble(
    ~gu_prefix, ~gu_name, ~living_area, ~living_area_order, ~expected_adm_n,
    "001111", "종로구", "도심권", 1L, 17L,
    "001114", "중구", "도심권", 1L, 15L,
    "001117", "용산구", "도심권", 1L, 16L,
    "001120", "성동구", "동북권", 2L, 17L,
    "001121", "광진구", "동북권", 2L, 15L,
    "001123", "동대문구", "동북권", 2L, 14L,
    "001126", "중랑구", "동북권", 2L, 16L,
    "001129", "성북구", "동북권", 2L, 20L,
    "001130", "강북구", "동북권", 2L, 13L,
    "001132", "도봉구", "동북권", 2L, 14L,
    "001135", "노원구", "동북권", 2L, 19L,
    "001138", "은평구", "서북권", 3L, 16L,
    "001141", "서대문구", "서북권", 3L, 14L,
    "001144", "마포구", "서북권", 3L, 16L,
    "001147", "양천구", "서남권", 4L, 18L,
    "001150", "강서구", "서남권", 4L, 20L,
    "001153", "구로구", "서남권", 4L, 16L,
    "001154", "금천구", "서남권", 4L, 10L,
    "001156", "영등포구", "서남권", 4L, 18L,
    "001159", "동작구", "서남권", 4L, 15L,
    "001162", "관악구", "서남권", 4L, 21L,
    "001165", "서초구", "동남권", 5L, 18L,
    "001168", "강남구", "동남권", 5L, 22L,
    "001171", "송파구", "동남권", 5L, 27L,
    "001174", "강동구", "동남권", 5L, 18L
  ) |>
    dplyr::mutate(gu_order = dplyr::row_number()) |>
    dplyr::select(
      gu_prefix, gu_name, gu_order,
      living_area, living_area_order, expected_adm_n
    )
}

build_adm_region_lookup <- function(boundary_tbl, boundary_year = 2020L) {
  # 행정동-자치구-생활권 lookup은 2020 기준 행정동 경계를 원천으로 삼는다.
  # Downstream reporting과 preprocessing에서 같은 정적 계약을 재사용한다.
  base <- if (inherits(boundary_tbl, "sf")) {
    sf::st_drop_geometry(boundary_tbl)
  } else {
    tibble::as_tibble(boundary_tbl)
  }

  if (!"adm_cd" %in% names(base)) {
    stop("[ERROR] boundary table must contain adm_cd", call. = FALSE)
  }
  if (!"adm_nm" %in% names(base)) base$adm_nm <- NA_character_
  if (!"adstrd_nm" %in% names(base)) base$adstrd_nm <- NA_character_

  clean_chr <- function(x) {
    out <- as.character(x)
    blank <- !is.na(out) & stringr::str_squish(out) == ""
    out[blank] <- NA_character_
    out
  }

  base$adm_nm_clean <- clean_chr(base$adm_nm)
  base$adstrd_nm_clean <- clean_chr(base$adstrd_nm)

  lookup <- base |>
    dplyr::transmute(
      adm_cd = as.character(.data$adm_cd),
      adm_nm = dplyr::coalesce(.data$adm_nm_clean, .data$adstrd_nm_clean),
      adstrd_nm = dplyr::coalesce(.data$adstrd_nm_clean, .data$adm_nm_clean),
      gu_prefix = substr(.data$adm_cd, 1L, 6L),
      boundary_year = as.integer(boundary_year)
    ) |>
    dplyr::left_join(seoul_gu_region_lookup(), by = "gu_prefix") |>
    dplyr::select(
      adm_cd, adm_nm, adstrd_nm, gu_prefix,
      gu_name, gu_order, living_area,
      living_area_order, boundary_year
    ) |>
    dplyr::distinct(.data$adm_cd, .keep_all = TRUE) |>
    dplyr::arrange(.data$living_area_order, .data$gu_order, .data$adm_cd)

  unmatched <- lookup |>
    dplyr::filter(is.na(.data$gu_name) | is.na(.data$living_area))
  if (nrow(unmatched) > 0L) {
    stop(
      sprintf(
        "[ERROR] Failed to assign Seoul region lookup for adm_cd: %s",
        paste(unmatched$adm_cd, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  lookup
}

summarise_adm_region_lookup_qc <- function(lookup) {
  required_cols <- c(
    "adm_cd", "adm_nm", "adstrd_nm", "gu_prefix", "gu_name",
    "gu_order", "living_area", "living_area_order", "boundary_year"
  )

  check_row <- function(check_id, pass, detail) {
    tibble::tibble(
      check_id = check_id,
      status = if (isTRUE(pass)) "PASS" else "FAIL",
      detail = as.character(detail)
    )
  }
  missing_required <- setdiff(required_cols, names(lookup))
  complete_required_n <- if (length(missing_required) == 0L) {
    sum(!stats::complete.cases(lookup[, required_cols, drop = FALSE]))
  } else {
    NA_integer_
  }

  expected_gu <- seoul_gu_region_lookup()
  expected_living <- expected_gu |>
    dplyr::group_by(.data$living_area, .data$living_area_order) |>
    dplyr::summarise(expected_adm_n = sum(.data$expected_adm_n), .groups = "drop")

  observed_gu <- lookup |>
    dplyr::count(.data$gu_name, name = "observed_adm_n") |>
    dplyr::left_join(expected_gu |> dplyr::select(gu_name, expected_adm_n), by = "gu_name")

  observed_living <- lookup |>
    dplyr::count(.data$living_area, name = "observed_adm_n") |>
    dplyr::left_join(expected_living, by = "living_area")

  gu_counts_ok <- all(observed_gu$observed_adm_n == observed_gu$expected_adm_n, na.rm = FALSE)
  living_counts_ok <- all(observed_living$observed_adm_n == observed_living$expected_adm_n, na.rm = FALSE)

  tibble::tibble() |>
    dplyr::bind_rows(
      check_row("schema_required_columns", length(missing_required) == 0L, paste(missing_required, collapse = ";")),
      check_row("row_count_425", nrow(lookup) == 425L, nrow(lookup)),
      check_row("unique_adm_cd_425", dplyr::n_distinct(lookup$adm_cd) == 425L, dplyr::n_distinct(lookup$adm_cd)),
      check_row("adm_cd_format_10_digits", all(grepl("^[0-9]{10}$", lookup$adm_cd)), "adm_cd must be zero-padded 10-digit code"),
      check_row("no_missing_region_fields", identical(complete_required_n, 0L), complete_required_n),
      check_row("gu_count_25", dplyr::n_distinct(lookup$gu_name) == 25L, dplyr::n_distinct(lookup$gu_name)),
      check_row("living_area_count_5", dplyr::n_distinct(lookup$living_area) == 5L, dplyr::n_distinct(lookup$living_area)),
      check_row("gu_expected_counts", gu_counts_ok, paste(observed_gu$gu_name, observed_gu$observed_adm_n, observed_gu$expected_adm_n, sep = ":", collapse = ";")),
      check_row("living_area_expected_counts", living_counts_ok, paste(observed_living$living_area, observed_living$observed_adm_n, observed_living$expected_adm_n, sep = ":", collapse = ";")),
      check_row("boundary_year_2020", all(lookup$boundary_year == 2020L), paste(sort(unique(lookup$boundary_year)), collapse = ";"))
    )
}


#==============================================================================
# 3. Spatial Weight Construction
#==============================================================================

build_listw <- function(sf_obj, type = "queen") {
  # Queen/Rook/kNN 기반 공간가중행렬을 같은 인터페이스로 생성한다.
  # `region.id`는 나중에 panel 정렬과 residual Moran에서 다시 쓰이므로
  # 가능하면 `adm_cd`를 그대로 row name으로 심어 둔다.
  region_ids <- if ("adm_cd" %in% names(sf_obj)) as.character(sf_obj$adm_cd) else as.character(seq_len(nrow(sf_obj)))

  nb <- switch(
    type,
    queen = spdep::poly2nb(sf_obj, queen = TRUE, row.names = region_ids),
    rook = spdep::poly2nb(sf_obj, queen = FALSE, row.names = region_ids),
    knn6 = {
      coords <- sf::st_coordinates(sf::st_point_on_surface(sf::st_geometry(sf_obj)))
      spdep::knn2nb(spdep::knearneigh(coords, k = 6), row.names = region_ids)
    },
    knn8 = {
      coords <- sf::st_coordinates(sf::st_point_on_surface(sf::st_geometry(sf_obj)))
      spdep::knn2nb(spdep::knearneigh(coords, k = 8), row.names = region_ids)
    },
    stop("unknown w type")
  )

  # style='W' row-standardization은 메인 연구설계의 기본 규칙이다.
  spdep::nb2listw(nb, style = "W", zero.policy = TRUE)
}


#==============================================================================
# 4. Moran Alignment Helpers
#==============================================================================

get_listw_region_ids <- function(listw_obj) {
  # listw에 저장된 region.id는 panel/geometry 정렬의 기준점이므로,
  # Moran 진단에서는 매번 이 값을 우선 확인한다.
  ids <- attr(listw_obj$neighbours, "region.id")
  if (is.null(ids)) stop("[ERROR] region.id is missing in spatial weights", call. = FALSE)
  as.character(ids)
}

align_numeric_vector_to_listw <- function(data, listw_obj, value_col, id_col = "adm_cd", min_units = 30L) {
  # Moran 계열 진단은 변수별 complete-case 표본으로 다시 W를 subset해야
  # 평균대치 없이도 통계량과 유효 표본 크기를 일관되게 해석할 수 있다.
  if (!id_col %in% names(data)) {
    stop(sprintf("[ERROR] id column missing: %s", id_col), call. = FALSE)
  }
  if (!value_col %in% names(data)) {
    stop(sprintf("[ERROR] value column missing: %s", value_col), call. = FALSE)
  }

  w_ids <- get_listw_region_ids(listw_obj)
  dat <- tibble::as_tibble(data) |>
    dplyr::mutate(
      .region_id = as.character(.data[[id_col]]),
      .value = suppressWarnings(as.numeric(.data[[value_col]]))
    )

  keep_ids <- intersect(w_ids, dat$.region_id)
  if (length(keep_ids) < min_units) {
    stop(sprintf("[ERROR] insufficient overlap between data and W ids: %d", length(keep_ids)), call. = FALSE)
  }

  dat <- dat |>
    dplyr::filter(.region_id %in% keep_ids) |>
    dplyr::slice(match(keep_ids, .region_id))
  lw_overlap <- spdep::subset.listw(listw_obj, subset = w_ids %in% keep_ids, zero.policy = TRUE)

  complete_idx <- is.finite(dat$.value)
  n_missing <- sum(!complete_idx)
  n_complete <- sum(complete_idx)
  if (n_complete < min_units) {
    stop(sprintf("[ERROR] insufficient complete-case overlap for Moran: %d", n_complete), call. = FALSE)
  }

  dat_cc <- dat[complete_idx, , drop = FALSE]
  lw_cc <- spdep::subset.listw(lw_overlap, subset = complete_idx, zero.policy = TRUE)

  list(
    data = dat_cc,
    values = dat_cc$.value,
    ids = dat_cc$.region_id,
    lw = lw_cc,
    n_total = as.integer(length(keep_ids)),
    n_complete = as.integer(n_complete),
    n_missing = as.integer(n_missing),
    missing_policy = "complete_case"
  )
}
