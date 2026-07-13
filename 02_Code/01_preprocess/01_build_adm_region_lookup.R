#!/usr/bin/env Rscript

#==============================================================================
# Script    : 01_build_adm_region_lookup.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build the canonical adm_cd-dong-gu-living-area lookup from the
#             2020 Seoul administrative-dong boundary.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-05-14
# Type      : static_lookup_building
# Inputs    : 2020 Seoul commercial-service administrative-dong boundary
# Outputs   : adm_region_lookup.parquet, adm_region_lookup.csv,
#             adm_region_lookup_qc.csv
# DependsOn : config.R, utils_io.R, utils_spatial.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# Load the shared config, package loader, safe IO helpers, and spatial helpers
# first so this script uses the same path registry as the rest of the pipeline.
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
source(here::here("02_Code", "99_utils", "utils_spatial.R"))
load_project_packages()

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 01_build_adm_region_lookup", timestamp()))

ensure_dirs(c(
  cfg$dir_analysis,
  cfg$dir_tables,
  cfg$dir_logs
))

#==============================================================================
# 1. Load Canonical 2020 Administrative Boundary
#==============================================================================

# The 2020 Seoul administrative-dong boundary is the spatial key origin for
# downstream preprocessing joins; the padded `adm_cd` created by the loader is
# the stable unit identifier reused across the quarterly panel.
boundary <- load_commercial_boundary(cfg$dir_boundary, cfg$target_crs)

#==============================================================================
# 2. Build Static Dong-Gu-Living-Area Lookup
#==============================================================================

# This is static reference metadata, not a quarterly panel table. It attaches
# gu and five-living-area labels to each 2020 administrative dong through the
# canonical `adm_cd` prefix contract.
lookup <- build_adm_region_lookup(
  boundary_tbl = boundary,
  boundary_year = cfg$boundary_year
)

#==============================================================================
# 3. QC Gate
#==============================================================================

# The lookup is a small upstream dependency, so failures should stop immediately:
# otherwise downstream joins, QC summaries, and reporting labels can drift
# quietly while still producing files.
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

#==============================================================================
# 4. Publish Canonical Outputs
#==============================================================================

# Parquet is the downstream canonical artifact; CSV is retained as the
# human-readable review/reporting copy.
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
