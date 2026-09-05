#==============================================================================
# Script    : packages.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Load and validate the package set required by the project
#             pipeline, with optional per-script extensions.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-02-28
# Type      : config
# Inputs    : optional extra package vector
# Outputs   : attached packages, project-wide options
# DependsOn : base R package loading
#==============================================================================

#==============================================================================
# 0. Package Registry and Discovery
#==============================================================================

normalize_package_vector <- function(pkgs) {
  if (is.null(pkgs)) {
    return(character(0))
  }

  pkgs <- trimws(as.character(pkgs))
  pkgs <- pkgs[nzchar(pkgs)]
  sort(unique(pkgs))
}

project_attached_packages <- function() {
  c(
    "arrow", "broom", "classInt", "cli", "dplyr", "fixest", "fs", "ggplot2", "here",
    "janitor", "Kendall", "lubridate", "modelsummary", "purrr", "readr", "readxl", "sf",
    "sfdep", "spdep", "splm", "stringr", "tibble", "tidyr", "zoo"
  )
}

project_runtime_namespace_packages <- function() {
  # Namespace-only dependencies are validated before long preprocessing or
  # modeling scripts can fail late in the run. Only packages reachable from the
  # canonical pipeline belong here, because load_project_packages() validates
  # this list on every startup and a missing entry aborts the run.
  #
  # The list must include every `pkg::` dependency of cfg$canonical_pipeline_scripts
  # and of 99_utils, or the guard fails at exactly the case it exists to prevent:
  # MASS::mvrnorm backs the SPDM impact simulation and GWmodel backs a twelve-hour
  # GTWR fit, so discovering either is absent hours into a run is the worst outcome.
  # Sidecar-only dependencies (cowplot, data.table, scales) are deliberately
  # excluded so a partial install cannot block a canonical run; they are still
  # covered by validate_project_packages(scope = "full_strict"), which discovers
  # `pkg::` usage across the whole project.
  c(
    "rlang", "stringi", "tidyselect",
    "MASS", "GWmodel", "sp",
    "terra", "sf", "exactextractr", "sfnetworks", "tidygraph", "igraph",
    "httr", "jsonlite"
  )
}

project_base_packages <- function() {
  c(
    "base", "compiler", "datasets", "grDevices", "graphics", "grid", "methods",
    "parallel", "splines", "stats", "stats4", "tcltk", "tools", "utils"
  )
}

resolve_project_root_for_packages <- function() {
  if (exists("cfg", inherits = TRUE)) {
    cfg_obj <- get("cfg", inherits = TRUE)
    if (is.list(cfg_obj) && !is.null(cfg_obj$project_root) && dir.exists(cfg_obj$project_root)) {
      return(normalizePath(cfg_obj$project_root, winslash = "/", mustWork = TRUE))
    }
  }

  if (exists("project_root", inherits = TRUE)) {
    root <- get("project_root", inherits = TRUE)
    if (is.character(root) && length(root) == 1L && dir.exists(root)) {
      return(normalizePath(root, winslash = "/", mustWork = TRUE))
    }
  }

  if (file.exists(file.path("02_Code", "00_setup", "packages.R"))) {
    return(normalizePath(".", winslash = "/", mustWork = TRUE))
  }

  if (requireNamespace("here", quietly = TRUE)) {
    root <- tryCatch(
      normalizePath(here::here(), winslash = "/", mustWork = TRUE),
      error = function(e) NA_character_
    )
    if (!is.na(root) && dir.exists(root)) {
      return(root)
    }
  }

  stop(
    "[ERROR] Could not resolve project root for package discovery.",
    call. = FALSE
  )
}

discover_project_r_files <- function(root = resolve_project_root_for_packages()) {
  code_root <- file.path(root, "02_Code")
  if (!dir.exists(code_root)) {
    return(character(0))
  }

  list.files(code_root, pattern = "[.][Rr]$", recursive = TRUE, full.names = TRUE)
}

read_project_r_lines <- function(root = resolve_project_root_for_packages()) {
  files <- discover_project_r_files(root = root)
  if (length(files) == 0L) {
    return(character(0))
  }

  unlist(
    lapply(
      files,
      function(path) {
        tryCatch(
          readLines(path, warn = FALSE, encoding = "UTF-8"),
          error = function(e) character(0)
        )
      }
    ),
    use.names = FALSE
  )
}

