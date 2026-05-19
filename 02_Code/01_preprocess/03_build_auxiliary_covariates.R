#==============================================================================
# Script    : 03_build_auxiliary_covariates.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build quarterly and static auxiliary covariates aligned to
#             `adm_cd-yq` so the quarterly panel can attach structural controls
#             without re-reading raw spatial sources.
# Author    : Codex
# Created   : 2026-02-28
# Type      : panel_building
# Inputs    : seoul_quarter_base.parquet plus raw land, park, transit, medical,
#             mall, senior-facility, and walk-environment sources;
#             Env: KAKAO_REST_API_KEY when unresolved geocoding requests are
#             not already covered by cache files
# Outputs   : aux_covariates.parquet, walk_betweenness_local800_len_v1.parquet,
#             source-specific pre-aggregation records, and related source QC logs
# DependsOn : 02_build_seoul_quarter_base.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# 이 스크립트는 여러 보조 데이터 source를 각각 전처리한 뒤,
# 분기 단위 `aux_covariates`로 묶는 가장 큰 preprocessing branch다.
# 흐름은 크게 네 단계다.
# 1) source별 helper 준비
# 2) source별 pre-aggregation record 생성
# 3) 분기단위 aux_covariates assemble
# 4) QC와 로그 저장
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
load_project_packages(extra = c("httr", "jsonlite", "sfnetworks", "tidygraph", "igraph", "terra", "exactextractr"))

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 03_build_auxiliary_covariates", timestamp()))

quarter_base_path <- value_or(cfg$paths$quarter_base, file.path(cfg$dir_analysis, "seoul_quarter_base.parquet"))

if (!file.exists(quarter_base_path)) {
  stop("[ERROR] seoul_quarter_base.parquet is required before building auxiliary covariates", call. = FALSE)
}

q <- arrow::read_parquet(quarter_base_path) |>
  tibble::as_tibble() |>
  standardize_keys()
assert_required_cols(q, c("adm_cd", "year", "quarter", "yq", "quarter_index"))

# quarter_base가 가진 adm_cd-yq 조합이 aux branch의 기준 격자다.
# 어떤 source를 읽든 최종 출력은 이 `base_quarter`에 맞춰 정렬된다.
years_target <- sort(unique(q$year))
base_quarter <- q |>
  dplyr::distinct(adm_cd, year, quarter, yq, quarter_index) |>
  dplyr::arrange(adm_cd, year, quarter)
base_year <- q |>
  dplyr::distinct(adm_cd, year) |>
  dplyr::arrange(adm_cd, year)
base_adm <- base_year |>
  dplyr::distinct(adm_cd)

make_quarter_start <- function(year, quarter) {
  lubridate::make_date(as.integer(year), (as.integer(quarter) - 1L) * 3L + 1L, 1L)
}

make_quarter_end <- function(year, quarter) {
  year <- as.integer(year)
  quarter <- as.integer(quarter)
  next_year <- year + as.integer(quarter == 4L)
  next_month <- ifelse(quarter == 4L, 1L, quarter * 3L + 1L)
  lubridate::make_date(next_year, next_month, 1L) - lubridate::days(1L)
}

quarter_calendar <- base_quarter |>
  dplyr::distinct(year, quarter, yq, quarter_index) |>
  dplyr::mutate(
    quarter_start = make_quarter_start(year, quarter),
    quarter_end = make_quarter_end(year, quarter)
  ) |>
  dplyr::arrange(quarter_index)

adm_boundary <- load_commercial_boundary(cfg$dir_boundary, target_crs = cfg$target_crs) |>
  dplyr::select(adm_cd, dplyr::any_of("adstrd_nm"), geometry) |>
  sf::st_make_valid()
adm_sf <- adm_boundary |>
  dplyr::select(adm_cd, geometry)

safe_num <- function(x) suppressWarnings(as.numeric(x))

senior_geocode_cache_path <- if (!is.null(cfg$paths$senior_geocode_cache)) {
  cfg$paths$senior_geocode_cache
} else {
  file.path(cfg$dir_intermediate, "senior_geocode_cache.parquet")
}
senior_manual_fix_path <- if (!is.null(cfg$senior_manual_fix_csv)) {
  cfg$senior_manual_fix_csv
} else {
  file.path(cfg$project_root, "02_Code", "00_setup", "senior_geocode_manual_fix.csv")
}
senior_geocode_qc_path <- if (!is.null(cfg$logs$senior_geocode_qc)) {
  cfg$logs$senior_geocode_qc
} else {
  file.path(cfg$dir_logs, "senior_geocode_qc.csv")
}
senior_geocode_type_qc_path <- if (!is.null(cfg$logs$senior_geocode_type_qc)) {
  cfg$logs$senior_geocode_type_qc
} else {
  file.path(cfg$dir_logs, "senior_geocode_type_qc.csv")
}
senior_geocode_unmatched_path <- if (!is.null(cfg$logs$senior_geocode_unmatched)) {
  cfg$logs$senior_geocode_unmatched
} else {
  file.path(cfg$dir_logs, "senior_geocode_unmatched_sample.csv")
}
medical_geocode_cache_path <- if (!is.null(cfg$paths$medical_geocode_cache)) {
  cfg$paths$medical_geocode_cache
} else {
  file.path(cfg$dir_intermediate, "medical_geocode_cache.parquet")
}
medical_geocode_qc_path <- if (!is.null(cfg$logs$medical_geocode_qc)) {
  cfg$logs$medical_geocode_qc
} else {
  file.path(cfg$dir_logs, "medical_geocode_qc.csv")
}
medical_geocode_unmatched_path <- if (!is.null(cfg$logs$medical_geocode_unmatched)) {
  cfg$logs$medical_geocode_unmatched
} else {
  file.path(cfg$dir_logs, "medical_geocode_unmatched_sample.csv")
}
mall_geocode_cache_path <- if (!is.null(cfg$paths$mall_geocode_cache)) {
  cfg$paths$mall_geocode_cache
} else {
  file.path(cfg$dir_intermediate, "mall_geocode_cache.parquet")
}
mall_geocode_qc_path <- if (!is.null(cfg$logs$mall_geocode_qc)) {
  cfg$logs$mall_geocode_qc
} else {
  file.path(cfg$dir_logs, "mall_geocode_qc.csv")
}
mall_geocode_unmatched_path <- if (!is.null(cfg$logs$mall_geocode_unmatched)) {
  cfg$logs$mall_geocode_unmatched
} else {
  file.path(cfg$dir_logs, "mall_geocode_unmatched_sample.csv")
}
apartment_geocode_cache_path <- if (!is.null(cfg$paths$apartment_geocode_cache)) {
  cfg$paths$apartment_geocode_cache
} else {
  file.path(cfg$dir_intermediate, "apartment_geocode_cache.parquet")
}
apartment_registry_qc_path <- if (!is.null(cfg$logs$apartment_registry_qc)) {
  cfg$logs$apartment_registry_qc
} else {
  file.path(cfg$dir_logs, "apartment_registry_qc.csv")
}
apartment_registry_unmatched_path <- if (!is.null(cfg$logs$apartment_registry_unmatched)) {
  cfg$logs$apartment_registry_unmatched
} else {
  file.path(cfg$dir_logs, "apartment_registry_unmatched_sample.csv")
}
apartment_geocode_qc_path <- if (!is.null(cfg$logs$apartment_geocode_qc)) {
  cfg$logs$apartment_geocode_qc
} else {
  file.path(cfg$dir_logs, "apartment_geocode_qc.csv")
}
#==============================================================================
# 1. Auxiliary Source Builder Helpers
#==============================================================================

# helper 계층은 크게 네 묶음이다.
# 1) raw 파일 읽기/이름 정리
# 2) point/line/polygon을 adm_cd에 매핑
# 3) geocoding과 cache/manual-fix 처리
# 4) preagg record를 연단위 aux 변수로 집계
# 특히 aux branch는 source별 데이터 구조가 크게 달라 한 번 만든 helper를
# 재사용할 수 있게 계약을 분명히 적어 두는 것이 중요하다.
build_readr_col_types <- function(path, locale) {
  hdr <- tryCatch(
    readr::read_csv(
      path,
      locale = locale,
      show_col_types = FALSE,
      n_max = 0,
      progress = FALSE
    ),
    error = function(e) NULL
  )

  if (is.null(hdr) || length(names(hdr)) == 0) {
    return(readr::cols(.default = readr::col_guess()))
  }

  # Administrative raw files often mix standard dates with free-form datetime
  # stamps; reading those columns as character avoids locale/version-sensitive
  # POSIX parsing before we explicitly normalize the fields we actually use.
  date_like <- grepl("일자|일시|date|Date|DATE|timestamp|time", names(hdr))
  if (!any(date_like)) {
    return(readr::cols(.default = readr::col_guess()))
  }

  spec_list <- stats::setNames(
    rep(list(readr::col_character()), sum(date_like)),
    names(hdr)[date_like]
  )

  do.call(readr::cols, c(list(.default = readr::col_guess()), spec_list))
}

read_csv_auto <- function(path, n_max = Inf) {
  read_one <- function(locale) {
    col_types <- build_readr_col_types(path, locale)

    if (!is.finite(n_max)) {
      readr::read_csv(
        path,
        locale = locale,
        show_col_types = FALSE,
        col_types = col_types,
        progress = FALSE
      )
    } else {
      readr::read_csv(
        path,
        locale = locale,
        show_col_types = FALSE,
        col_types = col_types,
        n_max = n_max,
        progress = FALSE
      )
    }
  }

  tryCatch(
    read_one(readr::locale(encoding = "CP949")),
    error = function(e) read_one(readr::locale(encoding = "UTF-8"))
  )
}

# 아래 파일/메타 helper는 "어떤 raw를 정본으로 읽을 것인가"를 고정한다.
# aux source는 sidecar, 검토용 export, 임시 사본이 섞이기 쉬워 broad globbing만 쓰면
# 실행 시점마다 다른 파일이 집히는 문제가 생길 수 있다.
find_raw_subdir <- function(prefix) {
  dirs <- list.dirs(cfg$dir_raw, recursive = FALSE, full.names = TRUE)
  hit <- dirs[stringr::str_detect(basename(dirs), paste0("^", prefix, "_"))]
  if (length(hit) == 0) return(NA_character_)
  hit[[1]]
}

resolve_canonical_source_paths <- function(source_key) {
  # source discovery를 broad scan에 맡기지 않고,
  # config에 적힌 canonical basename 계약으로 강제한다.
  # sidecar 파일이 추가돼도 조용히 잘못 집히지 않게 만드는 장치다.
  contract <- cfg$aux_source_contracts[[source_key]]
  if (is.null(contract)) {
    stop(sprintf("[ERROR] Missing aux source contract for '%s'.", source_key), call. = FALSE)
  }

  search_root <- if (!is.null(contract$search_root)) {
    contract$search_root
  } else if (!is.null(contract$dir_prefix)) {
    find_raw_subdir(contract$dir_prefix)
  } else {
    NA_character_
  }

  if (is.na(search_root) || !dir.exists(search_root)) {
    return(character(0))
  }

  files <- list.files(
    search_root,
    recursive = isTRUE(contract$recursive),
    full.names = TRUE,
    all.files = FALSE
  )
  files <- files[file.exists(files)]
  files <- files[!dir.exists(files)]
  normalized_basenames <- normalize_unicode_text(basename(files))

  resolved <- vapply(contract$expected_basenames, function(expected_basename) {
    hits <- files[normalized_basenames == normalize_unicode_text(expected_basename)]
    if (length(hits) == 0) {
      stop(
        sprintf(
          "[ERROR] Missing canonical %s source file '%s' under %s.",
          source_key,
          expected_basename,
          search_root
        ),
        call. = FALSE
      )
    }
    if (length(hits) > 1) {
      stop(
        sprintf(
          "[ERROR] Multiple %s source files matched canonical basename '%s': %s",
          source_key,
          expected_basename,
          paste(basename(hits), collapse = ", ")
        ),
        call. = FALSE
      )
    }
    hits[[1]]
  }, character(1))

  unname(resolved)
}

log_canonical_source_selection <- function(source_key, paths) {
  if (length(paths) == 0) {
    return(invisible(NULL))
  }

  append_log(
    cfg$logs$data_qc,
    sprintf("- %s canonical source selection: %s", source_key, paste(basename(paths), collapse = ", "))
  )
}

extract_year_from_path <- function(path) {
  ys <- stringr::str_extract_all(path, "(19|20)\\d{2}")[[1]]
  if (length(ys) == 0) return(NA_integer_)
  y <- suppressWarnings(as.integer(ys))
  y <- y[is.finite(y) & y >= 2000 & y <= 2100]
  if (length(y) == 0) return(NA_integer_)
  y[[1]]
}

parse_date_safe <- function(x) {
  if (inherits(x, "Date")) {
    return(as.Date(x))
  }
  if (inherits(x, "POSIXt")) {
    return(as.Date(x))
  }

  s_raw <- trimws(as.character(x))
  s_raw[s_raw %in% c("", "NA", "NaN", "NULL")] <- NA_character_

  out <- rep(as.Date(NA_character_), length(s_raw))
  if (length(s_raw) == 0) {
    return(out)
  }

  excel_num <- suppressWarnings(as.numeric(s_raw))
  is_excel_serial <- !is.na(excel_num) &
    is.finite(excel_num) &
    excel_num >= 20000 &
    excel_num <= 80000 &
    !grepl("[^0-9.]", s_raw)
  if (any(is_excel_serial)) {
    out[is_excel_serial] <- as.Date(excel_num[is_excel_serial], origin = "1899-12-30")
  }

  need_text <- !is_excel_serial & !is.na(s_raw)
  if (!any(need_text)) {
    return(out)
  }

  digits <- gsub("[^0-9]", "", s_raw[need_text])
  digits[digits == ""] <- NA_character_
  digits <- ifelse(!is.na(digits) & nchar(digits) >= 8, substr(digits, 1, 8), digits)

  parsed <- rep(as.Date(NA_character_), length(digits))
  can_parse <- !is.na(digits) & nchar(digits) == 8
  if (any(can_parse)) {
    parsed[can_parse] <- as.Date(digits[can_parse], format = "%Y%m%d")
  }

  out[need_text] <- parsed
  out
}

expand_static_to_year <- function(df_static, years = years_target) {
  tidyr::expand_grid(adm_cd = sort(unique(df_static$adm_cd)), year = years) |>
    dplyr::left_join(df_static, by = "adm_cd")
}

pick_column_name <- function(df, candidates) {
  nms <- names(df)
  if (length(nms) == 0) return(NA_character_)
  nms_utf8 <- iconv(as.character(nms), from = "", to = "UTF-8", sub = "")
  cand_utf8 <- iconv(as.character(candidates), from = "", to = "UTF-8", sub = "")

  hit <- match(cand_utf8, nms_utf8)
  if (any(!is.na(hit))) {
    return(nms[hit[which(!is.na(hit))[1]]])
  }

  hit <- match(tolower(cand_utf8), tolower(nms_utf8))
  if (any(!is.na(hit))) {
    return(nms[hit[which(!is.na(hit))[1]]])
  }

  NA_character_
}

normalize_digit_id <- function(x, width = NA_integer_) {
  out <- trimws(as.character(x))
  out[out %in% c("", "NA", "NaN", "NULL")] <- NA_character_
  out <- stringr::str_replace_all(out, "[^0-9]", "")
  out[out == ""] <- NA_character_

  if (is.finite(width)) {
    keep <- !is.na(out)
    out[keep] <- stringr::str_pad(out[keep], width = as.integer(width), side = "left", pad = "0")
  }

  out
}

extract_snapshot_date_from_path <- function(path) {
  digits <- gsub("[^0-9]", "", basename(path))
  token <- stringr::str_extract(digits, "(19|20)\\d{6}")
  if (is.na(token)) return(as.Date(NA_character_))
  suppressWarnings(lubridate::ymd(token, quiet = TRUE))
}

pick_price_column <- function(df) {
  nms <- names(df)
  numeric_cols <- nms[vapply(df, is.numeric, logical(1))]
  if (length(numeric_cols) == 0) return(NA_character_)

  preferred <- nms[grepl("pblntf|official|land|price|a9$|a16$|a17$|a18$|a19$", nms, ignore.case = TRUE)]
  cand <- unique(c(preferred, numeric_cols))

  score_tbl <- purrr::map_dfr(cand, function(nm) {
    x <- safe_num(df[[nm]])
    ok <- is.finite(x)
    if (sum(ok) < 100) return(tibble::tibble(col = nm, score = -Inf))

    x <- x[ok]
    med <- as.numeric(stats::quantile(x, 0.50, na.rm = TRUE))
    p95 <- as.numeric(stats::quantile(x, 0.95, na.rm = TRUE))
    pos_ratio <- mean(x > 0, na.rm = TRUE)
    zero_ratio <- mean(x == 0, na.rm = TRUE)

    score <- log1p(pmax(med, 0)) + log1p(pmax(p95, 0)) + 3 * pos_ratio - 2 * zero_ratio
    if (med < 1000) score <- score - 20
    tibble::tibble(col = nm, score = score)
  })

  if (nrow(score_tbl) == 0 || all(!is.finite(score_tbl$score))) return(NA_character_)
  score_tbl |>
    dplyr::arrange(dplyr::desc(score), col) |>
    dplyr::slice(1) |>
    dplyr::pull(col)
}

fill_group_year_series <- function(df, group_col, value_col, years = years_target) {
  if (nrow(df) == 0 || !group_col %in% names(df) || !value_col %in% names(df)) {
    return(tibble::tibble())
  }

  groups <- sort(unique(as.character(df[[group_col]])))
  base <- tidyr::expand_grid(group_id = groups, year = years)

  obs <- df |>
    dplyr::transmute(
      group_id = as.character(.data[[group_col]]),
      year = as.integer(year),
      value = safe_num(.data[[value_col]])
    )

  out <- base |>
    dplyr::left_join(obs, by = c("group_id", "year")) |>
    dplyr::group_by(group_id) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::mutate(
      value = zoo::na.approx(value, x = year, na.rm = FALSE, rule = 2),
      value = zoo::na.locf(value, na.rm = FALSE),
      value = zoo::na.locf(value, fromLast = TRUE, na.rm = FALSE)
    ) |>
    dplyr::ungroup()

  out <- out |>
    dplyr::transmute(group_id, year, value)
  names(out)[[1]] <- group_col
  names(out)[[3]] <- value_col
  out
}

build_land_price_series <- function(boundary_dir) {
  land_dir <- file.path(boundary_dir, "02_Land_Price")
  if (!dir.exists(land_dir)) {
    return(list(series = tibble::tibble(), observed = tibble::tibble()))
  }

  shp_paths <- list.files(land_dir, pattern = "[.]shp$", recursive = TRUE, full.names = TRUE)
  if (length(shp_paths) == 0) {
    return(list(series = tibble::tibble(), observed = tibble::tibble()))
  }

  meta <- tibble::tibble(path = shp_paths, year = vapply(shp_paths, extract_year_from_path, integer(1))) |>
    dplyr::filter(!is.na(year), year %in% years_target) |>
    dplyr::arrange(year, path) |>
    dplyr::group_by(year) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup()
  if (nrow(meta) == 0) {
    return(list(series = tibble::tibble(), observed = tibble::tibble()))
  }

  adm_ref <- adm_sf |>
    dplyr::select(adm_cd, geometry) |>
    sf::st_make_valid()
  adm_vect <- terra::vect(adm_ref)

  weighted_mean_or_na <- function(x, w) {
    x_num <- safe_num(x)
    w_num <- safe_num(w)
    keep <- is.finite(x_num) & x_num > 0 & is.finite(w_num) & w_num > 0
    if (!any(keep)) return(NA_real_)

    w_sum <- sum(w_num[keep], na.rm = TRUE)
    if (!is.finite(w_sum) || w_sum <= 0) return(NA_real_)

    sum(x_num[keep] * w_num[keep], na.rm = TRUE) / w_sum
  }

  summarize_land_price_weighted <- function(joined, yy, source_name, method) {
    out <- joined |>
      dplyr::filter(
        !is.na(adm_cd),
        is.finite(official_land_price),
        official_land_price > 0,
        is.finite(parcel_area_m2),
        parcel_area_m2 > 0
      ) |>
      dplyr::group_by(adm_cd) |>
      dplyr::summarise(
        official_land_price_area_weighted = weighted_mean_or_na(official_land_price, parcel_area_m2),
        land_price_parcel_n = dplyr::n(),
        land_price_area_m2 = sum(parcel_area_m2, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::filter(is.finite(official_land_price_area_weighted))

    append_log(
      cfg$logs$data_qc,
      sprintf(
        "- Land price area-weighted aggregate (%d): adm=%d parcels=%d area_m2=%.0f source=%s method=%s",
        yy,
        nrow(out),
        sum(out$land_price_parcel_n, na.rm = TRUE),
        sum(out$land_price_area_m2, na.rm = TRUE),
        source_name,
        method
      )
    )

    out |>
      dplyr::transmute(
        year = as.integer(yy),
        adm_cd,
        official_land_price = official_land_price_area_weighted
      )
  }

  aggregate_land_price_with_sf <- function(shp, yy) {
    sf_raw <- tryCatch(sf::st_read(shp, quiet = TRUE), error = function(e) NULL)
    if (is.null(sf_raw) || nrow(sf_raw) == 0) {
      append_log(cfg$logs$data_qc, sprintf("- Land price geometry skipped (%d): %s", yy, shp))
      return(tibble::tibble())
    }

    if (is.na(sf::st_crs(sf_raw))) {
      sf::st_crs(sf_raw) <- 5174L
    }
    sf_raw <- sf_raw |>
      sf::st_transform(cfg$target_crs) |>
      sf::st_make_valid() |>
      janitor::clean_names()

    tbl <- sf::st_drop_geometry(sf_raw)
    price_col <- pick_price_column(tbl)
    if (is.na(price_col) || !price_col %in% names(tbl)) {
      append_log(cfg$logs$data_qc, sprintf("- Land price value column missing (%d): %s", yy, shp))
      return(tibble::tibble())
    }

    sf_raw$parcel_area_m2 <- as.numeric(sf::st_area(sf_raw))

    sf_use <- sf_raw |>
      dplyr::transmute(
        official_land_price = safe_num(.data[[price_col]]),
        parcel_area_m2 = safe_num(parcel_area_m2),
        geometry
      ) |>
      dplyr::filter(
        is.finite(official_land_price),
        official_land_price > 0,
        is.finite(parcel_area_m2),
        parcel_area_m2 > 0
      )

    if (nrow(sf_use) == 0) {
      append_log(cfg$logs$data_qc, sprintf("- Land price positive priced/area parcels absent (%d): %s", yy, basename(shp)))
      return(tibble::tibble())
    }

    pts <- suppressWarnings(sf::st_point_on_surface(sf_use))
    joined <- suppressWarnings(sf::st_join(pts, adm_ref, join = sf::st_within, left = FALSE))

    matched_n <- nrow(joined)
    total_n <- nrow(sf_use)
    append_log(
      cfg$logs$data_qc,
      sprintf(
        "- Land price spatial match (%d): matched=%d unmatched=%d source=%s method=sf_fallback",
        yy,
        matched_n,
        total_n - matched_n,
        basename(shp)
      )
    )

    if (matched_n == 0) {
      return(tibble::tibble())
    }

    summarize_land_price_weighted(
      sf::st_drop_geometry(joined),
      yy = yy,
      source_name = basename(shp),
      method = "sf_point_on_surface_area_weighted"
    )
  }

  aggregate_land_price_with_terra <- function(shp, yy) {
    v_raw <- tryCatch(terra::vect(shp), error = function(e) NULL)
    if (is.null(v_raw) || nrow(v_raw) == 0) {
      append_log(cfg$logs$data_qc, sprintf("- Land price geometry skipped (%d): %s", yy, shp))
      return(tibble::tibble())
    }

    crs_raw <- terra::crs(v_raw, proj = TRUE)
    if (is.na(crs_raw) || identical(crs_raw, "")) {
      terra::crs(v_raw) <- "EPSG:5174"
    }

    names(v_raw) <- janitor::make_clean_names(names(v_raw))
    tbl <- tibble::as_tibble(terra::values(v_raw))
    price_col <- pick_price_column(tbl)
    if (is.na(price_col) || !price_col %in% names(tbl)) {
      append_log(cfg$logs$data_qc, sprintf("- Land price value column missing (%d): %s", yy, shp))
      return(tibble::tibble())
    }

    price_vals <- safe_num(tbl[[price_col]])
    keep <- is.finite(price_vals) & price_vals > 0
    if (!any(keep)) {
      append_log(cfg$logs$data_qc, sprintf("- Land price positive parcels absent (%d): %s", yy, basename(shp)))
      return(tibble::tibble())
    }

    v_use <- v_raw[keep, ]
    v_use$official_land_price <- price_vals[keep]

    parcel_area_m2 <- tryCatch(
      terra::expanse(v_use, unit = "m", transform = TRUE),
      error = function(e) {
        append_log(
          cfg$logs$data_qc,
          sprintf("- Land price area transform failed (%d): %s | fallback=transform_false | reason=%s", yy, basename(shp), e$message)
        )
        terra::expanse(v_use, unit = "m", transform = FALSE)
      }
    )
    area_keep <- is.finite(parcel_area_m2) & parcel_area_m2 > 0
    if (!any(area_keep)) {
      append_log(cfg$logs$data_qc, sprintf("- Land price positive parcel areas absent (%d): %s", yy, basename(shp)))
      return(tibble::tibble())
    }
    if (sum(!area_keep) > 0L) {
      append_log(
        cfg$logs$data_qc,
        sprintf("- Land price invalid parcel areas removed (%d): %d source=%s", yy, sum(!area_keep), basename(shp))
      )
    }

    v_use <- v_use[area_keep, ]
    v_use$parcel_area_m2 <- parcel_area_m2[area_keep]

    # Point-in-polygon matching only needs representative points in the final
    # CRS. Computing inside-centroids before projection avoids reprojecting all
    # parcel polygons and is materially faster on ~900k yearly parcels.
    pts <- terra::centroids(v_use, inside = TRUE)
    pts <- terra::project(pts, paste0("EPSG:", cfg$target_crs))

    hit <- terra::extract(adm_vect, pts)
    pts_tbl <- tibble::as_tibble(terra::values(pts))
    joined <- tibble::tibble(
      adm_cd = hit$adm_cd,
      official_land_price = pts_tbl$official_land_price,
      parcel_area_m2 = pts_tbl$parcel_area_m2
    ) |>
      dplyr::filter(
        !is.na(adm_cd),
        is.finite(official_land_price),
        official_land_price > 0,
        is.finite(parcel_area_m2),
        parcel_area_m2 > 0
      )

    matched_n <- nrow(joined)
    total_n <- nrow(pts_tbl)
    append_log(
      cfg$logs$data_qc,
      sprintf(
        "- Land price spatial match (%d): matched=%d unmatched=%d source=%s method=terra_centroid_inside",
        yy,
        matched_n,
        total_n - matched_n,
        basename(shp)
      )
    )

    if (matched_n == 0) {
      return(tibble::tibble())
    }

    summarize_land_price_weighted(
      joined,
      yy = yy,
      source_name = basename(shp),
      method = "terra_centroid_inside_area_weighted"
    )
  }

  out <- purrr::map2_dfr(meta$path, meta$year, function(shp, yy) {
    tryCatch(
      aggregate_land_price_with_terra(shp, yy),
      error = function(e) {
        append_log(
          cfg$logs$data_qc,
          sprintf("- Land price terra path failed (%d): %s | fallback=sf | reason=%s", yy, basename(shp), e$message)
        )
        aggregate_land_price_with_sf(shp, yy)
      }
    )
  })

  if (nrow(out) == 0) {
    return(list(series = tibble::tibble(), observed = tibble::tibble()))
  }

  observed <- out |>
    dplyr::distinct(year, adm_cd)
  series <- fill_group_year_series(out, "adm_cd", "official_land_price")

  list(series = series, observed = observed)
}

empty_land_price_lpi_quarter <- function() {
  tibble::tibble(
    adm_cd = character(),
    year = integer(),
    quarter = integer(),
    yq = character(),
    land_price_lpi_factor = numeric(),
    land_price_lpi_source_bjd_n = integer(),
    land_price_lpi_weight_coverage = numeric()
  )
}

find_land_price_lpi_csv <- function() {
  lpi_dir <- value_or(cfg$dir_land_price_lpi, file.path(cfg$dir_raw, "14_한국부동산원_전국지가변동률조사"))
  if (!dir.exists(lpi_dir)) return(NA_character_)

  csv_paths <- list.files(lpi_dir, pattern = "[.]csv$", recursive = TRUE, full.names = TRUE)
  csv_paths <- csv_paths[grepl("지가.*지수|지역별", basename(csv_paths))]
  if (length(csv_paths) == 0L) {
    csv_paths <- list.files(lpi_dir, pattern = "[.]csv$", recursive = TRUE, full.names = TRUE)
  }
  if (length(csv_paths) == 0L) return(NA_character_)

  csv_paths[[1L]]
}

find_legal_dong_boundary_shp <- function(boundary_dir) {
  shp_paths <- list.files(boundary_dir, pattern = "[.]shp$", recursive = TRUE, full.names = TRUE)
  hits <- shp_paths[grepl("LSMD_ADM_SECT_UMD", basename(shp_paths))]
  if (length(hits) == 0L) return(NA_character_)
  hits[[1L]]
}

find_seoul_sgg_boundary_shp <- function(boundary_dir) {
  shp_paths <- list.files(boundary_dir, pattern = "[.]shp$", recursive = TRUE, full.names = TRUE)
  hits <- shp_paths[grepl("LARD_ADM_SECT_SGG", basename(shp_paths))]
  if (length(hits) == 0L) return(NA_character_)
  hits[[1L]]
}

read_land_price_lpi_monthly <- function() {
  csv_path <- find_land_price_lpi_csv()
  if (is.na(csv_path) || !file.exists(csv_path)) {
    append_log(cfg$logs$data_qc, "- Land price LPI source missing: adjusted land price will be NA")
    return(tibble::tibble())
  }

  raw <- utils::read.csv(
    csv_path,
    fileEncoding = "CP949",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  if (ncol(raw) < 5L) {
    stop(sprintf("[ERROR] Land price LPI CSV has unexpected schema: %s", basename(csv_path)), call. = FALSE)
  }

  names(raw)[2:4] <- c("si_name", "gu_name", "dong_name")
  raw <- raw |>
    dplyr::filter(.data$No != "No")

  month_cols <- grep("^[0-9]{4}년 [0-9]{1,2}월$", names(raw), value = TRUE)
  if (!all(c("2018년 12월", "2025년 12월") %in% month_cols)) {
    stop(
      sprintf(
        "[ERROR] Land price LPI CSV must contain 2018년 12월 and 2025년 12월: %s",
        basename(csv_path)
      ),
      call. = FALSE
    )
  }

  dong_rows <- raw |>
    dplyr::filter(.data$gu_name != .data$dong_name) |>
    dplyr::select(gu_name, dong_name, dplyr::all_of(month_cols))

  monthly <- dong_rows |>
    tidyr::pivot_longer(
      dplyr::all_of(month_cols),
      names_to = "ym_label",
      values_to = "lpi_index"
    ) |>
    dplyr::mutate(
      year = as.integer(stringr::str_match(.data$ym_label, "^([0-9]{4})년")[, 2]),
      month = as.integer(stringr::str_match(.data$ym_label, "년 ([0-9]{1,2})월$")[, 2]),
      lpi_index = safe_num(.data$lpi_index)
    ) |>
    dplyr::filter(!is.na(.data$year), !is.na(.data$month))

  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Land price LPI raw read: %s (dong rows=%d, month cols=%d)",
      basename(csv_path),
      dplyr::n_distinct(paste(dong_rows$gu_name, dong_rows$dong_name, sep = "|")),
      length(month_cols)
    )
  )

  monthly
}

read_seoul_legal_dong_boundary <- function(boundary_dir) {
  legal_shp <- find_legal_dong_boundary_shp(boundary_dir)
  sgg_shp <- find_seoul_sgg_boundary_shp(boundary_dir)
  if (is.na(legal_shp) || !file.exists(legal_shp)) {
    append_log(cfg$logs$data_qc, "- Seoul legal-dong boundary missing: adjusted land price will be NA")
    return(NULL)
  }
  if (is.na(sgg_shp) || !file.exists(sgg_shp)) {
    stop("[ERROR] Seoul SGG boundary is required to match legal-dong LPI rows", call. = FALSE)
  }

  legal <- sf::st_read(legal_shp, quiet = TRUE, options = "ENCODING=CP949") |>
    sf::st_transform(cfg$target_crs) |>
    sf::st_make_valid() |>
    dplyr::transmute(
      sgg_cd = as.character(.data$COL_ADM_SE),
      bjd_cd = as.character(.data$EMD_CD),
      dong_name = as.character(.data$EMD_NM),
      geometry
    )

  sgg <- sf::st_read(sgg_shp, quiet = TRUE, options = "ENCODING=CP949") |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      sgg_cd = as.character(.data$ADM_SECT_C),
      gu_name = as.character(.data$SGG_NM)
    )

  legal |>
    dplyr::left_join(sgg, by = "sgg_cd") |>
    dplyr::select(bjd_cd, sgg_cd, gu_name, dong_name, geometry)
}

