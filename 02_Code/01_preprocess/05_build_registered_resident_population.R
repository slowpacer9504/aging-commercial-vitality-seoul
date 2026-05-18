#!/usr/bin/env Rscript

#==============================================================================
# Script    : 05_build_registered_resident_population.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build canonical quarterly resident-population and resident-aging
#             variables from MOIS monthly 5-year registered-population CSVs.
# Author    : Codex
# Created   : 2026-05-14
# Type      : panel_building
# Inputs    : MOIS registered population CSVs, seoul_quarter_base.parquet,
#             2020 Seoul administrative-dong boundary
# Outputs   : registered_resident_population.parquet,
#             registered_resident_population_monthly.parquet,
#             registered_resident_population_qc.csv,
#             registered_resident_population_mapping_qc.csv
# DependsOn : 02_build_seoul_quarter_base.R
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
load_project_packages()

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 05_build_registered_resident_population", timestamp()))

if (!file.exists(cfg$paths$quarter_base)) {
  stop(sprintf("[ERROR] Missing required input: %s", cfg$paths$quarter_base), call. = FALSE)
}

raw_files <- sort(list.files(
  cfg$dir_registered_resident_population,
  pattern = "1B04005N.*[.]csv$",
  recursive = TRUE,
  full.names = TRUE
))
if (length(raw_files) == 0L) {
  stop(
    sprintf("[ERROR] MOIS registered-population CSV files not found under: %s", cfg$dir_registered_resident_population),
    call. = FALSE
  )
}


#==============================================================================
# 1. Helpers
#==============================================================================

normalize_adm_name <- function(x) {
  x |>
    as.character() |>
    stringr::str_squish() |>
    stringr::str_replace_all("[ㆍ･\\.]", "·") |>
    stringr::str_replace_all("홍제제([0-9]+)동", "홍제\\1동") |>
    stringr::str_replace_all("상일제([0-9]+)동", "상일\\1동") |>
    stringr::str_replace_all("(?<!홍)제([0-9]+)", "\\1")
}

normalize_age_band <- function(x) {
  x |>
    as.character() |>
    stringr::str_squish() |>
    stringr::str_replace_all("세이상|세 이상", "+")
}

sum_or_na <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  finite <- is.finite(x)
  if (!any(finite)) return(NA_real_)
  sum(x[finite], na.rm = TRUE)
}

mean_or_na <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  finite <- is.finite(x)
  if (!any(finite)) return(NA_real_)
  mean(x[finite], na.rm = TRUE)
}

ratio_or_na <- function(num, den) {
  num <- suppressWarnings(as.numeric(num))
  den <- suppressWarnings(as.numeric(den))
  dplyr::if_else(is.finite(num) & is.finite(den) & den > 0, num / den, NA_real_)
}

parse_population_value <- function(x) {
  suppressWarnings(readr::parse_number(as.character(x), locale = readr::locale(grouping_mark = ",")))
}

apply_2020_boundary_harmonization <- function(gu_name, dong_name_norm, year) {
  dplyr::case_when(
    gu_name == "강동구" & dong_name_norm == "상일1동" ~ "상일동",
    gu_name == "강동구" & dong_name_norm == "상일2동" ~ "강일동",
    gu_name == "강남구" & dong_name_norm == "개포3동" ~ "일원2동",
    gu_name == "동대문구" & year >= 2025L & dong_name_norm %in% c("신설동", "용두동", "용신동") ~ "용신동",
    TRUE ~ dong_name_norm
  )
}

collapse_unique <- function(x) {
  x <- unique(stats::na.omit(as.character(x)))
  if (length(x) == 0L) return(NA_character_)
  paste(sort(x), collapse = ";")
}

has_proxy_row <- function(flag) {
  any(flag == 1L, na.rm = TRUE)
}

summarise_proxy_type <- function(flag, proxy_type) {
  if (has_proxy_row(flag)) return(collapse_unique(proxy_type[flag == 1L]))
  "direct"
}

summarise_proxy_source_adm_cd <- function(flag, source_adm_cd, direct_adm_cd) {
  if (has_proxy_row(flag)) return(collapse_unique(source_adm_cd[flag == 1L]))
  as.character(dplyr::first(direct_adm_cd))
}

summarise_proxy_year <- function(flag, proxy_year, direct_year) {
  if (has_proxy_row(flag)) return(as.integer(min(proxy_year[flag == 1L], na.rm = TRUE)))
  as.integer(dplyr::first(direct_year))
}

