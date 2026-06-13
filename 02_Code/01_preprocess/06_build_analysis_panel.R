#==============================================================================
# Script    : 06_build_analysis_panel.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build the merged quarterly base panel and shared pre-vitality panel
#             by combining the quarterly Seoul base, auxiliary covariates,
#             common contemporaneous transforms, and QC.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-04-22
# Type      : panel_building
# Inputs    : seoul_quarter_base.parquet, aux_covariates.parquet,
#             living_population_external_inflow.parquet,
#             golmok_survival_rate.parquet,
#             registered_resident_population.parquet
# Outputs   : panel_merged_base.parquet, panel_main_pre_vitality.parquet,
#             missing_data_log.csv, panel_join_coverage_qc.csv,
#             panel_structural_count_flags.csv
# DependsOn : 02_build_seoul_quarter_base.R, 03_build_auxiliary_covariates.R,
#             01_build_living_population_inflow.R,
#             04_build_golmok_survival_rate.R,
#             05_build_registered_resident_population.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# This script creates the active shared quarterly handoff:
# 1) `panel_merged_base` captures the post-join provenance checkpoint.
# 2) `panel_main_pre_vitality` adds shared contemporaneous transforms before
#    the final vitality-index publication step.
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
source(here::here("02_Code", "R", "utils_transform.R"))
load_project_packages()

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 06_build_analysis_panel", timestamp()))

quarter_base_path <- value_or(cfg$paths$quarter_base, file.path(cfg$dir_analysis, "seoul_quarter_base.parquet"))
quarter_aggregation_qc_path <- value_or(
  cfg$logs$panel_quarter_aggregation_qc,
  file.path(cfg$dir_logs, "panel_quarter_aggregation_qc.csv")
)

required <- c(
  quarter_base_path,
  cfg$paths$aux_covariates,
  cfg$paths$aux_covariates_lag_support,
  cfg$paths$golmok_survival_rate,
  cfg$paths$registered_resident_population,
  cfg$paths$registered_resident_population_lag_support
)
missing <- required[!file.exists(required)]
if (length(missing) > 0) {
  stop(sprintf("[ERROR] Missing required input: %s", paste(missing, collapse = ", ")), call. = FALSE)
}

quarter_base <- arrow::read_parquet(quarter_base_path) |> tibble::as_tibble() |> standardize_keys()
aux <- arrow::read_parquet(cfg$paths$aux_covariates) |> tibble::as_tibble() |> standardize_keys()
aux_lag_support <- arrow::read_parquet(cfg$paths$aux_covariates_lag_support) |>
  tibble::as_tibble() |>
  standardize_keys()
living_inflow <- if (file.exists(cfg$paths$living_population_external_inflow)) {
  arrow::read_parquet(cfg$paths$living_population_external_inflow) |>
    tibble::as_tibble() |>
    standardize_keys()
} else {
  quarter_base |>
    dplyr::select(adm_cd, year, quarter, yq, quarter_index) |>
    dplyr::mutate(
      external_inflow_pop = NA_real_,
      inner_external_inflow_pop = NA_real_,
      metro_external_inflow_pop = NA_real_,
      living_population_source = "missing_optional_quarterly_sidecar"
    )
}
survival_rate <- arrow::read_parquet(cfg$paths$golmok_survival_rate) |>
  tibble::as_tibble() |>
  standardize_keys()
registered_resident <- arrow::read_parquet(cfg$paths$registered_resident_population) |>
  tibble::as_tibble() |>
  standardize_keys()
registered_resident_lag_support <- arrow::read_parquet(cfg$paths$registered_resident_population_lag_support) |>
  tibble::as_tibble() |>
  standardize_keys()

if (!"yq" %in% names(living_inflow)) {
  living_inflow <- quarter_base |>
    dplyr::select(adm_cd, year, quarter, yq, quarter_index) |>
    dplyr::left_join(living_inflow, by = c("adm_cd", "year"))
} else if (!"quarter_index" %in% names(living_inflow)) {
  living_inflow <- living_inflow |>
    dplyr::left_join(
      quarter_base |>
        dplyr::select(adm_cd, yq, quarter_index),
      by = c("adm_cd", "yq")
    )
}
adm_area_lookup <- load_commercial_boundary(cfg$dir_boundary, target_crs = cfg$target_crs) |>
  dplyr::mutate(adm_area_km2 = as.numeric(sf::st_area(geometry)) / 10^6) |>
  sf::st_drop_geometry() |>
  dplyr::group_by(adm_cd) |>
  dplyr::summarise(adm_area_km2 = sum(adm_area_km2, na.rm = TRUE), .groups = "drop")


