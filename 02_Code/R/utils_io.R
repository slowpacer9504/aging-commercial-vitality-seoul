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
# 1. Directory and Log Helpers
#==============================================================================

ensure_dirs <- function(paths) {
  # Create required directories idempotently so downstream writes do not fail
  # because a parent folder is missing.
  # 폴더가 이미 있으면 그대로 두고, 없으면 만드는 idempotent helper다.
  # 스크립트 초반에 이 함수를 한 번 호출해 두면, 이후 write 단계에서는
  # 경로 존재 여부를 매번 다시 신경 쓰지 않아도 된다.
  invisible(lapply(paths, fs::dir_create))
}

append_log <- function(path, text) {
  # Logs are appended line-by-line to keep long pipeline runs inspectable after
  # failures or partial reruns.
  # 이 프로젝트는 실행 로그를 markdown/csv로 남겨서 rerun과 실패 원인
  # 추적이 가능하도록 한다.
  fs::dir_create(fs::path_dir(path))
  cat(text, file = path, append = TRUE, sep = "\n")
}

#==============================================================================
# 2. Safe Writers
#==============================================================================

build_atomic_temp_path <- function(path, suffix = ".tmp") {
  # 최종 파일에 바로 쓰지 않고 temp 파일에 먼저 기록하기 위한 경로 생성기.
  # 같은 디렉터리 안에서 임시 파일을 만들면 마지막 `rename`이 가장 단순하고 빠르다.
  dir <- fs::path_dir(path)
  ext <- tools::file_ext(path)
  stem <- tools::file_path_sans_ext(basename(path))
  stamp <- paste0(Sys.getpid(), "_", format(Sys.time(), "%Y%m%d%H%M%OS6"))
  fileext <- if (nzchar(ext)) paste0(".", ext, suffix) else suffix
  tempfile(pattern = paste0(".", stem, "_", stamp, "_"), tmpdir = dir, fileext = fileext)
}

atomic_rename <- function(from, to) {
  # temp 파일을 final path로 승격시키는 마지막 단계다.
  # 여기서 실패하면 저장이 완료되지 않은 것이므로 즉시 중단해
  # downstream이 오래된 파일을 새 산출물로 오인하지 않게 한다.
  ok <- isTRUE(file.rename(from, to))
  if (!ok) {
    stop(sprintf("[ERROR] Failed to promote staged file: %s -> %s", from, to), call. = FALSE)
  }
  invisible(to)
}

with_atomic_write <- function(path, write_fn) {
  # 파일 저장이 중간에 실패해도 반쯤 써진 산출물이 남지 않도록 하는
  # 공통 안전 래퍼다.
  # 이 프로젝트는 parquet/csv/rds를 여러 스크립트가 순차 소비하므로,
  # "존재는 하지만 깨진 파일"을 막는 것이 중요하다.
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
  # csv 저장도 atomic write를 강제해 QC 로그와 review 파일이 부분 저장되지 않게 한다.
  with_atomic_write(path, function(tmp) readr::write_csv(x, tmp))
}

write_parquet_safe <- function(x, path) {
  # 분석용 정본 parquet는 downstream 계약의 핵심이므로 가장 자주 쓰는 안전 writer다.
  with_atomic_write(path, function(tmp) arrow::write_parquet(x, tmp))
}

save_rds_safe <- function(x, path) {
  # listw, model object처럼 R 전용 객체 저장에도 같은 안전 규칙을 적용한다.
  with_atomic_write(path, function(tmp) saveRDS(x, tmp))
}


#==============================================================================
# 3. Korean CSV Reader
#==============================================================================

read_csv_kr <- function(path, encoding = NULL, ...) {
  enc <- encoding

  # Respect caller-specified encoding first, but default by OS to minimize
  # repeated boilerplate in raw-data ingestion scripts.
  # 한국 공공데이터는 CP949/UTF-8이 섞여 있어서 기본 인코딩 helper가
  # 있으면 raw source reader를 훨씬 단순하게 유지할 수 있다.
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
  # 후보 파일 경로가 여러 개일 때 첫 번째 존재 파일을 고르는 helper다.
  # optional output alias나 OS별 경로 차이를 흡수할 때 쓴다.
  idx <- which(file.exists(paths))
  if (length(idx) == 0) return(NA_character_)
  paths[idx[1]]
}

timestamp <- function() {
  # 로그 파일의 시각 표기를 프로젝트 전체에서 동일 형식으로 맞춘다.
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
}

get_panel_main_view_cols <- function(view_name) {
  # method-specific panel을 따로 저장하지 않는 대신, `panel_main`에서
  # 분석별 최소 열 목록을 가져온다.
  specs <- cfg$panel_main_view_specs
  cols <- specs[[view_name]]
  if (is.null(cols)) {
    stop(sprintf("[ERROR] Unknown panel_main view spec: %s", view_name), call. = FALSE)
  }
  unique(cols)
}

read_panel_main_view <- function(view_name, extra_cols = NULL, path = cfg$paths$panel_main) {
  # Arrow column projection으로 필요한 열만 읽는 lightweight reader다.
  # method별 slim panel 파일을 따로 만들지 않기 때문에,
  # 이 함수가 사실상 "panel_main의 method-specific view"를 구현한다.
  cols <- unique(c(get_panel_main_view_cols(view_name), extra_cols))
  arrow::read_parquet(path, col_select = tidyselect::all_of(cols)) |> tibble::as_tibble()
}
