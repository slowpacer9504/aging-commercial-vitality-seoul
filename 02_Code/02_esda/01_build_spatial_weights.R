#==============================================================================
# Script    : 01_build_spatial_weights.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build Queen, Rook, and kNN spatial weights on the 2020
#             commercial-administrative boundary used by the quarterly panel.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-02-28
# Type      : spatial_preprocessing
# Inputs    : 2020 commercial administrative boundary shapefile
# Outputs   : W_queen.rds, W_rook.rds, W_knn6.rds, W_knn8.rds,
#             spatial_weight_connectivity.csv
# DependsOn : 02_Code/99_utils/utils_spatial.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# This script publishes the reusable W objects shared by ESDA, TWFE residual
# Moran diagnostics, SPDM, and robustness scripts.
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
source(here::here("02_Code", "99_utils", "utils_spatial.R"))
load_project_packages()
ensure_dirs(cfg$required_dirs)


#==============================================================================
# 1. Load Boundary Geometry
#==============================================================================

# Spatial weights are defined on the exact geometry used by quarterly Seoul
# panel keys so ESDA and panel models share the same spatial support.
b2020 <- load_commercial_boundary(cfg$dir_boundary, cfg$target_crs)


#==============================================================================
# 2. Build and Save Weight Matrices
#==============================================================================

# Queen is the main contiguity W; Rook and kNN variants are published only as
# predefined robustness alternatives under the same boundary contract.
lw_q <- build_listw(b2020, "queen")
lw_r <- build_listw(b2020, "rook")
lw_6 <- build_listw(b2020, "knn6")
lw_8 <- build_listw(b2020, "knn8")

# Save order mirrors the main-to-robustness W hierarchy used in downstream
# documentation and QC.
save_rds_safe(lw_q, cfg$paths$w_queen)
save_rds_safe(lw_r, cfg$paths$w_rook)
save_rds_safe(lw_6, cfg$paths$w_knn6)
save_rds_safe(lw_8, cfg$paths$w_knn8)


#==============================================================================
# 3. Connectivity QC
#==============================================================================

# Connectivity QC makes isolated nodes, component splits, and unusually sparse
# or dense alternative W definitions visible immediately after publication.
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
