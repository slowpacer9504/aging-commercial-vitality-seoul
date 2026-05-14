#!/usr/bin/env Rscript

#==============================================================================
# Script    : 01_build_adm_region_lookup.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build the canonical adm_cd-dong-gu-living-area lookup from the
#             2020 Seoul administrative-dong boundary.
# Author    : Codex
# Created   : 2026-05-14
# Type      : static_lookup_building
# Inputs    : 2020 Seoul commercial-service administrative-dong boundary
# Outputs   : adm_region_lookup.parquet, adm_region_lookup.csv,
#             adm_region_lookup_qc.csv
# DependsOn : config.R, utils_io.R, utils_spatial.R
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
load_project_packages()

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 01_build_adm_region_lookup", timestamp()))

ensure_dirs(c(
  cfg$dir_analysis,
  cfg$dir_tables,
  cfg$dir_logs
))

boundary <- load_commercial_boundary(cfg$dir_boundary, cfg$target_crs)

lookup <- build_adm_region_lookup(
  boundary_tbl = boundary,
  boundary_year = cfg$boundary_year
)

qc <- summarise_adm_region_lookup_qc(lookup)

write_csv_safe(qc, cfg$logs$adm_region_lookup_qc)

if (any(qc$status == "FAIL")) {
  failed <- qc |>
    dplyr::filter(.data$status == "FAIL") |>
    dplyr::pull(.data$check_id)
  stop(
    sprintf("[ERROR] adm_region_lookup QC failed: %s", paste(failed, collapse = ", ")),
    call. = FALSE
  )
}

write_parquet_safe(lookup, cfg$paths$adm_region_lookup)
write_csv_safe(lookup, cfg$paths$adm_region_lookup_csv)

append_log(
  cfg$logs$data_qc,
  sprintf(
    "[DONE] adm_region_lookup rows=%s gu=%s living_area=%s",
    nrow(lookup),
    dplyr::n_distinct(lookup$gu_name),
    dplyr::n_distinct(lookup$living_area)
  )
)

message("[DONE] adm_region_lookup rows=", nrow(lookup))
