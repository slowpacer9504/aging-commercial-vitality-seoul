#!/usr/bin/env Rscript

#==============================================================================
# Script    : install_packages.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Install and strictly validate the full project package set for
#             a fresh Windows R / RStudio environment before running the
#             analytical pipeline.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-04-03
# Type      : config
# Inputs    : packages.R, CRAN access
# Outputs   : installed R packages in the active library path
# DependsOn : base R package installation
#==============================================================================

#==============================================================================
# 0. Script Path and Project Root Resolution
#==============================================================================

resolve_install_script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) > 0L) {
    return(normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = TRUE))
  }

  frame_files <- Filter(
    nzchar,
    vapply(
      sys.frames(),
      function(x) {
        if (!is.null(x$ofile)) as.character(x$ofile) else ""
      },
      FUN.VALUE = character(1)
    )
  )
  if (length(frame_files) > 0L) {
    return(normalizePath(frame_files[[length(frame_files)]], winslash = "/", mustWork = TRUE))
  }

  fallback <- file.path("02_Code", "00_setup", "install_packages.R")
  if (file.exists(fallback)) {
    return(normalizePath(fallback, winslash = "/", mustWork = TRUE))
  }

  stop(
    "[ERROR] Could not resolve install_packages.R path. Run it from the project root or use an absolute path.",
    call. = FALSE
  )
}

script_path <- resolve_install_script_path()
project_root <- normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/", mustWork = TRUE)
packages_script <- file.path(project_root, "02_Code", "00_setup", "packages.R")
source(packages_script, chdir = FALSE)


#==============================================================================
# 1. Strict Package Installation
#==============================================================================

format_package_block <- function(pkgs) {
  if (length(pkgs) == 0L) {
    return("- (none)")
  }
  paste(sprintf("- %s", pkgs), collapse = "\n")
}

local_repo_options <- options(repos = c(CRAN = "https://cran.rstudio.com"))
on.exit(options(local_repo_options), add = TRUE)

scope <- "full_strict"
requested_pkgs <- get_project_packages(scope = scope)
installed_before <- rownames(installed.packages())
already_installed <- requested_pkgs[requested_pkgs %in% installed_before]
missing_before <- requested_pkgs[!requested_pkgs %in% installed_before]

cat(sprintf("[INFO] Project root: %s\n", project_root))
cat(sprintf("[INFO] Package scope: %s\n", scope))
cat(sprintf("[INFO] CRAN mirror: %s\n", getOption("repos")[["CRAN"]]))

install_error <- NULL
if (length(missing_before) > 0L) {
  cat(sprintf("[INSTALL] Installing %d missing packages...\n", length(missing_before)))
  tryCatch(
    install.packages(missing_before, dependencies = TRUE),
    error = function(e) {
      install_error <<- conditionMessage(e)
    }
  )
} else {
  cat("[INSTALL] No missing packages detected.\n")
}


#==============================================================================
# 2. Final Validation and Summary
#==============================================================================

missing_after <- find_missing_project_packages(scope = scope)
newly_installed <- missing_before[!missing_before %in% missing_after]
failed_pkgs <- missing_before[missing_before %in% missing_after]

cat("\n[SUMMARY] Already installed\n")
cat(format_package_block(already_installed), "\n", sep = "")
cat("\n[SUMMARY] Newly installed\n")
cat(format_package_block(newly_installed), "\n", sep = "")
cat("\n[SUMMARY] Failed or still missing\n")
cat(format_package_block(failed_pkgs), "\n", sep = "")

if (length(failed_pkgs) > 0L) {
  error_suffix <- if (!is.null(install_error) && nzchar(install_error)) {
    sprintf(" | install.packages error: %s", install_error)
  } else {
    ""
  }
  stop(
    sprintf(
      "[ERROR] Package installation incomplete. Missing packages: %s%s",
      paste(failed_pkgs, collapse = ", "),
      error_suffix
    ),
    call. = FALSE
  )
}

validate_project_packages(scope = scope)
cat("\n[DONE] Full strict project package validation passed.\n")
