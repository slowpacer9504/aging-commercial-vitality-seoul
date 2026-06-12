#==============================================================================
# Script    : utils_io.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide shared helpers for directory creation, logging, and
#             standardized file IO across preprocessing and modeling scripts.
# Author    : Codex
# Created   : 2026-02-28
# Type      : utility
# Inputs    : file paths, data frames, R objects
# Outputs   : directories, logs, csv/parquet/rds files
# DependsOn : fs, readr, arrow
#==============================================================================

#==============================================================================
# 0. Small General Helpers
#==============================================================================

value_or <- function(x, default) {
  if (is.null(x) || length(x) == 0L) default else x
}

#==============================================================================
# 1. Directory and Log Helpers
#==============================================================================

ensure_dirs <- function(paths) {
  # Create required directories idempotently so downstream writes do not fail
  # because a parent folder is missing.
  invisible(lapply(paths, fs::dir_create))
}

append_log <- function(path, text) {
  # Logs are appended line-by-line to keep long pipeline runs inspectable after
  # failures or partial reruns.
  fs::dir_create(fs::path_dir(path))
  cat(text, file = path, append = TRUE, sep = "\n")
}

#==============================================================================
# 2. Safe Writers
#==============================================================================

build_atomic_temp_path <- function(path, suffix = ".tmp") {
  # Stage output in the destination directory so the final rename is simple and
  # stays on the same filesystem where possible.
  dir <- fs::path_dir(path)
  ext <- tools::file_ext(path)
  stem <- tools::file_path_sans_ext(basename(path))
  stamp <- paste0(Sys.getpid(), "_", format(Sys.time(), "%Y%m%d%H%M%OS6"))
  fileext <- if (nzchar(ext)) paste0(".", ext, suffix) else suffix
  tempfile(pattern = paste0(".", stem, "_", stamp, "_"), tmpdir = dir, fileext = fileext)
}

atomic_rename <- function(from, to) {
  # Promote the staged file only after the writer succeeds; a failed promotion
  # must stop the pipeline so stale outputs are not mistaken for new ones.
  ok <- isTRUE(file.rename(from, to))
  if (!ok) {
    stop(sprintf("[ERROR] Failed to promote staged file: %s -> %s", from, to), call. = FALSE)
  }
  invisible(to)
}

with_atomic_write <- function(path, write_fn) {
  # Shared safe-write wrapper for parquet, csv, and rds outputs consumed by
  # later scripts. Failed writes are cleaned up instead of leaving partial files.
  fs::dir_create(fs::path_dir(path))
  tmp <- build_atomic_temp_path(path)
  promoted <- FALSE

  on.exit({
    if (!promoted && file.exists(tmp)) {
      unlink(tmp)
    }
  }, add = TRUE)

  write_fn(tmp)
  atomic_rename(tmp, path)
  promoted <- TRUE
  invisible(path)
}

write_csv_safe <- function(x, path) {
  # Keep QC and review CSVs from being partially written during failed runs.
  with_atomic_write(path, function(tmp) readr::write_csv(x, tmp))
}

write_parquet_safe <- function(x, path) {
  # Canonical analysis parquet files use the same atomic-write contract.
  with_atomic_write(path, function(tmp) arrow::write_parquet(x, tmp))
}

save_rds_safe <- function(x, path) {
  # R-only objects, including listw and model outputs, follow the same safe save.
  with_atomic_write(path, function(tmp) saveRDS(x, tmp))
}


#==============================================================================
# 3. Korean CSV Reader
#==============================================================================

read_csv_kr <- function(path, encoding = NULL, ...) {
  enc <- encoding

  # Respect caller-specified encoding first, but default by OS to minimize
  # repeated boilerplate in raw-data ingestion scripts.
  if (is.null(enc)) {
    is_windows <- tolower(Sys.info()[["sysname"]]) == "windows"
    enc <- if (is_windows) "CP949" else "UTF-8"
  }

  readr::read_csv(path, locale = readr::locale(encoding = enc), show_col_types = FALSE, ...)
}


#==============================================================================
# 4. Miscellaneous Helpers
#==============================================================================

find_first_existing <- function(paths) {
  # Resolve path candidates in order for optional aliases and OS-specific paths.
  idx <- which(file.exists(paths))
  if (length(idx) == 0) return(NA_character_)
  paths[idx[1]]
}

timestamp <- function() {
  # Keep log timestamps in one project-wide format.
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
}

get_panel_main_view_cols <- function(view_name) {
  # Method-specific slim panels are read as projected views from `panel_main`
  # rather than being stored as separate intermediate files.
  specs <- cfg$panel_main_view_specs
  cols <- specs[[view_name]]
  if (is.null(cols)) {
    stop(sprintf("[ERROR] Unknown panel_main view spec: %s", view_name), call. = FALSE)
  }
  unique(cols)
}

get_analysis_yq_sequence <- function() {
  q_seq <- value_or(cfg$analysis_quarter_sequence$yq, character())
  q_seq <- unique(as.character(q_seq))
  q_seq[!is.na(q_seq) & nzchar(q_seq)]
}

filter_analysis_window <- function(data, enabled = TRUE) {
  if (!isTRUE(enabled) || !"yq" %in% names(data)) return(data)

  analysis_yq <- get_analysis_yq_sequence()
  if (length(analysis_yq) == 0L) return(data)

  data |>
    dplyr::filter(as.character(.data$yq) %in% analysis_yq)
}

read_panel_main_view <- function(view_name, extra_cols = NULL, path = cfg$paths$panel_main, analysis_window = TRUE) {
  # Arrow column projection implements each method-specific view while keeping a
  # single canonical `panel_main` parquet as the source of truth.
  cols <- unique(c(get_panel_main_view_cols(view_name), extra_cols))
  arrow::read_parquet(path, col_select = tidyselect::all_of(cols)) |>
    tibble::as_tibble() |>
    filter_analysis_window(enabled = analysis_window)
}