#==============================================================================
# 1. Input Validation Helpers
#==============================================================================

assert_unique_keys <- function(df, keys, label) {
  assert_required_cols(df, keys, name = label)
  dup <- df |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(n > 1L)
  if (nrow(dup) > 0) {
    stop(sprintf("[ERROR] %s duplicated keys: %d", label, nrow(dup)), call. = FALSE)
  }
  invisible(TRUE)
}

has_value <- function(x) {
  if (is.numeric(x)) {
    is.finite(x)
  } else {
    !is.na(x) & trimws(as.character(x)) != ""
  }
}

pooled_z <- function(x, reference = NULL) {
  x_num <- suppressWarnings(as.numeric(x))
  if (is.null(reference)) {
    reference <- rep(TRUE, length(x_num))
  }
  reference <- as.logical(reference)
  if (length(reference) != length(x_num)) {
    stop("[ERROR] pooled_z reference length must match input length", call. = FALSE)
  }
  reference[is.na(reference)] <- FALSE
  finite <- is.finite(x_num)
  reference_finite <- finite & reference
  out <- rep(NA_real_, length(x_num))
  if (sum(reference_finite) < 2L) return(out)

  x_sd <- stats::sd(x_num[reference_finite], na.rm = TRUE)
  if (!is.finite(x_sd) || x_sd <= 1e-8) return(out)

  out[finite] <- (x_num[finite] - mean(x_num[reference_finite], na.rm = TRUE)) / x_sd
  out
}

build_lag_source_calendar <- function(lag_quarters, source_label) {
  tibble::as_tibble(cfg$lag_support_quarter_sequence) |>
    dplyr::transmute(
      !!paste0(source_label, "_quarter_index") := as.integer(.data$quarter_index),
      !!paste0(source_label, "_source_yq") := as.character(.data$yq)
    )
}

summarize_join_coverage <- function(df, vars, source_name) {
  vars <- intersect(vars, names(df))
  if (length(vars) == 0L) {
    return(tibble::tibble(
      source = character(0),
      yq = character(0),
      variable = character(0),
      non_missing_n = integer(0),
      row_n = integer(0),
      non_missing_share = numeric(0)
    ))
  }

  df |>
    dplyr::select(yq, dplyr::all_of(vars)) |>
    tidyr::pivot_longer(cols = dplyr::all_of(vars), names_to = "variable", values_to = "value") |>
    dplyr::group_by(yq, variable) |>
    dplyr::summarise(
      non_missing_n = sum(has_value(value)),
      row_n = dplyr::n(),
      non_missing_share = non_missing_n / pmax(row_n, 1L),
      .groups = "drop"
    ) |>
    dplyr::mutate(source = source_name, .before = 1)
}


#==============================================================================
# 2. Validate Input Contracts and Join Base Layers
#==============================================================================

quarter_keys <- c("adm_cd", "year", "quarter", "yq", "quarter_index")
assert_required_cols(quarter_base, quarter_keys, "quarter_base")
assert_required_cols(aux, quarter_keys, "aux_covariates")
assert_required_cols(
  aux_lag_support,
  c(quarter_keys, "land_price_adjusted", "workplace_worker_pop", "bus_stop_count_aux", "subway_station_count_aux"),
  "aux_covariates_lag_support"
)
assert_required_cols(living_inflow, c("adm_cd", "year", "quarter", "yq", "quarter_index", "external_inflow_pop"), "living_population_external_inflow")
assert_required_cols(survival_rate, c("adm_cd", "year", "quarter", "yq", "quarter_index", "survival_3y"), "golmok_survival_rate")
assert_required_cols(
  registered_resident,
  c("adm_cd", "year", "quarter", "yq", "resident_pop", "age60_resident_pop", "age60_resident_share"),
  "registered_resident_population"
)
assert_required_cols(
  registered_resident_lag_support,
  c("adm_cd", "year", "quarter", "yq", "resident_pop", "age60_resident_share"),
  "registered_resident_population_lag_support"
)
assert_unique_keys(quarter_base, c("adm_cd", "yq"), "quarter_base")
assert_unique_keys(aux, c("adm_cd", "yq"), "aux_covariates")
assert_unique_keys(aux_lag_support, c("adm_cd", "yq"), "aux_covariates_lag_support")
assert_unique_keys(living_inflow, c("adm_cd", "yq"), "living_population_external_inflow")
assert_unique_keys(survival_rate, c("adm_cd", "yq"), "golmok_survival_rate")
assert_unique_keys(registered_resident, c("adm_cd", "yq"), "registered_resident_population")
assert_unique_keys(registered_resident_lag_support, c("adm_cd", "yq"), "registered_resident_population_lag_support")

