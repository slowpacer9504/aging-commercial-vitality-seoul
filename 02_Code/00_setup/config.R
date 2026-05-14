 #==============================================================================
# Script    : config.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Define shared paths, analysis constants, and runtime toggles for
#             the full preprocessing-modeling pipeline.
# Author    : Codex
# Created   : 2026-02-28
# Type      : config
# Inputs    : Project root resolved by here::here()
# Outputs   : cfg environment
# DependsOn : here
#==============================================================================

#==============================================================================
# 0. Configuration Environment
#==============================================================================

# Keep all global settings in a dedicated environment so that sourced scripts
# share one contract without polluting the global workspace.
# 이 파일은 프로젝트 전체 스크립트가 공통으로 참조하는 설정 계약이다.
# 경로, 핵심 상수, 입력 파일명, 산출물 파일명, QC 로그 경로를 한 곳에
# 모아두면, 스크립트마다 같은 값을 따로 적지 않아도 되고 구조 drift도
# 줄일 수 있다.
cfg <- new.env(parent = emptyenv())

# 아래 환경변수들은 "코드를 수정하지 않고 실행 모드만 바꿀 수 있는"
# 최소 런타임 스위치다. 다만 값이 비정상적이면 즉시 기본값으로 되돌린다.
cfg$output_tag <- trimws(Sys.getenv("CFG_OUTPUT_TAG", unset = ""))

cfg$tag_path <- function(path) {
  # 실험용 실행에서 파일명을 통째로 바꾸지 않고 suffix만 붙여
  # 버전을 분기하고 싶을 때 사용하는 helper다.
  # 디렉터리는 유지하고 basename만 바꾸는 이유는, downstream helper와
  # review inventory가 기존 폴더 구조를 그대로 인식하게 하기 위해서다.
  if (!nzchar(cfg$output_tag)) return(path)

  ext <- tools::file_ext(path)
  stem <- if (nzchar(ext)) {
    sub(paste0("[.]", ext, "$"), "", basename(path))
  } else {
    basename(path)
  }
  tagged_name <- if (nzchar(ext)) {
    sprintf("%s_%s.%s", stem, cfg$output_tag, ext)
  } else {
    sprintf("%s_%s", stem, cfg$output_tag)
  }

  file.path(dirname(path), tagged_name)
}


#==============================================================================
# 1. Project Paths
#==============================================================================

# 분석 프로젝트의 디렉터리 체계를 코드로 고정한다. 이후 스크립트는
# raw/processed/output/docs의 위치를 이 registry를 통해서만 본다.
cfg$project_root <- normalizePath(here::here(), winslash = "/", mustWork = TRUE)

cfg$dir_raw <- file.path(cfg$project_root, "01_Data", "01_Raw_Data")
cfg$dir_boundary <- file.path(cfg$project_root, "01_Data", "02_Boundary")
cfg$dir_processed <- file.path(cfg$project_root, "01_Data", "03_Processed_Data")
cfg$dir_intermediate <- file.path(cfg$dir_processed, "01_Intermediate")
cfg$dir_analysis <- file.path(cfg$dir_processed, "02_Analysis_Ready")
cfg$dir_panel <- file.path(cfg$dir_processed, "03_Panel")

cfg$dir_output <- file.path(cfg$project_root, "03_Output")
cfg$dir_tables <- file.path(cfg$dir_output, "01_Tables")
cfg$dir_figures <- file.path(cfg$dir_output, "02_Figures")
cfg$dir_maps <- file.path(cfg$dir_output, "03_Maps")
cfg$dir_logs <- file.path(cfg$dir_output, "04_Logs")
cfg$dir_report <- file.path(cfg$dir_output, "05_report")

cfg$dir_docs <- file.path(cfg$project_root, "04_Docs")
cfg$dir_design <- file.path(cfg$dir_docs, "01_Design")
cfg$dir_codebook <- file.path(cfg$dir_docs, "02_Codebook")
cfg$dir_doc_logs <- file.path(cfg$dir_docs, "03_Log")
cfg$senior_manual_fix_csv <- file.path(cfg$project_root, "02_Code", "00_setup", "senior_geocode_manual_fix.csv")

resolve_numbered_raw_dir <- function(prefix, fallback_name) {
  candidates <- list.dirs(cfg$dir_raw, recursive = FALSE, full.names = TRUE)
  hits <- candidates[grepl(sprintf("^%s_", prefix), basename(candidates))]
  if (length(hits) > 0L) return(hits[[1L]])
  file.path(cfg$dir_raw, fallback_name)
}

cfg$dir_living_population_inner <- resolve_numbered_raw_dir(
  "10",
  "10_서울생활인구 관내이동"
)
cfg$dir_living_population_metro <- resolve_numbered_raw_dir(
  "11",
  "11_서울생활인구 대도시권 내외국인"
)
cfg$dir_registered_resident_population <- resolve_numbered_raw_dir(
  "13",
  "13_주민등록인구현황_행정구역(읍면동)별:5세별 주민등록인구(2019~2025, 월)"
)
cfg$dir_golmok_survival_json <- file.path(cfg$dir_intermediate, "golmok_survival_json")


#==============================================================================
# 2. Core Analysis Constants
#==============================================================================

# These values encode the non-negotiable design decisions from the research
# plan, procedure, and codebook so that downstream scripts stay aligned.
# 여기 값들은 사실상 "연구 설계의 코드 표현"이다. 예를 들어 기준 경계,
# 공간가중치 후보, ESDA 난수 시드 같은 결정은 스크립트마다 달라지면
# 안 되므로 중앙화한다.
cfg$target_crs <- 5179L
cfg$boundary_year <- 2020L
cfg$default_w <- "queen"
cfg$alt_w <- c("rook", "knn6", "knn8")
cfg$esda_seed <- 20260317L
cfg$esda_global_moran_nsim <- 999L
cfg$esda_global_moran_p_value <- "permutation_two_sided_abs"
cfg$short_start <- 2019L
cfg$short_end <- 2025L
# Raw quarterly staging still needs the terminal quarter to validate source
# coverage before annual aggregation. This does not change the active annual
# panel contract, which publishes `adm_cd-year` only.
cfg$short_end_quarter <- 4L
cfg$covid_years <- 2020:2022
cfg$covid_start_year <- min(cfg$covid_years)
cfg$covid_end_year <- max(cfg$covid_years)
cfg$spdm_min_periods <- length(seq.int(cfg$short_start, cfg$short_end))
cfg$living_pop_hours <- trimws(Sys.getenv("LIVING_POP_HOURS", unset = "0-23"))
cfg$living_pop_sample_months <- trimws(Sys.getenv("LIVING_POP_SAMPLE_MONTHS", unset = ""))
cfg$run_living_pop_inflow <- tolower(trimws(Sys.getenv("RUN_LIVING_POP_INFLOW", unset = "false"))) %in% c("1", "true", "yes")
cfg$living_pop_force_rebuild <- tolower(trimws(Sys.getenv("LIVING_POP_FORCE_REBUILD", unset = "false"))) %in% c("1", "true", "yes")
cfg$living_pop_suppressed_value <- suppressWarnings(as.numeric(Sys.getenv("LIVING_POP_SUPPRESSED_VALUE", unset = "0")))
if (!is.finite(cfg$living_pop_suppressed_value)) cfg$living_pop_suppressed_value <- 0
cfg$living_pop_encoding <- trimws(Sys.getenv("LIVING_POP_ENCODING", unset = "UTF-8"))
cfg$golmok_survival_endpoint <- "https://golmok.seoul.go.kr/region/selectSurvivalRate.json"
cfg$golmok_survival_base_years <- c(2019L, 2022L, 2025L)
cfg$golmok_survival_quarter <- 4L
cfg$golmok_survival_study_years <- cfg$short_start:cfg$short_end
cfg$golmok_survival_force_rebuild <- tolower(trimws(Sys.getenv("GOLMOK_SURVIVAL_FORCE_REBUILD", unset = "false"))) %in% c("1", "true", "yes")
cfg$golmok_survival_cookie <- trimws(Sys.getenv("GOLMOK_COOKIE", unset = ""))

