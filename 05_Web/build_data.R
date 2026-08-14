#!/usr/bin/env Rscript
# =============================================================================
# build_data.R
#
# Builds the static data artifacts consumed by the FastAPI + MapLibre web app
# for exploring GTWR local-coefficient results on a Seoul administrative-dong
# map.
#
# Source data (read-only):
#   * 03_Output/01_Tables/gtwr_local_coefficients_{lean,extended}.csv
#   * 03_Output/01_Tables/gtwr_local_beta_panel_{lean,extended}.csv
#   * 03_Output/01_Tables/gtwr_main_models_{lean,extended}.csv
#   * 03_Output/01_Tables/adm_region_lookup.csv
#   * 01_Data/02_Boundary/01_Seoul/서울시 상권분석서비스(영역-행정동)/*.shp
#     (EPSG:5186, 425 administrative dongs, 8-digit ADSTRD_CD)
#
# Output (gitignored):
#   05_Web/data/geojson/seoul_adm_dong.geojson           EPSG:4326 FeatureCollection
#   05_Web/data/json/coefficients_{lean,extended}.json
#   05_Web/data/json/panel_{lean,external}.json (POINT_INDEX only, NOT the full panel — too big for a prebuilt file; backend reads panel CSV at startup)
#   05_Web/data/json/summary_{lean,extended}.json
#   05_Web/data/json/lookup.json
#   05_Web/data/_build_manifest.json                      coverage gate
#
# Coverage gate (exits nonzero on any failure):
#   - SHP features == 425
#   - 425 / 425 adm_cd in coefficients CSV have a geometry match
#   - output GeoJSON declared CRS is EPSG:4326
# =============================================================================

suppressPackageStartupMessages({
  library(sf)       # 1.0-21
  library(dplyr)    # 1.1-4
  library(jsonlite) # 2.0-0
})

# ---------------------------------------------------------------------------
# Paths: robust resolution whether run from project root or 05_Web/
# ---------------------------------------------------------------------------
if (dir.exists("05_Web")) {
  project_root <- normalizePath(".", mustWork = TRUE)
  web_dir      <- normalizePath("05_Web", mustWork = TRUE)
} else if (file.exists("build_data.R") && dir.exists("../03_Output")) {
  web_dir      <- normalizePath(".", mustWork = TRUE)
  project_root <- normalizePath("..", mustWork = TRUE)
} else {
  project_root <- normalizePath(".", mustWork = TRUE)
  web_dir      <- normalizePath("05_Web", mustWork = FALSE)
}
out_tables    <- file.path(project_root, "03_Output", "01_Tables")
boundary_dir  <- file.path(project_root, "01_Data", "02_Boundary", "01_Seoul")

out_geojson_dir <- file.path(web_dir, "data", "geojson")
out_json_dir    <- file.path(web_dir, "data", "json")
out_manifest    <- file.path(web_dir, "data", "_build_manifest.json")
dir.create(out_geojson_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_json_dir,    recursive = TRUE, showWarnings = FALSE)

# UTF-8 stdout (Korean paths / names print cleanly on macOS Terminal)
options(encoding = "UTF-8")

log <- function(...) cat(sprintf(...), "\n", sep = "")

# ---------------------------------------------------------------------------
# 1. Verify required input files exist before doing any work
# ---------------------------------------------------------------------------
expected_inputs <- c(
  file.path(out_tables, "gtwr_local_coefficients_lean.csv"),
  file.path(out_tables, "gtwr_local_coefficients_extended.csv"),
  file.path(out_tables, "gtwr_local_beta_panel_lean.csv"),
  file.path(out_tables, "gtwr_local_beta_panel_extended.csv"),
  file.path(out_tables, "gtwr_main_models_lean.csv"),
  file.path(out_tables, "gtwr_main_models_extended.csv"),
  file.path(out_tables, "adm_region_lookup.csv")
)
missing_inputs <- expected_inputs[!file.exists(expected_inputs)]
if (length(missing_inputs) > 0) {
  stop(
    "Missing required input files. Run the research pipeline ",
    "(02_Code/run_all.R + the GTWR sidecar 02_Code/03_models/03_run_gtwr_main.R) ",
    "before running build_data.R.\n  Missing:\n    ",
    paste(missing_inputs, collapse = "\n    ")
  )
}