build_land_price_lpi_factor <- function(boundary_dir) {
  lpi_monthly <- read_land_price_lpi_monthly()
  legal <- read_seoul_legal_dong_boundary(boundary_dir)
  if (nrow(lpi_monthly) == 0L || is.null(legal) || nrow(legal) == 0L) {
    return(empty_land_price_lpi_quarter())
  }

  legal_key <- legal |>
    sf::st_drop_geometry() |>
    dplyr::select(bjd_cd, sgg_cd, gu_name, dong_name)

  lpi_key <- lpi_monthly |>
    dplyr::distinct(gu_name, dong_name)

  lpi_match <- lpi_key |>
    dplyr::left_join(legal_key, by = c("gu_name", "dong_name"))

  unmatched_lpi <- lpi_match |>
    dplyr::filter(is.na(.data$bjd_cd))
  unmatched_legal <- legal_key |>
    dplyr::anti_join(lpi_key, by = c("gu_name", "dong_name"))

  raw_match_qc <- tibble::tibble(
    check_id = c("lpi_legal_dong_match", "legal_dong_lpi_match"),
    status = c(
      if (nrow(unmatched_lpi) == 0L) "PASS" else "FAIL",
      if (nrow(unmatched_legal) == 0L) "PASS" else "FAIL"
    ),
    detail = c(
      sprintf("lpi_rows=%d unmatched_lpi=%d", nrow(lpi_key), nrow(unmatched_lpi)),
      sprintf("legal_rows=%d unmatched_legal=%d", nrow(legal_key), nrow(unmatched_legal))
    )
  )
  write_csv_safe(raw_match_qc, file.path(cfg$dir_logs, "land_price_lpi_raw_match_qc.csv"))
  if (nrow(unmatched_lpi) > 0L || nrow(unmatched_legal) > 0L) {
    stop("[ERROR] Land price LPI legal-dong names do not fully match the legal-dong boundary", call. = FALSE)
  }

  lpi_bjd_monthly <- lpi_monthly |>
    dplyr::left_join(legal_key, by = c("gu_name", "dong_name")) |>
    dplyr::select(bjd_cd, sgg_cd, gu_name, dong_name, year, month, lpi_index)

  prev_dec <- lpi_bjd_monthly |>
    dplyr::filter(.data$month == 12L) |>
    dplyr::transmute(
      bjd_cd,
      base_year = .data$year + 1L,
      prev_dec_lpi_index = .data$lpi_index
    )

  quarter_months <- tibble::tibble(
    quarter = rep(seq.int(1L, 4L), each = 3L),
    month = seq.int(1L, 12L)
  )

  bjd_quarter <- lpi_bjd_monthly |>
    dplyr::filter(.data$year %in% years_target) |>
    dplyr::left_join(quarter_months, by = "month") |>
    dplyr::left_join(prev_dec, by = c("bjd_cd", "year" = "base_year")) |>
    dplyr::mutate(
      valid_month = is.finite(.data$lpi_index) &
        is.finite(.data$prev_dec_lpi_index) &
        .data$lpi_index > 0 &
        .data$prev_dec_lpi_index > 0,
      month_factor = dplyr::if_else(.data$valid_month, .data$lpi_index / .data$prev_dec_lpi_index, NA_real_)
    ) |>
    dplyr::group_by(bjd_cd, sgg_cd, gu_name, dong_name, year, quarter) |>
    dplyr::summarise(
      land_price_lpi_factor_bjd = if (sum(.data$valid_month) == 3L) mean(.data$month_factor, na.rm = TRUE) else NA_real_,
      land_price_lpi_month_n = sum(.data$valid_month),
      .groups = "drop"
    )

  adm_ref <- adm_sf |>
    dplyr::select(adm_cd, geometry) |>
    sf::st_make_valid()
  adm_ref$adm_area_m2 <- as.numeric(sf::st_area(adm_ref))

  crosswalk_sf <- suppressWarnings(
    sf::st_intersection(
      adm_ref |> dplyr::select(adm_cd, adm_area_m2),
      legal |> dplyr::select(bjd_cd, sgg_cd, gu_name, dong_name)
    )
  )

  crosswalk <- crosswalk_sf |>
    dplyr::mutate(intersect_area_m2 = as.numeric(sf::st_area(geometry))) |>
    sf::st_drop_geometry() |>
    dplyr::filter(is.finite(.data$intersect_area_m2), .data$intersect_area_m2 > 0) |>
    dplyr::group_by(adm_cd) |>
    dplyr::mutate(
      land_price_lpi_raw_weight = .data$intersect_area_m2 / dplyr::first(.data$adm_area_m2),
      land_price_lpi_raw_weight_sum = sum(.data$land_price_lpi_raw_weight, na.rm = TRUE),
      land_price_lpi_weight = .data$land_price_lpi_raw_weight / .data$land_price_lpi_raw_weight_sum
    ) |>
    dplyr::ungroup() |>
    dplyr::select(
      adm_cd, bjd_cd, sgg_cd, gu_name, dong_name,
      adm_area_m2, intersect_area_m2,
      land_price_lpi_raw_weight, land_price_lpi_raw_weight_sum, land_price_lpi_weight
    )

  write_parquet_safe(crosswalk, cfg$paths$land_price_lpi_crosswalk)

  crosswalk_qc <- crosswalk |>
    dplyr::group_by(adm_cd) |>
    dplyr::summarise(
      bjd_n = dplyr::n_distinct(.data$bjd_cd),
      raw_weight_sum = dplyr::first(.data$land_price_lpi_raw_weight_sum),
      normalized_weight_sum = sum(.data$land_price_lpi_weight, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::summarise(
      adm_n = dplyr::n(),
      min_bjd_n = min(.data$bjd_n),
      max_bjd_n = max(.data$bjd_n),
      min_raw_weight_sum = min(.data$raw_weight_sum, na.rm = TRUE),
      max_raw_weight_sum = max(.data$raw_weight_sum, na.rm = TRUE),
      min_normalized_weight_sum = min(.data$normalized_weight_sum, na.rm = TRUE),
      max_normalized_weight_sum = max(.data$normalized_weight_sum, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      status = dplyr::if_else(
        .data$adm_n == dplyr::n_distinct(base_adm$adm_cd) &
          abs(.data$min_normalized_weight_sum - 1) < 0.000001 &
          abs(.data$max_normalized_weight_sum - 1) < 0.000001,
        "PASS",
        "FAIL"
      )
    )
  write_csv_safe(crosswalk_qc, file.path(cfg$dir_logs, "land_price_lpi_crosswalk_qc.csv"))

  factor_adm <- suppressWarnings(
    crosswalk |>
      dplyr::left_join(bjd_quarter, by = c("bjd_cd", "sgg_cd", "gu_name", "dong_name"))
  ) |>
    dplyr::group_by(adm_cd, year, quarter) |>
    dplyr::summarise(
      land_price_lpi_source_bjd_n = dplyr::n_distinct(.data$bjd_cd[is.finite(.data$land_price_lpi_factor_bjd)]),
      land_price_lpi_weight_coverage = sum(
        .data$land_price_lpi_weight[is.finite(.data$land_price_lpi_factor_bjd)],
        na.rm = TRUE
      ),
      land_price_lpi_factor = dplyr::if_else(
        land_price_lpi_weight_coverage >= 0.999,
        exp(sum(.data$land_price_lpi_weight * log(.data$land_price_lpi_factor_bjd), na.rm = TRUE)),
        NA_real_
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      yq = sprintf("%dQ%d", .data$year, .data$quarter),
      land_price_lpi_source_bjd_n = as.integer(.data$land_price_lpi_source_bjd_n)
    ) |>
    dplyr::select(
      adm_cd, year, quarter, yq,
      land_price_lpi_factor,
      land_price_lpi_source_bjd_n,
      land_price_lpi_weight_coverage
    ) |>
    dplyr::arrange(adm_cd, year, quarter)

  write_parquet_safe(factor_adm, cfg$paths$land_price_lpi_factor)
  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Land price LPI factor built: rows=%d finite=%d crosswalk=%s factor=%s",
      nrow(factor_adm),
      sum(is.finite(factor_adm$land_price_lpi_factor)),
      basename(cfg$paths$land_price_lpi_crosswalk),
      basename(cfg$paths$land_price_lpi_factor)
    )
  )

  factor_adm
}

assign_point_ids_to_adm <- function(points_sf, id_col) {
  within <- suppressWarnings(
    sf::st_join(
      points_sf,
      adm_sf |>
        dplyr::transmute(adm_cd_join = adm_cd),
      join = sf::st_within,
      left = TRUE
    )
  ) |>
    sf::st_drop_geometry() |>
    dplyr::transmute(point_id = .data[[id_col]], adm_cd_within = as.character(adm_cd_join))

  miss_ids <- within |>
    dplyr::filter(is.na(adm_cd_within)) |>
    dplyr::pull(point_id)

  if (length(miss_ids) > 0) {
    miss_sf <- points_sf[points_sf[[id_col]] %in% miss_ids, , drop = FALSE]
    inter <- suppressWarnings(
      sf::st_join(
        miss_sf,
        adm_sf |>
          dplyr::transmute(adm_cd_join = adm_cd),
        join = sf::st_intersects,
        left = TRUE
      )
    ) |>
      sf::st_drop_geometry() |>
      dplyr::transmute(point_id = .data[[id_col]], adm_cd_inter = as.character(adm_cd_join)) |>
      dplyr::filter(!is.na(adm_cd_inter)) |>
      dplyr::arrange(point_id, adm_cd_inter) |>
      dplyr::group_by(point_id) |>
      dplyr::summarise(adm_cd_inter = dplyr::first(adm_cd_inter), .groups = "drop")

    within |>
      dplyr::left_join(inter, by = "point_id") |>
      dplyr::transmute(point_id, adm_cd = dplyr::coalesce(adm_cd_within, adm_cd_inter))
  } else {
    within |>
      dplyr::transmute(point_id, adm_cd = adm_cd_within)
  }
}

map_point_records_to_adm <- function(df, x_col, y_col, source_crs = NA_integer_, id_col = ".record_id") {
  if (!all(c(id_col, x_col, y_col) %in% names(df))) {
    stop(
      sprintf(
        "[ERROR] point mapping columns missing: %s",
        paste(setdiff(c(id_col, x_col, y_col), names(df)), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  out <- df |>
    dplyr::mutate(
      .x_num = safe_num(.data[[x_col]]),
      .y_num = safe_num(.data[[y_col]]),
      lon = NA_real_,
      lat = NA_real_,
      adm_cd = NA_character_
    )

  point_rows <- out |>
    dplyr::filter(is.finite(.x_num), is.finite(.y_num))

  if (nrow(point_rows) == 0) {
    return(out |>
      dplyr::mutate(
        adm_match_status = "missing_coords"
      ) |>
      dplyr::select(-.x_num, -.y_num))
  }

  crs_use <- source_crs
  if (!is.finite(crs_use)) {
    crs_use <- guess_point_crs(point_rows$.x_num, point_rows$.y_num)
  }

  pts_sf <- sf::st_as_sf(point_rows, coords = c(".x_num", ".y_num"), crs = as.integer(crs_use), remove = FALSE)
  pts_target <- sf::st_transform(pts_sf, cfg$target_crs)
  coords_wgs84 <- sf::st_coordinates(sf::st_transform(pts_target, 4326L))
  mapped_ids <- assign_point_ids_to_adm(pts_target, id_col)

  point_map <- pts_target |>
    sf::st_drop_geometry() |>
    dplyr::mutate(
      lon = coords_wgs84[, 1],
      lat = coords_wgs84[, 2]
    ) |>
    dplyr::select(dplyr::all_of(id_col), lon, lat) |>
    dplyr::left_join(mapped_ids, by = setNames("point_id", id_col))

  out |>
    dplyr::left_join(point_map, by = id_col, suffix = c("", "_mapped")) |>
    dplyr::mutate(
      lon = dplyr::coalesce(lon_mapped, lon),
      lat = dplyr::coalesce(lat_mapped, lat),
      adm_cd = dplyr::coalesce(adm_cd_mapped, adm_cd),
      adm_match_status = dplyr::case_when(
        !is.finite(.x_num) | !is.finite(.y_num) ~ "missing_coords",
        !is.na(adm_cd) ~ "matched",
        is.finite(lon) & is.finite(lat) ~ "adm_unmatched",
        TRUE ~ "missing_coords"
      )
    ) |>
    dplyr::select(-.x_num, -.y_num, -lon_mapped, -lat_mapped, -adm_cd_mapped)
}

build_base_year_values <- function(value_cols, fill = NA_real_) {
  vals <- rep(list(fill), length(value_cols))
  names(vals) <- value_cols
  base_year |>
    dplyr::mutate(!!!vals)
}

# betweenness cache는 "정적 adm-level 결과 1행/동"이라는 계약을 강하게 검증한다.
# 캐시 파일이 있더라도 spec_version, 반경, 가중방식, 집계방식이 다르면 재사용하지 않아
# 옛 정의의 값이 조용히 섞이는 일을 막는다.
normalize_walk_betweenness_cache <- function(df, label) {
  required_cols <- c("adm_cd", "betweenness_centrality")

  if (is.null(df) || !all(required_cols %in% names(df))) {
    return(NULL)
  }

  meta_expected <- list(
    spec_version = cfg$walk_betweenness_spec_version,
    radius_m = as.integer(cfg$walk_betweenness_radius_m),
    weight_mode = cfg$walk_betweenness_weight_mode,
    agg_mode = cfg$walk_betweenness_agg_mode
  )

  meta_cols <- c("spec_version", "radius_m", "weight_mode", "agg_mode")
  if (all(meta_cols %in% names(df))) {
    meta_actual <- df |>
      dplyr::summarise(
        spec_version = dplyr::first(spec_version),
        radius_m = dplyr::first(radius_m),
        weight_mode = dplyr::first(weight_mode),
        agg_mode = dplyr::first(agg_mode)
      )

    meta_bad <- !identical(as.character(meta_actual$spec_version[[1]]), as.character(meta_expected$spec_version)) ||
      !identical(as.integer(meta_actual$radius_m[[1]]), as.integer(meta_expected$radius_m)) ||
      !identical(as.character(meta_actual$weight_mode[[1]]), as.character(meta_expected$weight_mode)) ||
      !identical(as.character(meta_actual$agg_mode[[1]]), as.character(meta_expected$agg_mode))

    if (meta_bad) {
      append_log(
        cfg$logs$data_qc,
        sprintf(
          "- Walk betweenness %s invalid: metadata mismatch (expected %s/%sm/%s/%s, found %s/%s/%s/%s)",
          label,
          meta_expected$spec_version,
          meta_expected$radius_m,
          meta_expected$weight_mode,
          meta_expected$agg_mode,
          as.character(meta_actual$spec_version[[1]]),
          as.character(meta_actual$radius_m[[1]]),
          as.character(meta_actual$weight_mode[[1]]),
          as.character(meta_actual$agg_mode[[1]])
        )
      )
      return(NULL)
    }
  }

  cache_qc <- df |>
    dplyr::filter(!is.na(adm_cd)) |>
    dplyr::group_by(adm_cd) |>
    dplyr::summarise(
      n_distinct_non_na = dplyr::n_distinct(betweenness_centrality[is.finite(betweenness_centrality)]),
      .groups = "drop"
    )

  bad_adm <- cache_qc |>
    dplyr::filter(n_distinct_non_na > 1L)

  if (nrow(bad_adm) > 0) {
    append_log(
      cfg$logs$data_qc,
      sprintf(
        "- Walk betweenness %s invalid: %d adm_cd values vary across years",
        label,
        nrow(bad_adm)
      )
    )
    return(NULL)
  }

  df |>
    dplyr::filter(!is.na(adm_cd)) |>
    dplyr::group_by(adm_cd) |>
    dplyr::summarise(
      betweenness_centrality = {
        vals <- betweenness_centrality[is.finite(betweenness_centrality)]
        if (length(vals) == 0) NA_real_ else vals[[1]]
      },
      spec_version = cfg$walk_betweenness_spec_version,
      radius_m = as.integer(cfg$walk_betweenness_radius_m),
      weight_mode = cfg$walk_betweenness_weight_mode,
      agg_mode = cfg$walk_betweenness_agg_mode,
      .groups = "drop"
    ) |>
    dplyr::right_join(base_adm, by = "adm_cd") |>
    dplyr::mutate(
      spec_version = cfg$walk_betweenness_spec_version,
      radius_m = as.integer(cfg$walk_betweenness_radius_m),
      weight_mode = cfg$walk_betweenness_weight_mode,
      agg_mode = cfg$walk_betweenness_agg_mode
    ) |>
    dplyr::select(adm_cd, betweenness_centrality, spec_version, radius_m, weight_mode, agg_mode)
}

write_walk_betweenness_cache <- function(df) {
  cache_tbl <- normalize_walk_betweenness_cache(df, "cache write source")
  if (is.null(cache_tbl)) {
    return(invisible(NULL))
  }

  coverage_n <- sum(is.finite(cache_tbl$betweenness_centrality))
  if (coverage_n == 0) {
    append_log(cfg$logs$data_qc, "- Walk betweenness cache write skipped: no finite values")
    return(invisible(NULL))
  }

  write_parquet_safe(cache_tbl, cfg$paths$walk_betweenness_cache)
  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Walk betweenness cache updated: %s (%d/%d adm_cd)",
      basename(cfg$paths$walk_betweenness_cache),
      coverage_n,
      nrow(cache_tbl)
    )
  )

  invisible(cache_tbl)
}

load_cached_walk_betweenness <- function() {
  cache_path <- cfg$paths$walk_betweenness_cache

  # FALSE 모드에서 cache가 없으면 과거 정의를 억지로 재활용하지 않고 명시적으로 NULL을 돌린다.
  # 현재 betweenness는 사양이 바뀐 변수라, 잘못된 legacy 값보다 NA가 안전하다.
  if (!file.exists(cache_path)) {
    append_log(
      cfg$logs$data_qc,
      sprintf(
        "- Walk betweenness cache missing for spec %s: run once with cfg$run_walk_env_betweenness=TRUE",
        cfg$walk_betweenness_spec_version
      )
    )
    return(NULL)
  }

  cached <- tryCatch(
    arrow::read_parquet(
      cache_path,
      col_select = c(
        "adm_cd",
        "betweenness_centrality",
        "spec_version",
        "radius_m",
        "weight_mode",
        "agg_mode"
      )
    ) |>
      tibble::as_tibble() |>
      standardize_keys(),
    error = function(e) {
      append_log(
        cfg$logs$data_qc,
        sprintf("- Walk betweenness cache read failed: %s", conditionMessage(e))
      )
      NULL
    }
  )

  cached_tbl <- normalize_walk_betweenness_cache(cached, "dedicated cache")
  if (is.null(cached_tbl)) {
    return(NULL)
  }

  coverage_n <- sum(is.finite(cached_tbl$betweenness_centrality))
  if (coverage_n == 0) {
    append_log(cfg$logs$data_qc, "- Walk betweenness cache has no finite values: reuse skipped")
    return(NULL)
  }

  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Walk betweenness cache reused from %s (%s/%sm/%s/%s): %d/%d adm_cd",
      basename(cache_path),
      cfg$walk_betweenness_spec_version,
      cfg$walk_betweenness_radius_m,
      cfg$walk_betweenness_weight_mode,
      cfg$walk_betweenness_agg_mode,
      coverage_n,
      nrow(cached_tbl)
    )
  )

  cached_tbl |>
    dplyr::select(adm_cd, betweenness_centrality)
}

write_aux_source_preagg <- function(df, path, label) {
  # `*_source_preagg`는 raw 복사본이 아니라,
  # 지오코딩/직접매칭/유형분류까지 끝난 "집계 직전 record layer"다.
  write_parquet_safe(df, path)
  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Wrote %s source preagg: %s (%d rows x %d cols)",
      label,
      basename(path),
      nrow(df),
      ncol(df)
    )
  )
}

read_aux_source_preagg <- function(path, label) {
  if (!file.exists(path)) {
    stop(sprintf("[ERROR] %s source preagg not found: %s", label, path), call. = FALSE)
  }

  # assemble 단계에서는 이 preagg를 다시 읽어 연단위 count로 집계한다.
  # intermediate를 실제 first-class input으로 취급하려는 설계다.
  arrow::read_parquet(path) |>
    tibble::as_tibble() |>
    standardize_keys()
}