# Main short-run aging variables are registered here as the shared variable
# family. Individual model scripts may use a subset of this family as their
# canonical main exposure contract.
# 단기 영향분석의 age60 변수군은 여기서 공통 registry로 관리한다.
# 다만 TWFE/SPDM 메인 모형은 이 family의 부분집합만 canonical exposure로
# 사용할 수 있다.
cfg$impact_aging_vars <- c("age60_resident_share", "age60_floating_share", "age60_sales_share")
cfg$resident_age_support_vars <- c(
  "age20_resident_share", "age30_resident_share", "age40_resident_share",
  "age50_resident_share", "age60plus_resident_share",
  "age60_64_resident_pop", "age65_74_resident_pop", "age75plus_resident_pop", "age65plus_resident_pop",
  "age60_64_resident_share", "age65_74_resident_share", "age75plus_resident_share", "age65plus_resident_share"
)
cfg$twfe_main_exposure_vars <- c("age60_resident_share")
cfg$twfe_channel_vars <- c("age60_floating_share")
cfg$twfe_main_control_cols <- c(
  "ln_resident_pop",
  "ln_apartment_household_count", "ln_official_land_price", "transit_accessibility",
  "hospital_count_aux_core", "mall_count_aux_core"
)
cfg$floating_exposure_overlap_outcomes <- c("vitality_sub_social", "ln_floating_pop")
cfg$primary_outcomes <- c(
  "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability"
)
cfg$vitality_supplementary_outcomes <- c("vitality_index_base")
cfg$vitality_channel_path_outcomes <- c("vitality_index_base")
cfg$outcome_registry_channel_path_outcomes <- setdiff(
  cfg$vitality_channel_path_outcomes,
  c(cfg$primary_outcomes, cfg$vitality_supplementary_outcomes)
)
cfg$vitality_component_appendix_outcomes <- c(
  "ln_sales_count", "ln_total_sales", "ln_total_store_count",
  "sales_time_entropy", "sales_quarter_stability", "ln_floating_pop",
  "ln_external_inflow_pop",
  "floating_time_entropy", "floating_quarter_stability",
  "diversity_index", "survival_3y", "operating_months_rel_seoul"
)
cfg$vitality_robustness_outcomes <- c("vitality_index_entropy", "vitality_index_pca")
cfg$twfe_main_outcomes <- c(cfg$primary_outcomes, cfg$vitality_supplementary_outcomes)
cfg$twfe_channel_outcomes <- cfg$twfe_main_outcomes
cfg$twfe_interaction_outcomes <- cfg$twfe_main_outcomes
cfg$twfe_age_mix_outcomes <- cfg$twfe_main_outcomes
cfg$esda_main_outcomes <- c(cfg$primary_outcomes, cfg$vitality_supplementary_outcomes)
cfg$esda_main_global_moran_aging_vars <- c("age60_resident_share", "age60_floating_share")
cfg$esda_main_global_moran_vars <- c(cfg$esda_main_global_moran_aging_vars, cfg$esda_main_outcomes)
cfg$esda_main_univariate_lisa_vars <- cfg$esda_main_global_moran_vars
cfg$esda_main_bivariate_aging_vars <- cfg$esda_main_global_moran_aging_vars
cfg$esda_main_bivariate_outcomes <- cfg$esda_main_outcomes
cfg$esda_main_ehsa_vars <- c(cfg$esda_main_global_moran_aging_vars, cfg$esda_main_outcomes)
cfg$esda_ehsa_min_years <- 4L
cfg$outcome_registry <- data.frame(
  outcome = c(
    cfg$primary_outcomes,
    cfg$vitality_supplementary_outcomes,
    cfg$outcome_registry_channel_path_outcomes,
    cfg$vitality_component_appendix_outcomes,
    cfg$vitality_robustness_outcomes
  ),
  outcome_group = c(
    rep("primary", length(cfg$primary_outcomes)),
    rep("supplementary_vitality", length(cfg$vitality_supplementary_outcomes)),
    rep("canonical_channel_path", length(cfg$outcome_registry_channel_path_outcomes)),
    rep("appendix_component", length(cfg$vitality_component_appendix_outcomes)),
    rep("supplementary_vitality_robustness", length(cfg$vitality_robustness_outcomes))
  ),
  outcome_order = c(
    seq_along(cfg$primary_outcomes),
    length(cfg$primary_outcomes) + seq_along(cfg$vitality_supplementary_outcomes),
    length(cfg$primary_outcomes) + length(cfg$vitality_supplementary_outcomes) +
      seq_along(cfg$outcome_registry_channel_path_outcomes),
    length(cfg$primary_outcomes) + length(cfg$vitality_supplementary_outcomes) +
      length(cfg$outcome_registry_channel_path_outcomes) + seq_along(cfg$vitality_component_appendix_outcomes),
    length(cfg$primary_outcomes) + length(cfg$vitality_supplementary_outcomes) +
      length(cfg$outcome_registry_channel_path_outcomes) +
      length(cfg$vitality_component_appendix_outcomes) + seq_along(cfg$vitality_robustness_outcomes)
  ),
  stringsAsFactors = FALSE
)
cfg$spdm_main_outcomes <- cfg$twfe_main_outcomes
cfg$esda_representative_vitality_outcome <- "vitality_index_base"
cfg$spdm_channel_outcomes <- c(
  "vitality_sub_economic", "vitality_sub_temporal", "vitality_sub_stability",
  cfg$vitality_channel_path_outcomes
)
cfg$spdm_interaction_outcomes <- cfg$spdm_main_outcomes
cfg$spdm_age_mix_outcomes <- cfg$spdm_main_outcomes
cfg$spdm_sector_share_outcomes <- c(
  "sales_share_cs1", "sales_share_cs2", "sales_share_cs3",
  "store_share_cs1", "store_share_cs2", "store_share_cs3"
)
cfg$robustness_outcomes <- c(
  cfg$twfe_main_outcomes,
  cfg$vitality_component_appendix_outcomes,
  cfg$vitality_robustness_outcomes
)
cfg$gtwr_main_outcomes <- cfg$twfe_main_outcomes
cfg$gwr_delta_outcomes <- cfg$twfe_main_outcomes
cfg$gtwr_sector_share_outcomes <- c(
  "sales_share_cs1", "sales_share_cs2", "sales_share_cs3",
  "store_share_cs1", "store_share_cs2", "store_share_cs3"
)
cfg$spdm_main_exposure_vars <- c("age60_resident_share")
cfg$spdm_channel_vars <- c("age60_floating_share")
cfg$spdm_main_control_cols <- c(
  "ln_resident_pop",
  "ln_apartment_household_count", "ln_official_land_price", "transit_accessibility",
  "hospital_count_aux_core", "mall_count_aux_core"
)
cfg$gtwr_main_exposure_vars <- c("age60_resident_share")
cfg$gtwr_floating_exposure_vars <- c("age60_floating_share")
cfg$gwr_delta_main_exposure_vars <- cfg$gtwr_main_exposure_vars
cfg$gwr_delta_floating_exposure_vars <- cfg$gtwr_floating_exposure_vars
cfg$gtwr_age_band_domains <- c("resident", "floating")
cfg$gtwr_age_band_labels <- c("age20", "age30", "age40", "age50")