# Locate the 상권분석서비스 행정동 SHP. The folder / file names are Korean;
# the SHP has 425 features, with column ADSTRD_CD (8 digits) + ADSTRD_NM.
shp_dir  <- file.path(boundary_dir, "서울시 상권분석서비스(영역-행정동)")
shp_file <- list.files(shp_dir, pattern = "\\.shp$", full.names = TRUE)
if (length(shp_file) != 1L) {
  stop("Expected exactly one .shp under ", shp_dir, "; found: ",
       paste(shp_file, collapse = ", "))
}
log("[1] Found SHP: %s", basename(shp_file))

# ---------------------------------------------------------------------------
# 2. Read SHP, transform to EPSG:4326, attach ten-digit adm_cd
# ---------------------------------------------------------------------------
shp <- st_read(shp_file, quiet = TRUE)
log("[2] SHP features = %d, CRS in = %s", nrow(shp), st_crs(shp)$input)

# The SHP uses 8-digit ADSTRD_CD; the GTWR CSVs use 10-digit adm_cd of the form
# "00" + ADSTRD_CD (zero-padded). Normalise here.
if (!"ADSTRD_CD" %in% names(shp)) {
  stop("SHP missing ADSTRD_CD column; columns = ",
       paste(names(shp), collapse = ", "))
}
shp$adm_cd <- sprintf("00%08d", as.integer(shp$ADSTRD_CD))

# Reproject to WGS84 (MapLibre only accepts EPSG:4326).
shp4326 <- st_transform(shp, st_crs(4326))
log("[2] CRS out = %s", st_crs(shp4326)$input)

# ---------------------------------------------------------------------------
# 3. Adm_cd reconciliation against the GTWR coefficients CSVs
# ---------------------------------------------------------------------------
read_coeffs <- function(control_set) {
  read.csv(
    file.path(out_tables, sprintf("gtwr_local_coefficients_%s.csv", control_set)),
    colClasses = "character"
  )
}
coeffs_lean <- read_coeffs("lean")
coeffs_ext  <- read_coeffs("extended")

# All distinct adm_cd across both control sets
all_coeff_adm_cd <- unique(c(coeffs_lean$adm_cd, coeffs_ext$adm_cd))
shp_adm_cd <- shp4326$adm_cd
matched   <- intersect(all_coeff_adm_cd, shp_adm_cd)
missing_cd <- setdiff(all_coeff_adm_cd, shp_adm_cd)
extra_cd   <- setdiff(shp_adm_cd, all_coeff_adm_cd)

match_pct <- 100 * length(matched) / length(all_coeff_adm_cd)
log("[3] Coefficients unique adm_cd = %d ; SHP adm_cd = %d ; matched = %d (%.2f%%)",
    length(all_coeff_adm_cd), length(shp_adm_cd), length(matched), match_pct)
if (length(missing_cd) > 0) {
  log("[3] Coefficient adm_cd MISSING a geometry (%d): %s",
      length(missing_cd), paste(head(missing_cd, 10), collapse = ", "))
}
if (length(extra_cd) > 0) {
  log("[3] SHP adm_cd with no coefficients (%d): %s",
      length(extra_cd), paste(head(extra_cd, 10), collapse = ", "))
}

# ---------------------------------------------------------------------------
# 4. Write GeoJSON. Properties: adm_cd, adm_nm (== ADSTRD_NM).
#    Other lookup fields (gu_name, living_area) are joined into lookup.json so
#    the GeoJSON stays light; the backend merges them at request time.
# ---------------------------------------------------------------------------
shp_out <- shp4326[, c("adm_cd", "ADSTRD_NM")]
names(shp_out)[2] <- "adm_nm"
geojson_path <- file.path(out_geojson_dir, "seoul_adm_dong.geojson")
st_write(
  shp_out, geojson_path,
  driver = "GeoJSON",
  delete_dsn = TRUE,
  quiet = TRUE
)
log("[4] Wrote %s (%d features, EPSG:4326)", geojson_path, nrow(shp_out))