remove_obsolete_aux_intermediate_files <- function() {
  # naming contract가 여러 차례 바뀌었기 때문에,
  # 과거 intermediate를 남겨 두면 review helper와 사람이 쉽게 혼동한다.
  obsolete_paths <- file.path(
    cfg$dir_intermediate,
    c(
      "land_price_source_panel.parquet",
      "park_source_panel.parquet",
      "transit_source_panel.parquet",
      "medical_source_panel.parquet",
      "mall_source_panel.parquet",
      "senior_source_panel.parquet",
      "walk_environment_source_panel.parquet",
      "aux_land_price_panel.parquet",
      "aux_park_panel.parquet",
      "aux_bus_stop_panel.parquet",
      "aux_subway_station_panel.parquet",
      "aux_medical_panel.parquet",
      "aux_mall_panel.parquet",
      "aux_senior_panel.parquet",
      "aux_walk_environment_panel.parquet",
      "medical_source_raw.parquet",
      "mall_source_raw.parquet",
      "senior_source_raw.parquet",
      "bus_stop_source_raw.parquet",
      "subway_station_source_raw.parquet"
    )
  )

  existing <- obsolete_paths[file.exists(obsolete_paths)]
  if (length(existing) == 0) {
    return(invisible(NULL))
  }

  unlink(existing)
  append_log(
    cfg$logs$data_qc,
    sprintf("- Removed obsolete aux intermediate files: %s", paste(basename(existing), collapse = ", "))
  )
  invisible(NULL)
}

normalize_unicode_text <- function(x) {
  x <- as.character(x)
  if (requireNamespace("stringi", quietly = TRUE)) {
    return(stringi::stri_trans_nfc(x))
  }
  x
}

guess_point_crs <- function(x, y) {
  xx <- safe_num(x)
  yy <- safe_num(y)
  xx <- xx[is.finite(xx)]
  yy <- yy[is.finite(yy)]
  if (length(xx) == 0 || length(yy) == 0) return(cfg$target_crs)
  if (max(abs(xx), na.rm = TRUE) <= 180 && max(abs(yy), na.rm = TRUE) <= 90) return(4326L)
  if (stats::median(xx, na.rm = TRUE) < 300000) return(5174L)
  cfg$target_crs
}

build_permit_panel_count_by_type_from_mapped <- function(
  df,
  years = years_target,
  open_col,
  close_col,
  type_col,
  type_levels
) {
  min_year <- min(years)
  max_year <- max(years)
  min_date <- as.Date(sprintf("%d-01-01", min_year))
  max_date <- as.Date(sprintf("%d-12-31", max_year))

  df2 <- df |>
    dplyr::mutate(
      open_date = parse_date_safe(.data[[open_col]]),
      close_date = parse_date_safe(.data[[close_col]]),
      type_name = as.character(.data[[type_col]])
    ) |>
    dplyr::filter(
      !is.na(adm_cd),
      !is.na(open_date),
      open_date <= max_date,
      is.na(close_date) | close_date >= min_date,
      !is.na(type_name),
      type_name %in% type_levels
    ) |>
    dplyr::mutate(
      start_year = pmax(min_year, as.integer(format(open_date, "%Y"))),
      end_year = pmin(max_year, dplyr::if_else(is.na(close_date), max_year, as.integer(format(close_date, "%Y"))))
    ) |>
    dplyr::filter(start_year <= end_year)

  if (nrow(df2) == 0) {
    return(build_base_year_values(type_levels, fill = 0L))
  }

  out <- df2 |>
    dplyr::select(adm_cd, type_name, start_year, end_year) |>
    dplyr::mutate(year = purrr::map2(start_year, end_year, seq.int)) |>
    tidyr::unnest(year) |>
    dplyr::count(adm_cd, year, type_name, name = "n") |>
    tidyr::pivot_wider(
      names_from = type_name,
      values_from = n,
      values_fill = 0
    )

  for (nm in setdiff(type_levels, names(out))) {
    out[[nm]] <- 0L
  }

  out <- out |>
    dplyr::select(adm_cd, year, dplyr::all_of(type_levels))

  base_year |>
    dplyr::left_join(out, by = c("adm_cd", "year")) |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(type_levels),
        ~ dplyr::coalesce(.x, 0L)
      )
    )
}

build_point_preagg_year_count <- function(df, year_col, count_col) {
  # point source는 관측된 연도만 0/정수 count를 주고,
  # source가 애초에 없는 연도는 NA로 둔다. "0"과 "미관측"을 구분하려는 규칙이다.
  years_observed <- df |>
    dplyr::transmute(year = as.integer(.data[[year_col]])) |>
    dplyr::filter(is.finite(year)) |>
    dplyr::distinct(year) |>
    dplyr::pull(year)

  out <- df |>
    dplyr::transmute(
      adm_cd = adm_cd,
      year = as.integer(.data[[year_col]])
    ) |>
    dplyr::filter(!is.na(adm_cd), is.finite(year)) |>
    dplyr::count(adm_cd, year, name = count_col)

  base_year |>
    dplyr::left_join(out, by = c("adm_cd", "year")) |>
    dplyr::mutate(
      has_source_year = year %in% years_observed,
      !!count_col := dplyr::if_else(has_source_year, dplyr::coalesce(.data[[count_col]], 0L), NA_integer_)
    ) |>
    dplyr::select(-has_source_year)
}

build_point_preagg_quarter_count <- function(df, count_col) {
  # 분기 source는 관측 또는 as-of 발행된 yq만 0/정수 count를 주고,
  # source가 애초에 없는 분기는 NA로 둔다.
  yq_observed <- df |>
    dplyr::transmute(yq = as.character(yq)) |>
    dplyr::filter(!is.na(yq)) |>
    dplyr::distinct(yq) |>
    dplyr::pull(yq)

  out <- df |>
    dplyr::transmute(
      adm_cd = adm_cd,
      year = as.integer(year),
      quarter = as.integer(quarter),
      yq = as.character(yq)
    ) |>
    dplyr::filter(!is.na(adm_cd), !is.na(yq)) |>
    dplyr::count(adm_cd, year, quarter, yq, name = count_col)

  base_quarter |>
    dplyr::left_join(out, by = c("adm_cd", "year", "quarter", "yq")) |>
    dplyr::mutate(
      has_source_yq = yq %in% yq_observed,
      !!count_col := dplyr::if_else(has_source_yq, dplyr::coalesce(.data[[count_col]], 0L), NA_integer_)
    ) |>
    dplyr::select(-has_source_yq)
}

build_park_area_static <- function() {
  park_dir <- file.path(cfg$dir_boundary, "03_Park")
  shp <- list.files(park_dir, pattern = "[.]shp$", full.names = TRUE)
  if (length(shp) == 0) {
    return(base_adm |>
      dplyr::mutate(park_area = NA_real_))
  }

  parks <- sf::st_read(shp[[1]], quiet = TRUE)
  if (is.na(sf::st_crs(parks))) sf::st_crs(parks) <- 5174L
  parks <- sf::st_transform(parks, cfg$target_crs) |>
    janitor::clean_names()

  label_col <- intersect(c("label", "park_type", "ent_name"), names(parks))
  if (length(label_col) == 0) {
    parks$label <- NA_character_
    label_col <- "label"
  } else {
    label_col <- label_col[[1]]
  }

  parks <- parks |>
    dplyr::mutate(
      park_type = stringr::str_remove(as.character(.data[[label_col]]), "\\(.*\\)")
    ) |>
    dplyr::filter(!park_type %in% c("어린이공원", "어린이놀이터", "묘지공원")) |>
    sf::st_make_valid()

  adm_buf <- sf::st_buffer(adm_sf, dist = 400)
  inter <- suppressWarnings(sf::st_intersection(adm_buf, parks))

  if (nrow(inter) == 0) {
    return(base_adm |>
      dplyr::mutate(park_area = 0))
  }

  agg <- inter |>
    dplyr::mutate(park_area = as.numeric(sf::st_area(geometry))) |>
    sf::st_drop_geometry() |>
    dplyr::group_by(adm_cd) |>
    dplyr::summarise(park_area = sum(park_area, na.rm = TRUE), .groups = "drop")

  base_adm |>
    dplyr::left_join(agg, by = "adm_cd") |>
    dplyr::mutate(park_area = dplyr::coalesce(park_area, 0))
}

read_bus_snapshot_file <- function(path) {
  raw <- if (grepl("[.]xlsx$", path, ignore.case = TRUE)) {
    readxl::read_excel(path)
  } else {
    read_csv_auto(path)
  }

  if (nrow(raw) == 0) {
    return(tibble::tibble())
  }

  date_col <- pick_column_name(raw, c("STDR_DE", "기준일", "기준일자"))
  node_col <- pick_column_name(raw, c("NODE_ID", "표준ID"))
  ars_col <- pick_column_name(raw, c("ARSID", "ARS-ID", "ARS_ID", "STTN_NO"))
  name_col <- pick_column_name(raw, c("정류소명", "정류장명", "STTN_NM"))
  x_col <- pick_column_name(raw, c("X좌표", "CRDNT_X", "CRSNT_X", "x", "X"))
  y_col <- pick_column_name(raw, c("Y좌표", "CRDNT_Y", "CRSNT_Y", "y", "Y"))

  if (is.na(x_col) || is.na(y_col)) {
    append_log(cfg$logs$data_qc, sprintf("- Bus file skipped (coords missing): %s", basename(path)))
    return(tibble::tibble())
  }

  snapshot_date <- rep(as.Date(NA_character_), nrow(raw))
  if (!is.na(date_col)) {
    snapshot_date <- parse_date_safe(raw[[date_col]])
  }

  fallback_date <- extract_snapshot_date_from_path(path)
  if (!is.na(fallback_date)) {
    snapshot_date[is.na(snapshot_date)] <- fallback_date
  }

  year_guess <- extract_year_from_path(path)
  year <- suppressWarnings(as.integer(format(snapshot_date, "%Y")))
  if (is.finite(year_guess)) {
    year[is.na(year)] <- year_guess
  }
  if (any(is.na(snapshot_date) & is.finite(year))) {
    snapshot_date[is.na(snapshot_date) & is.finite(year)] <- as.Date(sprintf("%d-12-31", year[is.na(snapshot_date) & is.finite(year)]))
  }

  raw |>
    dplyr::transmute(
      year = as.integer(year),
      snapshot_date = snapshot_date,
      node_id = if (!is.na(node_col)) normalize_digit_id(.data[[node_col]]) else NA_character_,
      ars_id = if (!is.na(ars_col)) normalize_digit_id(.data[[ars_col]], width = 5L) else NA_character_,
      stop_name = if (!is.na(name_col)) as.character(.data[[name_col]]) else NA_character_,
      x = safe_num(.data[[x_col]]),
      y = safe_num(.data[[y_col]]),
      source_file = basename(path)
    ) |>
    dplyr::filter(
      year %in% years_target,
      is.finite(x),
      is.finite(y)
    )
}

build_bus_stop_panel <- function(bus_dir) {
  # 버스 source는 혼합 주기다. 2019/2020/2025는 단일 snapshot을
  # 해당 연도의 4개 분기 대표값으로 쓰고, 2021-2023 및 2024.01-04는
  # 분기말 이전 최신 월별 snapshot을 사용한다.
  bus_files <- resolve_canonical_source_paths("bus_stop")
  if (length(bus_files) == 0) {
    return(list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(bus_stop_count_aux = NA_real_)
    ))
  }
  log_canonical_source_selection("Bus", bus_files)

  bus_raw <- purrr::map_dfr(bus_files, read_bus_snapshot_file)
  if (nrow(bus_raw) == 0) {
    return(list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(bus_stop_count_aux = NA_real_)
    ))
  }

  bus_snapshot_tbl <- bus_raw |>
    dplyr::filter(!is.na(snapshot_date)) |>
    dplyr::distinct(snapshot_date, source_file) |>
    dplyr::mutate(snapshot_year = as.integer(format(snapshot_date, "%Y"))) |>
    dplyr::group_by(snapshot_year) |>
    dplyr::mutate(snapshot_n_in_year = dplyr::n_distinct(snapshot_date)) |>
    dplyr::ungroup()

  if (nrow(bus_snapshot_tbl) == 0) {
    return(list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(bus_stop_count_aux = NA_real_)
    ))
  }

  select_bus_snapshot <- function(target_year, target_quarter, quarter_start, quarter_end) {
    year_snapshots <- bus_snapshot_tbl |>
      dplyr::filter(snapshot_year == target_year) |>
      dplyr::arrange(snapshot_date)

    if (nrow(year_snapshots) == 0) {
      prior <- bus_snapshot_tbl |>
        dplyr::filter(snapshot_date <= quarter_end) |>
        dplyr::arrange(snapshot_date)
      if (nrow(prior) == 0) {
        return(tibble::tibble(
          selected_snapshot_date = as.Date(NA_character_),
          bus_source_precision = "missing_snapshot",
          selected_source_file = NA_character_
        ))
      }
      selected <- dplyr::slice_tail(prior, n = 1)
      return(tibble::tibble(
        selected_snapshot_date = selected$snapshot_date[[1]],
        bus_source_precision = "carried_forward",
        selected_source_file = selected$source_file[[1]]
      ))
    }

    if (dplyr::n_distinct(year_snapshots$snapshot_date) == 1L) {
      selected <- dplyr::slice_head(year_snapshots, n = 1)
      return(tibble::tibble(
        selected_snapshot_date = selected$snapshot_date[[1]],
        bus_source_precision = "annual_snapshot",
        selected_source_file = selected$source_file[[1]]
      ))
    }

    selected <- year_snapshots |>
      dplyr::filter(snapshot_date <= quarter_end) |>
      dplyr::arrange(snapshot_date) |>
      dplyr::slice_tail(n = 1)
    if (nrow(selected) == 0) {
      selected <- dplyr::slice_head(year_snapshots, n = 1)
    }

    precision <- dplyr::if_else(
      selected$snapshot_date[[1]] < quarter_start,
      "carried_forward",
      "monthly_snapshot"
    )
    tibble::tibble(
      selected_snapshot_date = selected$snapshot_date[[1]],
      bus_source_precision = precision,
      selected_source_file = selected$source_file[[1]]
    )
  }

  bus_quarter_plan <- quarter_calendar |>
    dplyr::mutate(
      selected = purrr::pmap(
        list(year, quarter, quarter_start, quarter_end),
        select_bus_snapshot
      )
    ) |>
    tidyr::unnest(selected) |>
    dplyr::select(
      year, quarter, yq, quarter_index, quarter_start, quarter_end,
      selected_snapshot_date, bus_source_precision, selected_source_file
    )

  bus_snapshot_records <- bus_raw |>
    dplyr::mutate(
      stop_uid = dplyr::coalesce(
        node_id,
        ars_id,
        sprintf("%.7f_%.7f", x, y)
      )
    ) |>
    dplyr::distinct(snapshot_date, stop_uid, .keep_all = TRUE)

  if (nrow(bus_snapshot_records) == 0) {
    return(list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(bus_stop_count_aux = NA_real_)
    ))
  }

  snapshot_log <- bus_quarter_plan |>
    dplyr::arrange(quarter_index) |>
    dplyr::mutate(
      txt = sprintf(
        "%s=%s [%s]",
        yq,
        format(selected_snapshot_date, "%Y-%m-%d"),
        bus_source_precision
      )
    ) |>
    dplyr::pull(txt) |>
    paste(collapse = ", ")
  append_log(cfg$logs$data_qc, sprintf("- Bus quarterly snapshots: %s", snapshot_log))

  bus_snapshot_mapped <- bus_snapshot_records |>
    dplyr::mutate(bus_stop_record_id = dplyr::row_number()) |>
    map_point_records_to_adm(
      x_col = "x",
      y_col = "y",
      source_crs = guess_point_crs(bus_snapshot_records$x, bus_snapshot_records$y),
      id_col = "bus_stop_record_id"
    )

  bus_quarter_raw <- bus_quarter_plan |>
    dplyr::filter(!is.na(selected_snapshot_date)) |>
    dplyr::select(
      year, quarter, yq, quarter_index,
      snapshot_date = selected_snapshot_date,
      bus_source_precision,
      selected_source_file
    ) |>
    dplyr::left_join(
      bus_snapshot_mapped |>
        dplyr::select(-year),
      by = "snapshot_date",
      relationship = "many-to-many"
    ) |>
    dplyr::arrange(quarter_index, stop_uid) |>
    dplyr::distinct(yq, stop_uid, .keep_all = TRUE)

  bus_quarter <- build_point_preagg_quarter_count(bus_quarter_raw, "bus_stop_count_aux")

  list(
    raw = bus_quarter_raw,
    quarter = bus_quarter
  )
}

assign_subway_open_rule <- function(df) {
  line_col <- pick_column_name(df, c("호선", "line"))
  name_col <- pick_column_name(df, c("역사명", "역명", "station_name"))
  default_open_date <- min(quarter_calendar$quarter_start, na.rm = TRUE)

  if (is.na(line_col) || is.na(name_col)) {
    return(tibble::tibble(
      open_date = rep(default_open_date, nrow(df)),
      subway_source_precision = rep("pre_2019_existing", nrow(df))
    ))
  }

  line <- trimws(as.character(df[[line_col]]))
  name <- trimws(as.character(df[[name_col]]))

  open_date <- dplyr::case_when(
    line == "김포골드라인" ~ as.Date("2019-09-28"),
    line == "5호선" & name %in% c("미사", "하남풍산") ~ as.Date("2020-08-08"),
    line == "5호선" & (name %in% c("강일", "하남검단산") | stringr::str_detect(name, "^하남시청")) ~ as.Date("2021-03-27"),
    line == "신분당선(연장2)" & name %in% c("신논현", "논현", "신사") ~ as.Date("2022-05-28"),
    line == "신림선" ~ as.Date("2022-05-28"),
    line == "진접선" ~ as.Date("2022-01-01"),
    line == "서해선" ~ as.Date("2023-08-26"),
    line == "8호선" & name == "암사역사공원" ~ as.Date("2024-08-10"),
    line == "별내선" ~ as.Date("2024-08-10"),
    line == "수도권 광역급행철도" ~ as.Date("2024-12-28"),
    TRUE ~ default_open_date
  )

  subway_source_precision <- dplyr::case_when(
    line == "진접선" ~ "year_only_rule",
    open_date == default_open_date ~ "pre_2019_existing",
    TRUE ~ "open_date_rule"
  )

  tibble::tibble(
    open_date = open_date,
    subway_source_precision = subway_source_precision
  )
}

build_subway_station_panel <- function(subway_dir) {
  # 지하철은 현재 station master를 읽은 뒤,
  # 노선별/역별 개통일 규칙을 적용해 quarterly source panel로 확장한다.
  subway_file <- resolve_canonical_source_paths("subway_station")
  if (length(subway_file) == 0) {
    return(list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(subway_station_count_aux = NA_real_)
    ))
  }
  log_canonical_source_selection("Subway", subway_file)

  subway_raw <- read_csv_auto(subway_file[[1]])
  lon_col <- pick_column_name(subway_raw, c("경도", "longitude", "lon"))
  lat_col <- pick_column_name(subway_raw, c("위도", "latitude", "lat"))
  line_col <- pick_column_name(subway_raw, c("호선", "line"))
  name_col <- pick_column_name(subway_raw, c("역사명", "역명", "station_name"))

  if (is.na(lon_col) || is.na(lat_col)) {
    append_log(cfg$logs$data_qc, sprintf("- Subway file skipped (coords missing): %s", basename(subway_file[[1]])))
    return(list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(subway_station_count_aux = NA_real_)
    ))
  }

  subway_open_rule <- assign_subway_open_rule(subway_raw)
  subway_station_base <- subway_raw |>
    dplyr::mutate(
      line_name = if (!is.na(line_col)) trimws(as.character(.data[[line_col]])) else NA_character_,
      station_name = if (!is.na(name_col)) trimws(as.character(.data[[name_col]])) else NA_character_,
      lon = safe_num(.data[[lon_col]]),
      lat = safe_num(.data[[lat_col]]),
      open_date = subway_open_rule$open_date,
      subway_source_precision = subway_open_rule$subway_source_precision,
      source_file = basename(subway_file[[1]])
    ) |>
    dplyr::filter(
      is.finite(lon),
      is.finite(lat),
      !is.na(open_date),
      open_date <= max(quarter_calendar$quarter_end, na.rm = TRUE)
    )

  subway_panel_raw <- tidyr::crossing(
    subway_station_base,
    quarter_calendar
  ) |>
    dplyr::filter(open_date <= quarter_end) |>
    dplyr::mutate(
      open_year = as.integer(format(open_date, "%Y")),
      open_quarter = lubridate::quarter(open_date),
      open_yq = sprintf("%dQ%d", open_year, open_quarter)
    ) |>
    dplyr::distinct(yq, line_name, station_name, lon, lat, .keep_all = TRUE)

  if (nrow(subway_panel_raw) == 0) {
    return(list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(subway_station_count_aux = 0L)
    ))
  }

  rule_log <- subway_station_base |>
    dplyr::distinct(line_name, station_name, open_date, subway_source_precision) |>
    dplyr::count(open_date, subway_source_precision, name = "station_n") |>
    dplyr::arrange(open_date, subway_source_precision) |>
    dplyr::mutate(
      txt = sprintf("%s/%s=%d", format(open_date, "%Y-%m-%d"), subway_source_precision, station_n)
    ) |>
    dplyr::pull(txt) |>
    paste(collapse = ", ")
  append_log(cfg$logs$data_qc, sprintf("- Subway opening-date allocation: %s", rule_log))

  subway_raw_mapped <- subway_panel_raw |>
    dplyr::mutate(subway_station_record_id = dplyr::row_number()) |>
    map_point_records_to_adm(
      x_col = "lon",
      y_col = "lat",
      source_crs = 4326L,
      id_col = "subway_station_record_id"
    )

  subway_quarter <- build_point_preagg_quarter_count(subway_raw_mapped, "subway_station_count_aux")

  list(
    raw = subway_raw_mapped,
    quarter = subway_quarter
  )
}

build_transit_panel <- function() {
  # transit은 bus와 subway를 분리 계산한 뒤 분기 단위로 다시 묶는다.
  # raw/preagg는 별도로 남기고, 최종 aux에서는 adm_cd-yq panel을 사용한다.
  bus_dir <- find_raw_subdir("07")
  subway_dir <- find_raw_subdir("09")

  bus_out <- if (is.na(bus_dir)) {
    list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(bus_stop_count_aux = NA_real_)
    )
  } else {
    build_bus_stop_panel(bus_dir)
  }

  subway_out <- if (is.na(subway_dir)) {
    list(
      raw = tibble::tibble(),
      quarter = base_quarter |>
        dplyr::mutate(subway_station_count_aux = NA_real_)
    )
  } else {
    build_subway_station_panel(subway_dir)
  }

  transit_out <- bus_out$quarter |>
    dplyr::left_join(subway_out$quarter, by = c("adm_cd", "year", "quarter", "yq", "quarter_index"))

  list(
    bus_raw = bus_out$raw,
    bus_quarter = bus_out$quarter,
    subway_raw = subway_out$raw,
    subway_quarter = subway_out$quarter,
    transit_quarter = transit_out
  )
}

medical_detail_step_cols <- c(
  "medical_clinic_count_aux",
  "medical_dental_clinic_count_aux",
  "medical_oriental_clinic_count_aux",
  "medical_hospital_count_aux",
  "medical_nursing_hospital_count_aux",
  "medical_oriental_hospital_count_aux",
  "medical_dental_hospital_count_aux",
  "medical_general_hospital_count_aux",
  "medical_public_health_center_count_aux",
  "medical_public_health_subcenter_count_aux",
  "medical_other_count_aux"
)
medical_detail_cols <- c(
  medical_detail_step_cols,
  "medical_public_health_count_aux"
)

mall_detail_cols <- c(
  "mall_ssm_count_aux",
  "mall_hypermarket_count_aux",
  "mall_department_store_count_aux",
  "mall_shopping_center_count_aux",
  "mall_other_count_aux"
)

senior_detail_cols <- c(
  "senior_gyeongrodang_count_aux",
  "senior_leisure_welfare_count_aux",
  "senior_medical_welfare_count_aux",
  "senior_job_support_count_aux",
  "senior_residential_welfare_count_aux",
  "senior_home_care_count_aux"
)

build_medical_panel <- function() {
  med_dir <- find_raw_subdir("08")
  if (is.na(med_dir)) {
    return(list(
      raw = tibble::tibble(),
      year = build_base_year_values(c("hospital_count_aux", medical_detail_cols))
    ))
  }
  med_files <- resolve_canonical_source_paths("medical")
  if (length(med_files) == 0) {
    return(list(
      raw = tibble::tibble(),
      year = build_base_year_values(c("hospital_count_aux", medical_detail_cols))
    ))
  }
  log_canonical_source_selection("Medical", med_files)
  med_raw <- purrr::map_dfr(med_files, function(path) {
    read_csv_auto(path) |>
      dplyr::mutate(source_file = basename(path))
  })
  if ("업태구분명" %in% names(med_raw)) {
    med_raw <- med_raw |>
      dplyr::filter(.data[["업태구분명"]] != "조산원")
  }

  med_raw <- fill_missing_coords_with_geocode(
    med_raw,
    x_col = "좌표정보(X)",
    y_col = "좌표정보(Y)",
    name_col = "사업장명",
    jibun_col = "지번주소",
    road_col = "도로명주소",
    cache_path = medical_geocode_cache_path,
    qc_path = medical_geocode_qc_path,
    unmatched_path = medical_geocode_unmatched_path,
    log_prefix = "Medical",
    source_crs = 5174L,
    use_keyword_stage = TRUE,
    return_audit = TRUE
  )

  med_raw <- med_raw |>
    dplyr::mutate(
      .record_id = dplyr::row_number(),
      medical_type = dplyr::case_when(
        stringr::str_detect(as.character(.data[["업태구분명"]]), "요양병원") ~ "medical_nursing_hospital_count_aux",
        .data[["업태구분명"]] == "의원" ~ "medical_clinic_count_aux",
        .data[["업태구분명"]] == "치과의원" ~ "medical_dental_clinic_count_aux",
        .data[["업태구분명"]] == "한의원" ~ "medical_oriental_clinic_count_aux",
        .data[["업태구분명"]] == "병원" ~ "medical_hospital_count_aux",
        .data[["업태구분명"]] == "한방병원" ~ "medical_oriental_hospital_count_aux",
        .data[["업태구분명"]] == "치과병원" ~ "medical_dental_hospital_count_aux",
        .data[["업태구분명"]] == "종합병원" ~ "medical_general_hospital_count_aux",
        .data[["업태구분명"]] == "보건소" ~ "medical_public_health_center_count_aux",
        .data[["업태구분명"]] == "보건지소" ~ "medical_public_health_subcenter_count_aux",
        TRUE ~ "medical_other_count_aux"
      )
    )

  med_raw <- map_point_records_to_adm(
    med_raw,
    x_col = "좌표정보(X)",
    y_col = "좌표정보(Y)",
    source_crs = 5174L,
    id_col = ".record_id"
  )

  med_detail <- build_permit_panel_count_by_type_from_mapped(
    med_raw,
    years = years_target,
    open_col = "인허가일자",
    close_col = "폐업일자",
    type_col = "medical_type",
    type_levels = medical_detail_step_cols
  )

  list(
    raw = med_raw |>
      dplyr::mutate(
        medical_record_id = .record_id
      ) |>
      dplyr::select(-.record_id),
    year = med_detail |>
      dplyr::mutate(
        medical_public_health_count_aux = medical_public_health_center_count_aux + medical_public_health_subcenter_count_aux,
        hospital_count_aux = rowSums(dplyr::pick(dplyr::all_of(medical_detail_step_cols)), na.rm = TRUE),
        .before = 3
      )
  )
}