# GTWR uses a more parsimonious default control contract than TWFE/SPDM
# because local design matrices are much more sensitive to collinearity.
# Set GTWR_CONTROL_SET=extended to use the larger pool. In the extended pool,
# bus and subway counts enter through the standardized transit-accessibility composite.
cfg$gtwr_lean_control_cols <- c(
  "ln_resident_pop", "ln_official_land_price"
)
cfg$gtwr_extended_control_cols <- c(
  "ln_resident_pop",
  "ln_apartment_household_count", "ln_official_land_price", "transit_accessibility",
  "hospital_count_aux_core", "mall_count_aux_core"
)
cfg$gtwr_control_set <- tolower(trimws(Sys.getenv("GTWR_CONTROL_SET", unset = "lean")))
if (!cfg$gtwr_control_set %in% c("lean", "extended")) cfg$gtwr_control_set <- "lean"
cfg$gwr_delta_control_cols <- cfg$gtwr_lean_control_cols
cfg$gtwr_available_control_cols <- unique(c(cfg$gtwr_lean_control_cols, cfg$gtwr_extended_control_cols))
cfg$gtwr_main_control_cols <- switch(
  cfg$gtwr_control_set,
  lean = cfg$gtwr_lean_control_cols,
  extended = cfg$gtwr_extended_control_cols
)
cfg$run_twfe_age_mix_sidecar <- tolower(trimws(Sys.getenv("RUN_TWFE_AGE_MIX_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_spdm_age_mix_sidecar <- tolower(trimws(Sys.getenv("RUN_SPDM_AGE_MIX_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_spdm_sector_share_sidecar <- tolower(trimws(Sys.getenv("RUN_SPDM_SECTOR_SHARE_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_gtwr_floating_sidecar <- tolower(trimws(Sys.getenv("RUN_GTWR_FLOATING_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_gtwr_age_band_sidecar <- tolower(trimws(Sys.getenv("RUN_GTWR_AGE_BAND_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_gtwr_sector_share_sidecar <- tolower(trimws(Sys.getenv("RUN_GTWR_SECTOR_SHARE_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_gwr_delta <- tolower(trimws(Sys.getenv("RUN_GWR_DELTA", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_gwr_delta_floating_sidecar <- tolower(trimws(Sys.getenv("RUN_GWR_DELTA_FLOATING_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$gwr_delta_window_years <- 3L
cfg$gwr_delta_windows_n <- cfg$gwr_delta_window_years
cfg$gwr_delta_kernel <- "bisquare"
cfg$gwr_delta_adaptive <- TRUE
cfg$gwr_delta_parallel_method <- "omp"
cfg$gwr_delta_parallel_arg <- NA_integer_
cfg$spdm_impact_sim_R <- 1000L
cfg$spdm_channel_impact_sim_R <- suppressWarnings(as.integer(Sys.getenv("SPDM_CHANNEL_IMPACT_SIM_R", unset = "1000")))
if (!is.finite(cfg$spdm_channel_impact_sim_R) || cfg$spdm_channel_impact_sim_R < 1L) cfg$spdm_channel_impact_sim_R <- 1000L
cfg$spdm_channel_impact_cores <- suppressWarnings(as.integer(Sys.getenv("SPDM_CHANNEL_IMPACT_CORES", unset = "4")))
if (!is.finite(cfg$spdm_channel_impact_cores) || cfg$spdm_channel_impact_cores < 1L) cfg$spdm_channel_impact_cores <- 1L
cfg$spdm_coef_se_method <- "model_based_asymptotic_ml_vcov"
cfg$spdm_spatial_param_se_method <- "model_based_asymptotic_ml_vcov"
cfg$spdm_impact_se_method <- "simulation_from_model_based_ml_vcov"
cfg$run_spdm_channel_bootstrap <- tolower(trimws(Sys.getenv("RUN_SPDM_CHANNEL_BOOTSTRAP", unset = "true"))) %in% c("1", "true", "yes")
cfg$spdm_channel_bootstrap_R <- suppressWarnings(as.integer(Sys.getenv("SPDM_CHANNEL_BOOTSTRAP_R", unset = "1000")))
if (!is.finite(cfg$spdm_channel_bootstrap_R) || cfg$spdm_channel_bootstrap_R < 1L) cfg$spdm_channel_bootstrap_R <- 1000L
cfg$spdm_channel_bootstrap_cores <- suppressWarnings(as.integer(Sys.getenv("SPDM_CHANNEL_BOOTSTRAP_CORES", unset = "4")))
if (!is.finite(cfg$spdm_channel_bootstrap_cores) || cfg$spdm_channel_bootstrap_cores < 1L) cfg$spdm_channel_bootstrap_cores <- 1L
cfg$spdm_channel_bootstrap_seed <- suppressWarnings(as.integer(Sys.getenv("SPDM_CHANNEL_BOOTSTRAP_SEED", unset = as.character(cfg$esda_seed))))
if (!is.finite(cfg$spdm_channel_bootstrap_seed)) cfg$spdm_channel_bootstrap_seed <- cfg$esda_seed
cfg$spdm_channel_bootstrap_method <- Sys.getenv("SPDM_CHANNEL_BOOTSTRAP_METHOD", unset = "adm_cd_wild_residual")
# Main true-SDM/SPDM impacts are computed with the explicit matrix formula
# S = (I - rho W)^(-1)(beta I + theta W). Keep this label aligned with the
# `sim_method` written to SPDM main outputs, so readers do not confuse it with
# the SAR-style multiplier fallback used by legacy/builtin spatial families.
cfg$spdm_impact_sim_method <- "manual_true_sdm_matrix"

# Builtin/legacy spatial impact fallback for non-manual SDM sidecars. Several
# appendix scripts still read the historical name, so retain it as a
# backwards-compatible alias rather than using it for the main true-SDM label.
cfg$spdm_builtin_impact_sim_type <- "mult"
cfg$spdm_impact_sim_type <- cfg$spdm_builtin_impact_sim_type
cfg$spdm_impact_empirical <- FALSE

# Active annual panel joins auxiliary variables directly on `adm_cd-year`.
# 더 이상 연 단위 보조변수를 분기 패널에 step expansion하지 않는다.
cfg$annual_join_policy <- "direct_adm_cd_year_join_no_quarter_expansion"
cfg$annual_asof_policy <- cfg$annual_join_policy

twfe_control_cols <- c(
  "ln_resident_pop",
  "resident_pop",
  "resident_pop_density", "total_household_commercial_density",
  "ln_spend_total", "facility_count", "ln_apartment_household_count", "ln_official_land_price",
  "transit_accessibility", "hospital_count_aux_core", "mall_count_aux_core",
  "avg_slope_degree", "intersection_density", "sidewalk_length_km"
)

cfg$panel_main_view_specs <- list(
  # 지금은 method별 parquet를 따로 저장하지 않는다. 대신 최종
  # `panel_main.parquet` 하나에서 분석 목적별로 필요한 열만 읽는다.
  # 이 list가 그 목적별 최소 열 목록이다.
  # 즉 여기 정의가 바뀌면 ESDA/TWFE/SPDM/GTWR 입력 계약도 함께 바뀌므로,
  # 코드북과 QC가 이 값을 같이 참조해야 한다.
  esda = unique(c(
    "adm_cd", "year",
    cfg$impact_aging_vars,
    cfg$esda_main_global_moran_aging_vars,
    cfg$resident_age_support_vars,
    "age60_resident_pop", "age60_floating_pop", "age60_sales_amount",
    "ln_age60_resident_pop", "ln_age60_floating_pop", "ln_age60_sales_amount", "age60_sales_lq",
    cfg$esda_main_outcomes,
    cfg$esda_representative_vitality_outcome
  )),
  twfe = unique(c(
    "adm_cd", "year", "covid_period",
    cfg$twfe_main_outcomes,
    cfg$vitality_component_appendix_outcomes,
    "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability",
    cfg$vitality_robustness_outcomes,
    cfg$impact_aging_vars, cfg$resident_age_support_vars, twfe_control_cols
  )),
  spdm = unique(c(
    "adm_cd", "year", "covid_period",
    cfg$spdm_main_outcomes,
    cfg$spdm_main_exposure_vars,
    cfg$resident_age_support_vars,
    cfg$spdm_main_control_cols
  )),
  gtwr = unique(c(
    "adm_cd", "year", "covid_period",
    cfg$gtwr_main_outcomes,
    cfg$gtwr_main_exposure_vars,
    cfg$gtwr_floating_exposure_vars,
    cfg$resident_age_support_vars,
    cfg$gtwr_main_control_cols
  )),
  gwr_delta = unique(c(
    "adm_cd", "year", "covid_period",
    cfg$gwr_delta_outcomes,
    cfg$gwr_delta_main_exposure_vars,
    cfg$gwr_delta_floating_exposure_vars,
    cfg$gwr_delta_control_cols
  ))
)


#==============================================================================
# 3. Raw Source Contracts
#==============================================================================

# Non-senior auxiliary inputs are pinned to canonical basenames so sidecar
# files or alternate dumps cannot silently change the preprocessing inputs.
# raw 폴더 안에는 sidecar 파일, 설명용 파일, 구버전 파일이 섞일 수
# 있다. broad scan으로 "첫 번째 csv"를 잡으면 입력이 조용히 바뀔 수
# 있으므로, auxiliary raw source는 basename 계약으로 고정한다.
cfg$aux_source_contracts <- list(
  bus_stop = list(
    dir_prefix = "07",
    recursive = FALSE,
    expected_basenames = c(
      "서울시 버스정류소 좌표 데이터(2019.07.10).xlsx",
      "서울시 버스정류소 좌표 데이터(2020.12.31).xlsx",
      "2021년각월1일기준_서울시버스정류소위치정보.csv",
      "2022년각월1일기준_서울시버스정류소위치정보.csv",
      "2023년각월1일기준_서울시버스정류소위치정보.csv",
      "2024년1~4월1일기준_서울시버스정류소위치정보.csv",
      "서울시버스정류소위치정보(20250204).xlsx"
    )
  ),
  subway_station = list(
    dir_prefix = "09",
    recursive = FALSE,
    expected_basenames = c("서울시 역사마스터 정보_EPSG4326.csv")
  ),
  medical = list(
    dir_prefix = "08",
    recursive = FALSE,
    expected_basenames = c(
      "서울시 병원 인허가 정보.csv",
      "서울시 의원 인허가 정보.csv"
    )
  ),
  mall = list(
    dir_prefix = "06",
    recursive = FALSE,
    expected_basenames = c("서울시 대규모점포 인허가 정보.csv")
  ),
  apartment_registry = list(
    dir_prefix = "12",
    recursive = FALSE,
    expected_basenames = c("서울시 공동주택 아파트 정보.csv")
  ),
  walk_network = list(
    dir_prefix = "05",
    recursive = TRUE,
    expected_basenames = c("서울시 자치구별 도보 네트워크 공간정보.csv")
  ),
  road = list(
    search_root = cfg$dir_raw,
    recursive = TRUE,
    expected_basenames = c("TL_SPRD_MANAGE_11_202509.shp")
  ),
  sidewalk = list(
    search_root = cfg$dir_raw,
    recursive = TRUE,
    expected_basenames = c("N3L_A0033320.shp")
  )
)


#==============================================================================
# 4. Optional High-Cost Modes
#==============================================================================

# GTWR is an opt-in local sidecar. The default main specification fixes the
# adaptive spatiotemporal bandwidth at 120 neighbors to avoid singular local
# design matrices in the extended control set while preserving local variation;
# bw.gtwr() search remains available only when explicitly requested through
# GTWR_BANDWIDTH_STRATEGY.
cfg$run_gtwr_main_sidecar <- tolower(trimws(Sys.getenv("RUN_GTWR_MAIN_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_gtwr <- cfg$run_gtwr_main_sidecar
cfg$gtwr_control_min_obs <- 500L
cfg$gtwr_control_min_units <- 30L
cfg$gtwr_control_min_sample_retention <- 0.95
cfg$gtwr_control_selection_strategy <- "fixed_control_set"
cfg$gtwr_control_zero_share_warn <- 0.80
cfg$gtwr_parallel_specs <- suppressWarnings(as.integer(Sys.getenv("GTWR_PARALLEL_SPECS", unset = "5")))
if (!is.finite(cfg$gtwr_parallel_specs) || cfg$gtwr_parallel_specs < 1L) cfg$gtwr_parallel_specs <- 1L
cfg$gtwr_resume_specs <- tolower(trimws(Sys.getenv("GTWR_RESUME_SPECS", unset = "true"))) %in% c("1", "true", "yes")
cfg$gtwr_refresh_spec_cache <- tolower(trimws(Sys.getenv("GTWR_REFRESH_SPEC_CACHE", unset = "false"))) %in% c("1", "true", "yes")
cfg$gtwr_reuse_st_dmat <- tolower(trimws(Sys.getenv("GTWR_REUSE_ST_DMAT", unset = "false"))) %in% c("1", "true", "yes")
cfg$gtwr_use_frozen_spec <- tolower(trimws(Sys.getenv("GTWR_USE_FROZEN_SPEC", unset = "true"))) %in% c("1", "true", "yes")
cfg$gtwr_refresh_frozen_spec <- tolower(trimws(Sys.getenv("GTWR_REFRESH_FROZEN_SPEC", unset = "false"))) %in% c("1", "true", "yes")
cfg$gtwr_kernel <- trimws(Sys.getenv("GTWR_KERNEL", unset = "bisquare"))
if (!cfg$gtwr_kernel %in% c("bisquare", "gaussian", "exponential", "tricube", "boxcar")) cfg$gtwr_kernel <- "bisquare"
cfg$gtwr_adaptive <- tolower(trimws(Sys.getenv("GTWR_ADAPTIVE", unset = "true"))) %in% c("1", "true", "yes")
cfg$gtwr_bandwidth_strategy <- tolower(trimws(Sys.getenv("GTWR_BANDWIDTH_STRATEGY", unset = "fixed")))
if (!cfg$gtwr_bandwidth_strategy %in% c("full_panel_bw_gtwr", "anchor_year_bw_gtwr", "fixed")) cfg$gtwr_bandwidth_strategy <- "fixed"
cfg$gtwr_bw_anchor_year <- suppressWarnings(as.integer(Sys.getenv("GTWR_BW_ANCHOR_YEAR", unset = as.character(cfg$short_start))))
if (!is.finite(cfg$gtwr_bw_anchor_year)) cfg$gtwr_bw_anchor_year <- cfg$short_start
cfg$gtwr_bw_approach <- trimws(Sys.getenv("GTWR_BW_APPROACH", unset = "CV"))
if (!cfg$gtwr_bw_approach %in% c("CV", "cv", "AIC", "aic", "AICc")) cfg$gtwr_bw_approach <- "CV"
cfg$gtwr_refresh_bw_cache <- tolower(trimws(Sys.getenv("GTWR_REFRESH_BW_CACHE", unset = "false"))) %in% c("1", "true", "yes")
cfg$gtwr_st_bw <- suppressWarnings(as.integer(Sys.getenv("GTWR_ST_BW", unset = "120")))
if (!is.finite(cfg$gtwr_st_bw) || cfg$gtwr_st_bw < 30L) cfg$gtwr_st_bw <- 120L
cfg$gtwr_lamda <- suppressWarnings(as.numeric(Sys.getenv("GTWR_LAMDA", unset = "0.05")))
if (!is.finite(cfg$gtwr_lamda) || cfg$gtwr_lamda < 0) cfg$gtwr_lamda <- 0.05
cfg$gtwr_ksi <- suppressWarnings(as.numeric(Sys.getenv("GTWR_KSI", unset = "0")))
if (!is.finite(cfg$gtwr_ksi) || cfg$gtwr_ksi < 0) cfg$gtwr_ksi <- 0
cfg$gtwr_local_cn_warn_threshold <- suppressWarnings(as.numeric(Sys.getenv("GTWR_LOCAL_CN_WARN_THRESHOLD", unset = "100")))
if (!is.finite(cfg$gtwr_local_cn_warn_threshold) || cfg$gtwr_local_cn_warn_threshold <= 0) {
  cfg$gtwr_local_cn_warn_threshold <- 100
}
cfg$run_gtwr_lamda_sensitivity <- tolower(trimws(Sys.getenv("RUN_GTWR_LAMDA_SENSITIVITY", unset = "false"))) %in% c("1", "true", "yes")
cfg$gtwr_lamda_sensitivity_grid <- trimws(Sys.getenv("GTWR_LAMDA_SENSITIVITY_GRID", unset = "0.025,0.05,0.1,0.2"))
cfg$gtwr_refresh_lamda_sensitivity_cache <- tolower(trimws(Sys.getenv("GTWR_REFRESH_LAMDA_SENSITIVITY_CACHE", unset = "false"))) %in% c("1", "true", "yes")
cfg$run_gtwr_bandwidth_sensitivity <- tolower(trimws(Sys.getenv("RUN_GTWR_BANDWIDTH_SENSITIVITY", unset = "false"))) %in% c("1", "true", "yes")
cfg$gtwr_bandwidth_sensitivity_grid <- trimws(Sys.getenv("GTWR_BANDWIDTH_SENSITIVITY_GRID", unset = "60,90,120,150,180"))
cfg$gtwr_refresh_bandwidth_sensitivity_cache <- tolower(trimws(Sys.getenv("GTWR_REFRESH_BANDWIDTH_SENSITIVITY_CACHE", unset = "false"))) %in% c("1", "true", "yes")
cfg$gtwr_write_legacy_alias <- FALSE
cfg$gwr_delta_write_legacy_alias <- FALSE
cfg$run_gtwr_experiment_sidecar <- tolower(trimws(Sys.getenv("RUN_GTWR_EXPERIMENT_SIDECAR", unset = "false"))) %in% c("1", "true", "yes")
cfg$gtwr_experiment_bw_approaches <- trimws(Sys.getenv("GTWR_EXPERIMENT_BW_APPROACHES", unset = "CV"))
cfg$gtwr_experiment_lamda_grid <- trimws(Sys.getenv("GTWR_EXPERIMENT_LAMDA_GRID", unset = "0.05"))
cfg$gtwr_experiment_ksi_grid <- trimws(Sys.getenv("GTWR_EXPERIMENT_KSI_GRID", unset = "0"))
cfg$gtwr_experiment_min_st_bw_grid <- trimws(Sys.getenv("GTWR_EXPERIMENT_MIN_ST_BW_GRID", unset = "120"))
cfg$gtwr_experiment_control_strategies <- trimws(Sys.getenv("GTWR_EXPERIMENT_CONTROL_STRATEGIES", unset = "baseline"))
cfg$gtwr_experiment_required_controls <- trimws(Sys.getenv("GTWR_EXPERIMENT_REQUIRED_CONTROLS", unset = ""))
cfg$gtwr_experiment_optional_pool <- trimws(Sys.getenv("GTWR_EXPERIMENT_OPTIONAL_POOL", unset = ""))
cfg$gtwr_experiment_outcomes <- trimws(Sys.getenv("GTWR_EXPERIMENT_OUTCOMES", unset = ""))
cfg$gtwr_experiment_topn_raw <- suppressWarnings(as.integer(Sys.getenv("GTWR_EXPERIMENT_TOPN_RAW", unset = "1")))
if (!is.finite(cfg$gtwr_experiment_topn_raw) || cfg$gtwr_experiment_topn_raw < 1L) cfg$gtwr_experiment_topn_raw <- 1L

cfg$run_walk_env_betweenness <- FALSE  # TRUE | FALSE
# walk betweenness는 계산비용이 커서 기본값은 FALSE로 두고,
# 새 사양(local800_len_v1) 캐시가 있을 때만 재사용하는 구조다.
cfg$walk_betweenness_radius_m <- 800L
cfg$walk_betweenness_weight_mode <- "length"
cfg$walk_betweenness_agg_mode <- "overlap_length_weighted_mean"
cfg$walk_betweenness_spec_version <- "local800_len_v1"


#==============================================================================
# 5. Output Path Registry
#==============================================================================

# Centralizing file contracts here reduces drift across scripts and simplifies
# QC checks that need to validate expected outputs.
# 데이터셋 파일명은 내부 파이프라인의 API 역할을 한다. 예를 들어
# `panel_main_pre_vitality`는 05의 출력이자 06의 입력이고,
# `panel_main`은 최종 canonical panel이다. 그래서 경로 계약도
# 중앙화해 둔다.
cfg$paths <- list(
  # 이 list의 각 항목은 "파일 경로"이면서 동시에 "파이프라인 계약 이름"이다.
  # 새 산출물을 추가할 때는 개별 스크립트가 아니라 이 registry부터 갱신한다.
  seoul_raw_integrated_long = file.path(cfg$dir_intermediate, "seoul_raw_integrated_long.parquet"),
  seoul_raw_integrated_wide = file.path(cfg$dir_intermediate, "seoul_raw_integrated_wide.parquet"),
  seoul_raw_review = file.path(cfg$dir_intermediate, "seoul_raw_review.parquet"),
  year_base = file.path(cfg$dir_analysis, "seoul_year_base.parquet"),
  adm_region_lookup = file.path(cfg$dir_analysis, "adm_region_lookup.parquet"),
  adm_region_lookup_csv = file.path(cfg$dir_tables, "adm_region_lookup.csv"),
  aux_covariates = file.path(cfg$dir_analysis, "aux_covariates.parquet"),
  living_population_external_inflow = file.path(cfg$dir_analysis, "living_population_external_inflow.parquet"),
  golmok_survival_rate = file.path(cfg$dir_analysis, "golmok_survival_rate.parquet"),
  golmok_survival_all_levels = file.path(cfg$dir_intermediate, "golmok_survival_all_levels.parquet"),
  registered_resident_population = file.path(cfg$dir_analysis, "registered_resident_population.parquet"),
  registered_resident_population_monthly = file.path(cfg$dir_intermediate, "registered_resident_population_monthly.parquet"),
  walk_betweenness_cache = file.path(
    cfg$dir_analysis,
    sprintf("walk_betweenness_%s.parquet", cfg$walk_betweenness_spec_version)
  ),
  medical_source_preagg = file.path(cfg$dir_intermediate, "medical_source_preagg.parquet"),
  mall_source_preagg = file.path(cfg$dir_intermediate, "mall_source_preagg.parquet"),
  apartment_registry_source_preagg = file.path(cfg$dir_intermediate, "apartment_registry_source_preagg.parquet"),
  senior_source_preagg = file.path(cfg$dir_intermediate, "senior_source_preagg.parquet"),
  bus_stop_source_preagg = file.path(cfg$dir_intermediate, "bus_stop_source_preagg.parquet"),
  subway_station_source_preagg = file.path(cfg$dir_intermediate, "subway_station_source_preagg.parquet"),
  senior_geocode_cache = file.path(cfg$dir_intermediate, "senior_geocode_cache.parquet"),
  medical_geocode_cache = file.path(cfg$dir_intermediate, "medical_geocode_cache.parquet"),
  mall_geocode_cache = file.path(cfg$dir_intermediate, "mall_geocode_cache.parquet"),
  apartment_geocode_cache = file.path(cfg$dir_intermediate, "apartment_geocode_cache.parquet"),
  panel_merged_base = file.path(cfg$dir_panel, "panel_merged_base.parquet"),
  panel_main_pre_vitality = file.path(cfg$dir_panel, "panel_main_pre_vitality.parquet"),
  panel_main = file.path(cfg$dir_panel, "panel_main.parquet"),
  vitality_components = file.path(cfg$dir_panel, "vitality_components.parquet"),
  w_queen = file.path(cfg$dir_panel, "W_queen.rds"),
  w_rook = file.path(cfg$dir_panel, "W_rook.rds"),
  w_knn6 = file.path(cfg$dir_panel, "W_knn6.rds"),
  w_knn8 = file.path(cfg$dir_panel, "W_knn8.rds"),
  twfe_main_models = file.path(cfg$dir_tables, "twfe_main_models.csv"),
  twfe_main_models_html = file.path(cfg$dir_tables, "twfe_main_models.html"),
  twfe_main_controls_used = file.path(cfg$dir_tables, "twfe_main_controls_used.csv"),
  twfe_main_diagnostics = file.path(cfg$dir_tables, "twfe_main_diagnostics.csv"),
  twfe_main_residual_moran = file.path(cfg$dir_tables, "twfe_main_residual_moran.csv"),
  twfe_main_residual_moran_by_year = file.path(cfg$dir_tables, "twfe_main_residual_moran_by_year.csv"),
  twfe_main_residual_moran_summary = file.path(cfg$dir_tables, "twfe_main_residual_moran_summary.csv"),
  twfe_main_coefplot = file.path(cfg$dir_figures, "twfe_main_coefplot.png"),
  twfe_main_coefplot_supplementary = file.path(cfg$dir_figures, "twfe_main_coefplot_supplementary.png"),
  twfe_channel_models = file.path(cfg$dir_tables, "twfe_channel_models.csv"),
  twfe_channel_controls_used = file.path(cfg$dir_tables, "twfe_channel_controls_used.csv"),
  twfe_interaction_models = file.path(cfg$dir_tables, "twfe_interaction_models.csv"),
  twfe_interaction_controls_used = file.path(cfg$dir_tables, "twfe_interaction_controls_used.csv"),
  twfe_interaction_diagnostics = file.path(cfg$dir_tables, "twfe_interaction_diagnostics.csv"),
  twfe_interaction_effect_summary = file.path(cfg$dir_tables, "twfe_interaction_effect_summary.csv"),
  twfe_age_mix_experiment_models = file.path(cfg$dir_tables, "twfe_age_mix_experiment_models.csv"),
  twfe_age_mix_experiment_controls_used = file.path(cfg$dir_tables, "twfe_age_mix_experiment_controls_used.csv"),
  twfe_age_mix_experiment_diagnostics = file.path(cfg$dir_tables, "twfe_age_mix_experiment_diagnostics.csv"),
  spdm_main_models = file.path(cfg$dir_tables, "spdm_main_models.csv"),
  spdm_impacts = file.path(cfg$dir_tables, "spdm_impacts.csv"),
  spdm_controls_used = file.path(cfg$dir_tables, "spdm_controls_used.csv"),
  spdm_main_diagnostics = file.path(cfg$dir_tables, "spdm_main_diagnostics.csv"),
  spdm_channel_models = file.path(cfg$dir_tables, "spdm_channel_models.csv"),
  spdm_channel_impacts = file.path(cfg$dir_tables, "spdm_channel_impacts.csv"),
  spdm_channel_controls_used = file.path(cfg$dir_tables, "spdm_channel_controls_used.csv"),
  spdm_channel_path_effects = file.path(cfg$dir_tables, "spdm_channel_path_effects.csv"),
  spdm_channel_bootstrap_draws = file.path(cfg$dir_tables, "spdm_channel_bootstrap_draws.csv"),
  spdm_channel_diagnostics = file.path(cfg$dir_tables, "spdm_channel_diagnostics.csv"),
  spdm_interaction_models = file.path(cfg$dir_tables, "spdm_interaction_models.csv"),
  spdm_interaction_impacts = file.path(cfg$dir_tables, "spdm_interaction_impacts.csv"),
  spdm_interaction_effect_summary = file.path(cfg$dir_tables, "spdm_interaction_effect_summary.csv"),
  spdm_interaction_controls_used = file.path(cfg$dir_tables, "spdm_interaction_controls_used.csv"),
  spdm_interaction_diagnostics = file.path(cfg$dir_tables, "spdm_interaction_diagnostics.csv"),
  spdm_age_mix_experiment_models = file.path(cfg$dir_tables, "spdm_age_mix_experiment_models.csv"),
  spdm_age_mix_experiment_impacts = file.path(cfg$dir_tables, "spdm_age_mix_experiment_impacts.csv"),
  spdm_age_mix_experiment_controls_used = file.path(cfg$dir_tables, "spdm_age_mix_experiment_controls_used.csv"),
  spdm_age_mix_experiment_diagnostics = file.path(cfg$dir_tables, "spdm_age_mix_experiment_diagnostics.csv"),
  spdm_sector_share_experiment_models = file.path(cfg$dir_tables, "spdm_sector_share_experiment_models.csv"),
  spdm_sector_share_experiment_impacts = file.path(cfg$dir_tables, "spdm_sector_share_experiment_impacts.csv"),
  spdm_sector_share_experiment_controls_used = file.path(cfg$dir_tables, "spdm_sector_share_experiment_controls_used.csv"),
  spdm_sector_share_experiment_diagnostics = file.path(cfg$dir_tables, "spdm_sector_share_experiment_diagnostics.csv"),
  spdm_sector_share_experiment_exposure_relations = file.path(cfg$dir_tables, "spdm_sector_share_experiment_exposure_relations.csv"),
  spdm_family_comparison = file.path(cfg$dir_tables, "spdm_family_comparison.csv"),
  spdm_family_models = file.path(cfg$dir_tables, "spdm_family_models.csv"),
  spdm_selection_tests = file.path(cfg$dir_tables, "spdm_selection_tests.csv"),
  spdm_selection_family_comparison = file.path(cfg$dir_tables, "spdm_selection_family_comparison.csv"),
  spatial_family_main_table = file.path(cfg$dir_tables, "spatial_family_main_table.csv"),
  gwr_delta_main_models = file.path(cfg$dir_tables, "gwr_delta_main_models.csv"),
  gwr_delta_local_coefficients = file.path(cfg$dir_tables, "gwr_delta_local_coefficients.csv"),
  gwr_delta_floating_models = file.path(cfg$dir_tables, "gwr_delta_floating_models.csv"),
  gwr_delta_floating_local_coefficients = file.path(cfg$dir_tables, "gwr_delta_floating_local_coefficients.csv"),
  gwr_delta_controls_used = file.path(cfg$dir_tables, "gwr_delta_controls_used.csv"),
  gwr_delta_summary_table = file.path(cfg$dir_tables, "gwr_delta_summary_table.csv"),
  gwr_delta_rankings_table = file.path(cfg$dir_tables, "gwr_delta_rankings_table.csv"),
  spdm_w_robustness_models = file.path(cfg$dir_tables, "spdm_w_robustness_models.csv"),
  spdm_w_robustness_impacts = file.path(cfg$dir_tables, "spdm_w_robustness_impacts.csv"),
  spdm_w_robustness_controls = file.path(cfg$dir_tables, "spdm_w_robustness_controls_used.csv"),
  spdm_w_robustness_diagnostics = file.path(cfg$dir_tables, "spdm_w_robustness_diagnostics.csv")
)

cfg$paths$twfe_residual_moran <- cfg$paths$twfe_main_residual_moran
cfg$paths$twfe_residual_moran_by_year <- cfg$paths$twfe_main_residual_moran_by_year
cfg$paths$twfe_residual_moran_summary <- cfg$paths$twfe_main_residual_moran_summary
cfg$paths$spdm_w_robustness_controls_used <- cfg$paths$spdm_w_robustness_controls
cfg$paths$global_morans_i <- file.path(cfg$dir_tables, "global_morans_i.csv")
cfg$paths$global_morans_i_by_w <- file.path(cfg$dir_tables, "global_morans_i_by_w.csv")
cfg$paths$global_bivariate_morans_i <- file.path(cfg$dir_tables, "global_bivariate_morans_i.csv")
cfg$paths$univariate_lisa_summary <- file.path(cfg$dir_tables, "univariate_lisa_summary.csv")
cfg$paths$univariate_lisa_local <- file.path(cfg$dir_tables, "univariate_lisa_local.csv")
cfg$paths$bivariate_lisa_summary <- file.path(cfg$dir_tables, "bivariate_lisa_summary.csv")
cfg$paths$bivariate_lisa_local <- file.path(cfg$dir_tables, "bivariate_lisa_local.csv")
cfg$paths$emerging_hotspot_summary <- file.path(cfg$dir_tables, "emerging_hotspot_summary.csv")
cfg$paths$emerging_hotspot_local <- file.path(cfg$dir_tables, "emerging_hotspot_local.csv")
cfg$paths$robustness_summary <- file.path(cfg$dir_tables, "robustness_summary.csv")
cfg$paths$robustness_compare <- file.path(cfg$dir_figures, "robustness_compare.png")
cfg$paths$method_dataset_contract_check <- file.path(cfg$dir_logs, "method_dataset_contract_check.csv")
cfg$paths$descriptive_statistics <- file.path(cfg$dir_tables, "descriptive_statistics.csv")
cfg$paths$main_variable_correlation_matrix <- file.path(cfg$dir_tables, "main_variable_correlation_matrix.csv")
cfg$paths$main_variable_correlation_pairs <- file.path(cfg$dir_tables, "main_variable_correlation_pairs.csv")
cfg$paths$main_variable_correlation_n_matrix <- file.path(cfg$dir_tables, "main_variable_correlation_n_matrix.csv")
cfg$paths$data_coverage <- file.path(cfg$dir_tables, "data_coverage.csv")
cfg$paths$mean_ln_sales_trend <- file.path(cfg$dir_figures, "mean_ln_sales_trend.png")

cfg$gtwr_control_set_token <- function(control_set = cfg$gtwr_control_set) {
  control_set <- tolower(trimws(as.character(control_set[[1]])))
  if (!control_set %in% c("lean", "extended")) "lean" else control_set
}
cfg$gtwr_main_output_tag <- function(control_set = cfg$gtwr_control_set) {
  cfg$gtwr_control_set_token(control_set)
}
cfg$get_gtwr_main_models_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_main_models_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_local_coefficients_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_local_coefficients_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_delta_summary_table_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_delta_summary_table_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_delta_rankings_table_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_delta_rankings_table_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_latest_summary_table_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_latest_summary_table_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_latest_rankings_table_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_latest_rankings_table_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_local_beta_panel_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_local_beta_panel_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_controls_used_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_controls_used_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_frozen_spec_path <- function(family_tag, control_set = cfg$gtwr_control_set) {
  family_tag <- tolower(as.character(family_tag[[1]]))
  control_set <- cfg$gtwr_control_set_token(control_set)
  stem <- switch(
    family_tag,
    gtwr_main = "gtwr_main_frozen_spec",
    gtwr_floating = "gtwr_floating_frozen_spec",
    gtwr_age_band = "gtwr_age_band_frozen_spec",
    gtwr_sector_share = "gtwr_sector_share_frozen_spec",
    stop(sprintf("unsupported GTWR frozen-spec family tag: %s", family_tag), call. = FALSE)
  )
  file.path(cfg$dir_tables, sprintf("%s_%s.csv", stem, control_set))
}
cfg$get_gtwr_main_frozen_spec_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_main_frozen_spec_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_main_spec_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_logs, "gtwr_spec_cache", cfg$gtwr_control_set_token(control_set), "main")
}
cfg$get_gtwr_main_bw_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_logs, "gtwr_bandwidth_cache", cfg$gtwr_control_set_token(control_set), "main")
}
cfg$get_gtwr_sidecar_spec_cache_dir <- function(family_tag, control_set = cfg$gtwr_control_set) {
  family_tag <- tolower(as.character(family_tag[[1]]))
  file.path(cfg$dir_logs, "gtwr_spec_cache", cfg$gtwr_control_set_token(control_set), family_tag)
}
cfg$get_gtwr_sidecar_bw_cache_dir <- function(family_tag, control_set = cfg$gtwr_control_set) {
  family_tag <- tolower(as.character(family_tag[[1]]))
  file.path(cfg$dir_logs, "gtwr_bandwidth_cache", cfg$gtwr_control_set_token(control_set), family_tag)
}
cfg$get_gtwr_floating_spec_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_sidecar_spec_cache_dir("floating", control_set)
}
cfg$get_gtwr_floating_bw_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_sidecar_bw_cache_dir("floating", control_set)
}
cfg$get_gtwr_age_band_spec_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_sidecar_spec_cache_dir("age_band", control_set)
}
cfg$get_gtwr_age_band_bw_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_sidecar_bw_cache_dir("age_band", control_set)
}
cfg$get_gtwr_sector_share_spec_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_sidecar_spec_cache_dir("sector_share", control_set)
}
cfg$get_gtwr_sector_share_bw_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_sidecar_bw_cache_dir("sector_share", control_set)
}
cfg$get_gtwr_lamda_sensitivity_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_lamda_sensitivity_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_lamda_sensitivity_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_logs, "gtwr_lamda_sensitivity_cache", cfg$gtwr_control_set_token(control_set), "main")
}
cfg$get_gtwr_bandwidth_sensitivity_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_bandwidth_sensitivity_%s.csv", cfg$gtwr_main_output_tag(control_set)))
}
cfg$get_gtwr_bandwidth_sensitivity_cache_dir <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_logs, "gtwr_bandwidth_sensitivity_cache", cfg$gtwr_control_set_token(control_set), "main")
}
cfg$get_gtwr_experiment_registry_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_experiment_registry_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_experiment_main_models_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_experiment_main_models_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_experiment_local_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_experiment_local_coefficients_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_experiment_panel_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_experiment_local_beta_panel_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_experiment_ranked_candidates_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_experiment_ranked_candidates_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_experiment_controls_used_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_experiment_controls_used_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_experiment_state_controls_used_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_experiment_controls_used_state_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_floating_models_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_floating_models_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_floating_local_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_floating_local_coefficients_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_floating_local_beta_panel_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_floating_local_beta_panel_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_floating_controls_used_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_floating_controls_used_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_floating_frozen_spec_path <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_frozen_spec_path("gtwr_floating", control_set)
}
cfg$get_gwr_delta_map_path <- function(family, outcome, focal_var) {
  file.path(
    cfg$dir_maps,
    sprintf(
      "gwr_delta_beta_map__%s__%s__%s.png",
      tolower(as.character(family[[1]])),
      as.character(outcome[[1]]),
      as.character(focal_var[[1]])
    )
  )
}
cfg$get_gtwr_age_band_models_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_age_band_models_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_age_band_panel_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_age_band_local_beta_panel_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_age_band_local_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_age_band_local_coefficients_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_age_band_controls_used_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_age_band_controls_used_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_age_band_frozen_spec_path <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_frozen_spec_path("gtwr_age_band", control_set)
}
cfg$get_gtwr_age_band_delta_summary_table_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_age_band_delta_summary_table_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_age_band_delta_rankings_table_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_age_band_delta_rankings_table_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_sector_share_models_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_sector_share_models_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_sector_share_panel_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_sector_share_local_beta_panel_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_sector_share_local_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_sector_share_local_coefficients_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_sector_share_controls_used_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_sector_share_controls_used_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_sector_share_frozen_spec_path <- function(control_set = cfg$gtwr_control_set) {
  cfg$get_gtwr_frozen_spec_path("gtwr_sector_share", control_set)
}
cfg$get_gtwr_sector_share_delta_summary_table_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_sector_share_delta_summary_table_%s.csv", cfg$gtwr_control_set_token(control_set)))
}
cfg$get_gtwr_sector_share_delta_rankings_table_path <- function(control_set = cfg$gtwr_control_set) {
  file.path(cfg$dir_tables, sprintf("gtwr_sector_share_delta_rankings_table_%s.csv", cfg$gtwr_control_set_token(control_set)))
}