registered_resident_cols <- c(
  "resident_pop", "age60_resident_pop", "age60_resident_share",
  "age20_resident_pop", "age30_resident_pop", "age40_resident_pop", "age50_resident_pop",
  "age60_64_resident_pop", "age65_74_resident_pop", "age75plus_resident_pop", "age65plus_resident_pop",
  "age20_resident_share", "age30_resident_share", "age40_resident_share", "age50_resident_share",
  "age60plus_resident_share",
  "age60_64_resident_share", "age65_74_resident_share", "age75plus_resident_share", "age65plus_resident_share",
  "registered_month_n", "age_group_total_abs_diff_max", "resident_population_source"
)

panel_merged_base <- quarter_base |>
  dplyr::select(-dplyr::any_of(registered_resident_cols)) |>
  dplyr::left_join(aux, by = quarter_keys) |>
  dplyr::left_join(living_inflow, by = quarter_keys) |>
  dplyr::left_join(survival_rate, by = quarter_keys) |>
  dplyr::left_join(registered_resident, by = quarter_keys) |>
  dplyr::select(-dplyr::any_of(c(
    "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal",
    "vitality_sub_stability", "vitality_index_base", "vitality_index_entropy",
    "vitality_index_pca",
    "worker_pop", "age60_worker_pop"
  )))

if (nrow(panel_merged_base) != nrow(quarter_base)) {
  stop(
    sprintf(
      "[ERROR] merged base row mismatch: quarter_base=%d, merged=%d",
      nrow(quarter_base), nrow(panel_merged_base)
    ),
    call. = FALSE
  )
}

panel_main_pre_vitality <- panel_merged_base |>
  dplyr::left_join(adm_area_lookup, by = "adm_cd")

if (nrow(panel_main_pre_vitality) != nrow(quarter_base)) {
  stop(
    sprintf(
      "[ERROR] pre-vitality panel row mismatch: quarter_base=%d, panel_main_pre_vitality=%d",
      nrow(quarter_base), nrow(panel_main_pre_vitality)
    ),
    call. = FALSE
  )
}


#==============================================================================
# 3. Derive Shared Quarterly Variables
#==============================================================================

