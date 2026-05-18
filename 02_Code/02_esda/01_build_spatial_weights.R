#==============================================================================
# Script    : 01_build_spatial_weights.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build Queen, Rook, and kNN spatial weights on the 2020
#             commercial-administrative boundary used by the quarterly panel.
# Author    : Codex
# Created   : 2026-02-28
# Type      : spatial_preprocessing
# Inputs    : 2020 commercial administrative boundary shapefile
# Outputs   : W_queen.rds, W_rook.rds, W_knn6.rds, W_knn8.rds,
#             spatial_weight_connectivity.csv
# DependsOn : 02_Code/R/utils_spatial.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# 이 스크립트는 이후 ESDA와 공간패널모형이 공통으로 재사용하는
# 공간가중행렬(`W_*`)만 만든다. 한 번 만들어 두면 모델 스크립트는
# 같은 경계와 같은 이웃 규칙을 반복 계산하지 않고 바로 읽어 쓴다.
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
load_project_packages()
ensure_dirs(cfg$required_dirs)


#==============================================================================
# 1. Load Boundary Geometry
#==============================================================================

# 가중행렬은 `panel_main`이 쓰는 2020 상권-행정동 경계와 정확히 같은
# 공간 지지체 위에서 정의해야 한다. 그래야 ESDA, TWFE 잔차 Moran,
# SPDM이 서로 다른 공간 단위를 섞지 않는다.
# Spatial weights are defined on the exact geometry used by quarterly Seoul
# panel keys so ESDA and panel models share the same spatial support.
b2020 <- load_commercial_boundary(cfg$dir_boundary, cfg$target_crs)


#==============================================================================
# 2. Build and Save Weight Matrices
#==============================================================================

# queen/rook은 인접면 기반, knn6/knn8은 최근접 중심점 기반 대안 규칙이다.
# 메인 분석은 queen을 기본으로 쓰고, 나머지는 robustness에서 비교한다.
lw_q <- build_listw(b2020, "queen")
lw_r <- build_listw(b2020, "rook")
lw_6 <- build_listw(b2020, "knn6")
lw_8 <- build_listw(b2020, "knn8")

# 파일 저장은 Queen -> Rook -> kNN 순으로 고정해 두면,
# downstream 문서와 QC에서 기본 W와 대안 W를 같은 순서로 설명할 수 있다.
save_rds_safe(lw_q, cfg$paths$w_queen)
save_rds_safe(lw_r, cfg$paths$w_rook)
save_rds_safe(lw_6, cfg$paths$w_knn6)
save_rds_safe(lw_8, cfg$paths$w_knn8)


#==============================================================================
# 3. Connectivity QC
#==============================================================================

# 저장 직후 연결성 요약을 남겨 두면, 고립 노드가 생겼는지,
# 대안 W가 지나치게 희소하거나 과밀한지 바로 확인할 수 있다.
summarize_connectivity <- function(lw, w_type) {
  nb <- lw$neighbours
  degrees <- spdep::card(nb)
  comp <- spdep::n.comp.nb(nb)
  comp_sizes <- if (!is.null(comp$comp.id) && length(comp$comp.id) > 0) {
    tabulate(comp$comp.id)
  } else {
    integer()
  }
  row_sums <- vapply(lw$weights, sum, numeric(1))

  tibble::tibble(
    w_type = w_type,
    n_nodes = length(nb),
    avg_neighbors = mean(degrees),
    min_neighbors = min(degrees),
    max_neighbors = max(degrees),
    isolated_nodes = sum(degrees == 0),
    connected_components = as.integer(comp$nc),
    largest_component_share = if (length(comp_sizes) == 0) NA_real_ else max(comp_sizes) / length(nb),
    row_sum_min = min(row_sums),
    row_sum_max = max(row_sums)
  )
}

qc <- dplyr::bind_rows(
  summarize_connectivity(lw_q, "queen"),
  summarize_connectivity(lw_r, "rook"),
  summarize_connectivity(lw_6, "knn6"),
  summarize_connectivity(lw_8, "knn8")
)

write_csv_safe(qc, file.path(cfg$dir_tables, "spatial_weight_connectivity.csv"))
append_log(cfg$logs$data_qc, sprintf("\n## [%s] 01_build_spatial_weights", timestamp()))
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Spatial weights saved: %s",
    qc |>
      dplyr::mutate(
        txt = sprintf(
          "%s(n=%d, isolates=%d, comp=%d, deg=%.2f/%d-%d)",
          w_type, n_nodes, isolated_nodes, connected_components, avg_neighbors, min_neighbors, max_neighbors
        )
      ) |>
      dplyr::pull(txt) |>
      paste(collapse = "; ")
  )
)