cfg$paths$presentation_esda_global_moran <- file.path(
  cfg$dir_report,
  "presentation_esda_global_moran.csv"
)
cfg$paths$presentation_esda_bivariate_summary <- file.path(
  cfg$dir_report,
  "presentation_esda_bivariate_summary.csv"
)
cfg$paths$presentation_esda_bivariate_lisa <- file.path(
  cfg$dir_report,
  "presentation_esda_bivariate_lisa.png"
)
cfg$paths$presentation_twfe_space_dependence <- file.path(
  cfg$dir_report,
  "presentation_twfe_space_dependence.csv"
)
cfg$paths$presentation_twfe_coefplot <- file.path(
  cfg$dir_report,
  "presentation_twfe_coefplot.png"
)
cfg$paths$presentation_spdm_main <- file.path(
  cfg$dir_report,
  "presentation_spdm_main.csv"
)
cfg$paths$presentation_spdm_main_plot <- file.path(
  cfg$dir_report,
  "presentation_spdm_main.png"
)
cfg$paths$presentation_spdm_w_robustness <- file.path(
  cfg$dir_report,
  "presentation_spdm_w_robustness.csv"
)
cfg$paths$presentation_spdm_w_robustness_plot <- file.path(
  cfg$dir_report,
  "presentation_spdm_w_robustness.png"
)
cfg$paths$presentation_spdm_w_robustness_all_outcomes <- file.path(
  cfg$dir_report,
  "presentation_spdm_w_robustness_all_outcomes.csv"
)
cfg$paths$presentation_spdm_w_robustness_all_outcomes_plot <- file.path(
  cfg$dir_report,
  "presentation_spdm_w_robustness_all_outcomes.png"
)
cfg$paths$presentation_spdm_channel <- file.path(
  cfg$dir_report,
  "presentation_spdm_channel.csv"
)
cfg$paths$presentation_spdm_channel_path_diagram <- file.path(
  cfg$dir_report,
  "presentation_spdm_channel_path_diagram.png"
)
cfg$paths$presentation_spdm_channel_path_diagram_data <- file.path(
  cfg$dir_report,
  "presentation_spdm_channel_path_diagram.csv"
)
cfg$paths$presentation_spdm_channel_plot <- file.path(
  cfg$dir_report,
  "presentation_spdm_channel.png"
)
cfg$paths$presentation_gtwr_summary <- file.path(
  cfg$dir_report,
  "presentation_gtwr_summary.csv"
)
cfg$paths$presentation_gtwr_summary_plot <- file.path(
  cfg$dir_report,
  "presentation_gtwr_summary.png"
)
cfg$paths$presentation_manifest <- file.path(
  cfg$dir_report,
  "presentation_manifest.csv"
)