# ---------------------------------------------------------------------------
# 4b. Build seoul_gu.geojson (Dissolved outer boundaries of 25 autonomous districts)
# ---------------------------------------------------------------------------
lookup_raw <- read.csv(
  file.path(out_tables, "adm_region_lookup.csv"),
  colClasses = "character"
)
shp_with_gu <- merge(shp4326, lookup_raw[, c("adm_cd", "gu_name", "living_area")], by = "adm_cd", all.x = TRUE)
gu_shp <- shp_with_gu %>%
  group_by(gu_name, living_area) %>%
  summarize(geometry = st_union(geometry), .groups = "drop")

gu_geojson_path <- file.path(out_geojson_dir, "seoul_gu.geojson")
st_write(
  gu_shp, gu_geojson_path,
  driver = "GeoJSON",
  delete_dsn = TRUE,
  quiet = TRUE
)
log("[4b] Wrote %s (%d district boundary features)", gu_geojson_path, nrow(gu_shp))

# ---------------------------------------------------------------------------
# 4c. Build seoul_outer_mask.geojson (World polygon with unified Seoul hole)
# ---------------------------------------------------------------------------
seoul_unified <- st_union(st_geometry(shp4326))
world_poly <- st_polygon(list(matrix(
  c(-180, -90,
     180, -90,
     180,  90,
    -180,  90,
    -180, -90),
  ncol = 2, byrow = TRUE
)))
world_sfc <- st_sfc(world_poly, crs = 4326)
seoul_mask <- st_difference(world_sfc, seoul_unified)
seoul_mask_sf <- st_sf(geometry = seoul_mask)

mask_geojson_path <- file.path(out_geojson_dir, "seoul_outer_mask.geojson")
st_write(
  seoul_mask_sf, mask_geojson_path,
  driver = "GeoJSON",
  delete_dsn = TRUE,
  quiet = TRUE
)
log("[4c] Wrote %s (unified outer mask)", mask_geojson_path)

# ---------------------------------------------------------------------------
# 5. Build lookup.json (adm_cd -> {adm_nm, gu_name, living_area, ...})
# ---------------------------------------------------------------------------
lookup <- read.csv(
  file.path(out_tables, "adm_region_lookup.csv"),
  colClasses = "character"
)
lookup_list <- setNames(
  lapply(seq_len(nrow(lookup)), function(i) as.list(lookup[i, ])),
  lookup$adm_cd
)
write_json(lookup_list, file.path(out_json_dir, "lookup.json"), auto_unbox = TRUE, na = "null")
log("[5] Wrote lookup.json (%d entries)", length(lookup_list))

# ---------------------------------------------------------------------------
# 6. coefficients_{lean,extended}.json — per-control_set, then nested
#    outcome -> adm_cd -> estimate + metadata. Compact representation for the
#    FastAPI loader.
# ---------------------------------------------------------------------------
build_coefficients_nested <- function(df) {
  nested <- list()
  outcomes <- unique(df$outcome)
  for (oc in outcomes) {
    sub <- df[df$outcome == oc, ]
    by_adm <- setNames(
      lapply(sub$adm_cd, function(cd) {
        row <- sub[sub$adm_cd == cd, ]
        # Convert numerics from character
        as_num <- function(x) suppressWarnings(as.numeric(x))
        list(
          adm_cd       = row$adm_cd,
          outcome       = row$outcome,
          focal_var     = row$focal_var,
          estimate      = as_num(row$estimate),
          earliest_estimate = as_num(row$earliest_estimate),
          latest_estimate   = as_num(row$latest_estimate),
          earliest_yq   = row$earliest_yq,
          latest_yq     = row$latest_yq,
          target_yq     = row$target_yq,
          estimate_type = row$estimate_type,
          control_set   = row$control_set,
          method        = row$method,
          n_obs         = suppressWarnings(as.integer(row$n_obs)),
          n_eff         = as_num(row$n_eff),
          bw_obs_n      = suppressWarnings(as.integer(row$bw_obs_n)),
          local_cn_gtwr_earliest = as_num(row$local_cn_gtwr_earliest),
          local_cn_gtwr_latest   = as_num(row$local_cn_gtwr_latest),
          collinearity_warn_latest = as.logical(row$collinearity_warn_latest),
          collinearity_warn_flag   = as.logical(row$collinearity_warn_flag),
          status        = row$status,
          message       = row$message,
          collinearity_diag_message = row$collinearity_diag_message
        )
      }),
      sub$adm_cd
    )
    nested[[oc]] <- by_adm
  }
  nested
}