discover_namespace_packages_in_lines <- function(lines) {
  if (length(lines) == 0L) {
    return(character(0))
  }

  matches <- regmatches(lines, gregexpr("[A-Za-z][A-Za-z0-9.]*::", lines, perl = TRUE))
  sub("::$", "", unlist(matches, use.names = FALSE))
}

discover_project_namespace_packages <- function(root = resolve_project_root_for_packages()) {
  # Discovery reads the R parser's own SYMBOL_PACKAGE tokens rather than
  # scanning raw text for `pkg::`. A text scan cannot tell code from prose, so
  # it collected package names out of comments and strings: the comment in
  # project_runtime_namespace_packages() that says "every `pkg::` dependency"
  # made "pkg" a package under scope = "full_strict", and install_packages.R
  # then aborted every run on a package that does not exist. The parser sees
  # only real namespace qualifications.
  files <- discover_project_r_files(root = root)
  if (length(files) == 0L) {
    return(character(0))
  }

  pkgs <- unlist(
    lapply(
      files,
      function(path) {
        parsed <- tryCatch(
          {
            pd <- utils::getParseData(parse(path, keep.source = TRUE, encoding = "UTF-8"))
            if (is.null(pd)) NULL else pd$text[pd$token == "SYMBOL_PACKAGE"]
          },
          error = function(e) NULL
        )

        # A file that cannot be parsed falls back to the old line scan. Over-
        # reporting one unparseable file is safer here than silently dropping
        # its dependencies from a strict install check.
        if (is.null(parsed)) {
          return(discover_namespace_packages_in_lines(
            tryCatch(readLines(path, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
          ))
        }

        gsub('^["`\']|["`\']$', "", parsed)
      }
    ),
    use.names = FALSE
  )

  setdiff(normalize_package_vector(pkgs), project_base_packages())
}

discover_declared_extra_packages <- function(root = resolve_project_root_for_packages()) {
  lines <- read_project_r_lines(root = root)
  if (length(lines) == 0L) {
    return(character(0))
  }

  load_lines <- grep("load_project_packages\\s*\\(", lines, value = TRUE, perl = TRUE)
  if (length(load_lines) == 0L) {
    return(character(0))
  }

  matches <- regmatches(load_lines, gregexpr("\"[A-Za-z][A-Za-z0-9.]*\"", load_lines, perl = TRUE))
  pkgs <- gsub("^\"|\"$", "", unlist(matches, use.names = FALSE))

  normalize_package_vector(pkgs)
}


#==============================================================================
# 1. Package Validation Helpers
#==============================================================================

get_project_packages <- function(scope = c("runtime", "full_strict"), extra = NULL) {
  scope <- match.arg(scope)

  runtime_pkgs <- normalize_package_vector(c(
    project_attached_packages(),
    project_runtime_namespace_packages(),
    extra
  ))

  if (identical(scope, "runtime")) {
    return(runtime_pkgs)
  }

  strict_pkgs <- normalize_package_vector(c(
    runtime_pkgs,
    discover_declared_extra_packages(),
    discover_project_namespace_packages()
  ))

  strict_pkgs
}

find_missing_project_packages <- function(scope = c("runtime", "full_strict"), extra = NULL) {
  scope <- match.arg(scope)
  pkgs <- get_project_packages(scope = scope, extra = extra)

  pkgs[!vapply(pkgs, requireNamespace, FUN.VALUE = logical(1), quietly = TRUE)]
}

validate_project_packages <- function(scope = c("runtime", "full_strict"), extra = NULL) {
  scope <- match.arg(scope)
  missing <- find_missing_project_packages(scope = scope, extra = extra)

  if (length(missing) > 0L) {
    stop(
      sprintf(
        "[ERROR] Missing packages for scope '%s': %s",
        scope,
        paste(missing, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(get_project_packages(scope = scope, extra = extra))
}


#==============================================================================
# 2. Package Loader
#==============================================================================

load_project_packages <- function(extra = NULL) {
  # Keep the attached set minimal; namespace-only dependencies are validated
  # without attachment to avoid unnecessary masking conflicts.
  attach_pkgs <- normalize_package_vector(c(project_attached_packages(), extra))

  missing <- find_missing_project_packages(scope = "runtime", extra = extra)
  if (length(missing) > 0L) {
    stop(sprintf("[ERROR] Missing packages: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }

  invisible(lapply(attach_pkgs, library, character.only = TRUE))
  options(scipen = 999)
  options(dplyr.summarise.inform = FALSE)
  invisible(attach_pkgs)
}