cfg$canonical_pipeline_scripts <- c(
  "02_Code/01_preprocess/01_build_adm_region_lookup.R",
  "02_Code/01_preprocess/02_build_seoul_year_base.R",
  "02_Code/01_preprocess/03_build_auxiliary_covariates.R",
  "02_Code/01_preprocess/04_build_golmok_survival_rate.R",
  "02_Code/01_preprocess/05_build_registered_resident_population.R",
  "02_Code/01_preprocess/06_build_analysis_panel.R",
  "02_Code/01_preprocess/07_build_vitality_index.R",
  "02_Code/02_esda/01_build_spatial_weights.R",
  "02_Code/02_esda/02_run_esda.R",
  "02_Code/03_models/01_run_twfe_main.R",
  "02_Code/03_models/02_run_spdm_main.R",
  "02_Code/03_models/03_run_spdm_channel_path.R",
  "02_Code/04_robustness/01_run_spdm_w_robustness.R",
  "02_Code/04_robustness/02_run_robustness.R",
  "02_Code/06_qc/01_validate_method_dataset_alignment.R",
  "02_Code/05_reporting/01_make_tables_figures.R"
)
cfg$optional_sidecar_scripts <- list(
  living_pop_inflow = "02_Code/80_optional/preprocess/01_build_living_population_inflow.R",
  gtwr_main = "02_Code/80_optional/gtwr/01_run_gtwr_main.R"
)
cfg$manual_annual_appendix_scripts <- c(
  "02_Code/80_optional/twfe/01_run_twfe_channel_models.R",
  "02_Code/80_optional/twfe/02_run_twfe_interaction_models.R",
  "02_Code/80_optional/twfe/03_run_twfe_age_mix_experiment.R",
  "02_Code/80_optional/spdm/01_run_spdm_interaction_models.R",
  "02_Code/80_optional/spdm/02_run_spdm_age_mix_experiment.R",
  "02_Code/80_optional/spdm/03_run_spdm_sector_share_experiment.R",
  "02_Code/80_optional/spdm/04_run_spdm_selection_sidecar.R",
  "02_Code/80_optional/spdm/05_run_spdm_family_comparison_sidecar.R",
  "02_Code/80_optional/gtwr/02_run_gtwr_floating_only.R",
  "02_Code/80_optional/gtwr/03_run_gtwr_age_band.R",
  "02_Code/80_optional/gtwr/04_run_gtwr_sector_share.R",
  "02_Code/80_optional/gtwr/05_run_gwr_delta.R",
  "02_Code/80_optional/gtwr/06_run_gtwr_experiment.R"
)
cfg$deferred_sidecar_scripts <- cfg$manual_annual_appendix_scripts
cfg$active_output_contract <- list(
  shared_data = c(
    cfg$paths$year_base,
    cfg$paths$adm_region_lookup,
    cfg$paths$aux_covariates,
    cfg$paths$living_population_external_inflow,
    cfg$paths$golmok_survival_rate,
    cfg$paths$registered_resident_population,
    cfg$paths$panel_merged_base,
    cfg$paths$panel_main_pre_vitality,
    cfg$paths$panel_main,
    cfg$paths$vitality_components,
    cfg$paths$w_queen,
    cfg$paths$w_rook,
    cfg$paths$w_knn6,
    cfg$paths$w_knn8
  ),
  esda = c(
    cfg$paths$global_morans_i,
    cfg$paths$global_morans_i_by_w,
    cfg$paths$global_bivariate_morans_i,
    cfg$paths$univariate_lisa_summary,
    cfg$paths$univariate_lisa_local,
    cfg$paths$bivariate_lisa_summary,
    cfg$paths$bivariate_lisa_local,
    cfg$paths$emerging_hotspot_summary,
    cfg$paths$emerging_hotspot_local
  ),
  twfe = c(
    cfg$paths$twfe_main_models,
    cfg$paths$twfe_main_models_html,
    cfg$paths$twfe_main_controls_used,
    cfg$paths$twfe_main_diagnostics,
    cfg$paths$twfe_main_residual_moran,
    cfg$paths$twfe_main_residual_moran_by_year,
    cfg$paths$twfe_main_residual_moran_summary,
    cfg$paths$twfe_main_coefplot
  ),
  spdm = c(
    cfg$paths$spdm_main_models,
    cfg$paths$spdm_impacts,
    cfg$paths$spdm_controls_used,
    cfg$paths$spdm_main_diagnostics,
    cfg$paths$spdm_channel_models,
    cfg$paths$spdm_channel_impacts,
    cfg$paths$spdm_channel_controls_used,
    cfg$paths$spdm_channel_path_effects,
    cfg$paths$spdm_channel_bootstrap_draws,
    cfg$paths$spdm_channel_diagnostics
  ),
  spdm_w_robustness = c(
    cfg$paths$spdm_w_robustness_models,
    cfg$paths$spdm_w_robustness_impacts,
    cfg$paths$spdm_w_robustness_controls_used,
    cfg$paths$spdm_w_robustness_diagnostics
  ),
  robustness = c(
    cfg$paths$robustness_summary,
    cfg$paths$robustness_compare
  ),
  qc = c(cfg$paths$method_dataset_contract_check),
  reporting = c(
    cfg$paths$descriptive_statistics,
    cfg$paths$main_variable_correlation_matrix,
    cfg$paths$main_variable_correlation_pairs,
    cfg$paths$main_variable_correlation_n_matrix,
    cfg$paths$data_coverage,
    cfg$paths$mean_ln_sales_trend
  )
)