build_mall_panel <- function() {
  mall_dir <- find_raw_subdir("06")
  if (is.na(mall_dir)) {
    return(list(
      raw = tibble::tibble(),
      year = build_base_year_values(c("mall_count_aux", mall_detail_cols))
    ))
  }
  mall_files <- resolve_canonical_source_paths("mall")
  if (length(mall_files) == 0) {
    return(list(
      raw = tibble::tibble(),
      year = build_base_year_values(c("mall_count_aux", mall_detail_cols))
    ))
  }
  log_canonical_source_selection("Mall", mall_files)
  mall_raw <- purrr::map_dfr(mall_files, function(path) {
    read_csv_auto(path) |>
      dplyr::mutate(source_file = basename(path))
  })
  if ("업태구분명" %in% names(mall_raw)) {
    mall_raw <- mall_raw |>
      dplyr::mutate(
        업태구분명_std = normalize_unicode_text(as.character(.data[["업태구분명"]])),
        업태구분명_std = stringr::str_squish(.data[["업태구분명_std"]]),
        업태구분명_std = dplyr::na_if(.data[["업태구분명_std"]], "")
      )
  }
  if ("업태구분명" %in% names(mall_raw)) {
    mall_raw <- mall_raw |>
      dplyr::filter(.data[["업태구분명_std"]] != "시장")
  }
  if ("사업장명" %in% names(mall_raw)) {
    mall_raw <- mall_raw |>
      dplyr::filter(!stringr::str_detect(as.character(.data[["사업장명"]]), "시장"))
  }

  mall_name_address_fix <- c(
    "종로세운상가" = "서울 종로구 장사동 116-4",
    "현대시티타워" = "서울 중구 을지로6가 17-2",
    "(주)미소종합유통" = "서울 마포구 용강동 122-16",
    "홈플러스익스프레스 용강점" = "서울 마포구 용강동 122-16",
    "영등포지하상가" = "서울 영등포구 영등포동3가 32",
    "영등포역앞지하상가" = "서울 영등포구 영등포동3가 33",
    "영등포로타리지하상가" = "서울 영등포구 영등포동3가 32",
    "영등포기계상가" = "서울 영등포구 양평동1가 271",
    "대림상가" = "서울특별시 서초구 잠원동 57-20"
  )
  mall_fix_tbl <- tibble::tibble(
    facility_name = names(mall_name_address_fix),
    fix_address = unname(mall_name_address_fix)
  )

  mall_raw <- fill_missing_coords_with_geocode(
    mall_raw,
    x_col = "좌표정보(X)",
    y_col = "좌표정보(Y)",
    name_col = "사업장명",
    jibun_col = "지번주소",
    road_col = "도로명주소",
    cache_path = mall_geocode_cache_path,
    qc_path = mall_geocode_qc_path,
    unmatched_path = mall_geocode_unmatched_path,
    log_prefix = "Mall",
    source_crs = 5174L,
    manual_fix_tbl = mall_fix_tbl,
    use_keyword_stage = FALSE,
    return_audit = TRUE
  )

  keywords_ssm <- "GS|지에스|롯데슈퍼|롯데프레시|롯데프레쉬|FRESH|롯데마켓|롯데마이슈퍼|롯데프리미엄푸드마켓|롯데하이마트|마켓999|익스프레스|에브리데이|노브랜드|농협"
  keywords_mart <- "이마트|홈플러스|롯데마트|코스트코"
  keywords_dept <- "백화점|이랜드|뉴코아"

  mall_raw <- mall_raw |>
    dplyr::mutate(
      .record_id = dplyr::row_number(),
      mall_type = dplyr::case_when(
        .data[["사업장명"]] == "롯데쇼핑(주) 금천 독산점" ~ "mall_ssm_count_aux",
        .data[["사업장명"]] == "롯데쇼핑(주) 아울렛 가산점" ~ "mall_ssm_count_aux",
        .data[["사업장명"]] == "(주)농협유통 하나로마트 성내점" ~ "mall_hypermarket_count_aux",
        .data[["사업장명"]] == "건강백화점 동의보감" ~ "mall_other_count_aux",
        stringr::str_detect(as.character(.data[["사업장명"]]), "영풍문고") ~ "mall_other_count_aux",
        stringr::str_detect(as.character(.data[["사업장명"]]), keywords_ssm) ~ "mall_ssm_count_aux",
        stringr::str_detect(as.character(.data[["사업장명"]]), keywords_mart) ~ "mall_hypermarket_count_aux",
        stringr::str_detect(as.character(.data[["사업장명"]]), keywords_dept) ~ "mall_department_store_count_aux",
        stringr::str_detect(as.character(.data[["사업장명"]]), "유통") &
          !stringr::str_detect(as.character(.data[["사업장명"]]), "농협") ~ "mall_other_count_aux",
        stringr::str_detect(as.character(.data[["사업장명"]]), "상가|프라자") ~ "mall_other_count_aux",
        .data[["업태구분명_std"]] %in% c("복합쇼핑몰", "쇼핑센터") ~ "mall_shopping_center_count_aux",
        .data[["업태구분명_std"]] == "백화점" ~ "mall_department_store_count_aux",
        .data[["업태구분명_std"]] == "대형마트" ~ "mall_hypermarket_count_aux",
        TRUE ~ "mall_other_count_aux"
      )
    )

  mall_raw <- map_point_records_to_adm(
    mall_raw,
    x_col = "좌표정보(X)",
    y_col = "좌표정보(Y)",
    source_crs = 5174L,
    id_col = ".record_id"
  )

  mall_detail <- build_permit_panel_count_by_type_from_mapped(
    mall_raw,
    years = years_target,
    open_col = "인허가일자",
    close_col = "폐업일자",
    type_col = "mall_type",
    type_levels = mall_detail_cols
  )

  list(
    raw = mall_raw |>
      dplyr::mutate(
        mall_record_id = .record_id
      ) |>
      dplyr::select(-.record_id),
    year = mall_detail |>
      dplyr::mutate(
        mall_count_aux = rowSums(dplyr::pick(dplyr::all_of(mall_detail_cols)), na.rm = TRUE),
        .before = 3
      )
  )
}

clean_senior_address <- function(x) {
  out <- as.character(x)
  out <- stringr::str_replace_all(out, "\\(.*?\\)", "")
  out <- stringr::str_replace(out, ",.*$", "")
  out <- stringr::str_replace_all(out, "\\s+", " ")
  out <- stringr::str_trim(out)
  out[out %in% c("", "NA", "NULL")] <- NA_character_
  out
}

# senior geocoding 전처리는 주소를 여러 단계로 단순화해
# "원문 보존"과 "지오코더 친화적 질의"를 분리한다.
# 특히 괄호, 층/호수, 쉼표 뒤 설명문은 검색 실패를 유발하기 쉬워 순차적으로 제거한다.
clean_address_for_geocode <- function(x) {
  out <- clean_senior_address(x)
  ifelse(is.na(out), NA_character_, stringr::str_squish(out))
}

normalize_sgg_name <- function(x) {
  x |>
    as.character() |>
    stringr::str_replace_all("\\s+", "") |>
    stringr::str_replace_all("서울특별시|서울", "") |>
    stringr::str_extract("[가-힣]+구")
}

extract_sgg_from_address <- function(x) {
  clean_address_for_geocode(x) |>
    normalize_sgg_name()
}

compose_geocode_address <- function(address, sgg_name = NA_character_) {
  out <- clean_address_for_geocode(address)
  if (is.na(out) || out == "") return(NA_character_)

  if (stringr::str_detect(out, "^서울\\s")) {
    out <- stringr::str_replace(out, "^서울\\s", "서울특별시 ")
  }
  if (stringr::str_detect(out, "^서울특별시\\s")) return(out)

  sgg <- normalize_sgg_name(sgg_name)
  if (!is.na(sgg) && sgg != "") return(stringr::str_squish(paste("서울특별시", sgg, out)))
  if (stringr::str_detect(out, "^[가-힣]+구\\s")) return(stringr::str_squish(paste("서울특별시", out)))
  out
}

compose_senior_address <- function(address, sgg_name = NA_character_) {
  compose_geocode_address(address, sgg_name = sgg_name)
}

dedupe_nonempty_keep_order <- function(x) {
  x <- as.character(x)
  x <- x[!is.na(x) & x != ""]
  x[!duplicated(x)]
}

simplify_senior_address_for_geocode <- function(x) {
  out <- clean_senior_address(x)
  out <- stringr::str_replace(out, "\\s+(지하\\s*)?[0-9]+층\\b.*$", "")
  out <- stringr::str_replace(out, "\\s+[0-9A-Za-z-]+호\\b.*$", "")
  out <- stringr::str_replace(out, "\\s+[0-9A-Za-z-]+동\\s+[0-9A-Za-z-]+호\\b.*$", "")
  out <- stringr::str_squish(out)
  out[out %in% c("", "NA", "NULL")] <- NA_character_
  out
}

compose_senior_candidate_address <- function(address, sgg_name = NA_character_, simplify = FALSE) {
  addr <- if (isTRUE(simplify)) simplify_senior_address_for_geocode(address) else clean_address_for_geocode(address)
  compose_geocode_address(addr, sgg_name = sgg_name)
}

normalize_name_match_key <- function(x) {
  out <- as.character(x)
  out <- normalize_unicode_text(out)
  out <- stringr::str_squish(out)
  out[out %in% c("", "NA", "NULL")] <- NA_character_
  out
}

normalize_address_match_key <- function(x) {
  out <- clean_address_for_geocode(x)
  out <- normalize_unicode_text(out)
  out <- stringr::str_squish(out)
  out[out %in% c("", "NA", "NULL")] <- NA_character_
  out
}

read_geocode_query_cache <- function(path) {
  empty <- tibble::tibble(
    query_type = character(),
    query_text = character(),
    query_region = character(),
    lon = numeric(),
    lat = numeric(),
    status = character(),
    updated_at = character()
  )

  if (!file.exists(path)) {
    return(empty)
  }

  x <- tryCatch(
    arrow::read_parquet(path) |> tibble::as_tibble(),
    error = function(e) tibble::tibble()
  )
  if (nrow(x) == 0) {
    return(empty)
  }

  x |>
    dplyr::transmute(
      query_type = tolower(as.character(query_type)),
      query_text = stringr::str_squish(as.character(query_text)),
      query_region = dplyr::coalesce(stringr::str_squish(as.character(query_region)), ""),
      lon = safe_num(lon),
      lat = safe_num(lat),
      status = as.character(status),
      updated_at = as.character(updated_at)
    ) |>
    dplyr::filter(
      !is.na(query_type), query_type != "",
      !is.na(query_text), query_text != ""
    )
}

get_geocode_query_cache_latest <- function(cache_hist) {
  if (nrow(cache_hist) == 0) return(cache_hist)
  cache_hist |>
    dplyr::mutate(.ord = dplyr::row_number()) |>
    dplyr::arrange(query_type, query_text, query_region, updated_at, .ord) |>
    dplyr::group_by(query_type, query_text, query_region) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::select(-.ord)
}

# query cache는 질의문 단위의 히스토리를 남기되, 재사용 시에는 최신 성공/실패 상태 1건만 쓴다.
# 이렇게 해야 동일 질의가 여러 실행에서 반복되어도 마지막 판단을 기준으로 deterministic하게 동작한다.
geocode_kakao_query_single <- function(query_type, query_text, query_region = "", api_key, max_retry = 3L) {
  query_type <- tolower(as.character(query_type[[1]]))
  query_text <- stringr::str_squish(as.character(query_text[[1]]))
  query_region <- dplyr::coalesce(stringr::str_squish(as.character(query_region[[1]])), "")

  base_row <- tibble::tibble(
    query_type = query_type,
    query_text = query_text,
    query_region = query_region,
    lon = NA_real_,
    lat = NA_real_,
    status = "error",
    updated_at = timestamp()
  )

  if (!query_type %in% c("address", "keyword")) {
    base_row$status <- "invalid_type"
    return(base_row)
  }
  if (is.na(query_text) || !nzchar(query_text)) {
    base_row$status <- "blank"
    return(base_row)
  }

  url <- if (query_type == "address") {
    "https://dapi.kakao.com/v2/local/search/address.json"
  } else {
    "https://dapi.kakao.com/v2/local/search/keyword.json"
  }

  for (attempt in seq_len(max_retry)) {
    resp <- tryCatch(
      httr::GET(
        url,
        query = list(query = query_text),
        httr::add_headers(Authorization = sprintf("KakaoAK %s", api_key)),
        httr::timeout(10)
      ),
      error = function(e) e
    )

    if (inherits(resp, "error")) {
      if (attempt == max_retry) {
        base_row$status <- "request_error"
        return(base_row)
      }
      Sys.sleep(0.4 * attempt)
      next
    }

    code <- httr::status_code(resp)
    if (code == 200L) {
      payload <- tryCatch(
        jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8")),
        error = function(e) NULL
      )
      docs <- tryCatch(tibble::as_tibble(payload$documents), error = function(e) tibble::tibble())
      if (nrow(docs) == 0) {
        base_row$status <- "not_found"
        return(base_row)
      }

      row_pick <- 1L
      if (query_type == "keyword" && nzchar(query_region)) {
        addr_name <- if ("address_name" %in% names(docs)) as.character(docs$address_name) else rep("", nrow(docs))
        road_name <- if ("road_address_name" %in% names(docs)) as.character(docs$road_address_name) else rep("", nrow(docs))
        region_hit <- which(
          stringr::str_detect(addr_name, stringr::fixed(query_region)) |
            stringr::str_detect(road_name, stringr::fixed(query_region))
        )
        if (length(region_hit) > 0) row_pick <- region_hit[[1]]
      }

      base_row$lon <- safe_num(docs$x[[row_pick]])
      base_row$lat <- safe_num(docs$y[[row_pick]])
      base_row$status <- if (is.finite(base_row$lon) && is.finite(base_row$lat)) "ok" else "parse_error"
      return(base_row)
    }

    if (code %in% c(429L, 500L, 502L, 503L, 504L) && attempt < max_retry) {
      Sys.sleep(0.5 * attempt)
      next
    }
    base_row$status <- sprintf("http_%d", code)
    return(base_row)
  }

  base_row$status <- "retry_exhausted"
  base_row
}

lookup_geocode_queries <- function(
  query_tbl,
  cache_path,
  api_key,
  log_prefix,
  stage_label,
  rate_sec = 0.12,
  max_retry = 3L
) {
  query_tbl <- query_tbl |>
    dplyr::transmute(
      query_type = tolower(as.character(query_type)),
      query_text = stringr::str_squish(as.character(query_text)),
      query_region = dplyr::coalesce(stringr::str_squish(as.character(query_region)), "")
    ) |>
    dplyr::filter(
      query_type %in% c("address", "keyword"),
      !is.na(query_text), query_text != ""
    ) |>
    dplyr::distinct()

  if (nrow(query_tbl) == 0) {
    return(list(
      lookup = tibble::tibble(
        query_type = character(),
        query_text = character(),
        query_region = character(),
        lon = numeric(),
        lat = numeric(),
        status = character(),
        updated_at = character()
      ),
      stats = tibble::tibble(query_n = 0L, cache_hit_n = 0L, api_call_n = 0L, geocode_success_n = 0L)
    ))
  }

  cache_hist <- read_geocode_query_cache(cache_path)
  cache_latest <- get_geocode_query_cache_latest(cache_hist)
  cache_terminal <- cache_latest |>
    dplyr::filter(status %in% c("ok", "not_found"))

  cache_hit_n <- dplyr::semi_join(query_tbl, cache_terminal, by = c("query_type", "query_text", "query_region")) |>
    nrow()
  need_query <- dplyr::anti_join(query_tbl, cache_terminal, by = c("query_type", "query_text", "query_region"))

  if (nrow(need_query) > 0 && !nzchar(api_key)) {
    stop(
      sprintf(
        "[ERROR] KAKAO_REST_API_KEY is required: unresolved %s queries=%d, cache=%s",
        log_prefix,
        nrow(need_query),
        cache_path
      ),
      call. = FALSE
    )
  }

  if (nrow(need_query) > 0) {
    append_log(cfg$logs$data_qc, sprintf("- %s requests (%s): %d", log_prefix, stage_label, nrow(need_query)))
    queried <- purrr::map_dfr(seq_len(nrow(need_query)), function(i) {
      out <- geocode_kakao_query_single(
        need_query$query_type[[i]],
        need_query$query_text[[i]],
        need_query$query_region[[i]],
        api_key = api_key,
        max_retry = max_retry
      )
      if (i %% 200L == 0L || i == nrow(need_query)) {
        append_log(cfg$logs$data_qc, sprintf("- %s progress (%s): %d/%d", log_prefix, stage_label, i, nrow(need_query)))
      }
      Sys.sleep(rate_sec)
      out
    })
    cache_hist <- dplyr::bind_rows(cache_hist, queried)
    write_parquet_safe(cache_hist, cache_path)
    cache_latest <- get_geocode_query_cache_latest(cache_hist)
  }

  lookup <- query_tbl |>
    dplyr::left_join(cache_latest, by = c("query_type", "query_text", "query_region"))

  geocode_success_n <- sum(lookup$status == "ok" & is.finite(lookup$lon) & is.finite(lookup$lat), na.rm = TRUE)
  list(
    lookup = lookup,
    stats = tibble::tibble(
      query_n = as.integer(nrow(query_tbl)),
      cache_hit_n = as.integer(cache_hit_n),
      api_call_n = as.integer(nrow(need_query)),
      geocode_success_n = as.integer(geocode_success_n)
    )
  )
}