registered_split_allocation_rules <- function() {
  tibble::tribble(
    ~parent_adm_cd, ~allocated_adm_cd, ~start_year, ~end_year, ~reference_year, ~proxy_type,
    "0011530780", "0011530780", cfg$short_start, 2019L, 2020L, "pre_2020_oryu2_hangdong_split_2020_ratio",
    "0011530780", "0011530800", cfg$short_start, 2019L, 2020L, "pre_2020_oryu2_hangdong_split_2020_ratio"
  )
}

apply_registered_split_allocations <- function(monthly_age_pop) {
  rules <- registered_split_allocation_rules()
  if (nrow(rules) == 0L) return(monthly_age_pop)

  rule_groups <- rules |>
    dplyr::distinct(parent_adm_cd, start_year, end_year, reference_year, proxy_type)

  split_weights <- monthly_age_pop |>
    dplyr::select(adm_cd, year, month, age_band, population) |>
    dplyr::inner_join(rules, by = c("adm_cd" = "allocated_adm_cd")) |>
    dplyr::filter(.data$year == .data$reference_year, .data$age_band != "계") |>
    dplyr::group_by(.data$parent_adm_cd, .data$reference_year, .data$month, .data$age_band) |>
    dplyr::mutate(
      reference_total = sum(.data$population, na.rm = TRUE),
      split_weight = dplyr::if_else(
        is.finite(.data$population) & is.finite(.data$reference_total) & .data$reference_total > 0,
        .data$population / .data$reference_total,
        NA_real_
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::rename(allocated_adm_cd = adm_cd) |>
    dplyr::select(parent_adm_cd, allocated_adm_cd, reference_year, month, age_band, split_weight)

  invalid_weights <- split_weights |>
    dplyr::filter(!is.finite(.data$split_weight))
  if (nrow(invalid_weights) > 0L) {
    stop("[ERROR] invalid registered-population split weights for pre-2020 boundary allocation", call. = FALSE)
  }

  source_parent <- monthly_age_pop |>
    dplyr::select(adm_cd, year, month, age_band, population, source_rows) |>
    dplyr::inner_join(rule_groups, by = c("adm_cd" = "parent_adm_cd")) |>
    dplyr::filter(.data$year >= .data$start_year, .data$year <= .data$end_year) |>
    dplyr::mutate(parent_adm_cd = .data$adm_cd)

  if (nrow(source_parent) == 0L) return(monthly_age_pop)

  allocated_detail <- source_parent |>
    dplyr::filter(.data$age_band != "계") |>
    dplyr::left_join(
      split_weights,
      by = c("parent_adm_cd", "reference_year", "month", "age_band")
    ) |>
    dplyr::filter(!is.na(.data$allocated_adm_cd)) |>
    dplyr::mutate(allocated_population = .data$population * .data$split_weight)

  allocated_total <- allocated_detail |>
    dplyr::group_by(
      .data$parent_adm_cd, .data$allocated_adm_cd, .data$year, .data$month,
      .data$source_rows, .data$reference_year, .data$proxy_type
    ) |>
    dplyr::summarise(
      age_band = "계",
      allocated_population = sum(.data$allocated_population, na.rm = TRUE),
      .groups = "drop"
    )

  allocated_raw <- dplyr::bind_rows(
    allocated_detail |>
      dplyr::select(
        parent_adm_cd, allocated_adm_cd, year, month, age_band, source_rows,
        reference_year, proxy_type, allocated_population
      ),
    allocated_total |>
      dplyr::select(
        parent_adm_cd, allocated_adm_cd, year, month, age_band, source_rows,
        reference_year, proxy_type, allocated_population
      )
  )

  allocation_check <- allocated_raw |>
    dplyr::group_by(.data$parent_adm_cd, .data$year, .data$month, .data$age_band) |>
    dplyr::summarise(
      allocated_population = sum(.data$allocated_population, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::left_join(
      source_parent |>
        dplyr::select(
          parent_adm_cd, year, month, age_band,
          original_population = population
        ),
      by = c("parent_adm_cd", "year", "month", "age_band")
    ) |>
    dplyr::mutate(abs_diff = abs(.data$original_population - .data$allocated_population))
  max_allocation_diff <- max(allocation_check$abs_diff, na.rm = TRUE)
  if (is.finite(max_allocation_diff) && max_allocation_diff > 1e-6) {
    stop(
      sprintf("[ERROR] registered-population split allocation does not preserve parent totals: max_diff=%.8f", max_allocation_diff),
      call. = FALSE
    )
  }

  allocated <- allocated_raw |>
    dplyr::transmute(
      adm_cd = .data$allocated_adm_cd,
      year = .data$year,
      month = .data$month,
      age_band = .data$age_band,
      population = .data$allocated_population,
      source_rows = .data$source_rows,
      registered_boundary_proxy_flag = 1L,
      registered_boundary_proxy_type = .data$proxy_type,
      registered_boundary_proxy_source_adm_cd = .data$parent_adm_cd,
      registered_boundary_proxy_source_year = .data$year,
      registered_boundary_proxy_reference_year = .data$reference_year
    )

  parent_keys <- source_parent |>
    dplyr::distinct(adm_cd, year, month, age_band)

  monthly_age_pop |>
    dplyr::anti_join(parent_keys, by = c("adm_cd", "year", "month", "age_band")) |>
    dplyr::bind_rows(allocated) |>
    dplyr::arrange(.data$adm_cd, .data$year, .data$month, .data$age_band)
}

add_gu_context <- function(df, region_col = "행정구역(동읍면)별") {
  gu_names <- seoul_gu_region_lookup()$gu_name
  region <- as.character(df[[region_col]])
  gu_name <- rep(NA_character_, length(region))
  row_type <- rep("dong", length(region))
  current_gu <- NA_character_

  for (ii in seq_along(region)) {
    this_region <- stringr::str_squish(region[[ii]])
    if (identical(this_region, "서울특별시")) {
      current_gu <- NA_character_
      row_type[[ii]] <- "city"
    } else if (this_region %in% gu_names) {
      current_gu <- this_region
      row_type[[ii]] <- "gu"
    } else {
      row_type[[ii]] <- "dong"
    }
    gu_name[[ii]] <- current_gu
  }

  df |>
    dplyr::mutate(
      gu_name = gu_name,
      row_type = row_type
    )
}

read_one_registered_file <- function(path) {
  raw <- read.csv(path, fileEncoding = "CP949", check.names = FALSE, stringsAsFactors = FALSE)
  raw <- tibble::as_tibble(raw, .name_repair = "minimal")
  named_cols <- !is.na(names(raw)) & nzchar(names(raw))
  raw <- raw[, named_cols, drop = FALSE]
  raw <- add_gu_context(raw)

  month_cols <- grep("^[0-9]{4}[.][0-9]{2}", names(raw), value = TRUE)
  if (length(month_cols) == 0L) {
    stop(sprintf("[ERROR] no month columns detected: %s", basename(path)), call. = FALSE)
  }
  file_years <- unique(as.integer(substr(month_cols, 1L, 4L)))
  if (length(file_years) != 1L || !is.finite(file_years[[1]])) {
    stop(sprintf("[ERROR] expected one year per MOIS file: %s", basename(path)), call. = FALSE)
  }

  raw |>
    dplyr::filter(
      .data$row_type == "dong",
      !is.na(.data$gu_name),
      stringr::str_detect(as.character(.data$항목), "총인구수")
    ) |>
    dplyr::transmute(
      source_file = basename(path),
      source_year = file_years[[1]],
      gu_name,
      dong_name_raw = as.character(.data$`행정구역(동읍면)별`),
      dong_name_norm = normalize_adm_name(.data$`행정구역(동읍면)별`),
      age_band = normalize_age_band(.data$`5세별`),
      dplyr::across(dplyr::all_of(month_cols), identity)
    ) |>
    tidyr::pivot_longer(
      cols = dplyr::all_of(month_cols),
      names_to = "month_label",
      values_to = "resident_value_raw"
    ) |>
    dplyr::mutate(
      year = as.integer(substr(.data$month_label, 1L, 4L)),
      month = as.integer(substr(.data$month_label, 6L, 7L)),
      resident_value = parse_population_value(.data$resident_value_raw)
    ) |>
    dplyr::select(-resident_value_raw)
}

build_boundary_lookup <- function() {
  region_lookup <- if (file.exists(cfg$paths$adm_region_lookup)) {
    arrow::read_parquet(cfg$paths$adm_region_lookup) |>
      tibble::as_tibble()
  } else {
    load_commercial_boundary(cfg$dir_boundary, target_crs = cfg$target_crs) |>
      build_adm_region_lookup(boundary_year = cfg$boundary_year)
  }

  boundary <- region_lookup |>
    dplyr::transmute(
      adm_cd = as.character(.data$adm_cd),
      adm_cd_raw = as.character(.data$adm_cd),
      boundary_dong_name = as.character(.data$adstrd_nm),
      boundary_dong_name_norm = normalize_adm_name(.data$adstrd_nm),
      gu_prefix = as.character(.data$gu_prefix),
      gu_name = as.character(.data$gu_name),
      gu_order = as.integer(.data$gu_order),
      living_area = as.character(.data$living_area),
      living_area_order = as.integer(.data$living_area_order)
    )

  dup <- boundary |>
    dplyr::count(.data$gu_name, .data$boundary_dong_name_norm, name = "n") |>
    dplyr::filter(.data$n > 1L)
  if (nrow(dup) > 0L) {
    stop("[ERROR] duplicate boundary lookup keys detected", call. = FALSE)
  }

  boundary
}


#==============================================================================
# 2. Read, Harmonize, and Map to 2020 adm_cd
#==============================================================================

registered_long <- purrr::map_dfr(raw_files, read_one_registered_file) |>
  dplyr::filter(.data$year >= cfg$short_start, .data$year <= cfg$short_end)

boundary_lookup <- build_boundary_lookup()

registered_mapped <- registered_long |>
  dplyr::mutate(
    canonical_dong_name_norm = apply_2020_boundary_harmonization(.data$gu_name, .data$dong_name_norm, .data$year)
  ) |>
  dplyr::left_join(
    boundary_lookup,
    by = c("gu_name" = "gu_name", "canonical_dong_name_norm" = "boundary_dong_name_norm")
  )

mapping_qc <- registered_mapped |>
  dplyr::distinct(
    source_year, gu_name, dong_name_raw, dong_name_norm, canonical_dong_name_norm,
    adm_cd, boundary_dong_name
  ) |>
  dplyr::mutate(mapping_status = dplyr::if_else(is.na(.data$adm_cd), "unmatched", "matched")) |>
  dplyr::arrange(.data$source_year, .data$gu_name, .data$dong_name_raw)

write_csv_safe(mapping_qc, cfg$logs$registered_resident_population_mapping_qc)

unmatched <- mapping_qc |>
  dplyr::filter(.data$mapping_status == "unmatched")
if (nrow(unmatched) > 0L) {
  stop(
    sprintf(
      "[ERROR] unmatched MOIS resident-population administrative rows: %d. See %s",
      nrow(unmatched),
      cfg$logs$registered_resident_population_mapping_qc
    ),
    call. = FALSE
  )
}


#==============================================================================
# 3. Monthly and Annual Resident Population Variables
#==============================================================================

age_0_19 <- c("0 - 4세", "5 - 9세", "10 - 14세", "15 - 19세")
age20 <- c("20 - 24세", "25 - 29세")
age30 <- c("30 - 34세", "35 - 39세")
age40 <- c("40 - 44세", "45 - 49세")
age50 <- c("50 - 54세", "55 - 59세")
age60_64 <- c("60 - 64세")
age65_74 <- c("65 - 69세", "70 - 74세")
age75plus <- c("75 - 79세", "80 - 84세", "85 - 89세", "90 - 94세", "95 - 99세", "100+")
age60plus <- c(age60_64, age65_74, age75plus)
age65plus <- c(age65_74, age75plus)
age_all <- c(age_0_19, age20, age30, age40, age50, age60plus)

monthly_age_pop <- registered_mapped |>
  dplyr::filter(!is.na(.data$adm_cd)) |>
  dplyr::group_by(.data$adm_cd, .data$year, .data$month, .data$age_band) |>
  dplyr::summarise(
    population = sum_or_na(.data$resident_value),
    source_rows = dplyr::n(),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    registered_boundary_proxy_flag = 0L,
    registered_boundary_proxy_type = "direct",
    registered_boundary_proxy_source_adm_cd = .data$adm_cd,
    registered_boundary_proxy_source_year = .data$year,
    registered_boundary_proxy_reference_year = .data$year
  ) |>
  apply_registered_split_allocations()

monthly <- monthly_age_pop |>
  dplyr::group_by(.data$adm_cd, .data$year, .data$month) |>
  dplyr::summarise(
    resident_pop = sum_or_na(.data$population[.data$age_band == "계"]),
    age20_resident_pop = sum_or_na(.data$population[.data$age_band %in% age20]),
    age30_resident_pop = sum_or_na(.data$population[.data$age_band %in% age30]),
    age40_resident_pop = sum_or_na(.data$population[.data$age_band %in% age40]),
    age50_resident_pop = sum_or_na(.data$population[.data$age_band %in% age50]),
    age60_64_resident_pop = sum_or_na(.data$population[.data$age_band %in% age60_64]),
    age65_74_resident_pop = sum_or_na(.data$population[.data$age_band %in% age65_74]),
    age75plus_resident_pop = sum_or_na(.data$population[.data$age_band %in% age75plus]),
    age60_resident_pop = sum_or_na(.data$population[.data$age_band %in% age60plus]),
    age65plus_resident_pop = sum_or_na(.data$population[.data$age_band %in% age65plus]),
    age_group_total_pop = sum_or_na(.data$population[.data$age_band %in% age_all]),
    registered_boundary_proxy_flag = max(.data$registered_boundary_proxy_flag, na.rm = TRUE),
    registered_boundary_proxy_type = summarise_proxy_type(
      .data$registered_boundary_proxy_flag,
      .data$registered_boundary_proxy_type
    ),
    registered_boundary_proxy_source_adm_cd = summarise_proxy_source_adm_cd(
      .data$registered_boundary_proxy_flag,
      .data$registered_boundary_proxy_source_adm_cd,
      .data$adm_cd
    ),
    registered_boundary_proxy_source_year = summarise_proxy_year(
      .data$registered_boundary_proxy_flag,
      .data$registered_boundary_proxy_source_year,
      .data$year
    ),
    registered_boundary_proxy_reference_year = summarise_proxy_year(
      .data$registered_boundary_proxy_flag,
      .data$registered_boundary_proxy_reference_year,
      .data$year
    ),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    age_mix_total_resident_pop = .data$age20_resident_pop + .data$age30_resident_pop +
      .data$age40_resident_pop + .data$age50_resident_pop + .data$age60_resident_pop,
    age_group_total_abs_diff = abs(.data$resident_pop - .data$age_group_total_pop)
  ) |>
  dplyr::arrange(.data$adm_cd, .data$year, .data$month)

quarterly <- monthly |>
  dplyr::mutate(quarter = as.integer(ceiling(.data$month / 3))) |>
  dplyr::group_by(.data$adm_cd, .data$year, .data$quarter) |>
  dplyr::summarise(
    registered_month_n = sum(is.finite(.data$resident_pop)),
    resident_pop = mean_or_na(.data$resident_pop),
    age20_resident_pop = mean_or_na(.data$age20_resident_pop),
    age30_resident_pop = mean_or_na(.data$age30_resident_pop),
    age40_resident_pop = mean_or_na(.data$age40_resident_pop),
    age50_resident_pop = mean_or_na(.data$age50_resident_pop),
    age60_64_resident_pop = mean_or_na(.data$age60_64_resident_pop),
    age65_74_resident_pop = mean_or_na(.data$age65_74_resident_pop),
    age75plus_resident_pop = mean_or_na(.data$age75plus_resident_pop),
    age60_resident_pop = mean_or_na(.data$age60_resident_pop),
    age65plus_resident_pop = mean_or_na(.data$age65plus_resident_pop),
    age_mix_total_resident_pop = mean_or_na(.data$age_mix_total_resident_pop),
    resident_pop_month_sum = sum_or_na(.data$resident_pop),
    age20_resident_pop_month_sum = sum_or_na(.data$age20_resident_pop),
    age30_resident_pop_month_sum = sum_or_na(.data$age30_resident_pop),
    age40_resident_pop_month_sum = sum_or_na(.data$age40_resident_pop),
    age50_resident_pop_month_sum = sum_or_na(.data$age50_resident_pop),
    age60_64_resident_pop_month_sum = sum_or_na(.data$age60_64_resident_pop),
    age65_74_resident_pop_month_sum = sum_or_na(.data$age65_74_resident_pop),
    age75plus_resident_pop_month_sum = sum_or_na(.data$age75plus_resident_pop),
    age60_resident_pop_month_sum = sum_or_na(.data$age60_resident_pop),
    age65plus_resident_pop_month_sum = sum_or_na(.data$age65plus_resident_pop),
    age_mix_total_resident_pop_month_sum = sum_or_na(.data$age_mix_total_resident_pop),
    age_group_total_abs_diff_max = suppressWarnings(max(.data$age_group_total_abs_diff, na.rm = TRUE)),
    registered_boundary_proxy_flag = max(.data$registered_boundary_proxy_flag, na.rm = TRUE),
    registered_boundary_proxy_type = summarise_proxy_type(
      .data$registered_boundary_proxy_flag,
      .data$registered_boundary_proxy_type
    ),
    registered_boundary_proxy_source_adm_cd = summarise_proxy_source_adm_cd(
      .data$registered_boundary_proxy_flag,
      .data$registered_boundary_proxy_source_adm_cd,
      .data$adm_cd
    ),
    registered_boundary_proxy_source_year = summarise_proxy_year(
      .data$registered_boundary_proxy_flag,
      .data$registered_boundary_proxy_source_year,
      .data$year
    ),
    registered_boundary_proxy_reference_year = summarise_proxy_year(
      .data$registered_boundary_proxy_flag,
      .data$registered_boundary_proxy_reference_year,
      .data$year
    ),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    age60_resident_share = ratio_or_na(.data$age60_resident_pop, .data$resident_pop),
    age60_64_resident_share = ratio_or_na(.data$age60_64_resident_pop, .data$resident_pop),
    age65_74_resident_share = ratio_or_na(.data$age65_74_resident_pop, .data$resident_pop),
    age75plus_resident_share = ratio_or_na(.data$age75plus_resident_pop, .data$resident_pop),
    age65plus_resident_share = ratio_or_na(.data$age65plus_resident_pop, .data$resident_pop),
    age20_resident_share = ratio_or_na(.data$age20_resident_pop, .data$age_mix_total_resident_pop),
    age30_resident_share = ratio_or_na(.data$age30_resident_pop, .data$age_mix_total_resident_pop),
    age40_resident_share = ratio_or_na(.data$age40_resident_pop, .data$age_mix_total_resident_pop),
    age50_resident_share = ratio_or_na(.data$age50_resident_pop, .data$age_mix_total_resident_pop),
    yq = make_yq(.data$year, .data$quarter),
    age60plus_resident_share = ratio_or_na(.data$age60_resident_pop, .data$age_mix_total_resident_pop),
    resident_population_source = "MOIS_registered_population_5year_monthly"
  ) |>
  dplyr::select(
    adm_cd, year, quarter, yq,
    resident_pop, age60_resident_pop, age60_resident_share,
    age20_resident_pop, age30_resident_pop, age40_resident_pop, age50_resident_pop,
    age60_64_resident_pop, age65_74_resident_pop, age75plus_resident_pop, age65plus_resident_pop,
    age20_resident_share, age30_resident_share, age40_resident_share, age50_resident_share,
    age60plus_resident_share,
    age60_64_resident_share, age65_74_resident_share, age75plus_resident_share, age65plus_resident_share,
    registered_month_n, age_group_total_abs_diff_max, resident_population_source,
    registered_boundary_proxy_flag, registered_boundary_proxy_type,
    registered_boundary_proxy_source_adm_cd, registered_boundary_proxy_source_year,
    registered_boundary_proxy_reference_year
  ) |>
  dplyr::arrange(.data$adm_cd, .data$year, .data$quarter)

quarter_base_keys <- arrow::read_parquet(cfg$paths$quarter_base, col_select = tidyselect::all_of(c("adm_cd", "year", "quarter", "yq", "quarter_index"))) |>
  tibble::as_tibble() |>
  standardize_keys() |>
  dplyr::arrange(.data$adm_cd, .data$year, .data$quarter)
validate_panel_keys(quarter_base_keys, c("adm_cd", "yq"))

missing_quarter_keys <- quarter_base_keys |>
  dplyr::anti_join(quarterly, by = c("adm_cd", "year", "quarter", "yq"))
if (nrow(missing_quarter_keys) > 0L) {
  stop(
    sprintf("[ERROR] registered resident population missing for panel keys: %d", nrow(missing_quarter_keys)),
    call. = FALSE
  )
}

registered_panel <- quarter_base_keys |>
  dplyr::left_join(quarterly, by = c("adm_cd", "year", "quarter", "yq"))

validate_panel_keys(registered_panel, c("adm_cd", "yq"))

missing_core <- registered_panel |>
  dplyr::filter(!is.finite(.data$resident_pop) | !is.finite(.data$age60_resident_share))
if (nrow(missing_core) > 0L) {
  stop(
    sprintf("[ERROR] registered resident population missing for panel keys: %d", nrow(missing_core)),
    call. = FALSE
  )
}


#==============================================================================
# 4. QC and Save
#==============================================================================

qc_yq <- registered_panel |>
  dplyr::group_by(.data$yq) |>
  dplyr::summarise(
    scope = "yq",
    row_n = dplyr::n(),
    adm_n = dplyr::n_distinct(.data$adm_cd),
    resident_pop_missing_n = sum(!is.finite(.data$resident_pop)),
    age60_share_missing_n = sum(!is.finite(.data$age60_resident_share)),
    registered_month_n_min = min(.data$registered_month_n, na.rm = TRUE),
    registered_month_n_max = max(.data$registered_month_n, na.rm = TRUE),
    boundary_proxy_n = sum(.data$registered_boundary_proxy_flag == 1L, na.rm = TRUE),
    age60_share_min = min(.data$age60_resident_share, na.rm = TRUE),
    age60_share_max = max(.data$age60_resident_share, na.rm = TRUE),
    age_group_total_abs_diff_max = max(.data$age_group_total_abs_diff_max, na.rm = TRUE),
    .groups = "drop"
  )

qc_overall <- registered_panel |>
  dplyr::summarise(
    yq = NA_character_,
    scope = "overall",
    row_n = dplyr::n(),
    adm_n = dplyr::n_distinct(.data$adm_cd),
    resident_pop_missing_n = sum(!is.finite(.data$resident_pop)),
    age60_share_missing_n = sum(!is.finite(.data$age60_resident_share)),
    registered_month_n_min = min(.data$registered_month_n, na.rm = TRUE),
    registered_month_n_max = max(.data$registered_month_n, na.rm = TRUE),
    boundary_proxy_n = sum(.data$registered_boundary_proxy_flag == 1L, na.rm = TRUE),
    age60_share_min = min(.data$age60_resident_share, na.rm = TRUE),
    age60_share_max = max(.data$age60_resident_share, na.rm = TRUE),
    age_group_total_abs_diff_max = max(.data$age_group_total_abs_diff_max, na.rm = TRUE)
  )

qc <- dplyr::bind_rows(qc_yq, qc_overall) |>
  dplyr::mutate(
    source_file_n = length(raw_files),
    expected_year_min = cfg$short_start,
    expected_year_max = cfg$short_end
  ) |>
  dplyr::select(scope, yq, dplyr::everything())

bad_month_coverage <- registered_panel |>
  dplyr::filter(.data$registered_month_n != 3L)
if (nrow(bad_month_coverage) > 0L) {
  stop(
    sprintf("[ERROR] non-3-month registered resident coverage detected: %d panel rows", nrow(bad_month_coverage)),
    call. = FALSE
  )
}

if (any(!is.finite(registered_panel$age60_resident_share) |
        registered_panel$age60_resident_share < 0 |
        registered_panel$age60_resident_share > 1)) {
  stop("[ERROR] invalid age60_resident_share values in registered resident population layer", call. = FALSE)
}

write_parquet_safe(monthly, cfg$paths$registered_resident_population_monthly)
write_parquet_safe(registered_panel, cfg$paths$registered_resident_population)
write_csv_safe(qc, cfg$logs$registered_resident_population_qc)

append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Registered resident population published: %s (rows=%d, raw_files=%d)",
    basename(cfg$paths$registered_resident_population),
    nrow(registered_panel),
    length(raw_files)
  )
)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Registered resident mapping QC: %s (rows=%d, unmatched=%d)",
    basename(cfg$logs$registered_resident_population_mapping_qc),
    nrow(mapping_qc),
    nrow(unmatched)
  )
)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Registered resident QC: %s (max age-sum diff=%.6f)",
    basename(cfg$logs$registered_resident_population_qc),
    max(qc$age_group_total_abs_diff_max, na.rm = TRUE)
  )
)

message(sprintf("[DONE] registered resident population rows=%d", nrow(registered_panel)))