cfg$obsolete_panel_paths <- file.path(
  cfg$dir_panel,
  c("panel_main_core.parquet", "panel_esda.parquet", "panel_twfe.parquet", "panel_spdm.parquet", "panel_gtwr.parquet")
)
# 예전 산출물 이름은 cleanup 대상으로 따로 보존한다. 이렇게 해야
# 오래된 파일이 helper inventory나 QC를 혼동시키지 않는다.


#==============================================================================
# 6. Log Path Registry
#==============================================================================

# 이 프로젝트는 데이터셋뿐 아니라 QC와 provenance 로그도 산출물의
# 일부로 본다. 그래서 로그 경로도 paths처럼 중앙 registry로 관리한다.
cfg$logs <- list(
  # 로그도 분석 산출물의 일부로 취급하므로, tag 적용 여부와 저장 위치를
  # 데이터셋 경로와 같은 수준으로 명시적으로 관리한다.
  data_qc = cfg$tag_path(file.path(cfg$dir_logs, "data_qc_log.md")),
  model_run = file.path(cfg$dir_logs, "model_run_log.md"),
  missing_data = cfg$tag_path(file.path(cfg$dir_logs, "missing_data_log.csv")),
  senior_geocode_qc = file.path(cfg$dir_logs, "senior_geocode_qc.csv"),
  senior_geocode_type_qc = file.path(cfg$dir_logs, "senior_geocode_type_qc.csv"),
  senior_geocode_unmatched = file.path(cfg$dir_logs, "senior_geocode_unmatched_sample.csv"),
  medical_geocode_qc = file.path(cfg$dir_logs, "medical_geocode_qc.csv"),
  medical_geocode_unmatched = file.path(cfg$dir_logs, "medical_geocode_unmatched_sample.csv"),
  mall_geocode_qc = file.path(cfg$dir_logs, "mall_geocode_qc.csv"),
  mall_geocode_unmatched = file.path(cfg$dir_logs, "mall_geocode_unmatched_sample.csv"),
  apartment_registry_qc = file.path(cfg$dir_logs, "apartment_registry_qc.csv"),
  apartment_registry_unmatched = file.path(cfg$dir_logs, "apartment_registry_unmatched_sample.csv"),
  apartment_geocode_qc = file.path(cfg$dir_logs, "apartment_geocode_qc.csv"),
  living_population_inflow_manifest = file.path(cfg$dir_logs, "living_population_inflow_manifest.csv"),
  living_population_inflow_qc = file.path(cfg$dir_logs, "living_population_inflow_qc.csv"),
  adm_region_lookup_qc = file.path(cfg$dir_logs, "adm_region_lookup_qc.csv"),
  golmok_survival_rate_qc = file.path(cfg$dir_logs, "golmok_survival_rate_qc.csv"),
  registered_resident_population_qc = file.path(cfg$dir_logs, "registered_resident_population_qc.csv"),
  registered_resident_population_mapping_qc = file.path(cfg$dir_logs, "registered_resident_population_mapping_qc.csv"),
  panel_year_aggregation_qc = file.path(cfg$dir_logs, "panel_year_aggregation_qc.csv"),
  transit_aux_qc = file.path(cfg$dir_logs, "transit_aux_qc.csv"),
  vitality_component_qc = file.path(cfg$dir_logs, "vitality_component_qc.csv"),
  decision = file.path(cfg$dir_doc_logs, "decision_log.md"),
  inventory = file.path(cfg$dir_logs, "data_file_inventory.csv"),
  cleanup = file.path(cfg$dir_logs, "refactor_cleanup_log.md")
)


#==============================================================================
# 7. Required Directories
#==============================================================================

# 실행 전에 필요한 디렉터리를 한 번에 보장하기 위한 목록이다.
cfg$required_dirs <- c(
  cfg$dir_intermediate, cfg$dir_analysis, cfg$dir_panel,
  cfg$dir_golmok_survival_json,
  cfg$dir_tables, cfg$dir_figures, cfg$dir_maps, cfg$dir_logs, cfg$dir_report,
  cfg$dir_design, cfg$dir_codebook, cfg$dir_doc_logs
)

invisible(cfg)