fill_missing_coords_with_geocode <- function(
  df,
  x_col = "좌표정보(X)",
  y_col = "좌표정보(Y)",
  name_col = "사업장명",
  jibun_col = "지번주소",
  road_col = "도로명주소",
  cache_path,
  qc_path,
  unmatched_path,
  log_prefix,
  source_crs = 5174L,
  manual_fix_tbl = NULL,
  use_keyword_stage = FALSE,
  return_audit = FALSE,
  rate_sec = 0.12,
  max_retry = 3L
) {
  if (!all(c(x_col, y_col, name_col, jibun_col, road_col) %in% names(df))) {
    stop(
      sprintf(
        "[ERROR] geocode source columns missing for %s: %s",
        log_prefix,
        paste(setdiff(c(x_col, y_col, name_col, jibun_col, road_col), names(df)), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  # Read the Kakao REST API key from the environment only at call time so
  # cached geocoding results can still be reused without hardcoding secrets.
  api_key <- Sys.getenv("KAKAO_REST_API_KEY", unset = "")
  out <- df |>
    dplyr::mutate(
      .record_id = dplyr::row_number(),
      .x_orig = safe_num(.data[[x_col]]),
      .y_orig = safe_num(.data[[y_col]]),
      .facility_name = stringr::str_squish(as.character(.data[[name_col]])),
      .jibun_raw = as.character(.data[[jibun_col]]),
      .road_raw = as.character(.data[[road_col]])
    )

  if (!is.null(manual_fix_tbl) && nrow(manual_fix_tbl) > 0) {
    out <- out |>
      dplyr::left_join(manual_fix_tbl, by = c(".facility_name" = "facility_name")) |>
      dplyr::mutate(
        .jibun_raw = dplyr::coalesce(fix_address, .jibun_raw)
      ) |>
      dplyr::select(-fix_address)
  }

  out <- out |>
    dplyr::mutate(
      .missing_coord = !is.finite(.x_orig) | !is.finite(.y_orig),
      .jibun_clean = vapply(.jibun_raw, compose_geocode_address, character(1), sgg_name = NA_character_),
      .road_clean = vapply(.road_raw, compose_geocode_address, character(1), sgg_name = NA_character_),
      .keyword_region = dplyr::coalesce(
        extract_sgg_from_address(.road_clean),
        extract_sgg_from_address(.jibun_clean)
      ),
      geocode_coord_missing = .missing_coord
    )

  raw_missing_coord_n <- sum(out$.missing_coord, na.rm = TRUE)
  if (raw_missing_coord_n == 0L) {
    qc_tbl <- tibble::tibble(
      run_ts = timestamp(),
      raw_missing_coord_n = 0L,
      dedup_query_n = 0L,
      address_stage1_hit_n = 0L,
      address_stage2_hit_n = 0L,
      keyword_stage3_hit_n = 0L,
      cache_hit_n = 0L,
      api_call_n = 0L,
      final_filled_n = 0L,
      final_filled_rate = NA_real_,
      remaining_unresolved_n = 0L
    )
    write_csv_safe(qc_tbl, qc_path)
    write_csv_safe(tibble::tibble(), unmatched_path)
    if (isTRUE(return_audit)) {
      return(
        df |>
          dplyr::mutate(
            geocode_coord_missing = FALSE,
            geocode_coord_filled = FALSE,
            geocode_stage = NA_character_,
            geocode_status = NA_character_,
            geocode_point_lon = NA_real_,
            geocode_point_lat = NA_real_
          )
      )
    }
    return(df)
  }

  stage1_candidates <- out |>
    dplyr::filter(.missing_coord) |>
    dplyr::transmute(
      .record_id,
      query_type = "address",
      query_text = .jibun_clean,
      query_region = ""
    )
  stage1_queries <- stage1_candidates |>
    dplyr::filter(!is.na(query_text), query_text != "") |>
    dplyr::distinct(query_type, query_text, query_region)
  stage1_lookup <- lookup_geocode_queries(
    stage1_queries,
    cache_path = cache_path,
    api_key = api_key,
    log_prefix = log_prefix,
    stage_label = "jibun_address",
    rate_sec = rate_sec,
    max_retry = max_retry
  )
  stage1_rows <- stage1_candidates |>
    dplyr::left_join(stage1_lookup$lookup, by = c("query_type", "query_text", "query_region")) |>
    dplyr::rename(stage1_lon = lon, stage1_lat = lat, stage1_status = status)
  out <- out |>
    dplyr::left_join(stage1_rows, by = ".record_id") |>
    dplyr::mutate(
      .resolved_stage1 = .missing_coord & is.finite(stage1_lon) & is.finite(stage1_lat)
    )
  address_stage1_hit_n <- sum(out$.resolved_stage1, na.rm = TRUE)

  stage2_candidates <- out |>
    dplyr::filter(.missing_coord, !.resolved_stage1) |>
    dplyr::transmute(
      .record_id,
      query_type = "address",
      query_text = .road_clean,
      query_region = ""
    )
  stage2_queries <- stage2_candidates |>
    dplyr::filter(!is.na(query_text), query_text != "") |>
    dplyr::distinct(query_type, query_text, query_region)
  stage2_lookup <- lookup_geocode_queries(
    stage2_queries,
    cache_path = cache_path,
    api_key = api_key,
    log_prefix = log_prefix,
    stage_label = "road_address",
    rate_sec = rate_sec,
    max_retry = max_retry
  )
  stage2_rows <- stage2_candidates |>
    dplyr::left_join(stage2_lookup$lookup, by = c("query_type", "query_text", "query_region")) |>
    dplyr::rename(stage2_lon = lon, stage2_lat = lat, stage2_status = status)
  out <- out |>
    dplyr::left_join(stage2_rows, by = ".record_id") |>
    dplyr::mutate(
      .resolved_stage2 = .missing_coord & !.resolved_stage1 & is.finite(stage2_lon) & is.finite(stage2_lat)
    )
  address_stage2_hit_n <- sum(out$.resolved_stage2, na.rm = TRUE)

  stage3_queries <- tibble::tibble(query_type = character(), query_text = character(), query_region = character())
  stage3_lookup <- list(
    lookup = tibble::tibble(query_type = character(), query_text = character(), query_region = character(), lon = numeric(), lat = numeric(), status = character(), updated_at = character()),
    stats = tibble::tibble(query_n = 0L, cache_hit_n = 0L, api_call_n = 0L, geocode_success_n = 0L)
  )

  if (use_keyword_stage) {
    stage3_candidates <- out |>
      dplyr::filter(.missing_coord, !.resolved_stage1, !.resolved_stage2) |>
      dplyr::transmute(
        .record_id,
        query_type = "keyword",
        query_text = .facility_name,
        query_region = dplyr::coalesce(.keyword_region, "")
      )
    stage3_queries <- stage3_candidates |>
      dplyr::filter(!is.na(query_text), query_text != "", query_region != "") |>
      dplyr::distinct(query_type, query_text, query_region)
    stage3_lookup <- lookup_geocode_queries(
      stage3_queries,
      cache_path = cache_path,
      api_key = api_key,
      log_prefix = log_prefix,
      stage_label = "business_keyword",
      rate_sec = rate_sec,
      max_retry = max_retry
    )
    stage3_rows <- stage3_candidates |>
      dplyr::left_join(stage3_lookup$lookup, by = c("query_type", "query_text", "query_region")) |>
      dplyr::rename(stage3_lon = lon, stage3_lat = lat, stage3_status = status)
    out <- out |>
      dplyr::left_join(stage3_rows, by = ".record_id") |>
      dplyr::mutate(
        .resolved_stage3 = .missing_coord &
          !.resolved_stage1 &
          !.resolved_stage2 &
          is.finite(stage3_lon) &
          is.finite(stage3_lat)
      )
  } else {
    out <- out |>
      dplyr::mutate(
        stage3_lon = NA_real_,
        stage3_lat = NA_real_,
        stage3_status = NA_character_,
        .resolved_stage3 = FALSE
      )
  }
  keyword_stage3_hit_n <- sum(out$.resolved_stage3, na.rm = TRUE)

  dedup_query_n <- dplyr::bind_rows(stage1_queries, stage2_queries, stage3_queries) |>
    dplyr::distinct() |>
    nrow()
  cache_hit_n <- stage1_lookup$stats$cache_hit_n[[1]] + stage2_lookup$stats$cache_hit_n[[1]] + stage3_lookup$stats$cache_hit_n[[1]]
  api_call_n <- stage1_lookup$stats$api_call_n[[1]] + stage2_lookup$stats$api_call_n[[1]] + stage3_lookup$stats$api_call_n[[1]]

  out <- out |>
    dplyr::mutate(
      .geocoded_lon = dplyr::coalesce(stage1_lon, stage2_lon, stage3_lon),
      .geocoded_lat = dplyr::coalesce(stage1_lat, stage2_lat, stage3_lat),
      geocode_stage = dplyr::case_when(
        is.finite(stage1_lon) & is.finite(stage1_lat) ~ "jibun_address",
        is.finite(stage2_lon) & is.finite(stage2_lat) ~ "road_address",
        is.finite(stage3_lon) & is.finite(stage3_lat) ~ "business_keyword",
        TRUE ~ NA_character_
      ),
      geocode_status = dplyr::coalesce(stage3_status, stage2_status, stage1_status)
    )

  resolved_fill <- out |>
    dplyr::filter(.missing_coord, is.finite(.geocoded_lon), is.finite(.geocoded_lat)) |>
    dplyr::select(.record_id, .geocoded_lon, .geocoded_lat)

  if (nrow(resolved_fill) > 0) {
    coords_fill <- resolved_fill |>
      sf::st_as_sf(coords = c(".geocoded_lon", ".geocoded_lat"), crs = 4326L) |>
      sf::st_transform(source_crs) |>
      sf::st_coordinates()

    resolved_fill <- resolved_fill |>
      dplyr::mutate(
        x_fill = coords_fill[, 1],
        y_fill = coords_fill[, 2]
      ) |>
      dplyr::select(.record_id, x_fill, y_fill)

    out <- out |>
      dplyr::left_join(resolved_fill, by = ".record_id") |>
      dplyr::mutate(
        !!x_col := dplyr::coalesce(x_fill, .x_orig),
        !!y_col := dplyr::coalesce(y_fill, .y_orig),
        geocode_coord_filled = .missing_coord & is.finite(x_fill) & is.finite(y_fill)
      ) |>
      dplyr::select(-x_fill, -y_fill)
  } else {
    out <- out |>
      dplyr::mutate(
        !!x_col := .x_orig,
        !!y_col := .y_orig,
        geocode_coord_filled = FALSE
      )
  }

  final_filled_n <- sum(out$.missing_coord & is.finite(safe_num(out[[x_col]])) & is.finite(safe_num(out[[y_col]])), na.rm = TRUE)
  remaining_unresolved_n <- raw_missing_coord_n - final_filled_n
  final_filled_rate <- if (raw_missing_coord_n > 0) final_filled_n / raw_missing_coord_n else NA_real_

  unmatched_tbl <- out |>
    dplyr::filter(.missing_coord, !(is.finite(safe_num(.data[[x_col]])) & is.finite(safe_num(.data[[y_col]])))) |>
    dplyr::transmute(
      facility_name = .facility_name,
      jibun_address = .jibun_raw,
      road_address = .road_raw,
      keyword_region = .keyword_region,
      stage1_status,
      stage2_status,
      stage3_status,
      final_status = geocode_status
    ) |>
    dplyr::distinct() |>
    dplyr::slice_head(n = 1000)
  write_csv_safe(unmatched_tbl, unmatched_path)

  qc_tbl <- tibble::tibble(
    run_ts = timestamp(),
    raw_missing_coord_n = as.integer(raw_missing_coord_n),
    dedup_query_n = as.integer(dedup_query_n),
    address_stage1_hit_n = as.integer(address_stage1_hit_n),
    address_stage2_hit_n = as.integer(address_stage2_hit_n),
    keyword_stage3_hit_n = as.integer(keyword_stage3_hit_n),
    cache_hit_n = as.integer(cache_hit_n),
    api_call_n = as.integer(api_call_n),
    final_filled_n = as.integer(final_filled_n),
    final_filled_rate = final_filled_rate,
    remaining_unresolved_n = as.integer(remaining_unresolved_n)
  )
  write_csv_safe(qc_tbl, qc_path)

  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- %s geocode/fill: missing=%d dedup_query=%d stage1=%d stage2=%d stage3=%d final=%d(%.3f) unresolved=%d cache_hit=%d api_call=%d",
      log_prefix,
      raw_missing_coord_n,
      dedup_query_n,
      address_stage1_hit_n,
      address_stage2_hit_n,
      keyword_stage3_hit_n,
      final_filled_n,
      final_filled_rate,
      remaining_unresolved_n,
      cache_hit_n,
      api_call_n
    )
  )

  out <- out |>
    dplyr::mutate(
      geocode_coord_filled = dplyr::coalesce(geocode_coord_filled, FALSE)
    )

  if (isTRUE(return_audit)) {
    out <- out |>
      dplyr::mutate(
        geocode_point_lon = NA_real_,
        geocode_point_lat = NA_real_
      )

    valid_pts <- out |>
      dplyr::filter(is.finite(safe_num(.data[[x_col]])), is.finite(safe_num(.data[[y_col]]))) |>
      dplyr::transmute(
        .record_id,
        .x_out = safe_num(.data[[x_col]]),
        .y_out = safe_num(.data[[y_col]])
      )

    if (nrow(valid_pts) > 0) {
      crs_use <- source_crs
      if (!is.finite(crs_use)) {
        crs_use <- guess_point_crs(valid_pts$.x_out, valid_pts$.y_out)
      }

      pts_sf <- sf::st_as_sf(valid_pts, coords = c(".x_out", ".y_out"), crs = as.integer(crs_use), remove = FALSE)
      coords_wgs84 <- sf::st_coordinates(sf::st_transform(pts_sf, 4326L))
      point_tbl <- valid_pts |>
        dplyr::mutate(
          geocode_point_lon = coords_wgs84[, 1],
          geocode_point_lat = coords_wgs84[, 2]
        ) |>
        dplyr::select(.record_id, geocode_point_lon, geocode_point_lat)

      out <- out |>
        dplyr::select(-geocode_point_lon, -geocode_point_lat) |>
        dplyr::left_join(point_tbl, by = ".record_id")
    }
  }

  out <- out |>
    dplyr::select(-dplyr::starts_with("."))

  if (!isTRUE(return_audit)) {
    out <- out |>
      dplyr::select(-dplyr::any_of(c(
        "geocode_coord_missing",
        "geocode_coord_filled",
        "geocode_stage",
        "geocode_status",
        "geocode_point_lon",
        "geocode_point_lat"
      )))
  }

  out
}

parse_apartment_date <- function(x) {
  x_chr <- as.character(x)
  x_chr <- stringr::str_squish(x_chr)
  x_chr[x_chr %in% c("", "NA", "NULL", "-", ".")] <- NA_character_
  x_chr <- stringr::str_replace_all(x_chr, "[.]", "-")
  x_chr <- stringr::str_replace(x_chr, "\\s.*$", "")

  out <- suppressWarnings(as.Date(x_chr))
  need <- is.na(out) & !is.na(x_chr)
  if (any(need)) {
    out[need] <- suppressWarnings(as.Date(lubridate::ymd(x_chr[need], quiet = TRUE)))
  }
  need <- is.na(out) & !is.na(x_chr)
  if (any(need)) {
    parsed <- suppressWarnings(lubridate::parse_date_time(
      x_chr[need],
      orders = c("ymd", "Ymd", "ym", "Y"),
      quiet = TRUE
    ))
    out[need] <- as.Date(parsed)
  }
  out
}

apartment_household_manual_fixes <- tibble::tibble(
  apartment_code = c("A13071302", "A10021005", "A10023955"),
  apartment_name_fix = c("래미안크레시티", "래미안신반포팰리스", "에피소드수유838"),
  household_count_override = c(2397, 843, 818),
  household_count_fix_note = c(
    "manual correction: raw k-total-household value was 0",
    "manual correction: raw k-total-household value was missing",
    "manual correction: verified household count differs from raw k-total-household value"
  )
)

apartment_adm_manual_fixes <- tibble::tibble(
  apartment_code = c(
    "A10023604",
    "A10023955",
    "A10023372",
    "B20161229",
    "B11680001",
    "B11680041",
    "B11680060"
  ),
  apartment_name_adm_fix = c(
    "고척아이파크MD",
    "에피소드수유838",
    "BX201 청년주택",
    "신월신도브래뉴2차",
    "일원대우",
    "도곡3차아이파크",
    "도곡2차 I-Park"
  ),
  adm_cd_override = c(
    "0011530720", # 고척1동
    "0011305635", # 수유3동
    "0011620585", # 낙성대동
    "0011470600", # 신월5동
    "0011680740", # 일원2동
    "0011680655", # 도곡1동
    "0011680655"  # 도곡1동
  ),
  adm_cd_fix_note = c(
    "manual correction: coordinate missing; verified address maps to 고척1동",
    "manual correction: coordinate missing; verified address maps to 수유3동",
    "manual correction: coordinate missing; verified address maps to 낙성대동",
    "manual correction: coordinate missing; verified address maps to 신월5동",
    "manual correction: coordinate missing; verified address maps to 일원2동",
    "manual correction: coordinate missing; verified address maps to 도곡1동",
    "manual correction: coordinate missing; verified address maps to 도곡1동"
  )
)

read_apartment_registry_raw <- function(path) {
  raw <- read_csv_auto(path)
  code_col <- pick_column_name(raw, c("k-아파트코드", "K-아파트코드", "아파트코드"))
  name_col <- pick_column_name(raw, c("k-아파트명", "K-아파트명", "아파트명", "단지명"))
  type_col <- pick_column_name(raw, c("k-단지분류(아파트,주상복합등등)", "단지분류", "주택유형"))
  road_col <- pick_column_name(raw, c("kapt도로명주소", "도로명주소", "주소(도로명)"))
  sgg_col <- pick_column_name(raw, c("주소(시군구)", "시군구"))
  dong_col <- pick_column_name(raw, c("주소(읍면동)", "읍면동", "법정동"))
  rest_col <- pick_column_name(raw, c("나머지주소", "주소(도로상세주소)", "상세주소"))
  building_col <- pick_column_name(raw, c("k-전체동수", "전체동수", "동수"))
  household_col <- pick_column_name(raw, c("k-전체세대수", "전체세대수", "세대수"))
  approval_col <- pick_column_name(raw, c("k-사용검사일-사용승인일", "K-사용검사일", "사용검사일", "사용승인일"))
  complex_approval_col <- pick_column_name(raw, c("단지승인일", "단지사용승인일"))
  lon_col <- pick_column_name(raw, c("좌표X", "좌표x", "경도", "x", "X"))
  lat_col <- pick_column_name(raw, c("좌표Y", "좌표y", "위도", "y", "Y"))

  required <- c(code_col, name_col, sgg_col, dong_col, building_col, household_col, lon_col, lat_col)
  if (any(is.na(required))) {
    stop(
      sprintf(
        "[ERROR] apartment registry missing required columns: %s",
        paste(c("code", "name", "sgg", "dong", "building", "household", "lon", "lat")[is.na(required)], collapse = ", ")
      ),
      call. = FALSE
    )
  }

  approval_date <- if (!is.na(approval_col)) parse_apartment_date(raw[[approval_col]]) else rep(as.Date(NA), nrow(raw))
  complex_approval_date <- if (!is.na(complex_approval_col)) parse_apartment_date(raw[[complex_approval_col]]) else rep(as.Date(NA), nrow(raw))

  raw |>
    dplyr::transmute(
      apartment_record_id = dplyr::row_number(),
      apartment_code = stringr::str_squish(as.character(.data[[code_col]])),
      apartment_name = stringr::str_squish(as.character(.data[[name_col]])),
      apartment_type = if (!is.na(type_col)) stringr::str_squish(as.character(.data[[type_col]])) else NA_character_,
      kapt_road_address = if (!is.na(road_col)) clean_address_for_geocode(.data[[road_col]]) else NA_character_,
      sgg_name = normalize_sgg_name(.data[[sgg_col]]),
      dong_name = stringr::str_squish(as.character(.data[[dong_col]])),
      rest_address = if (!is.na(rest_col)) stringr::str_squish(as.character(.data[[rest_col]])) else NA_character_,
      building_count = safe_num(gsub(",", "", as.character(.data[[building_col]]))),
      household_count = safe_num(gsub(",", "", as.character(.data[[household_col]]))),
      use_approval_date = dplyr::coalesce(approval_date, complex_approval_date),
      approval_date_raw = if (!is.na(approval_col)) as.character(.data[[approval_col]]) else NA_character_,
      complex_approval_date_raw = if (!is.na(complex_approval_col)) as.character(.data[[complex_approval_col]]) else NA_character_,
      lon_src = safe_num(.data[[lon_col]]),
      lat_src = safe_num(.data[[lat_col]]),
      source_file = basename(path)
    ) |>
    dplyr::mutate(
      apartment_code = dplyr::na_if(apartment_code, ""),
      apartment_name = dplyr::na_if(apartment_name, ""),
      dong_name = dplyr::na_if(dong_name, ""),
      building_count = dplyr::if_else(is.finite(building_count) & building_count >= 0, building_count, NA_real_),
      household_count = dplyr::if_else(is.finite(household_count) & household_count >= 0, household_count, NA_real_),
      use_approval_year = as.integer(format(use_approval_date, "%Y")),
      address_for_geocode = dplyr::coalesce(
        kapt_road_address,
        purrr::map2_chr(
          stringr::str_squish(paste(dong_name, rest_address)),
          sgg_name,
          ~ compose_geocode_address(.x, sgg_name = .y)
        )
      ),
      dong_key = normalize_name_match_key(dong_name)
    ) |>
    dplyr::left_join(apartment_household_manual_fixes, by = "apartment_code") |>
    dplyr::mutate(
      household_count_raw_clean = household_count,
      household_count_manual_fix = !is.na(household_count_override),
      household_count_manual_fix_note = dplyr::if_else(
        household_count_manual_fix,
        household_count_fix_note,
        NA_character_
      ),
      household_count = dplyr::coalesce(household_count_override, household_count)
    ) |>
    dplyr::select(-apartment_name_fix, -household_count_override, -household_count_fix_note)
}

build_apartment_adm_name_lookup <- function() {
  if (!"adstrd_nm" %in% names(adm_boundary)) {
    return(tibble::tibble(dong_key = character(), adm_cd_name = character()))
  }

  adm_boundary |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      adm_cd_name = adm_cd,
      dong_key = normalize_name_match_key(adstrd_nm)
    ) |>
    dplyr::filter(!is.na(dong_key), dong_key != "") |>
    dplyr::group_by(dong_key) |>
    dplyr::filter(dplyr::n() == 1L) |>
    dplyr::ungroup()
}

lookup_apartment_geocode_queries <- function(query_tbl, cache_path, log_prefix = "Apartment", rate_sec = 0.12, max_retry = 3L) {
  query_tbl <- query_tbl |>
    dplyr::transmute(
      query_type = tolower(as.character(query_type)),
      query_text = stringr::str_squish(as.character(query_text)),
      query_region = dplyr::coalesce(stringr::str_squish(as.character(query_region)), "")
    ) |>
    dplyr::filter(
      query_type %in% c("address", "keyword"),
      !is.na(query_text), query_text != ""
    ) |>
    dplyr::distinct()

  empty_lookup <- tibble::tibble(
    query_type = character(),
    query_text = character(),
    query_region = character(),
    lon = numeric(),
    lat = numeric(),
    status = character(),
    updated_at = character()
  )
  if (nrow(query_tbl) == 0) {
    return(list(
      lookup = empty_lookup,
      stats = tibble::tibble(query_n = 0L, cache_hit_n = 0L, api_call_n = 0L, geocode_success_n = 0L, skipped_missing_credentials = FALSE)
    ))
  }

  api_key <- Sys.getenv("KAKAO_REST_API_KEY", unset = "")
  cache_hist <- read_geocode_query_cache(cache_path)
  cache_latest <- get_geocode_query_cache_latest(cache_hist)
  cache_terminal <- cache_latest |>
    dplyr::filter(status %in% c("ok", "not_found"))

  cache_hit_n <- dplyr::semi_join(query_tbl, cache_terminal, by = c("query_type", "query_text", "query_region")) |>
    nrow()
  need_query <- dplyr::anti_join(query_tbl, cache_terminal, by = c("query_type", "query_text", "query_region"))
  skipped_missing_credentials <- nrow(need_query) > 0 && !nzchar(api_key)

  if (skipped_missing_credentials) {
    append_log(
      cfg$logs$data_qc,
      sprintf("- %s geocoding skipped unresolved queries due to missing KAKAO_REST_API_KEY: %d", log_prefix, nrow(need_query))
    )
  }

  if (nrow(need_query) > 0 && nzchar(api_key)) {
    append_log(cfg$logs$data_qc, sprintf("- %s geocoding requests: %d", log_prefix, nrow(need_query)))
    queried <- purrr::map_dfr(seq_len(nrow(need_query)), function(i) {
      out <- geocode_kakao_query_single(
        query_type = need_query$query_type[[i]],
        query_text = need_query$query_text[[i]],
        query_region = need_query$query_region[[i]],
        api_key = api_key,
        max_retry = max_retry
      )
      if (i %% 100L == 0L || i == nrow(need_query)) {
        append_log(cfg$logs$data_qc, sprintf("- %s geocoding progress: %d/%d", log_prefix, i, nrow(need_query)))
      }
      Sys.sleep(rate_sec)
      out
    })
    cache_hist <- dplyr::bind_rows(cache_hist, queried)
    write_parquet_safe(cache_hist, cache_path)
    cache_latest <- get_geocode_query_cache_latest(cache_hist)
  }

  lookup <- query_tbl |>
    dplyr::left_join(cache_latest, by = c("query_type", "query_text", "query_region"))
  geocode_success_n <- sum(lookup$status == "ok" & is.finite(lookup$lon) & is.finite(lookup$lat), na.rm = TRUE)

  list(
    lookup = lookup,
    stats = tibble::tibble(
      query_n = as.integer(nrow(query_tbl)),
      cache_hit_n = as.integer(cache_hit_n),
      api_call_n = as.integer(if (nzchar(api_key)) nrow(need_query) else 0L),
      geocode_success_n = as.integer(geocode_success_n),
      skipped_missing_credentials = skipped_missing_credentials
    )
  )
}

fill_apartment_adm_with_geocode <- function(df) {
  missing_rows <- df |>
    dplyr::filter(is.na(adm_cd))
  if (nrow(missing_rows) == 0) {
    return(list(
      data = df,
      stats = tibble::tibble(query_n = 0L, cache_hit_n = 0L, api_call_n = 0L, geocode_success_n = 0L, geocode_adm_matched_n = 0L, skipped_missing_credentials = FALSE)
    ))
  }

  candidates <- dplyr::bind_rows(
    missing_rows |>
      dplyr::transmute(
        apartment_record_id,
        stage_rank = 1L,
        query_type = "address",
        query_text = kapt_road_address,
        query_region = ""
      ),
    missing_rows |>
      dplyr::transmute(
        apartment_record_id,
        stage_rank = 2L,
        query_type = "address",
        query_text = address_for_geocode,
        query_region = ""
      )
  ) |>
    dplyr::filter(!is.na(query_text), query_text != "") |>
    dplyr::distinct(apartment_record_id, stage_rank, query_type, query_text, query_region)

  geo_lookup <- lookup_apartment_geocode_queries(
    candidates |> dplyr::select(query_type, query_text, query_region),
    cache_path = apartment_geocode_cache_path
  )

  resolved <- candidates |>
    dplyr::left_join(geo_lookup$lookup, by = c("query_type", "query_text", "query_region")) |>
    dplyr::filter(status == "ok", is.finite(lon), is.finite(lat)) |>
    dplyr::arrange(apartment_record_id, stage_rank) |>
    dplyr::group_by(apartment_record_id) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      apartment_record_id,
      geocode_stage = dplyr::case_when(stage_rank == 1L ~ "road_address", TRUE ~ "composed_address"),
      geocode_status = status,
      geocode_lon = lon,
      geocode_lat = lat
    )

  if (nrow(resolved) > 0) {
    resolved_mapped <- resolved |>
      dplyr::select(apartment_record_id, geocode_lon, geocode_lat, geocode_stage, geocode_status) |>
      map_point_records_to_adm(
        x_col = "geocode_lon",
        y_col = "geocode_lat",
        source_crs = 4326L,
        id_col = "apartment_record_id"
      ) |>
      dplyr::transmute(
        apartment_record_id,
        adm_cd_geocode = adm_cd,
        geocode_point_lon = lon,
        geocode_point_lat = lat,
        geocode_stage,
        geocode_status,
        geocode_adm_match_status = adm_match_status
      )
  } else {
    resolved_mapped <- tibble::tibble(
      apartment_record_id = integer(),
      adm_cd_geocode = character(),
      geocode_point_lon = numeric(),
      geocode_point_lat = numeric(),
      geocode_stage = character(),
      geocode_status = character(),
      geocode_adm_match_status = character()
    )
  }

  out <- df |>
    dplyr::left_join(resolved_mapped, by = "apartment_record_id") |>
    dplyr::mutate(
      adm_cd = dplyr::coalesce(adm_cd, adm_cd_geocode),
      adm_match_status = dplyr::case_when(
        !is.na(adm_cd_geocode) ~ "geocode_address",
        TRUE ~ adm_match_status
      )
    ) |>
    dplyr::select(-adm_cd_geocode)

  list(
    data = out,
    stats = geo_lookup$stats |>
      dplyr::mutate(
        geocode_adm_matched_n = as.integer(sum(!is.na(resolved_mapped$adm_cd_geocode), na.rm = TRUE))
      )
  )
}

build_apartment_registry_panel <- function() {
  apartment_file <- resolve_canonical_source_paths("apartment_registry")
  if (length(apartment_file) == 0) {
    stop("[ERROR] Seoul apartment registry source is required for ln_apartment_household_count", call. = FALSE)
  }
  log_canonical_source_selection("Apartment registry", apartment_file)

  apt_raw <- read_apartment_registry_raw(apartment_file[[1]])
  apt_mapped <- apt_raw |>
    map_point_records_to_adm(
      x_col = "lon_src",
      y_col = "lat_src",
      source_crs = 4326L,
      id_col = "apartment_record_id"
    )

  coord_present_n <- sum(is.finite(apt_mapped$lon_src) & is.finite(apt_mapped$lat_src), na.rm = TRUE)
  spatial_matched_n <- sum(apt_mapped$adm_match_status == "matched", na.rm = TRUE)

  name_lookup <- build_apartment_adm_name_lookup()
  apt_mapped <- apt_mapped |>
    dplyr::left_join(name_lookup, by = "dong_key") |>
    dplyr::mutate(
      adm_cd = dplyr::coalesce(adm_cd, adm_cd_name),
      adm_match_status = dplyr::case_when(
        is.na(adm_match_status) & !is.na(adm_cd_name) ~ "unique_dong_name",
        adm_match_status %in% c("missing_coords", "adm_unmatched") & !is.na(adm_cd_name) ~ "unique_dong_name",
        TRUE ~ adm_match_status
      )
    ) |>
    dplyr::select(-adm_cd_name)
  name_matched_n <- sum(apt_mapped$adm_match_status == "unique_dong_name", na.rm = TRUE)

  geo_out <- fill_apartment_adm_with_geocode(apt_mapped)
  apt_final <- geo_out$data |>
    dplyr::left_join(apartment_adm_manual_fixes, by = "apartment_code") |>
    dplyr::mutate(
      adm_cd_before_manual_fix = adm_cd,
      adm_cd_manual_fix = is.na(adm_cd) & !is.na(adm_cd_override),
      adm_cd_manual_fix_note = dplyr::if_else(
        adm_cd_manual_fix,
        adm_cd_fix_note,
        NA_character_
      ),
      adm_cd = dplyr::if_else(adm_cd_manual_fix, adm_cd_override, adm_cd),
      adm_match_status = dplyr::case_when(
        adm_cd_manual_fix ~ "manual_adm",
        !is.na(adm_cd) & is.na(adm_match_status) ~ "matched",
        TRUE ~ adm_match_status
      )
    ) |>
    dplyr::select(-apartment_name_adm_fix, -adm_cd_override, -adm_cd_fix_note)

  household_nonneg <- dplyr::if_else(is.finite(apt_final$household_count) & apt_final$household_count > 0, apt_final$household_count, 0)
  final_unmatched <- apt_final |>
    dplyr::filter(is.na(adm_cd))
  unmatched_households <- sum(
    dplyr::if_else(is.finite(final_unmatched$household_count) & final_unmatched$household_count > 0, final_unmatched$household_count, 0),
    na.rm = TRUE
  )
  total_households <- sum(household_nonneg, na.rm = TRUE)
  unmatched_household_share <- if (total_households > 0) unmatched_households / total_households else NA_real_

  active <- apt_final |>
    dplyr::filter(
      !is.na(adm_cd),
      is.finite(use_approval_year),
      use_approval_year <= max(years_target)
    ) |>
    dplyr::mutate(
      complex_uid = dplyr::coalesce(apartment_code, paste0("row_", apartment_record_id)),
      building_count = dplyr::coalesce(building_count, 0),
      household_count = dplyr::coalesce(household_count, 0),
      year = purrr::map(use_approval_year, ~ years_target[years_target >= .x])
    ) |>
    tidyr::unnest(year)

  apt_year <- if (nrow(active) == 0) {
    base_year |>
      dplyr::mutate(
        apartment_complex_count_kapt = NA_real_,
        apartment_building_count = NA_real_,
        apartment_household_count = NA_real_
      )
  } else {
    active |>
      dplyr::group_by(adm_cd, year) |>
      dplyr::summarise(
        apartment_complex_count_kapt = dplyr::n_distinct(complex_uid),
        apartment_building_count = sum(building_count, na.rm = TRUE),
        apartment_household_count = sum(household_count, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::right_join(base_year, by = c("adm_cd", "year")) |>
      dplyr::mutate(
        apartment_complex_count_kapt = dplyr::coalesce(apartment_complex_count_kapt, 0),
        apartment_building_count = dplyr::coalesce(apartment_building_count, 0),
        apartment_household_count = dplyr::coalesce(apartment_household_count, 0)
      ) |>
      dplyr::select(adm_cd, year, apartment_complex_count_kapt, apartment_building_count, apartment_household_count) |>
      dplyr::arrange(adm_cd, year)
  }

  qc_tbl <- tibble::tibble(
    run_ts = timestamp(),
    raw_n = nrow(apt_raw),
    unique_apartment_code_n = dplyr::n_distinct(apt_raw$apartment_code, na.rm = TRUE),
    coordinate_present_n = as.integer(coord_present_n),
    coordinate_missing_n = as.integer(nrow(apt_raw) - coord_present_n),
    spatial_matched_n = as.integer(spatial_matched_n),
    unique_dong_name_matched_n = as.integer(name_matched_n),
    geocode_query_n = as.integer(geo_out$stats$query_n[[1]]),
    geocode_cache_hit_n = as.integer(geo_out$stats$cache_hit_n[[1]]),
    geocode_api_call_n = as.integer(geo_out$stats$api_call_n[[1]]),
    geocode_success_n = as.integer(geo_out$stats$geocode_success_n[[1]]),
    geocode_adm_matched_n = as.integer(geo_out$stats$geocode_adm_matched_n[[1]]),
    geocode_skipped_missing_credentials = isTRUE(geo_out$stats$skipped_missing_credentials[[1]]),
    approval_date_missing_n = sum(is.na(apt_final$use_approval_date)),
    building_count_missing_n = sum(!is.finite(apt_final$building_count)),
    household_count_missing_n = sum(!is.finite(apt_final$household_count)),
    household_count_manual_fix_n = sum(apt_final$household_count_manual_fix, na.rm = TRUE),
    adm_cd_manual_fix_n = sum(apt_final$adm_cd_manual_fix, na.rm = TRUE),
    final_adm_matched_n = sum(!is.na(apt_final$adm_cd)),
    final_unmatched_n = nrow(final_unmatched),
    final_unmatched_households = unmatched_households,
    total_households = total_households,
    final_unmatched_household_share = unmatched_household_share,
    panel_rows = nrow(apt_year),
    panel_min_year = min(apt_year$year, na.rm = TRUE),
    panel_max_year = max(apt_year$year, na.rm = TRUE)
  )
  write_csv_safe(qc_tbl, apartment_registry_qc_path)

  unmatched_tbl <- final_unmatched |>
    dplyr::transmute(
      apartment_code,
      apartment_name,
      sgg_name,
      dong_name,
      kapt_road_address,
      address_for_geocode,
      household_count,
      use_approval_date,
      adm_match_status,
      geocode_stage,
      geocode_status
    ) |>
    dplyr::slice_head(n = 1000)
  write_csv_safe(unmatched_tbl, apartment_registry_unmatched_path)

  write_csv_safe(
    geo_out$stats |>
      dplyr::mutate(run_ts = timestamp(), .before = 1),
    apartment_geocode_qc_path
  )

  if (is.finite(unmatched_household_share) && unmatched_household_share > 0.01) {
    stop(
      sprintf("[ERROR] apartment registry final unmatched household share exceeds 1%%: %.4f", unmatched_household_share),
      call. = FALSE
    )
  }

  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Apartment registry: raw=%d coord_present=%d spatial=%d name=%d geocode=%d final_matched=%d unmatched_household_share=%.4f",
      nrow(apt_raw),
      coord_present_n,
      spatial_matched_n,
      name_matched_n,
      geo_out$stats$geocode_adm_matched_n[[1]],
      sum(!is.na(apt_final$adm_cd)),
      unmatched_household_share
    )
  )

  list(
    raw = apt_final,
    year = apt_year
  )
}