medical_detail_cols <- c(
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
walk_env_cols <- c("intersection_density", "avg_slope_degree", "betweenness_centrality")

expected_numeric_cols <- c(
  "official_land_price", "land_price_lpi_factor", "land_price_adjusted",
  "land_price_lpi_source_bjd_n", "land_price_lpi_weight_coverage",
  "workplace_worker_pop", "workplace_worker_source_year", "workplace_worker_raw_dong_n",
  "apartment_complex_count",
  "apartment_complex_count_kapt", "apartment_building_count", "apartment_household_count",
  "subway_station_count", "bus_stop_count", "hospital_count", "mall_count",
  "bus_stop_count_aux", "subway_station_count_aux",
  "hospital_count_aux", "hospital_count_aux_core", "mall_count_aux", "mall_count_aux_core",
  "medical_public_health_count_aux",
  "spend_total", "income_level", "resident_pop", "floating_pop",
  "age20_resident_pop", "age30_resident_pop", "age40_resident_pop", "age50_resident_pop",
  "age60_resident_pop", "age60_64_resident_pop", "age65_74_resident_pop",
  "age75plus_resident_pop", "age65plus_resident_pop",
  "age60_floating_pop", "age60_sales_amount",
  "total_household_commercial", "total_sales", "sales_count", "total_store_count",
  "facility_count", "sales_time_entropy", "sales_time_entropy_06_24",
  "sales_quarter_stability", "floating_time_entropy", "floating_time_entropy_06_24",
  "floating_quarter_stability",
  "inner_external_inflow_pop", "metro_external_inflow_pop", "external_inflow_pop",
  "inner_n_slots", "metro_n_slots", "inner_n_months", "metro_n_months",
  "survival_1y", "survival_1y_survived", "survival_1y_cohort",
  "survival_3y", "survival_3y_survived", "survival_3y_cohort",
  "survival_5y", "survival_5y_survived", "survival_5y_cohort",
  "age20_resident_share", "age30_resident_share", "age40_resident_share",
  "age50_resident_share", "age60plus_resident_share",
  "age60_resident_share", "age60_64_resident_share", "age65_74_resident_share",
  "age75plus_resident_share", "age65plus_resident_share",
  "registered_month_n", "age_group_total_abs_diff_max",
  "age60_floating_share", "age60_sales_share",
  "opening_rate", "closure_rate", "instability_index", "diversity_index",
  "operating_months_avg", "closure_months_avg", "seoul_operating_months_avg",
  "operating_months_rel_seoul", "park_area", "senior_facility_count",
  "road_length_km", "sidewalk_length_km",
  medical_detail_cols, mall_detail_cols, senior_detail_cols, walk_env_cols
)

for (nm in expected_numeric_cols) {
  if (!nm %in% names(panel_main_pre_vitality)) panel_main_pre_vitality[[nm]] <- NA_real_
}
for (nm in c("facility_available", "apartment_available")) {
  if (!nm %in% names(panel_main_pre_vitality)) panel_main_pre_vitality[[nm]] <- NA_integer_
}

analysis_reference <- as.character(panel_main_pre_vitality$yq) %in% get_analysis_yq_sequence()

panel_main_pre_vitality <- panel_main_pre_vitality |>
  dplyr::mutate(
    medical_public_health_count_aux = dplyr::coalesce(
      medical_public_health_count_aux,
      medical_public_health_center_count_aux + medical_public_health_subcenter_count_aux
    ),
    hospital_count_aux_core = dplyr::coalesce(
      hospital_count_aux_core,
      medical_general_hospital_count_aux + medical_hospital_count_aux + medical_public_health_center_count_aux
    ),
    mall_count_aux_core = dplyr::coalesce(
      mall_count_aux_core,
      mall_hypermarket_count_aux + mall_department_store_count_aux + mall_shopping_center_count_aux
    ),
    covid_period = dplyr::if_else(
      quarter_index >= cfg$covid_start_idx & quarter_index <= cfg$covid_end_idx,
      1L,
      0L
    ),
    resident_pop = dplyr::if_else(is.finite(resident_pop), pmax(resident_pop, 0), NA_real_),
    age20_resident_pop = dplyr::if_else(is.finite(age20_resident_pop), pmax(age20_resident_pop, 0), NA_real_),
    age30_resident_pop = dplyr::if_else(is.finite(age30_resident_pop), pmax(age30_resident_pop, 0), NA_real_),
    age40_resident_pop = dplyr::if_else(is.finite(age40_resident_pop), pmax(age40_resident_pop, 0), NA_real_),
    age50_resident_pop = dplyr::if_else(is.finite(age50_resident_pop), pmax(age50_resident_pop, 0), NA_real_),
    age60_resident_pop = dplyr::if_else(is.finite(age60_resident_pop), pmax(age60_resident_pop, 0), NA_real_),
    age60_64_resident_pop = dplyr::if_else(is.finite(age60_64_resident_pop), pmax(age60_64_resident_pop, 0), NA_real_),
    age65_74_resident_pop = dplyr::if_else(is.finite(age65_74_resident_pop), pmax(age65_74_resident_pop, 0), NA_real_),
    age75plus_resident_pop = dplyr::if_else(is.finite(age75plus_resident_pop), pmax(age75plus_resident_pop, 0), NA_real_),
    age65plus_resident_pop = dplyr::if_else(is.finite(age65plus_resident_pop), pmax(age65plus_resident_pop, 0), NA_real_),
    age60_floating_pop = dplyr::if_else(is.finite(age60_floating_pop), pmax(age60_floating_pop, 0), NA_real_),
    age60_sales_amount = dplyr::if_else(is.finite(age60_sales_amount), pmax(age60_sales_amount, 0), NA_real_),
    sales_count = dplyr::if_else(is.finite(sales_count), pmax(sales_count, 0), NA_real_),
    external_inflow_pop = dplyr::if_else(is.finite(external_inflow_pop), pmax(external_inflow_pop, 0), NA_real_),
    apartment_complex_count_kapt = dplyr::if_else(is.finite(apartment_complex_count_kapt), pmax(apartment_complex_count_kapt, 0), NA_real_),
    apartment_building_count = dplyr::if_else(is.finite(apartment_building_count), pmax(apartment_building_count, 0), NA_real_),
    apartment_household_count = dplyr::if_else(is.finite(apartment_household_count), pmax(apartment_household_count, 0), NA_real_),
    workplace_worker_pop = dplyr::if_else(is.finite(workplace_worker_pop), pmax(workplace_worker_pop, 0), NA_real_),
    bus_stop_count_aux = dplyr::if_else(is.finite(bus_stop_count_aux), pmax(bus_stop_count_aux, 0), NA_real_),
    subway_station_count_aux = dplyr::if_else(is.finite(subway_station_count_aux), pmax(subway_station_count_aux, 0), NA_real_),
    transit_accessibility = {
      bus_z <- pooled_z(bus_stop_count_aux, reference = analysis_reference)
      subway_z <- pooled_z(subway_station_count_aux, reference = analysis_reference)
      dplyr::if_else(is.finite(bus_z) & is.finite(subway_z), (bus_z + subway_z) / 2, NA_real_)
    },
    ln_age60_resident_pop = safe_log1p(age60_resident_pop),
    ln_age60_floating_pop = safe_log1p(age60_floating_pop),
    ln_age60_sales_amount = safe_log1p(age60_sales_amount),
    ln_total_sales = safe_log1p(total_sales),
    ln_sales_count = safe_log1p(sales_count),
    ln_total_store_count = safe_log1p(total_store_count),
    stability_score = -closure_rate,
    ln_resident_pop = safe_log1p(resident_pop),
    ln_workplace_worker_pop = safe_log1p(workplace_worker_pop),
    ln_apartment_household_count = safe_log1p(apartment_household_count),
    ln_floating_pop = safe_log1p(floating_pop),
    ln_external_inflow_pop = safe_log1p(external_inflow_pop),
    ln_spend_total = safe_log1p(spend_total),
    ln_official_land_price = dplyr::if_else(
      is.finite(official_land_price) & official_land_price > 0,
      log(official_land_price),
      NA_real_
    ),
    ln_land_price_adjusted = dplyr::if_else(
      is.finite(land_price_adjusted) & land_price_adjusted > 0,
      log(land_price_adjusted),
      NA_real_
    ),
    store_density = dplyr::if_else(
      is.finite(adm_area_km2) & adm_area_km2 > 0,
      total_store_count / adm_area_km2,
      NA_real_
    ),
    ln_store_density = safe_log1p(store_density),
    resident_pop_density = dplyr::if_else(
      is.finite(adm_area_km2) & adm_area_km2 > 0,
      resident_pop / adm_area_km2,
      NA_real_
    ),
    ln_resident_pop_density = safe_log1p(resident_pop_density),
    floating_pop_density = dplyr::if_else(
      is.finite(adm_area_km2) & adm_area_km2 > 0,
      floating_pop / adm_area_km2,
      NA_real_
    ),
    ln_floating_pop_density = safe_log1p(floating_pop_density),
    total_household_commercial_density = dplyr::if_else(
      is.finite(adm_area_km2) & adm_area_km2 > 0,
      total_household_commercial / adm_area_km2,
      NA_real_
    ),
    sales_per_store = dplyr::if_else(
      is.finite(total_store_count) & total_store_count > 0,
      total_sales / total_store_count,
      NA_real_
    ),
    ln_sales_per_store = safe_log1p(sales_per_store),
    sales_per_capita = dplyr::if_else(
      is.finite(resident_pop) & resident_pop > 0,
      total_sales / resident_pop,
      NA_real_
    ),
    apartment_count = apartment_complex_count
  )

facility_cols <- intersect(
  c("facility_count", "hospital_count", "mall_count", "subway_station_count", "bus_stop_count"),
  names(panel_main_pre_vitality)
)
facility_obs <- if (length(facility_cols) == 0L) {
  rep(FALSE, nrow(panel_main_pre_vitality))
} else {
  Reduce("|", lapply(facility_cols, function(vn) has_value(panel_main_pre_vitality[[vn]])))
}
apartment_obs <- if ("apartment_household_count" %in% names(panel_main_pre_vitality)) {
  has_value(panel_main_pre_vitality$apartment_household_count)
} else if ("apartment_count" %in% names(panel_main_pre_vitality)) {
  has_value(panel_main_pre_vitality$apartment_count)
} else {
  rep(FALSE, nrow(panel_main_pre_vitality))
}

panel_main_pre_vitality$facility_available <- dplyr::coalesce(
  as.integer(panel_main_pre_vitality$facility_available),
  dplyr::if_else(facility_obs, 1L, 0L)
)
panel_main_pre_vitality$apartment_available <- dplyr::coalesce(
  as.integer(panel_main_pre_vitality$apartment_available),
  dplyr::if_else(apartment_obs, 1L, 0L)
)

panel_main_pre_vitality <- panel_main_pre_vitality |>
  dplyr::group_by(yq) |>
  dplyr::mutate(
    city_age60_sales_share = dplyr::if_else(
      sum(total_sales, na.rm = TRUE) > 0,
      sum(age60_sales_amount, na.rm = TRUE) / sum(total_sales, na.rm = TRUE),
      NA_real_
    ),
    age60_sales_lq = dplyr::if_else(
      is.finite(age60_sales_share) & is.finite(city_age60_sales_share) & city_age60_sales_share > 0,
      age60_sales_share / city_age60_sales_share,
      NA_real_
    )
  ) |>
  dplyr::ungroup()


#==============================================================================
# 4. Derive Canonical Lagged Model Variables
#==============================================================================

lag4_calendar <- build_lag_source_calendar(cfg$main_covariate_lag_quarters, "lag4")
lag4_values <- panel_main_pre_vitality |>
  dplyr::select(adm_cd, yq, quarter_index) |>
  dplyr::mutate(lag4_quarter_index = as.integer(.data$quarter_index) - cfg$main_covariate_lag_quarters) |>
  dplyr::left_join(lag4_calendar, by = "lag4_quarter_index") |>
  dplyr::left_join(
    registered_resident_lag_support |>
      dplyr::select(
        adm_cd,
        lag4_source_yq = yq,
        lag4_resident_pop = resident_pop,
        lag4_age60_resident_share = age60_resident_share
      ),
    by = c("adm_cd", "lag4_source_yq")
  ) |>
  dplyr::left_join(
    aux_lag_support |>
      dplyr::select(
        adm_cd,
        lag4_source_yq = yq,
        lag4_land_price_adjusted = land_price_adjusted,
        lag4_workplace_worker_pop = workplace_worker_pop,
        lag4_bus_stop_count_aux = bus_stop_count_aux,
        lag4_subway_station_count_aux = subway_station_count_aux
      ),
    by = c("adm_cd", "lag4_source_yq")
  ) |>
  dplyr::mutate(
    lag4_ln_resident_pop = safe_log1p(.data$lag4_resident_pop),
    lag4_ln_land_price_adjusted = dplyr::if_else(
      is.finite(.data$lag4_land_price_adjusted) & .data$lag4_land_price_adjusted > 0,
      log(.data$lag4_land_price_adjusted),
      NA_real_
    ),
    lag4_ln_workplace_worker_pop = safe_log1p(.data$lag4_workplace_worker_pop),
    lag4_transit_accessibility = {
      lag4_analysis_reference <- as.character(.data$yq) %in% get_analysis_yq_sequence()
      bus_z <- pooled_z(lag4_bus_stop_count_aux, reference = lag4_analysis_reference)
      subway_z <- pooled_z(lag4_subway_station_count_aux, reference = lag4_analysis_reference)
      dplyr::if_else(is.finite(bus_z) & is.finite(subway_z), (bus_z + subway_z) / 2, NA_real_)
    }
  ) |>
  dplyr::select(
    adm_cd, yq,
    lag4_age60_resident_share,
    lag4_ln_resident_pop,
    lag4_ln_land_price_adjusted,
    lag4_transit_accessibility,
    lag4_ln_workplace_worker_pop
  )

panel_main_pre_vitality <- panel_main_pre_vitality |>
  dplyr::left_join(lag4_values, by = c("adm_cd", "yq")) |>
  dplyr::arrange(adm_cd, quarter_index) |>
  dplyr::group_by(adm_cd) |>
  dplyr::mutate(
    lag2_age60_floating_share = dplyr::lag(
      .data$age60_floating_share,
      n = cfg$channel_mediator_lag_quarters
    )
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(adm_cd, year, quarter)

lag4_required_cols <- intersect(
  c(
    "lag4_age60_resident_share",
    "lag4_ln_resident_pop",
    "lag4_ln_land_price_adjusted",
    "lag4_transit_accessibility",
    "lag4_ln_workplace_worker_pop"
  ),
  names(panel_main_pre_vitality)
)
lag4_missing <- panel_main_pre_vitality |>
  dplyr::filter(dplyr::if_any(dplyr::all_of(lag4_required_cols), ~ !is.finite(.x)))
if (nrow(lag4_missing) > 0L) {
  stop(
    sprintf("[ERROR] missing 4-quarter lagged resident/control variables: rows=%d", nrow(lag4_missing)),
    call. = FALSE
  )
}

lag2_missing_after_warmup <- panel_main_pre_vitality |>
  dplyr::filter(
    .data$quarter_index > cfg$channel_mediator_lag_quarters,
    !is.finite(.data$lag2_age60_floating_share)
  )
if (nrow(lag2_missing_after_warmup) > 0L) {
  stop(
    sprintf("[ERROR] missing 2-quarter lagged floating-aging mediator after warm-up: rows=%d", nrow(lag2_missing_after_warmup)),
    call. = FALSE
  )
}


#==============================================================================
# 5. Validate Shared Temporal Contract
#==============================================================================

validate_panel_keys(panel_main_pre_vitality, c("adm_cd", "yq"))

forbidden_temporal_cols <- grep("(_l[0-9]+$|_f[0-9]+$|_yoy$)", names(panel_main_pre_vitality), value = TRUE)
if (length(forbidden_temporal_cols) > 0L) {
  stop(
    sprintf(
      "[ERROR] forbidden temporal-derived columns remain in quarterly panel: %s",
      paste(head(forbidden_temporal_cols, 12L), collapse = ", ")
    ),
    call. = FALSE
  )
}

unapproved_lag_cols <- setdiff(
  grep("^lag[0-9]+_", names(panel_main_pre_vitality), value = TRUE),
  value_or(cfg$approved_temporal_lag_cols, character())
)
if (length(unapproved_lag_cols) > 0L) {
  stop(
    sprintf(
      "[ERROR] shared quarterly panel contains unregistered lag columns: %s",
      paste(head(unapproved_lag_cols, 12L), collapse = ", ")
    ),
    call. = FALSE
  )
}


#==============================================================================
# 6. Coverage QC and Structural Count QC
#==============================================================================

quarter_base_core_vars <- intersect(
  c(
    "age60_floating_share", "age60_sales_share",
    "total_household_commercial",
    "spend_total", "sales_count", "facility_count", "apartment_count",
    "hospital_count", "mall_count", "bus_stop_count", "subway_station_count"
  ),
  names(panel_main_pre_vitality)
)
registered_resident_core_vars <- intersect(
  c(
    "resident_pop", "age60_resident_pop", "age60_resident_share",
    "age20_resident_pop", "age30_resident_pop", "age40_resident_pop", "age50_resident_pop",
    "age60_64_resident_pop", "age65_74_resident_pop", "age75plus_resident_pop", "age65plus_resident_pop",
    "age20_resident_share", "age30_resident_share", "age40_resident_share", "age50_resident_share",
    "age60plus_resident_share", "age60_64_resident_share", "age65_74_resident_share",
    "age75plus_resident_share", "age65plus_resident_share",
    "registered_month_n", "age_group_total_abs_diff_max"
  ),
  names(panel_main_pre_vitality)
)
aux_core_vars <- intersect(
  c(
    "official_land_price", "ln_official_land_price",
    "land_price_lpi_factor", "land_price_adjusted", "ln_land_price_adjusted",
    "land_price_lpi_source_bjd_n", "land_price_lpi_weight_coverage",
    "workplace_worker_pop", "ln_workplace_worker_pop", "workplace_worker_source_year",
    "bus_stop_count_aux", "subway_station_count_aux", "transit_accessibility",
    "apartment_complex_count_kapt", "apartment_building_count", "apartment_household_count",
    "ln_apartment_household_count",
    "hospital_count_aux_core", "mall_count_aux_core",
    medical_detail_cols, mall_detail_cols, senior_detail_cols,
    "park_area", "senior_facility_count", walk_env_cols,
    "road_length_km", "sidewalk_length_km"
  ),
  names(panel_main_pre_vitality)
)
lagged_model_core_vars <- intersect(
  value_or(cfg$approved_temporal_lag_cols, character()),
  names(panel_main_pre_vitality)
)
living_pop_core_vars <- intersect(
  c(
    "inner_external_inflow_pop", "metro_external_inflow_pop", "external_inflow_pop",
    "inner_n_slots", "metro_n_slots", "inner_n_months", "metro_n_months",
    "ln_external_inflow_pop"
  ),
  names(panel_main_pre_vitality)
)
survival_core_vars <- intersect(
  c(
    "survival_1y", "survival_1y_survived", "survival_1y_cohort",
    "survival_3y", "survival_3y_survived", "survival_3y_cohort",
    "survival_5y", "survival_5y_survived", "survival_5y_cohort"
  ),
  names(panel_main_pre_vitality)
)

join_cov <- dplyr::bind_rows(
  summarize_join_coverage(panel_main_pre_vitality, quarter_base_core_vars, "quarter_base"),
  summarize_join_coverage(panel_main_pre_vitality, registered_resident_core_vars, "registered_resident_population"),
  summarize_join_coverage(panel_main_pre_vitality, aux_core_vars, "aux"),
  summarize_join_coverage(panel_main_pre_vitality, lagged_model_core_vars, "lagged_model_vars"),
  summarize_join_coverage(panel_main_pre_vitality, living_pop_core_vars, "living_population_external_inflow"),
  summarize_join_coverage(panel_main_pre_vitality, survival_core_vars, "golmok_survival_rate")
) |>
  dplyr::arrange(source, variable, yq)

join_cov_path <- file.path(cfg$dir_logs, "panel_join_coverage_qc.csv")
write_csv_safe(join_cov, join_cov_path)

count_vars <- intersect(
  c(
    "resident_pop", "total_household_commercial", "total_store_count", "floating_pop", "external_inflow_pop",
    "workplace_worker_pop",
    "apartment_complex_count_kapt", "apartment_building_count", "apartment_household_count"
  ),
  names(panel_main_pre_vitality)
)
if (length(count_vars) > 0) {
  count_flags <- panel_main_pre_vitality |>
    dplyr::select(adm_cd, yq, dplyr::all_of(count_vars)) |>
    tidyr::pivot_longer(cols = dplyr::all_of(count_vars), names_to = "variable", values_to = "value") |>
    dplyr::mutate(
      flag_negative = is.finite(value) & value < 0,
      flag_tiny_positive = is.finite(value) & value > 0 & value < 1
    ) |>
    dplyr::filter(flag_negative | flag_tiny_positive)
} else {
  count_flags <- tibble::tibble(
    adm_cd = character(0),
    yq = character(0),
    variable = character(0),
    value = numeric(0),
    flag_negative = logical(0),
    flag_tiny_positive = logical(0)
  )
}

count_flag_path <- file.path(cfg$dir_logs, "panel_structural_count_flags.csv")
write_csv_safe(count_flags, count_flag_path)

if (any(count_flags$flag_negative, na.rm = TRUE)) {
  stop("[ERROR] negative values detected in structural count variables", call. = FALSE)
}


#==============================================================================
# 7. Persist Outputs
#==============================================================================

write_parquet_safe(panel_merged_base, cfg$paths$panel_merged_base)
write_parquet_safe(panel_main_pre_vitality, cfg$paths$panel_main_pre_vitality)
if (file.exists(cfg$paths$panel_main)) unlink(cfg$paths$panel_main)
unlink(cfg$obsolete_panel_paths[file.exists(cfg$obsolete_panel_paths)])
write_csv_safe(summarize_missing(panel_main_pre_vitality), cfg$logs$missing_data)

append_log(cfg$logs$data_qc, sprintf("- Panel merged base rows: %d", nrow(panel_merged_base)))
append_log(
  cfg$logs$data_qc,
  sprintf("- Pre-vitality quarterly panel published: %s (rows=%d)", basename(cfg$paths$panel_main_pre_vitality), nrow(panel_main_pre_vitality))
)
append_log(cfg$logs$data_qc, sprintf("- Panel join coverage QC: %s (rows=%d)", basename(join_cov_path), nrow(join_cov)))
if (file.exists(quarter_aggregation_qc_path)) {
  append_log(
    cfg$logs$data_qc,
    sprintf("- Quarterly aggregation QC carried forward: %s", basename(quarter_aggregation_qc_path))
  )
}
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Panel structural count flags: %s (rows=%d, tiny_positive=%d)",
    basename(count_flag_path),
    nrow(count_flags),
    sum(count_flags$flag_tiny_positive, na.rm = TRUE)
  )
)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Final panel removed after pre-vitality publish=%s; obsolete panel files removed=%d",
    !file.exists(cfg$paths$panel_main),
    sum(!file.exists(cfg$obsolete_panel_paths))
  )
)