write_coeffs <- function(control_set, df) {
  nested <- build_coefficients_nested(df)
  out <- file.path(out_json_dir, sprintf("coefficients_%s.json", control_set))
  write_json(nested, out, auto_unbox = TRUE, pretty = FALSE, na = "null")
  log("[6] Wrote %s (%d outcomes)", out, length(nested))
}
write_coeffs("lean", coeffs_lean)
write_coeffs("extended", coeffs_ext)

# ---------------------------------------------------------------------------
# 7. summary_{lean,extended}.json — per-outcome global summary row from
#    gtwr_main_models_*.csv. We surface a curated subset of columns.
# ---------------------------------------------------------------------------
SUMMARY_COLS <- c(
  "method", "outcome", "focal_var", "target_yq", "estimate_type",
  "earliest_yq", "latest_yq", "n_locations", "n_valid",
  "mean_beta", "sd_beta", "p25_beta", "p50_beta", "p75_beta",
  "share_positive", "st_bw",
  "global_lm_r2", "global_lm_r2_adj",
  "gtw_aic", "gtw_aicc", "gtw_enp", "gtw_edf",
  "collinearity_warn_n", "collinearity_warn_share",
  "latest_missing_n", "latest_coverage_share", "max_local_cn_gtwr",
  "control_set", "outcome_group", "outcome_order"
)
build_summary <- function(control_set) {
  df <- read.csv(
    file.path(out_tables, sprintf("gtwr_main_models_%s.csv", control_set)),
    colClasses = "character"
  )
  df <- df[df$method == "GWmodel::gtwr", ]
  keep <- intersect(SUMMARY_COLS, names(df))
  res <- lapply(seq_len(nrow(df)), function(i) {
    out_row <- as.list(df[i, keep])
    num_cols <- c("mean_beta","sd_beta","p25_beta","p50_beta","p75_beta",
                   "share_positive","st_bw","global_lm_r2","global_lm_r2_adj",
                   "gtw_aic","gtw_aicc","gtw_enp","gtw_edf",
                   "collinearity_warn_share","latest_coverage_share",
                   "max_local_cn_gtwr")
    for (col in intersect(num_cols, names(out_row))) {
      out_row[[col]] <- suppressWarnings(as.numeric(out_row[[col]]))
    }
    int_cols <- c("n_locations","n_valid","collinearity_warn_n","latest_missing_n","outcome_order")
    for (col in intersect(int_cols, names(out_row))) {
      out_row[[col]] <- suppressWarnings(as.integer(out_row[[col]]))
    }
    out_row
  })
  out <- file.path(out_json_dir, sprintf("summary_%s.json", control_set))
  write_json(res, out, auto_unbox = TRUE, pretty = FALSE, na = "null")
  log("[7] Wrote %s (%d outcomes)", out, length(res))
}
build_summary("lean")
build_summary("extended")