read_senior_manual_fix_tbl <- function(path) {
  empty <- tibble::tibble(
    facility_type = character(),
    facility_name = character(),
    address_clean = character(),
    override_address = character(),
    active = logical(),
    note = character(),
    .fix_ord = integer(),
    facility_type_key = character(),
    facility_name_key = character(),
    address_clean_key = character()
  )

  if (!file.exists(path)) return(empty)

  x <- tryCatch(
    readr::read_csv(path, show_col_types = FALSE, progress = FALSE, locale = readr::locale(encoding = "UTF-8")),
    error = function(e) NULL
  )
  if (is.null(x) || nrow(x) == 0) return(empty)

  required_cols <- c("facility_type", "facility_name", "address_clean", "override_address", "active", "note")
  missing_cols <- setdiff(required_cols, names(x))
  if (length(missing_cols) > 0) {
    stop(
      sprintf(
        "[ERROR] senior manual fix file missing columns: %s",
        paste(missing_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  x |>
    dplyr::mutate(
      .fix_ord = dplyr::row_number(),
      facility_type = dplyr::na_if(stringr::str_squish(as.character(facility_type)), ""),
      facility_name = dplyr::na_if(stringr::str_squish(as.character(facility_name)), ""),
      address_clean = dplyr::na_if(stringr::str_squish(as.character(address_clean)), ""),
      override_address = vapply(
        override_address,
        compose_senior_address,
        character(1),
        sgg_name = NA_character_
      ),
      active = dplyr::case_when(
        is.logical(active) ~ active,
        tolower(as.character(active)) %in% c("true", "t", "1", "yes", "y") ~ TRUE,
        tolower(as.character(active)) %in% c("false", "f", "0", "no", "n") ~ FALSE,
        TRUE ~ FALSE
      ),
      note = as.character(note),
      facility_type_key = dplyr::coalesce(facility_type, NA_character_),
      facility_name_key = normalize_name_match_key(facility_name),
      address_clean_key = normalize_address_match_key(address_clean)
    ) |>
    dplyr::filter(
      active,
      !is.na(facility_name_key),
      !is.na(override_address),
      override_address != ""
    ) |>
    dplyr::select(
      facility_type, facility_name, address_clean, override_address, active, note,
      .fix_ord, facility_type_key, facility_name_key, address_clean_key
    )
}

select_senior_manual_fix <- function(senior_base, manual_fix_tbl) {
  if (nrow(senior_base) == 0 || nrow(manual_fix_tbl) == 0) {
    return(tibble::tibble(
      facility_id = integer(),
      manual_override_address = character()
    ))
  }

  senior_keys <- senior_base |>
    dplyr::transmute(
      facility_id,
      facility_type_key = facility_type,
      facility_name_key = normalize_name_match_key(facility_name),
      address_clean_key = normalize_address_match_key(address_clean)
    )

  senior_keys |>
    dplyr::left_join(
      manual_fix_tbl,
      by = "facility_name_key"
    ) |>
    dplyr::filter(
      !is.na(override_address),
      is.na(facility_type_key.y) | facility_type_key.y == facility_type_key.x,
      is.na(address_clean_key.y) | address_clean_key.y == address_clean_key.x
    ) |>
    dplyr::mutate(
      .match_rank = dplyr::case_when(
        !is.na(facility_type_key.y) & !is.na(address_clean_key.y) ~ 1L,
        !is.na(facility_type_key.y) & is.na(address_clean_key.y) ~ 2L,
        is.na(facility_type_key.y) & !is.na(address_clean_key.y) ~ 3L,
        TRUE ~ 4L
      )
    ) |>
    dplyr::arrange(facility_id, .match_rank, .fix_ord) |>
    dplyr::group_by(facility_id) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      facility_id,
      manual_override_address = override_address
    )
}

empty_senior_geocode_cache <- function() {
  tibble::tibble(
    provider = character(),
    query_text = character(),
    query_stage = character(),
    lon = numeric(),
    lat = numeric(),
    status = character(),
    updated_at = character()
  )
}

read_senior_geocode_cache <- function(path) {
  if (!file.exists(path)) {
    return(empty_senior_geocode_cache())
  }

  x <- tryCatch(
    arrow::read_parquet(path) |> tibble::as_tibble(),
    error = function(e) tibble::tibble()
  )
  if (nrow(x) == 0) {
    return(empty_senior_geocode_cache())
  }

  if (!"query_text" %in% names(x) && "query_address" %in% names(x)) {
    x$query_text <- as.character(x$query_address)
  }
  if (!"provider" %in% names(x)) {
    x$provider <- "kakao_address"
  }
  if (!"query_stage" %in% names(x)) {
    x$query_stage <- "manual_single"
  }

  x |>
    dplyr::transmute(
      provider = as.character(provider),
      query_text = as.character(query_text),
      query_stage = as.character(query_stage),
      lon = safe_num(lon),
      lat = safe_num(lat),
      status = as.character(status),
      updated_at = as.character(updated_at)
    ) |>
    dplyr::filter(!is.na(provider), provider != "", !is.na(query_text), query_text != "")
}

get_senior_geocode_cache_latest <- function(cache_hist) {
  if (nrow(cache_hist) == 0) return(cache_hist)
  cache_hist |>
    dplyr::mutate(.ord = dplyr::row_number()) |>
    dplyr::group_by(provider, query_text) |>
    dplyr::group_modify(function(.x, .y) {
      terminal_rows <- .x |>
        dplyr::filter(status %in% c("ok", "not_found"))
      preferred <- if (nrow(terminal_rows) > 0) terminal_rows else .x
      preferred |>
        dplyr::arrange(updated_at, .ord) |>
        dplyr::slice_tail(n = 1)
    }) |>
    dplyr::ungroup() |>
    dplyr::select(-.ord)
}

make_senior_geocode_result <- function(provider, query_text, query_stage = NA_character_) {
  tibble::tibble(
    provider = as.character(provider),
    query_text = as.character(query_text),
    query_stage = as.character(query_stage),
    lon = NA_real_,
    lat = NA_real_,
    status = "error",
    updated_at = timestamp()
  )
}

geocode_kakao_single <- function(query_text, query_stage = NA_character_, api_key, max_retry = 3L) {
  base_row <- make_senior_geocode_result("kakao_address", query_text, query_stage)

  if (is.na(query_text) || !nzchar(query_text)) {
    base_row$status <- "blank"
    return(base_row)
  }

  url <- "https://dapi.kakao.com/v2/local/search/address.json"
  for (attempt in seq_len(max_retry)) {
    resp <- tryCatch(
      httr::GET(
        url,
        query = list(query = query_text),
        httr::add_headers(Authorization = sprintf("KakaoAK %s", api_key)),
        httr::timeout(10)
      ),
      error = function(e) e
    )

    if (inherits(resp, "error")) {
      if (attempt == max_retry) {
        base_row$status <- "request_error"
        return(base_row)
      }
      Sys.sleep(0.4 * attempt)
      next
    }

    code <- httr::status_code(resp)
    if (code == 200L) {
      payload <- tryCatch(
        jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8")),
        error = function(e) NULL
      )
      docs <- payload$documents
      if (!is.null(docs) && length(docs$x) > 0 && length(docs$y) > 0) {
        base_row$lon <- safe_num(docs$x[[1]])
        base_row$lat <- safe_num(docs$y[[1]])
        base_row$status <- if (is.finite(base_row$lon) && is.finite(base_row$lat)) "ok" else "parse_error"
        return(base_row)
      }
      base_row$status <- "not_found"
      return(base_row)
    }

    if (code %in% c(429L, 500L, 502L, 503L, 504L) && attempt < max_retry) {
      Sys.sleep(0.5 * attempt)
      next
    }
    base_row$status <- sprintf("http_%d", code)
    return(base_row)
  }

  base_row$status <- "retry_exhausted"
  base_row
}

geocode_naver_single <- function(query_text, query_stage = NA_character_, client_id, client_secret, max_retry = 3L) {
  base_row <- make_senior_geocode_result("naver_address", query_text, query_stage)

  if (is.na(query_text) || !nzchar(query_text)) {
    base_row$status <- "blank"
    return(base_row)
  }

  url <- "https://maps.apigw.ntruss.com/map-geocode/v2/geocode"
  for (attempt in seq_len(max_retry)) {
    resp <- tryCatch(
      httr::GET(
        url,
        query = list(query = query_text),
        httr::add_headers(
          `X-NCP-APIGW-API-KEY-ID` = client_id,
          `X-NCP-APIGW-API-KEY` = client_secret
        ),
        httr::timeout(10)
      ),
      error = function(e) e
    )

    if (inherits(resp, "error")) {
      if (attempt == max_retry) {
        base_row$status <- "request_error"
        return(base_row)
      }
      Sys.sleep(0.4 * attempt)
      next
    }

    code <- httr::status_code(resp)
    if (code == 200L) {
      payload <- tryCatch(
        jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8")),
        error = function(e) NULL
      )
      addrs <- tryCatch(tibble::as_tibble(payload$addresses), error = function(e) tibble::tibble())
      if (nrow(addrs) == 0) {
        base_row$status <- "not_found"
        return(base_row)
      }
      base_row$lon <- safe_num(addrs$x[[1]])
      base_row$lat <- safe_num(addrs$y[[1]])
      base_row$status <- if (is.finite(base_row$lon) && is.finite(base_row$lat)) "ok" else "parse_error"
      return(base_row)
    }

    if (code %in% c(429L, 500L, 502L, 503L, 504L) && attempt < max_retry) {
      Sys.sleep(0.5 * attempt)
      next
    }
    base_row$status <- sprintf("http_%d", code)
    return(base_row)
  }

  base_row$status <- "retry_exhausted"
  base_row
}

lookup_senior_geocode_queries <- function(
  query_tbl,
  cache_path,
  provider,
  kakao_api_key = "",
  naver_client_id = "",
  naver_client_secret = "",
  rate_sec = 0.12,
  max_retry = 3L
) {
  provider <- as.character(provider[[1]])
  query_tbl <- query_tbl |>
    dplyr::transmute(
      query_stage = as.character(query_stage),
      query_text = stringr::str_squish(as.character(query_text))
    ) |>
    dplyr::filter(!is.na(query_text), query_text != "") |>
    dplyr::distinct(query_stage, query_text)

  if (nrow(query_tbl) == 0) {
    return(list(
      lookup = empty_senior_geocode_cache(),
      stats = tibble::tibble(
        query_n = 0L,
        cache_hit_n = 0L,
        api_call_n = 0L,
        geocode_success_n = 0L,
        skipped_missing_credentials = FALSE
      )
    ))
  }

  cache_hist <- read_senior_geocode_cache(cache_path)
  cache_latest <- get_senior_geocode_cache_latest(cache_hist)
  cache_terminal <- cache_latest |>
    dplyr::filter(provider == !!provider, status %in% c("ok", "not_found"))

  unique_queries <- query_tbl |>
    dplyr::distinct(query_text)
  cache_hit_n <- unique_queries |>
    dplyr::semi_join(cache_terminal, by = "query_text") |>
    nrow()
  need_query <- unique_queries |>
    dplyr::anti_join(cache_terminal, by = "query_text")

  missing_credentials <- (
    provider == "kakao_address" && !nzchar(kakao_api_key)
  ) || (
    provider == "naver_address" && (!nzchar(naver_client_id) || !nzchar(naver_client_secret))
  )

  if (nrow(need_query) > 0 && missing_credentials) {
    append_log(
      cfg$logs$data_qc,
      sprintf(
        "- Senior geocoding skipped unresolved %s queries due to missing credentials: %d",
        provider,
        nrow(need_query)
      )
    )
  }

  if (nrow(need_query) > 0 && !missing_credentials) {
    append_log(cfg$logs$data_qc, sprintf("- Senior geocoding requests (%s): %d", provider, nrow(need_query)))
    queried <- purrr::map_dfr(seq_len(nrow(need_query)), function(i) {
      query_text <- need_query$query_text[[i]]
      out <- if (provider == "kakao_address") {
        geocode_kakao_single(query_text, query_stage = "cache_write", api_key = kakao_api_key, max_retry = max_retry)
      } else {
        geocode_naver_single(query_text, query_stage = "cache_write", client_id = naver_client_id, client_secret = naver_client_secret, max_retry = max_retry)
      }
      if (i %% 200L == 0L || i == nrow(need_query)) {
        append_log(cfg$logs$data_qc, sprintf("- Senior geocoding progress (%s): %d/%d", provider, i, nrow(need_query)))
      }
      Sys.sleep(rate_sec)
      out
    })
    cache_hist <- dplyr::bind_rows(cache_hist, queried)
    write_parquet_safe(cache_hist, cache_path)
    cache_latest <- get_senior_geocode_cache_latest(cache_hist)
  }

  lookup <- query_tbl |>
    dplyr::mutate(provider = provider) |>
    dplyr::left_join(
      cache_latest |>
        dplyr::filter(provider == !!provider) |>
        dplyr::select(provider, query_text, lon, lat, status, updated_at),
      by = c("provider", "query_text")
    )

  geocode_success_n <- lookup |>
    dplyr::distinct(query_text, .keep_all = TRUE) |>
    dplyr::summarise(n = sum(status == "ok" & is.finite(lon) & is.finite(lat), na.rm = TRUE)) |>
    dplyr::pull(n) |>
    as.integer()

  list(
    lookup = lookup,
    stats = tibble::tibble(
      query_n = as.integer(dplyr::n_distinct(query_tbl$query_text)),
      cache_hit_n = as.integer(cache_hit_n),
      api_call_n = as.integer(nrow(need_query)),
      geocode_success_n = geocode_success_n,
      skipped_missing_credentials = missing_credentials
    )
  )
}

build_senior_geocode_candidates <- function(df) {
  # senior는 주소 품질이 가장 불안정하므로 후보 주소를 여러 개 만든다.
  # 원문 주소 -> 정규화 주소 순으로 stage를 부여해, 어떤 후보가 실제로
  # 성공했는지 QC에서 추적할 수 있게 한다.
  if (nrow(df) == 0) {
    return(tibble::tibble(
      facility_id = integer(),
      facility_type = character(),
      facility_name = character(),
      source_file = character(),
      query_stage = character(),
      stage_order = integer(),
      query_text = character()
    ))
  }

  purrr::pmap_dfr(
    df |>
      dplyr::select(
        facility_id, facility_type, facility_name, source_file, sgg_name,
        address_facility_raw, address_jibun_raw, address_road_raw
      ),
    function(facility_id, facility_type, facility_name, source_file, sgg_name, address_facility_raw, address_jibun_raw, address_road_raw) {
      raw_candidates <- dedupe_nonempty_keep_order(c(
        compose_senior_candidate_address(address_facility_raw, sgg_name, simplify = FALSE),
        compose_senior_candidate_address(address_jibun_raw, sgg_name, simplify = FALSE),
        compose_senior_candidate_address(address_road_raw, sgg_name, simplify = FALSE)
      ))
      normalized_candidates <- dedupe_nonempty_keep_order(c(
        compose_senior_candidate_address(address_facility_raw, sgg_name, simplify = TRUE),
        compose_senior_candidate_address(address_jibun_raw, sgg_name, simplify = TRUE),
        compose_senior_candidate_address(address_road_raw, sgg_name, simplify = TRUE)
      ))
      normalized_candidates <- normalized_candidates[!normalized_candidates %in% raw_candidates]

      candidates <- c(raw_candidates, normalized_candidates)
      stages <- c(
        c("raw_primary", "raw_secondary", "raw_tertiary")[seq_along(raw_candidates)],
        c("normalized_primary", "normalized_secondary", "normalized_tertiary")[seq_along(normalized_candidates)]
      )

      if (length(candidates) == 0) {
        return(tibble::tibble())
      }

      tibble::tibble(
        facility_id = as.integer(facility_id),
        facility_type = as.character(facility_type),
        facility_name = as.character(facility_name),
        source_file = as.character(source_file),
        query_stage = stages,
        stage_order = seq_along(stages),
        query_text = candidates
      )
    }
  )
}

map_senior_points_to_adm <- function(df_geo, adm_polygons) {
  pts <- df_geo |>
    dplyr::filter(status == "ok", is.finite(lon), is.finite(lat)) |>
    dplyr::distinct(facility_id, .keep_all = TRUE)
  if (nrow(pts) == 0) {
    return(tibble::tibble(facility_id = integer(), adm_cd = character()))
  }

  pts_sf <- sf::st_as_sf(pts, coords = c("lon", "lat"), crs = 4326L, remove = FALSE) |>
    sf::st_transform(cfg$target_crs)

  within <- suppressWarnings(
    sf::st_join(
      pts_sf,
      adm_polygons |>
        dplyr::select(adm_cd),
      join = sf::st_within,
      left = TRUE
    )
  )

  out <- within |>
    sf::st_drop_geometry() |>
    dplyr::transmute(facility_id, adm_cd_within = as.character(adm_cd))

  miss_ids <- out |>
    dplyr::filter(is.na(adm_cd_within)) |>
    dplyr::pull(facility_id)

  if (length(miss_ids) > 0) {
    miss_sf <- pts_sf[pts_sf$facility_id %in% miss_ids, , drop = FALSE]
    inter <- suppressWarnings(
      sf::st_join(
        miss_sf,
        adm_polygons |>
          dplyr::select(adm_cd),
        join = sf::st_intersects,
        left = TRUE
      )
    ) |>
      sf::st_drop_geometry() |>
      dplyr::transmute(facility_id, adm_cd_inter = as.character(adm_cd)) |>
      dplyr::filter(!is.na(adm_cd_inter)) |>
      dplyr::arrange(facility_id, adm_cd_inter) |>
      dplyr::group_by(facility_id) |>
      dplyr::summarise(adm_cd_inter = dplyr::first(adm_cd_inter), .groups = "drop")

    out <- out |>
      dplyr::left_join(inter, by = "facility_id") |>
      dplyr::transmute(facility_id, adm_cd = dplyr::coalesce(adm_cd_within, adm_cd_inter))
  } else {
    out <- out |>
      dplyr::transmute(facility_id, adm_cd = adm_cd_within)
  }

  out
}

build_senior_static <- function() {
  # senior branch의 원칙은 세 가지다.
  # 1) canonical source file만 허용
  # 2) multi-candidate geocoding + cache/manual/Naver fallback
  # 3) 최종 집계는 adm direct match only
  # 즉, geocode 성공만으로는 부족하고 행정동에 직접 붙은 시설만 count한다.
  senior_value_cols <- c("senior_facility_count", senior_detail_cols)
  senior_dir <- find_raw_subdir("03")
  if (is.na(senior_dir)) {
    stop("[ERROR] Senior raw directory is missing under 01_Data/01_Raw_Data/03_노인복지시설.", call. = FALSE)
  }

  find_required_senior_source <- function(dir, expected_basename) {
    files <- list.files(dir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
    files <- files[file.exists(files)]
    files <- files[!dir.exists(files)]
    hits <- files[normalize_unicode_text(basename(files)) == normalize_unicode_text(expected_basename)]
    if (length(hits) == 0) return(NA_character_)
    if (length(hits) > 1) {
      stop(
        sprintf(
          "[ERROR] Multiple senior source files matched canonical basename '%s': %s",
          expected_basename,
          paste(basename(hits), collapse = ", ")
        ),
        call. = FALSE
      )
    }
    hits[[1]]
  }

  senior_sources <- tibble::tribble(
    ~facility_type, ~expected_basename, ~source_role,
    "senior_gyeongrodang_count_aux", "(서울시경로당)현황3644(25.6월말 기준).xlsx", "gyeongrodang_xlsx",
    "senior_leisure_welfare_count_aux", "서울시 사회복지시설(노인여가복지시설) 목록.csv", "welfare_csv",
    "senior_medical_welfare_count_aux", "서울시 사회복지시설(노인의료복지시설) 목록.csv", "welfare_csv",
    "senior_job_support_count_aux", "서울시 사회복지시설(노인일자리지원기관) 목록.csv", "welfare_csv",
    "senior_residential_welfare_count_aux", "서울시 사회복지시설(노인주거복지시설) 목록.csv", "welfare_csv",
    "senior_home_care_count_aux", "서울시 사회복지시설(재가노인복지시설) 목록.csv", "welfare_csv"
  ) |>
    dplyr::mutate(
      source_path = vapply(expected_basename, find_required_senior_source, character(1), dir = senior_dir)
    )

  missing_sources <- senior_sources |>
    dplyr::filter(is.na(source_path))
  if (nrow(missing_sources) > 0) {
    stop(
      sprintf(
        "[ERROR] Missing senior facility source files for: %s",
        paste(sprintf("%s [%s]", missing_sources$facility_type, missing_sources$expected_basename), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Senior source selection: %s",
      paste(sprintf("%s=%s", senior_sources$facility_type, basename(senior_sources$source_path)), collapse = "; ")
    )
  )

  parse_senior_file <- function(facility_type, source_path, source_role, expected_basename) {
    if (identical(source_role, "gyeongrodang_xlsx")) {
      raw <- readxl::read_excel(
        source_path,
        skip = 6,
        col_names = c("연번", "시도명", "시군구명", "시설종류", "시설명", "주소", "지자체명", "담당부서", "전화번호")
      )
    } else {
      raw <- read_csv_auto(source_path)
    }
    if (nrow(raw) == 0) {
      return(tibble::tibble())
    }

    if ("상세영업상태명" %in% names(raw)) {
      raw <- raw |>
        dplyr::filter(!stringr::str_detect(as.character(.data[["상세영업상태명"]]), "폐업"))
    }
    if ("영업상태명" %in% names(raw)) {
      raw <- raw |>
        dplyr::filter(!stringr::str_detect(as.character(.data[["영업상태명"]]), "폐업"))
    }

    if (identical(source_role, "gyeongrodang_xlsx")) {
      return(tibble::tibble(
        facility_type = facility_type,
        facility_name = as.character(raw[["시설명"]]),
        address_facility_raw = as.character(raw[["주소"]]),
        address_jibun_raw = as.character(raw[["주소"]]),
        address_road_raw = NA_character_,
        sgg_name = as.character(raw[["시군구명"]]),
        source_file = basename(source_path)
      ))
    }

    name_cols <- intersect(c("시설명", "사업장명"), names(raw))
    facility_addr_cols <- intersect(c("시설주소"), names(raw))
    jibun_cols <- intersect(c("소재지전체주소", "지번주소"), names(raw))
    road_cols <- intersect(c("도로명전체주소", "도로명주소"), names(raw))
    sgg_cols <- intersect(c("시군구명", "자치구(시)구분"), names(raw))
    if (length(name_cols) == 0 || (length(facility_addr_cols) + length(jibun_cols) + length(road_cols)) == 0) {
      stop(
        sprintf(
          "[ERROR] Senior source '%s' is missing required name/address columns.",
          expected_basename
        ),
        call. = FALSE
      )
    }

    sgg_vec <- if (length(sgg_cols) > 0) as.character(raw[[sgg_cols[[1]]]]) else rep(NA_character_, nrow(raw))

    tibble::tibble(
      facility_type = facility_type,
      facility_name = as.character(raw[[name_cols[[1]]]]),
      address_facility_raw = if (length(facility_addr_cols) > 0) as.character(raw[[facility_addr_cols[[1]]]]) else rep(NA_character_, nrow(raw)),
      address_jibun_raw = if (length(jibun_cols) > 0) as.character(raw[[jibun_cols[[1]]]]) else rep(NA_character_, nrow(raw)),
      address_road_raw = if (length(road_cols) > 0) as.character(raw[[road_cols[[1]]]]) else rep(NA_character_, nrow(raw)),
      sgg_name = sgg_vec,
      source_file = basename(source_path)
    )
  }

  senior_raw <- purrr::pmap_dfr(
    senior_sources |>
      dplyr::select(facility_type, source_path, source_role, expected_basename),
    parse_senior_file
  )
  raw_record_n <- nrow(senior_raw)
  if (raw_record_n == 0) {
    stop("[ERROR] Senior facility sources were found but yielded zero records.", call. = FALSE)
  }

  senior_base <- senior_raw |>
    dplyr::mutate(
      facility_type = as.character(facility_type),
      facility_name = stringr::str_squish(as.character(facility_name)),
      sgg_name = normalize_sgg_name(sgg_name),
      address_facility_raw = clean_senior_address(address_facility_raw),
      address_jibun_raw = clean_senior_address(address_jibun_raw),
      address_road_raw = clean_senior_address(address_road_raw),
      address_clean = dplyr::coalesce(
        mapply(compose_senior_address, address_facility_raw, sgg_name, USE.NAMES = FALSE),
        mapply(compose_senior_address, address_jibun_raw, sgg_name, USE.NAMES = FALSE),
        mapply(compose_senior_address, address_road_raw, sgg_name, USE.NAMES = FALSE)
      )
    ) |>
    dplyr::filter(!is.na(facility_name), facility_name != "", !is.na(address_clean), address_clean != "") |>
    dplyr::distinct(facility_type, facility_name, address_clean, .keep_all = TRUE) |>
    dplyr::mutate(facility_id = dplyr::row_number()) |>
    dplyr::select(
      facility_id, facility_type, facility_name, address_clean, sgg_name,
      source_file, address_facility_raw, address_jibun_raw, address_road_raw
    )

  dedup_record_n <- nrow(senior_base)
  if (dedup_record_n == 0) {
    stop("[ERROR] Senior facility records were all dropped after cleaning/deduplication.", call. = FALSE)
  }

  kakao_api_key <- Sys.getenv("KAKAO_REST_API_KEY", unset = "")
  naver_client_id <- Sys.getenv("NAVER_CLIENT_ID", unset = "")
  naver_client_secret <- Sys.getenv("NAVER_CLIENT_SECRET", unset = "")
  manual_fix_tbl <- read_senior_manual_fix_tbl(senior_manual_fix_path)
  manual_matches <- select_senior_manual_fix(senior_base, manual_fix_tbl)

  base_candidates <- build_senior_geocode_candidates(senior_base)
  geocode_primary <- lookup_senior_geocode_queries(
    base_candidates |>
      dplyr::select(query_stage, query_text),
    cache_path = senior_geocode_cache_path,
    provider = "kakao_address",
    kakao_api_key = kakao_api_key,
    naver_client_id = naver_client_id,
    naver_client_secret = naver_client_secret
  )
  base_candidate_results <- base_candidates |>
    dplyr::left_join(
      geocode_primary$lookup |>
        dplyr::select(query_stage, query_text, lon, lat, status, updated_at),
      by = c("query_stage", "query_text")
    ) |>
    dplyr::mutate(
      provider = "kakao_address",
      success = status == "ok" & is.finite(lon) & is.finite(lat)
    )

  resolved_after_primary <- base_candidate_results |>
    dplyr::filter(success) |>
    dplyr::distinct(facility_id) |>
    dplyr::pull(facility_id)

  manual_candidates <- senior_base |>
    dplyr::filter(!facility_id %in% resolved_after_primary) |>
    dplyr::left_join(manual_matches, by = "facility_id") |>
    dplyr::filter(!is.na(manual_override_address), manual_override_address != "") |>
    dplyr::transmute(
      facility_id,
      facility_type,
      facility_name,
      source_file,
      query_stage = "manual_override",
      stage_order = 99L,
      query_text = manual_override_address
    ) |>
    dplyr::distinct(facility_id, query_stage, query_text, .keep_all = TRUE)

  geocode_manual <- lookup_senior_geocode_queries(
    manual_candidates |>
      dplyr::select(query_stage, query_text),
    cache_path = senior_geocode_cache_path,
    provider = "kakao_address",
    kakao_api_key = kakao_api_key,
    naver_client_id = naver_client_id,
    naver_client_secret = naver_client_secret
  )
  manual_candidate_results <- manual_candidates |>
    dplyr::left_join(
      geocode_manual$lookup |>
        dplyr::select(query_stage, query_text, lon, lat, status, updated_at),
      by = c("query_stage", "query_text")
    ) |>
    dplyr::mutate(
      provider = "kakao_address",
      success = status == "ok" & is.finite(lon) & is.finite(lat)
    )

  resolved_after_kakao <- dplyr::bind_rows(base_candidate_results, manual_candidate_results) |>
    dplyr::filter(success) |>
    dplyr::distinct(facility_id) |>
    dplyr::pull(facility_id)

  unresolved_after_kakao <- senior_base |>
    dplyr::filter(!facility_id %in% resolved_after_kakao) |>
    dplyr::pull(facility_id)

  naver_candidates <- dplyr::bind_rows(
    base_candidates |>
      dplyr::filter(facility_id %in% unresolved_after_kakao),
    manual_candidates |>
      dplyr::filter(facility_id %in% unresolved_after_kakao)
  ) |>
    dplyr::distinct(facility_id, query_stage, query_text, .keep_all = TRUE)

  geocode_naver <- lookup_senior_geocode_queries(
    naver_candidates |>
      dplyr::select(query_stage, query_text),
    cache_path = senior_geocode_cache_path,
    provider = "naver_address",
    kakao_api_key = kakao_api_key,
    naver_client_id = naver_client_id,
    naver_client_secret = naver_client_secret
  )
  naver_candidate_results <- naver_candidates |>
    dplyr::left_join(
      geocode_naver$lookup |>
        dplyr::select(query_stage, query_text, lon, lat, status, updated_at),
      by = c("query_stage", "query_text")
    ) |>
    dplyr::mutate(
      provider = "naver_address",
      success = status == "ok" & is.finite(lon) & is.finite(lat)
    )

  candidate_results <- dplyr::bind_rows(
    base_candidate_results,
    manual_candidate_results,
    naver_candidate_results
  ) |>
    dplyr::mutate(
      provider_order = dplyr::case_when(
        provider == "kakao_address" ~ 1L,
        provider == "naver_address" ~ 2L,
        TRUE ~ 9L
      ),
      attempt_order = provider_order * 100L + stage_order
    )

  final_success <- candidate_results |>
    dplyr::filter(success) |>
    dplyr::arrange(facility_id, provider_order, stage_order) |>
    dplyr::group_by(facility_id) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      facility_id,
      lon,
      lat,
      status = "ok",
      geocode_provider = provider,
      geocode_stage = query_stage,
      geocode_query_text = query_text
    )

  last_attempt <- candidate_results |>
    dplyr::arrange(facility_id, attempt_order) |>
    dplyr::group_by(facility_id) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      facility_id,
      last_provider = provider,
      last_attempt_stage = query_stage,
      last_status = status
    )

  candidate_attempts <- candidate_results |>
    dplyr::count(facility_id, name = "candidate_attempt_n")

  senior_geo <- senior_base |>
    dplyr::left_join(final_success, by = "facility_id") |>
    dplyr::left_join(last_attempt, by = "facility_id") |>
    dplyr::left_join(candidate_attempts, by = "facility_id") |>
    dplyr::left_join(
      manual_matches |>
        dplyr::mutate(manual_fix_available = TRUE),
      by = "facility_id"
    ) |>
    dplyr::mutate(
      candidate_attempt_n = dplyr::coalesce(candidate_attempt_n, 0L),
      manual_fix_available = dplyr::coalesce(manual_fix_available, FALSE),
      geocode_success = !is.na(status) & status == "ok" & is.finite(lon) & is.finite(lat)
    )

  senior_match <- map_senior_points_to_adm(senior_geo, adm_sf)
  senior_geo <- senior_geo |>
    dplyr::left_join(senior_match, by = "facility_id")

  geocode_success_n <- senior_geo |>
    dplyr::summarise(n = sum(geocode_success, na.rm = TRUE)) |>
    dplyr::pull(n) |>
    as.integer()
  direct_match_n <- senior_geo |>
    dplyr::summarise(n = sum(geocode_success & !is.na(adm_cd), na.rm = TRUE)) |>
    dplyr::pull(n) |>
    as.integer()
  direct_match_rate <- if (dedup_record_n > 0) direct_match_n / dedup_record_n else NA_real_
  geocode_fail_n <- as.integer(dedup_record_n - geocode_success_n)
  adm_unmatched_n <- as.integer(geocode_success_n - direct_match_n)

  direct_counts <- senior_geo |>
    dplyr::filter(!is.na(adm_cd), facility_type %in% senior_detail_cols) |>
    dplyr::count(adm_cd, facility_type, name = "direct_count")

  final_assigned_n <- direct_match_n
  final_assigned_rate <- direct_match_rate
  manual_fix_applied_n <- as.integer(dplyr::n_distinct(manual_candidates$facility_id))
  rescued_by_manual_n <- final_success |>
    dplyr::filter(geocode_stage == "manual_override") |>
    dplyr::summarise(n = dplyr::n_distinct(facility_id)) |>
    dplyr::pull(n) |>
    as.integer()
  rescued_by_naver_n <- final_success |>
    dplyr::filter(geocode_provider == "naver_address") |>
    dplyr::summarise(n = dplyr::n_distinct(facility_id)) |>
    dplyr::pull(n) |>
    as.integer()

  unmatched_tbl <- senior_geo |>
    dplyr::mutate(
      match_status = dplyr::case_when(
        !geocode_success ~ "geocode_fail",
        is.na(adm_cd) ~ "adm_match_fail",
        TRUE ~ "matched"
      )
    ) |>
    dplyr::filter(match_status != "matched") |>
    dplyr::select(
      facility_type, facility_name, address_clean,
      address_facility_raw, address_jibun_raw, address_road_raw,
      sgg_name, source_file, manual_fix_available, manual_override_address,
      last_provider, last_attempt_stage, last_status, candidate_attempt_n,
      match_status
    ) |>
    dplyr::distinct() |>
    dplyr::slice_head(n = 1000)
  write_csv_safe(unmatched_tbl, senior_geocode_unmatched_path)

  qc_tbl <- tibble::tibble(
    run_ts = timestamp(),
    raw_record_n = as.integer(raw_record_n),
    dedup_record_n = as.integer(dedup_record_n),
    candidate_query_n = as.integer(nrow(dplyr::bind_rows(base_candidates, manual_candidates))),
    kakao_attempt_n = as.integer(geocode_primary$stats$query_n[[1]] + geocode_manual$stats$query_n[[1]]),
    kakao_success_n = as.integer(geocode_primary$stats$geocode_success_n[[1]] + geocode_manual$stats$geocode_success_n[[1]]),
    manual_fix_applied_n = manual_fix_applied_n,
    naver_attempt_n = as.integer(geocode_naver$stats$query_n[[1]]),
    naver_success_n = as.integer(geocode_naver$stats$geocode_success_n[[1]]),
    rescued_by_manual_n = rescued_by_manual_n,
    rescued_by_naver_n = rescued_by_naver_n,
    geocode_success_n = geocode_success_n,
    direct_match_n = direct_match_n,
    direct_match_rate = direct_match_rate,
    geocode_fail_n = geocode_fail_n,
    unmatched_after_geocode_n = adm_unmatched_n,
    unmatched_after_geocode_rate = if (geocode_success_n > 0) adm_unmatched_n / geocode_success_n else NA_real_,
    final_assigned_n = final_assigned_n,
    adm_match_n = final_assigned_n,
    adm_match_rate = final_assigned_rate
  )
  write_csv_safe(qc_tbl, senior_geocode_qc_path)

  type_qc_tbl <- tibble::tibble(facility_type = senior_detail_cols) |>
    dplyr::left_join(
      senior_raw |>
        dplyr::count(facility_type, name = "raw_record_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      senior_base |>
        dplyr::count(facility_type, name = "dedup_record_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      dplyr::bind_rows(base_candidates, manual_candidates) |>
        dplyr::count(facility_type, name = "candidate_query_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      manual_candidates |>
        dplyr::distinct(facility_type, facility_id) |>
        dplyr::count(facility_type, name = "manual_fix_applied_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      candidate_results |>
        dplyr::filter(provider == "kakao_address", success) |>
        dplyr::distinct(facility_type, facility_id) |>
        dplyr::count(facility_type, name = "kakao_success_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      candidate_results |>
        dplyr::filter(provider == "naver_address", success) |>
        dplyr::distinct(facility_type, facility_id) |>
        dplyr::count(facility_type, name = "naver_success_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      final_success |>
        dplyr::filter(geocode_stage == "manual_override") |>
        dplyr::left_join(
          senior_base |>
            dplyr::select(facility_id, facility_type),
          by = "facility_id"
        ) |>
        dplyr::count(facility_type, name = "rescued_by_manual_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      final_success |>
        dplyr::filter(geocode_provider == "naver_address") |>
        dplyr::left_join(
          senior_base |>
            dplyr::select(facility_id, facility_type),
          by = "facility_id"
        ) |>
        dplyr::count(facility_type, name = "rescued_by_naver_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      senior_geo |>
        dplyr::filter(geocode_success) |>
        dplyr::count(facility_type, name = "geocode_success_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      senior_geo |>
        dplyr::filter(geocode_success, !is.na(adm_cd)) |>
        dplyr::count(facility_type, name = "direct_match_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      senior_geo |>
        dplyr::filter(!geocode_success) |>
        dplyr::count(facility_type, name = "geocode_fail_n"),
      by = "facility_type"
    ) |>
    dplyr::left_join(
      senior_geo |>
        dplyr::filter(geocode_success, is.na(adm_cd)) |>
        dplyr::count(facility_type, name = "unmatched_after_geocode_n"),
      by = "facility_type"
    ) |>
    dplyr::mutate(
      run_ts = timestamp(),
      dplyr::across(
        c(
          raw_record_n, dedup_record_n, candidate_query_n, manual_fix_applied_n,
          kakao_success_n, naver_success_n, rescued_by_manual_n, rescued_by_naver_n,
          geocode_success_n, direct_match_n, geocode_fail_n, unmatched_after_geocode_n
        ),
        ~ as.integer(dplyr::coalesce(.x, 0L))
      ),
      direct_match_rate = dplyr::if_else(dedup_record_n > 0, direct_match_n / dedup_record_n, NA_real_),
      unmatched_after_geocode_rate = dplyr::if_else(geocode_success_n > 0, unmatched_after_geocode_n / geocode_success_n, NA_real_),
      final_assigned_n = direct_match_n,
      adm_match_n = direct_match_n,
      adm_match_rate = dplyr::if_else(dedup_record_n > 0, direct_match_n / dedup_record_n, NA_real_)
    ) |>
    dplyr::select(
      run_ts, facility_type, raw_record_n, dedup_record_n, candidate_query_n,
      manual_fix_applied_n, kakao_success_n, naver_success_n,
      rescued_by_manual_n, rescued_by_naver_n, geocode_success_n,
      direct_match_n, direct_match_rate, geocode_fail_n,
      unmatched_after_geocode_n, unmatched_after_geocode_rate,
      final_assigned_n, adm_match_n, adm_match_rate
    )
  write_csv_safe(type_qc_tbl, senior_geocode_type_qc_path)

  append_log(
    cfg$logs$data_qc,
    sprintf(
      "- Senior facility geocode/match: raw=%d dedup=%d candidates=%d kakao_attempt=%d kakao_success=%d manual_fix=%d naver_attempt=%d naver_success=%d rescued_manual=%d rescued_naver=%d geocode_ok=%d direct=%d(%.3f) adm_unmatched=%d geocode_fail=%d final=%d(%.3f)",
      raw_record_n,
      dedup_record_n,
      qc_tbl$candidate_query_n[[1]],
      qc_tbl$kakao_attempt_n[[1]],
      qc_tbl$kakao_success_n[[1]],
      qc_tbl$manual_fix_applied_n[[1]],
      qc_tbl$naver_attempt_n[[1]],
      qc_tbl$naver_success_n[[1]],
      qc_tbl$rescued_by_manual_n[[1]],
      qc_tbl$rescued_by_naver_n[[1]],
      geocode_success_n,
      direct_match_n,
      direct_match_rate,
      adm_unmatched_n,
      geocode_fail_n,
      final_assigned_n,
      final_assigned_rate
    )
  )

  counts_by_type <- tidyr::crossing(base_adm, facility_type = senior_detail_cols) |>
    dplyr::left_join(
      direct_counts |>
        dplyr::select(adm_cd, facility_type, direct_count),
      by = c("adm_cd", "facility_type")
    ) |>
    dplyr::mutate(direct_count = dplyr::coalesce(direct_count, 0L)) |>
    dplyr::transmute(
      adm_cd,
      facility_type,
      facility_count = as.integer(direct_count)
    ) |>
    tidyr::pivot_wider(
      names_from = facility_type,
      values_from = facility_count,
      values_fill = 0L
    )

  for (nm in setdiff(senior_detail_cols, names(counts_by_type))) {
    counts_by_type[[nm]] <- 0L
  }

  senior_static <- base_adm |>
    dplyr::left_join(counts_by_type, by = "adm_cd") |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(senior_detail_cols),
        ~ as.integer(dplyr::coalesce(.x, 0L))
      ),
      senior_facility_count = as.integer(rowSums(dplyr::pick(dplyr::all_of(senior_detail_cols)), na.rm = TRUE))
    ) |>
    dplyr::select(adm_cd, senior_facility_count, dplyr::all_of(senior_detail_cols))

  if (!identical(
    senior_static$senior_facility_count,
    as.integer(rowSums(dplyr::select(senior_static, dplyr::all_of(senior_detail_cols)), na.rm = TRUE))
  )) {
    stop("[ERROR] senior_facility_count must equal the row-sum of senior detail counts.", call. = FALSE)
  }

  senior_numeric_values <- unlist(
    senior_static[, c("senior_facility_count", senior_detail_cols), drop = FALSE],
    use.names = FALSE
  )
  if (any(!is.na(senior_numeric_values) & senior_numeric_values %% 1 != 0)) {
    stop("[ERROR] Senior facility counts must remain integer after direct-only aggregation.", call. = FALSE)
  }

  senior_raw <- senior_geo |>
    dplyr::mutate(
      senior_record_id = facility_id
    ) |>
    dplyr::select(-facility_id)

  list(
    raw = senior_raw,
    static = senior_static
  )
}

build_senior_year_from_preagg <- function(df, years = years_target) {
  # senior는 현재 정적 stock으로 해석한다.
  # 그래서 preagg에서 adm별 typed count를 만든 뒤 모든 target year로 복제한다.
  if (nrow(df) == 0) {
    return(build_base_year_values(c("senior_facility_count", senior_detail_cols), fill = 0L))
  }

  counts_by_type <- df |>
    dplyr::filter(!is.na(adm_cd), facility_type %in% senior_detail_cols) |>
    dplyr::count(adm_cd, facility_type, name = "facility_count") |>
    tidyr::pivot_wider(
      names_from = facility_type,
      values_from = facility_count,
      values_fill = 0L
    )

  for (nm in setdiff(senior_detail_cols, names(counts_by_type))) {
    counts_by_type[[nm]] <- 0L
  }

  senior_static <- base_adm |>
    dplyr::left_join(counts_by_type, by = "adm_cd") |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(senior_detail_cols),
        ~ as.integer(dplyr::coalesce(.x, 0L))
      ),
      senior_facility_count = as.integer(rowSums(dplyr::pick(dplyr::all_of(senior_detail_cols)), na.rm = TRUE))
    ) |>
    dplyr::select(adm_cd, senior_facility_count, dplyr::all_of(senior_detail_cols))

  expand_static_to_year(senior_static, years = years)
}

build_physical_env_static <- function(park_static) {
  # physical environment는 서로 성격이 다른 source를 묶는다.
  # road/sidewalk shapefile -> 길이 합계
  # walk network csv -> 교차점 밀도, betweenness
  # DEM -> 평균 경사도
  # 모두 행정동 단위의 정적 구조 변수로 저장한다.
  line_length_by_adm <- function(shp_path, fallback_crs = NA_integer_) {
    # line source는 순수 선형 shp와 polygon boundary가 섞여 들어올 수 있다.
    # polygon이면 boundary를 선으로 바꾼 뒤 길이를 재고, intersection 실패 시에는
    # st_join fallback으로라도 adm별 총연장을 확보한다.
    if (!file.exists(shp_path)) {
      return(base_adm |>
        dplyr::mutate(len_km = NA_real_))
    }

    x_raw <- sf::st_read(shp_path, quiet = TRUE)
    if (is.na(sf::st_crs(x_raw)) && is.finite(fallback_crs)) sf::st_crs(x_raw) <- fallback_crs
    if (is.na(sf::st_crs(x_raw))) {
      return(base_adm |>
        dplyr::mutate(len_km = NA_real_))
    }

    x_raw <- x_raw |>
      sf::st_transform(cfg$target_crs) |>
      sf::st_make_valid()

    gtype <- unique(as.character(sf::st_geometry_type(x_raw, by_geometry = TRUE)))
    if (any(grepl("LINESTRING", gtype))) {
      x_line <- suppressWarnings(sf::st_collection_extract(x_raw, "LINESTRING", warn = FALSE))
    } else if (any(grepl("POLYGON", gtype))) {
      poly <- suppressWarnings(sf::st_collection_extract(x_raw, "POLYGON", warn = FALSE))
      if (nrow(poly) == 0) {
        return(base_adm |>
          dplyr::mutate(len_km = NA_real_))
      }
      x_line <- suppressWarnings(
        sf::st_collection_extract(
          sf::st_as_sf(sf::st_boundary(poly)),
          "LINESTRING",
          warn = FALSE
        )
      )
    } else {
      return(base_adm |>
        dplyr::mutate(len_km = NA_real_))
    }

    if (nrow(x_line) == 0) {
      return(base_adm |>
        dplyr::mutate(len_km = NA_real_))
    }

    inter <- tryCatch(
      suppressWarnings(
        sf::st_intersection(
          adm_sf |>
            dplyr::select(adm_cd),
          x_line |>
            dplyr::select(geometry)
        )
      ),
      error = function(e) NULL
    )

    if (is.null(inter)) {
      joined <- suppressWarnings(
        sf::st_join(
          x_line |>
            dplyr::select(geometry),
          adm_sf |>
            dplyr::select(adm_cd),
          join = sf::st_intersects,
          left = FALSE
        )
      )
      if (nrow(joined) == 0) {
        return(base_adm |>
          dplyr::mutate(len_km = 0))
      }

      agg <- joined |>
        dplyr::mutate(len_km = as.numeric(sf::st_length(geometry)) / 1000) |>
        sf::st_drop_geometry() |>
        dplyr::group_by(adm_cd) |>
        dplyr::summarise(len_km = sum(len_km, na.rm = TRUE), .groups = "drop")

      return(base_adm |>
        dplyr::left_join(agg, by = "adm_cd") |>
        dplyr::mutate(len_km = dplyr::coalesce(len_km, 0)))
    }

    inter_line <- suppressWarnings(sf::st_collection_extract(inter, "LINESTRING", warn = FALSE))
    if (nrow(inter_line) == 0) {
      return(base_adm |>
        dplyr::mutate(len_km = 0))
    }

    agg <- inter_line |>
      dplyr::mutate(len_km = as.numeric(sf::st_length(geometry)) / 1000) |>
      sf::st_drop_geometry() |>
      dplyr::group_by(adm_cd) |>
      dplyr::summarise(len_km = sum(len_km, na.rm = TRUE), .groups = "drop")

    base_adm |>
      dplyr::left_join(agg, by = "adm_cd") |>
      dplyr::mutate(len_km = dplyr::coalesce(len_km, 0))
  }

  build_walk_network_metrics <- function() {
    ped_dir <- find_raw_subdir("05")
    ped_files <- resolve_canonical_source_paths("walk_network")
    if (length(ped_files) == 0) {
      append_log(cfg$logs$data_qc, "- Walk network source missing: intersection_density/betweenness set to NA")
      return(base_adm |>
        dplyr::mutate(
          intersection_density = NA_real_,
          betweenness_centrality = NA_real_
        ))
    }
    log_canonical_source_selection("Walk network", ped_files)

    df_ped_raw <- read_csv_auto(ped_files[[1]])
    if (!"노드링크 유형" %in% names(df_ped_raw)) {
      df_ped_raw <- df_ped_raw |>
        dplyr::rename(
          `노드링크 유형` = 1, `노드 WKT` = 2, `노드 ID` = 3, `링크 WKT` = 5,
          `링크 ID` = 6, `링크 유형 코드` = 7, `시작노드 ID` = 8, `종료노드 ID` = 9,
          `링크 길이` = 10, `고가도로` = 15, `지하철네트워크` = 16, `교량` = 17,
          `터널` = 18, `육교` = 19, `횡단보도` = 20, `공원,녹지` = 21, `건물내` = 22
        )
    }

    required_cols <- c("노드링크 유형", "노드 ID", "링크 WKT", "링크 유형 코드", "시작노드 ID", "종료노드 ID", "링크 길이")
    miss <- setdiff(required_cols, names(df_ped_raw))
    if (length(miss) > 0) {
      append_log(cfg$logs$data_qc, sprintf("- Walk network columns missing: %s", paste(miss, collapse = ", ")))
      return(base_adm |>
        dplyr::mutate(
          intersection_density = NA_real_,
          betweenness_centrality = NA_real_
        ))
    }

    for (nm in c("고가도로", "지하철네트워크", "교량", "터널", "육교", "횡단보도", "공원,녹지", "건물내")) {
      if (!nm %in% names(df_ped_raw)) df_ped_raw[[nm]] <- 0
    }

    df_nodes <- df_ped_raw |>
      dplyr::filter(`노드링크 유형` == "NODE") |>
      dplyr::select(node_id = `노드 ID`, node_over = `육교`, node_cross = `횡단보도`) |>
      dplyr::mutate(dplyr::across(c(node_over, node_cross), ~ tidyr::replace_na(safe_num(.), 0)))

    df_links_raw <- df_ped_raw |>
      dplyr::filter(`노드링크 유형` == "LINK") |>
      dplyr::filter(as.character(`링크 유형 코드`) >= "1000" & as.character(`링크 유형 코드`) <= "1111") |>
      dplyr::filter(!is.na(`링크 WKT`) & `링크 WKT` != "")

    if (nrow(df_links_raw) == 0) {
      append_log(cfg$logs$data_qc, "- Walk network has no eligible pedestrian links")
      return(base_adm |>
        dplyr::mutate(
          intersection_density = NA_real_,
          betweenness_centrality = NA_real_
        ))
    }

    df_links_fixed <- df_links_raw |>
      dplyr::left_join(df_nodes, by = c("시작노드 ID" = "node_id")) |>
      dplyr::rename(s_over = node_over, s_cross = node_cross) |>
      dplyr::left_join(df_nodes, by = c("종료노드 ID" = "node_id")) |>
      dplyr::rename(e_over = node_over, e_cross = node_cross) |>
      dplyr::mutate(
        `횡단보도` = tidyr::replace_na(safe_num(`횡단보도`), 0),
        `육교` = tidyr::replace_na(safe_num(`육교`), 0),
        `고가도로` = tidyr::replace_na(safe_num(`고가도로`), 0),
        `지하철네트워크` = tidyr::replace_na(safe_num(`지하철네트워크`), 0),
        `교량` = tidyr::replace_na(safe_num(`교량`), 0),
        `터널` = tidyr::replace_na(safe_num(`터널`), 0),
        `공원,녹지` = tidyr::replace_na(safe_num(`공원,녹지`), 0),
        `건물내` = tidyr::replace_na(safe_num(`건물내`), 0),
        is_crosswalk = dplyr::if_else(s_cross == 1 & e_cross == 1, 1, `횡단보도`),
        is_overpass = dplyr::if_else(s_over == 1 & e_over == 1, 1, `육교`)
      )

    # 교차점 밀도와 betweenness는 같은 raw를 쓰지만 계산 단위가 다르다.
    # 교차점 밀도는 geometry에서 node degree를 읽고, betweenness는 raw node-id edge graph로 계산한다.
    # topology는 node-id가 더 안정적이고, 행정동 집계는 geometry가 더 적합하기 때문이다.
    df_ped_links <- df_links_fixed |>
      dplyr::transmute(
        edge_row_id = dplyr::row_number(),
        link_id = as.character(`링크 ID`),
        from_node_id = as.character(`시작노드 ID`),
        to_node_id = as.character(`종료노드 ID`),
        wkt = `링크 WKT`,
        link_type = as.character(`링크 유형 코드`),
        len_m = safe_num(`링크 길이`)
      ) |>
      dplyr::filter(is.finite(len_m), len_m > 0)

    if (nrow(df_ped_links) == 0) {
      append_log(cfg$logs$data_qc, "- Walk network link filtering produced no valid links")
      return(base_adm |>
        dplyr::mutate(
          intersection_density = NA_real_,
          betweenness_centrality = NA_real_
        ))
    }

    sf_ped_proj <- sf::st_as_sf(df_ped_links, wkt = "wkt", crs = 4326) |>
      sf::st_transform(cfg$target_crs) |>
      sf::st_make_valid()

    ped_net <- sfnetworks::as_sfnetwork(sf_ped_proj, directed = FALSE)

    area_tbl <- adm_sf |>
      dplyr::mutate(area_km2 = as.numeric(sf::st_area(geometry)) / 10^6) |>
      sf::st_drop_geometry() |>
      dplyr::select(adm_cd, area_km2)

    nodes_sf <- ped_net |>
      tidygraph::activate("nodes") |>
      dplyr::mutate(node_degree = tidygraph::centrality_degree(mode = "all", loops = FALSE)) |>
      sf::st_as_sf() |>
      dplyr::mutate(point_id = dplyr::row_number())

    node_map <- assign_point_ids_to_adm(nodes_sf, "point_id")
    intersection_tbl <- area_tbl |>
      dplyr::left_join(
        node_map |>
          dplyr::left_join(
            nodes_sf |>
              sf::st_drop_geometry() |>
              dplyr::select(point_id, node_degree),
            by = "point_id"
          ) |>
          dplyr::filter(!is.na(adm_cd), is.finite(node_degree), node_degree >= 3) |>
          dplyr::count(adm_cd, name = "intersection_count"),
        by = "adm_cd"
      ) |>
      dplyr::mutate(
        intersection_count = dplyr::coalesce(intersection_count, 0L),
        intersection_density = intersection_count / pmax(area_km2, 1e-9)
      ) |>
      dplyr::select(adm_cd, intersection_density)

    if (!isTRUE(cfg$run_walk_env_betweenness)) {
      append_log(cfg$logs$data_qc, "- Walk betweenness skipped: cfg$run_walk_env_betweenness=FALSE")
      cached_betweenness <- load_cached_walk_betweenness()
      betweenness_tbl <- if (is.null(cached_betweenness)) {
        base_adm |>
          dplyr::mutate(betweenness_centrality = NA_real_)
      } else {
        cached_betweenness
      }
    } else {
      append_log(
        cfg$logs$data_qc,
        sprintf(
          "- Walk betweenness enabled: local edge betweenness (%sm cutoff, %s-weighted, %s)",
          cfg$walk_betweenness_radius_m,
          cfg$walk_betweenness_weight_mode,
          cfg$walk_betweenness_agg_mode
        )
      )

      graph_edges <- df_ped_links |>
        dplyr::filter(
          !is.na(from_node_id),
          !is.na(to_node_id),
          from_node_id != "",
          to_node_id != "",
          from_node_id != to_node_id
        ) |>
        dplyr::select(from = from_node_id, to = to_node_id, len_m, edge_row_id)

      if (nrow(graph_edges) == 0) {
        append_log(cfg$logs$data_qc, "- Walk betweenness skipped: no valid raw node-id edges after filtering")
        betweenness_tbl <- base_adm |>
          dplyr::mutate(betweenness_centrality = NA_real_)
      } else {
        # betweenness는 서울 전체 보행 그래프에서 계산하되,
        # shortest path는 길이(len_m) 가중, cutoff는 800m로 제한한다.
        # 즉 "도시 전체 전략 중심성"보다 근린 보행권 내 통과 잠재력에 더 가깝게 만든다.
        ped_graph <- igraph::graph_from_data_frame(
          d = graph_edges,
          directed = FALSE,
          vertices = NULL
        )

        edge_betweenness <- igraph::edge_betweenness(
          graph = ped_graph,
          directed = FALSE,
          weights = igraph::E(ped_graph)$len_m,
          cutoff = as.numeric(cfg$walk_betweenness_radius_m)
        )

        centrality_edges <- sf_ped_proj |>
          dplyr::left_join(
            tibble::tibble(
              edge_row_id = as.integer(igraph::E(ped_graph)$edge_row_id),
              betweenness = as.numeric(edge_betweenness)
            ),
            by = "edge_row_id"
          ) |>
          dplyr::filter(is.finite(betweenness)) |>
          sf::st_make_valid()

        inter <- tryCatch(
          suppressWarnings(
            sf::st_intersection(
              adm_sf |>
                dplyr::select(adm_cd) |>
                sf::st_make_valid(),
              centrality_edges |>
                dplyr::select(edge_row_id, betweenness) |>
                sf::st_make_valid()
            )
          ),
          error = function(e) {
            append_log(
              cfg$logs$data_qc,
              sprintf("- Walk betweenness intersection failed after validity repair: %s", conditionMessage(e))
            )
            NULL
          }
        )

        if (is.null(inter) || nrow(inter) == 0) {
          append_log(cfg$logs$data_qc, "- Walk betweenness overlap aggregation unavailable: returning NA")
          betweenness_tbl <- base_adm |>
            dplyr::mutate(betweenness_centrality = NA_real_)
        } else {
          betweenness_tbl <- inter |>
            dplyr::mutate(overlap_len_m = as.numeric(sf::st_length(geometry))) |>
            sf::st_drop_geometry() |>
            dplyr::filter(
              is.finite(betweenness),
              is.finite(overlap_len_m),
              overlap_len_m > 0
            ) |>
            dplyr::group_by(adm_cd) |>
            dplyr::summarise(
              betweenness_centrality = sum(betweenness * overlap_len_m, na.rm = TRUE) /
                sum(overlap_len_m, na.rm = TRUE),
              .groups = "drop"
            )
        }
      }

      betweenness_tbl <- base_adm |>
        dplyr::left_join(betweenness_tbl, by = "adm_cd")
      write_walk_betweenness_cache(betweenness_tbl)
    }

    intersection_tbl |>
      dplyr::left_join(
        betweenness_tbl |>
          dplyr::select(adm_cd, betweenness_centrality),
        by = "adm_cd"
      )
  }

  build_slope_static <- function() {
    dem_paths <- unique(c(
      list.files(cfg$dir_boundary, pattern = "[.]img$", recursive = TRUE, full.names = TRUE),
      list.files(cfg$dir_raw, pattern = "[.]img$", recursive = TRUE, full.names = TRUE)
    ))
    dem_paths <- dem_paths[grepl("DEM|dem|표고", dem_paths)]

    if (length(dem_paths) == 0) {
      append_log(cfg$logs$data_qc, "- DEM source missing: avg_slope_degree set to NA")
      return(base_adm |>
        dplyr::mutate(avg_slope_degree = NA_real_))
    }

    dem_terra <- terra::rast(dem_paths[[1]])
    slope_terra <- terra::terrain(dem_terra, v = "slope", unit = "degrees", neighbors = 8)

    adm_dem <- adm_sf
    dem_crs <- tryCatch(terra::crs(dem_terra, proj = TRUE), error = function(e) "")
    if (!is.na(dem_crs) && nzchar(dem_crs)) {
      adm_dem <- sf::st_transform(adm_sf, dem_crs)
    }

    slope_vals <- exactextractr::exact_extract(slope_terra, adm_dem, fun = "mean")
    base_adm |>
      dplyr::mutate(avg_slope_degree = safe_num(slope_vals))
  }

  road_path <- resolve_canonical_source_paths("road")
  walk_path <- resolve_canonical_source_paths("sidewalk")
  log_canonical_source_selection("Road", road_path)
  log_canonical_source_selection("Sidewalk", walk_path)

  road_len <- if (length(road_path) > 0) {
    line_length_by_adm(road_path[[1]], fallback_crs = 5179L) |>
      dplyr::rename(road_length_km = len_km)
  } else {
    base_adm |>
      dplyr::mutate(road_length_km = NA_real_)
  }
  walk_len <- if (length(walk_path) > 0) {
    walk_fallback <- if (grepl("N3L_A0033320", walk_path[[1]])) 5179L else 5174L
    line_length_by_adm(walk_path[[1]], fallback_crs = walk_fallback) |>
      dplyr::rename(sidewalk_length_km = len_km)
  } else {
    base_adm |>
      dplyr::mutate(sidewalk_length_km = NA_real_)
  }

  walk_env_static <- tryCatch(
    build_walk_network_metrics(),
    error = function(e) {
      append_log(cfg$logs$data_qc, sprintf("- Walk network metrics failed: %s", conditionMessage(e)))
      base_adm |>
        dplyr::mutate(
          intersection_density = NA_real_,
          betweenness_centrality = NA_real_
        )
    }
  )

  slope_static <- tryCatch(
    build_slope_static(),
    error = function(e) {
      append_log(cfg$logs$data_qc, sprintf("- Slope calculation failed: %s", conditionMessage(e)))
      base_adm |>
        dplyr::mutate(avg_slope_degree = NA_real_)
    }
  )

  out <- base_adm |>
    dplyr::left_join(road_len, by = "adm_cd") |>
    dplyr::left_join(walk_len, by = "adm_cd") |>
    dplyr::left_join(walk_env_static, by = "adm_cd") |>
    dplyr::left_join(slope_static, by = "adm_cd")

  out |>
    dplyr::select(
      adm_cd,
      road_length_km,
      sidewalk_length_km,
      intersection_density,
      avg_slope_degree,
      betweenness_centrality
    )
}

log_coverage <- function(df, var_name) {
  if (!var_name %in% names(df)) return(invisible(NULL))
  cov_tbl <- df |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      n = dplyr::n(),
      non_na = sum(is.finite(.data[[var_name]])),
      cov = mean(is.finite(.data[[var_name]])),
      .groups = "drop"
    )
  txt <- cov_tbl |>
    dplyr::mutate(txt = sprintf("%d: %d/%d (%.1f%%)", year, non_na, n, 100 * cov)) |>
    dplyr::pull(txt) |>
    paste(collapse = ", ")
  append_log(cfg$logs$data_qc, sprintf("- %s coverage by year: %s", var_name, txt))
}

#==============================================================================
# 2. Build Each Auxiliary Source
#==============================================================================
# 이 섹션에서는 source별 builder를 실제로 실행해
# preagg record 또는 연단위/static result를 만든다.
# source별 산출물을 분리 보관해 두는 이유는 이후 검토와 재집계를 쉽게 하기 위해서다.
append_log(cfg$logs$data_qc, "- Building official land price (representative-point area-weighted aggregation)")
land_price_obj <- build_land_price_series(cfg$dir_boundary)
land_price_series <- land_price_obj$series
land_price_obs <- land_price_obj$observed

land_price_adm <- if (nrow(land_price_series) > 0) {
  base_year |>
    dplyr::left_join(land_price_series, by = c("adm_cd", "year")) |>
    dplyr::left_join(
      land_price_obs |>
        dplyr::mutate(land_price_observed = TRUE),
      by = c("adm_cd", "year")
    ) |>
    dplyr::mutate(land_price_observed = dplyr::coalesce(land_price_observed, FALSE))
} else {
  base_year |>
    dplyr::mutate(
      official_land_price = NA_real_,
      land_price_observed = FALSE
    )
}

land_price_qc <- land_price_adm |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    adm_n = dplyr::n(),
    finite_n = sum(is.finite(official_land_price)),
    observed_n = sum(is.finite(official_land_price) & land_price_observed),
    imputed_n = sum(is.finite(official_land_price) & !land_price_observed),
    observed_share = dplyr::if_else(finite_n > 0, observed_n / finite_n, NA_real_),
    .groups = "drop"
  )

land_price_qc_path <- file.path(cfg$dir_logs, "land_price_imputation_qc.csv")
write_csv_safe(land_price_qc, land_price_qc_path)
obs_share_min <- suppressWarnings(min(land_price_qc$observed_share, na.rm = TRUE))
obs_share_max <- suppressWarnings(max(land_price_qc$observed_share, na.rm = TRUE))
if (!is.finite(obs_share_min)) obs_share_min <- NA_real_
if (!is.finite(obs_share_max)) obs_share_max <- NA_real_
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Land price imputation QC written: %s (observed share range %.3f~%.3f)",
    basename(land_price_qc_path),
    obs_share_min,
    obs_share_max
  )
)

append_log(cfg$logs$data_qc, "- Building official land price LPI adjustment factors")
land_price_lpi_factor <- build_land_price_lpi_factor(cfg$dir_boundary)

land_price_quarter <- base_quarter |>
  dplyr::left_join(
    land_price_adm |>
      dplyr::select(adm_cd, year, official_land_price),
    by = c("adm_cd", "year")
  ) |>
  dplyr::left_join(
    land_price_lpi_factor,
    by = c("adm_cd", "year", "quarter", "yq")
  ) |>
  dplyr::mutate(
    land_price_adjusted = dplyr::if_else(
      is.finite(.data$official_land_price) &
        .data$official_land_price > 0 &
        is.finite(.data$land_price_lpi_factor) &
        .data$land_price_lpi_factor > 0,
      .data$official_land_price * .data$land_price_lpi_factor,
      NA_real_
    )
  )

land_price_lpi_adjustment_qc <- land_price_quarter |>
  dplyr::group_by(year, quarter, yq) |>
  dplyr::summarise(
    adm_n = dplyr::n(),
    factor_finite_n = sum(is.finite(.data$land_price_lpi_factor)),
    adjusted_finite_n = sum(is.finite(.data$land_price_adjusted)),
    factor_min = suppressWarnings(min(.data$land_price_lpi_factor, na.rm = TRUE)),
    factor_max = suppressWarnings(max(.data$land_price_lpi_factor, na.rm = TRUE)),
    weight_coverage_min = suppressWarnings(min(.data$land_price_lpi_weight_coverage, na.rm = TRUE)),
    weight_coverage_max = suppressWarnings(max(.data$land_price_lpi_weight_coverage, na.rm = TRUE)),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    dplyr::across(
      c(factor_min, factor_max, weight_coverage_min, weight_coverage_max),
      ~ dplyr::if_else(is.finite(.x), .x, NA_real_)
    )
  )

land_price_lpi_adjustment_qc_path <- file.path(cfg$dir_logs, "land_price_lpi_adjustment_qc.csv")
write_csv_safe(land_price_lpi_adjustment_qc, land_price_lpi_adjustment_qc_path)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Land price LPI adjustment QC written: %s (adjusted finite=%d/%d)",
    basename(land_price_lpi_adjustment_qc_path),
    sum(is.finite(land_price_quarter$land_price_adjusted)),
    nrow(land_price_quarter)
  )
)

append_log(cfg$logs$data_qc, "- Building park area static")
park_static <- build_park_area_static()
park_year <- expand_static_to_year(park_static, years_target)

append_log(cfg$logs$data_qc, "- Building transit quarter-source panel (mixed-frequency bus snapshots + subway opening-date rules)")
transit_out <- build_transit_panel()
bus_raw <- transit_out$bus_raw
bus_quarter <- transit_out$bus_quarter
subway_raw <- transit_out$subway_raw
subway_quarter <- transit_out$subway_quarter
transit_quarter <- transit_out$transit_quarter

bus_snapshot_meta <- if (nrow(bus_raw) == 0) {
  tibble::tibble(
    year = integer(),
    quarter = integer(),
    yq = character(),
    quarter_index = integer(),
    bus_snapshot_date = character(),
    bus_source_precision = character(),
    bus_source_file = character()
  )
} else {
  bus_raw |>
    dplyr::distinct(year, quarter, yq, quarter_index, snapshot_date, bus_source_precision, selected_source_file) |>
    dplyr::group_by(year, quarter, yq, quarter_index) |>
    dplyr::summarise(
      bus_snapshot_date = paste(sort(unique(format(snapshot_date, "%Y-%m-%d"))), collapse = "|"),
      bus_source_precision = paste(sort(unique(bus_source_precision)), collapse = "|"),
      bus_source_file = paste(sort(unique(selected_source_file)), collapse = "|"),
      .groups = "drop"
    )
}

subway_precision_meta <- if (nrow(subway_raw) == 0) {
  tibble::tibble(
    year = integer(),
    quarter = integer(),
    yq = character(),
    quarter_index = integer(),
    subway_source_precision = character()
  )
} else {
  subway_raw |>
    dplyr::distinct(year, quarter, yq, quarter_index, subway_source_precision) |>
    dplyr::group_by(year, quarter, yq, quarter_index) |>
    dplyr::summarise(
      subway_source_precision = paste(sort(unique(subway_source_precision)), collapse = "|"),
      .groups = "drop"
    )
}

transit_qc <- transit_quarter |>
  dplyr::group_by(year, quarter, yq, quarter_index) |>
  dplyr::summarise(
    adm_n = dplyr::n(),
    bus_finite_n = sum(is.finite(bus_stop_count_aux)),
    bus_total = sum(bus_stop_count_aux, na.rm = TRUE),
    subway_finite_n = sum(is.finite(subway_station_count_aux)),
    subway_total = sum(subway_station_count_aux, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(bus_snapshot_meta, by = c("year", "quarter", "yq", "quarter_index")) |>
  dplyr::left_join(subway_precision_meta, by = c("year", "quarter", "yq", "quarter_index")) |>
  dplyr::arrange(quarter_index)
write_csv_safe(transit_qc, cfg$logs$transit_aux_qc)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Transit aux summary: %s (bus totals=%s; subway totals=%s)",
    basename(cfg$logs$transit_aux_qc),
    paste(sprintf("%s=%d", transit_qc$yq, transit_qc$bus_total), collapse = ", "),
    paste(sprintf("%s=%d", transit_qc$yq, transit_qc$subway_total), collapse = ", ")
  )
)

append_log(cfg$logs$data_qc, "- Building medical year-source panel")
medical_out <- build_medical_panel()
medical_raw <- medical_out$raw
hospital_year <- medical_out$year

append_log(cfg$logs$data_qc, "- Building large-store year-source panel")
mall_out <- build_mall_panel()
mall_raw <- mall_out$raw
mall_year <- mall_out$year

append_log(cfg$logs$data_qc, "- Building apartment registry year-source stock panel (point match + approval-year stock)")
apartment_out <- build_apartment_registry_panel()
apartment_raw <- apartment_out$raw
apartment_year <- apartment_out$year

append_log(cfg$logs$data_qc, "- Building senior-facility static counts (multi-candidate geocode + manual fixes + Naver fallback + direct adm match)")
senior_out <- build_senior_static()
senior_raw <- senior_out$raw
senior_static <- senior_out$static
senior_year <- expand_static_to_year(senior_static, years_target)

append_log(cfg$logs$data_qc, "- Building walk-environment variables")
physical_static <- build_physical_env_static(park_static)
physical_year <- expand_static_to_year(physical_static, years_target)

# record-level 검토가 필요한 source만 preagg 파일을 남긴다.
# medical/mall/senior/bus/subway는 주소·좌표·직접매칭 검토 가치가 크기 때문이다.
write_aux_source_preagg(medical_raw, cfg$paths$medical_source_preagg, "medical")
write_aux_source_preagg(mall_raw, cfg$paths$mall_source_preagg, "mall")
write_aux_source_preagg(apartment_raw, cfg$paths$apartment_registry_source_preagg, "apartment_registry")
write_aux_source_preagg(senior_raw, cfg$paths$senior_source_preagg, "senior")
write_aux_source_preagg(bus_raw, cfg$paths$bus_stop_source_preagg, "bus_stop")
write_aux_source_preagg(subway_raw, cfg$paths$subway_station_source_preagg, "subway_station")
remove_obsolete_aux_intermediate_files()

#==============================================================================
# 3. Assemble Auxiliary Covariate Panel
#==============================================================================

# assemble 단계에서는 방금 저장한 preagg를 다시 읽어 aux 변수로 집계한다.
# 이렇게 해야 intermediate가 실제 생산-소비 관계를 가지게 되고,
# source raw를 다시 열지 않고도 집계 parity를 검증할 수 있다.
medical_source_preagg <- read_aux_source_preagg(cfg$paths$medical_source_preagg, "medical")
mall_source_preagg <- read_aux_source_preagg(cfg$paths$mall_source_preagg, "mall")
apartment_source_preagg <- read_aux_source_preagg(cfg$paths$apartment_registry_source_preagg, "apartment_registry")
senior_source_preagg <- read_aux_source_preagg(cfg$paths$senior_source_preagg, "senior")
bus_stop_source_preagg <- read_aux_source_preagg(cfg$paths$bus_stop_source_preagg, "bus_stop")
subway_station_source_preagg <- read_aux_source_preagg(cfg$paths$subway_station_source_preagg, "subway_station")

medical_source_year <- if (nrow(medical_source_preagg) == 0) {
  build_base_year_values(c("hospital_count_aux", medical_detail_cols))
} else {
  build_permit_panel_count_by_type_from_mapped(
    medical_source_preagg,
    years = years_target,
    open_col = "인허가일자",
    close_col = "폐업일자",
    type_col = "medical_type",
    type_levels = medical_detail_step_cols
  ) |>
    dplyr::mutate(
      medical_public_health_count_aux = medical_public_health_center_count_aux + medical_public_health_subcenter_count_aux,
      hospital_count_aux = rowSums(dplyr::pick(dplyr::all_of(medical_detail_step_cols)), na.rm = TRUE),
      .before = 3
    )
}

mall_source_year <- if (nrow(mall_source_preagg) == 0) {
  build_base_year_values(c("mall_count_aux", mall_detail_cols))
} else {
  build_permit_panel_count_by_type_from_mapped(
    mall_source_preagg,
    years = years_target,
    open_col = "인허가일자",
    close_col = "폐업일자",
    type_col = "mall_type",
    type_levels = mall_detail_cols
  ) |>
    dplyr::mutate(
      mall_count_aux = rowSums(dplyr::pick(dplyr::all_of(mall_detail_cols)), na.rm = TRUE),
      .before = 3
    )
}

senior_source_year <- build_senior_year_from_preagg(senior_source_preagg, years = years_target)

apartment_source_year <- if (nrow(apartment_source_preagg) == 0) {
  build_base_year_values(c("apartment_complex_count_kapt", "apartment_building_count", "apartment_household_count"), fill = NA_real_)
} else {
  apartment_source_preagg |>
    dplyr::filter(
      !is.na(adm_cd),
      is.finite(use_approval_year),
      use_approval_year <= max(years_target)
    ) |>
    dplyr::mutate(
      complex_uid = dplyr::coalesce(apartment_code, paste0("row_", apartment_record_id)),
      building_count = dplyr::coalesce(safe_num(building_count), 0),
      household_count = dplyr::coalesce(safe_num(household_count), 0),
      year = purrr::map(use_approval_year, ~ years_target[years_target >= .x])
    ) |>
    tidyr::unnest(year) |>
    dplyr::group_by(adm_cd, year) |>
    dplyr::summarise(
      apartment_complex_count_kapt = dplyr::n_distinct(complex_uid),
      apartment_building_count = sum(building_count, na.rm = TRUE),
      apartment_household_count = sum(household_count, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::right_join(base_year, by = c("adm_cd", "year")) |>
    dplyr::mutate(
      apartment_complex_count_kapt = dplyr::coalesce(apartment_complex_count_kapt, 0),
      apartment_building_count = dplyr::coalesce(apartment_building_count, 0),
      apartment_household_count = dplyr::coalesce(apartment_household_count, 0)
    ) |>
    dplyr::select(adm_cd, year, apartment_complex_count_kapt, apartment_building_count, apartment_household_count) |>
    dplyr::arrange(adm_cd, year)
}

bus_stop_source_quarter <- if (nrow(bus_stop_source_preagg) == 0) {
  base_quarter |>
    dplyr::mutate(bus_stop_count_aux = NA_real_)
} else {
  build_point_preagg_quarter_count(bus_stop_source_preagg, "bus_stop_count_aux")
}

subway_station_source_quarter <- if (nrow(subway_station_source_preagg) == 0) {
  base_quarter |>
    dplyr::mutate(subway_station_count_aux = NA_real_)
} else {
  build_point_preagg_quarter_count(subway_station_source_preagg, "subway_station_count_aux")
}

transit_source_quarter <- bus_stop_source_quarter |>
  dplyr::left_join(
    subway_station_source_quarter,
    by = c("adm_cd", "year", "quarter", "yq", "quarter_index")
  )

# `aux`는 아직 저장 전 객체이고, 여기서 모든 source의 as-of 결과를
# adm_cd-yq 격자에 맞춰 하나로 합친다. 혼합주기 source는 source precision
# 한계를 QC와 설계 문서에 남긴다.
aux <- base_quarter |>
  dplyr::left_join(
    land_price_quarter |>
      dplyr::select(
        adm_cd, year, quarter, yq, quarter_index,
        official_land_price,
        land_price_lpi_factor,
        land_price_adjusted,
        land_price_lpi_source_bjd_n,
        land_price_lpi_weight_coverage
      ),
    by = c("adm_cd", "year", "quarter", "yq", "quarter_index")
  ) |>
  dplyr::left_join(park_year, by = c("adm_cd", "year")) |>
  dplyr::left_join(senior_source_year, by = c("adm_cd", "year")) |>
  dplyr::left_join(transit_source_quarter, by = c("adm_cd", "year", "quarter", "yq", "quarter_index")) |>
  dplyr::left_join(medical_source_year, by = c("adm_cd", "year")) |>
  dplyr::left_join(mall_source_year, by = c("adm_cd", "year")) |>
  dplyr::left_join(apartment_source_year, by = c("adm_cd", "year")) |>
  dplyr::left_join(physical_year, by = c("adm_cd", "year")) |>
  dplyr::arrange(adm_cd, year, quarter) |>
  dplyr::mutate(
    dplyr::across(
      c(
        official_land_price, land_price_lpi_factor, land_price_adjusted,
        land_price_lpi_source_bjd_n, land_price_lpi_weight_coverage,
        park_area, senior_facility_count,
        bus_stop_count_aux, subway_station_count_aux, hospital_count_aux, mall_count_aux,
        apartment_complex_count_kapt, apartment_building_count, apartment_household_count,
        road_length_km, sidewalk_length_km, intersection_density, avg_slope_degree, betweenness_centrality,
        dplyr::all_of(senior_detail_cols),
        dplyr::all_of(medical_detail_cols),
        dplyr::all_of(mall_detail_cols)
      ),
      safe_num
    )
  )

validate_panel_keys(aux, c("adm_cd", "yq"))

#==============================================================================
# 4. Save Output and Coverage Logs
#==============================================================================

# source별 preagg는 사람과 QC가 검토하고, `aux_covariates`는 downstream panel이 소비한다.
write_parquet_safe(aux, cfg$paths$aux_covariates)
append_log(cfg$logs$data_qc, sprintf("- Aux covariates rows: %d", nrow(aux)))

for (v in c(
  "official_land_price", "land_price_lpi_factor", "land_price_adjusted",
  "land_price_lpi_source_bjd_n", "land_price_lpi_weight_coverage",
  "park_area", "senior_facility_count",
  "bus_stop_count_aux", "subway_station_count_aux", "hospital_count_aux", "mall_count_aux",
  "apartment_complex_count_kapt", "apartment_building_count", "apartment_household_count",
  "road_length_km", "sidewalk_length_km", "intersection_density", "avg_slope_degree", "betweenness_centrality",
  senior_detail_cols,
  medical_detail_cols, mall_detail_cols
)) {
  log_coverage(aux, v)
}

append_log(cfg$logs$data_qc, "- aux_covariates assembled from current auxiliary source builders")
append_log(cfg$logs$data_qc, "- source-specific preagg records were aligned to quarterly auxiliary covariates where applicable")