# ---------------------------------------------------------------------------
# 7b. panel_{lean,extended}.json & quarter_estimates_{lean,extended}.json
#     Enables 100% pure static mode (Cloudflare/GitHub Pages) without backend
# ---------------------------------------------------------------------------
build_panel_json <- function(control_set) {
  panel_csv <- file.path(out_tables, sprintf("gtwr_local_beta_panel_%s.csv", control_set))
  df <- read.csv(panel_csv, colClasses = "character")
  as_num <- function(x) suppressWarnings(as.numeric(x))
  as_int <- function(x) suppressWarnings(as.integer(x))
  
  # 1. adm_cd -> outcome -> list of points
  by_adm_outcome <- list()
  adms <- unique(df$adm_cd)
  outcomes <- unique(df$outcome)
  
  # 2. outcome -> yq -> adm_cd -> estimate (for instant quarter map switching)
  quarter_map <- list()
  for (oc in outcomes) {
    quarter_map[[oc]] <- list()
    df_oc <- df[df$outcome == oc, ]
    yqs <- unique(df_oc$yq)
    for (yq_val in yqs) {
      sub_yq <- df_oc[df_oc$yq == yq_val, ]
      est_vec <- as.list(setNames(as_num(sub_yq$estimate), sub_yq$adm_cd))
      quarter_map[[oc]][[yq_val]] <- est_vec
    }
  }
  
  out_qmap <- file.path(out_json_dir, sprintf("quarter_estimates_%s.json", control_set))
  write_json(quarter_map, out_qmap, auto_unbox = TRUE, pretty = FALSE, na = "null")
  log("[7b] Wrote %s", out_qmap)

  # Group by adm_cd
  for (cd in adms) {
    sub_adm <- df[df$adm_cd == cd, ]
    by_adm_outcome[[cd]] <- list()
    for (oc in outcomes) {
      sub_oc <- sub_adm[sub_adm$outcome == oc, ]
      if (nrow(sub_oc) > 0) {
        pts <- lapply(seq_len(nrow(sub_oc)), function(i) {
          r <- sub_oc[i, ]
          list(
            adm_cd        = r$adm_cd,
            year          = as_int(r$year),
            quarter       = as_int(r$quarter),
            yq            = r$yq,
            quarter_index = as_int(r$quarter_index),
            time_id       = as_int(r$time_id),
            outcome       = r$outcome,
            focal_var     = r$focal_var,
            estimate      = as_num(r$estimate),
            estimate_type = r$estimate_type,
            control_set   = r$control_set,
            n_obs         = as_int(r$n_obs),
            n_eff         = as_num(r$n_eff),
            bw_obs_n      = as_int(r$bw_obs_n)
          )
        })
        by_adm_outcome[[cd]][[oc]] <- pts
      }
    }
  }
  out_panel <- file.path(out_json_dir, sprintf("panel_%s.json", control_set))
  write_json(by_adm_outcome, out_panel, auto_unbox = TRUE, pretty = FALSE, na = "null")
  log("[7b] Wrote %s (%d adms)", out_panel, length(by_adm_outcome))
}
build_panel_json("lean")
build_panel_json("extended")

# ---------------------------------------------------------------------------
# 8. _build_manifest.json — the coverage gate that the FastAPI lifespan reads.
# ---------------------------------------------------------------------------
# Break notes for the diverging color scale. Symmetric around zero using a
# single fixed domain computed across all (control_set × outcome) latest
# estimates so the colour scale stays comparable across views.
all_estimates <- as.numeric(c(coeffs_lean$estimate, coeffs_ext$estimate))
all_estimates <- all_estimates[is.finite(all_estimates)]
abs_q <- quantile(abs(all_estimates), probs = c(0.33, 0.67, 0.95), na.rm = TRUE)
max_abs <- max(abs(all_estimates), na.rm = TRUE)
breaks_estimate <- as.numeric(c(-max_abs, -abs_q[3], -abs_q[2], -abs_q[1], 0,
                                 abs_q[1], abs_q[2], abs_q[3], max_abs))

# Earliest-to-latest delta (latest_estimate - earliest_estimate) across all
# outcomes/control sets. Symmetric, zero-centred, own colour breaks.
delta_lean <- as.numeric(coeffs_lean$latest_estimate) - as.numeric(coeffs_lean$earliest_estimate)
delta_ext  <- as.numeric(coeffs_ext$latest_estimate)  - as.numeric(coeffs_ext$earliest_estimate)
delta_all  <- c(delta_lean, delta_ext)
delta_all  <- delta_all[is.finite(delta_all)]
delta_abs_q <- quantile(abs(delta_all), probs = c(0.33, 0.67, 0.95), na.rm = TRUE)
delta_max   <- max(abs(delta_all), na.rm = TRUE)
delta_breaks <- as.numeric(c(-delta_max, -delta_abs_q[3], -delta_abs_q[2], -delta_abs_q[1], 0,
                              delta_abs_q[1], delta_abs_q[2], delta_abs_q[3], delta_max))

delta_earliest_yq <- unique(coeffs_lean$earliest_yq)[1]
delta_latest_yq   <- unique(coeffs_lean$latest_yq)[1]

manifest <- list(
  generated_at        = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  project_root         = project_root,
  crs_out              = "EPSG:4326",
  crs_in               = st_crs(shp)$input,
  geojson_features     = nrow(shp4326),
  shp_file             = basename(shp_file),
  control_sets         = c("lean", "extended"),
  outcomes             = sort(unique(c(coeffs_lean$outcome, coeffs_ext$outcome))),
  focal_var            = unique(c(coeffs_lean$focal_var, coeffs_ext$focal_var)),
  target_yq            = sort(unique(c(coeffs_lean$target_yq, coeffs_ext$target_yq))),
  csv_adm_cd_total     = length(all_coeff_adm_cd),
  csv_adm_cd_matched   = length(matched),
  csv_adm_cd_match_percent = round(match_pct, 4),
  missing_adm_cd       = missing_cd,
  extra_adm_cd         = extra_cd,
  panel_quarters       = c("2019Q4", "2020Q1", "2020Q2", "2020Q3", "2020Q4",
                           "2021Q1", "2021Q2", "2021Q3", "2021Q4",
                           "2022Q1", "2022Q2", "2022Q3", "2022Q4",
                           "2023Q1", "2023Q2", "2023Q3", "2023Q4",
                           "2024Q1", "2024Q2", "2024Q3", "2024Q4",
                           "2025Q1", "2025Q2", "2025Q3", "2025Q4"),
  estimate_breaks      = breaks_estimate,
  delta_breaks         = delta_breaks,
  delta_earliest_yq    = delta_earliest_yq,
  delta_latest_yq      = delta_latest_yq,
  artifacts = list(
    geojson = "geojson/seoul_adm_dong.geojson",
    coefficients_lean = "json/coefficients_lean.json",
    coefficients_extended = "json/coefficients_extended.json",
    summary_lean = "json/summary_lean.json",
    summary_extended = "json/summary_extended.json",
    lookup = "json/lookup.json"
  )
)
write_json(manifest, out_manifest, auto_unbox = TRUE, pretty = TRUE, na = "null")
log("[8] Wrote %s", out_manifest)

# ---------------------------------------------------------------------------
# 8b. Sync artifacts to frontend/public/data for standalone static mode
# ---------------------------------------------------------------------------
public_data_dir <- file.path(web_dir, "frontend", "public", "data")
dir.create(file.path(public_data_dir, "geojson"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(public_data_dir, "json"),    recursive = TRUE, showWarnings = FALSE)

file.copy(geojson_path, file.path(public_data_dir, "geojson", "seoul_adm_dong.geojson"), overwrite = TRUE)
file.copy(gu_geojson_path, file.path(public_data_dir, "geojson", "seoul_gu.geojson"), overwrite = TRUE)
file.copy(mask_geojson_path, file.path(public_data_dir, "geojson", "seoul_outer_mask.geojson"), overwrite = TRUE)
file.copy(out_manifest, file.path(public_data_dir, "_build_manifest.json"), overwrite = TRUE)
json_files <- list.files(out_json_dir, pattern = "\\.json$", full.names = TRUE)
file.copy(json_files, file.path(public_data_dir, "json"), overwrite = TRUE)
log("[8b] Synced static data artifacts to frontend/public/data/")

# ---------------------------------------------------------------------------
# 9. Coverage gate — exit nonzero on any violation
# ---------------------------------------------------------------------------
ok <- TRUE
if (nrow(shp4326) != 425L) {
  message("GATE FAIL: geojson_features != 425 (got ", nrow(shp4326), ")")
  ok <- FALSE
}
if (length(matched) != length(all_coeff_adm_cd)) {
  message("GATE FAIL: csv_adm_cd_match_percent < 100 (got ", round(match_pct, 2), "%)")
  ok <- FALSE
}
if (!identical(st_crs(shp4326)$epsg, 4326L)) {
  message("GATE FAIL: output CRS is not WGS 84 / EPSG:4326 (got ", st_crs(shp4326)$input, ")")
  ok <- FALSE
}
if (!ok) {
  stop("build_data.R coverage gate FAILED. See messages above.")
}
log("[9] Coverage gate: OK (features=425, match=100%%, CRS=EPSG:4326)")
log("Done.")
