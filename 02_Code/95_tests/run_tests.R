#!/usr/bin/env Rscript

#==============================================================================
# Script    : run_tests.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the numeric regression tests for the utility functions that
#             produce reported quantities, and exit non-zero on any failure.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-04
# Type      : qc
# Inputs    : 02_Code/95_tests/test_*.R; optionally 03_Output/01_Tables for the
#             published-output regression checks, which skip when absent
# Outputs   : console report; exit status 0 (pass) or 1 (fail)
# DependsOn : 00_setup/config.R, 00_setup/packages.R, 99_utils/*
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# The suite deliberately uses base R only. testthat is not in renv.lock, and a
# test harness is a poor reason to add a dependency to a pinned analysis
# environment. The three assertions below are all this suite needs.
options(scipen = 999)

suppressWarnings(suppressMessages({
  source(here::here("02_Code", "00_setup", "config.R"))
  source(here::here("02_Code", "00_setup", "packages.R"))
  load_project_packages()
  source(here::here("02_Code", "99_utils", "utils_io.R"))
  source(here::here("02_Code", "99_utils", "utils_spdm.R"))
  source(here::here("02_Code", "99_utils", "utils_gtwr_main.R"))
}))


#==============================================================================
# 1. Minimal Assertion Harness
#==============================================================================

.tests <- new.env(parent = emptyenv())
.tests$pass <- 0L
.tests$fail <- 0L
.tests$skip <- 0L
.tests$failures <- character(0)
.tests$context <- "(none)"

test_context <- function(name) {
  .tests$context <- name
  cat(sprintf("\n%s\n", name))
}

.record <- function(ok, label, detail = "") {
  if (isTRUE(ok)) {
    .tests$pass <- .tests$pass + 1L
    cat(sprintf("  PASS  %s\n", label))
  } else {
    .tests$fail <- .tests$fail + 1L
    .tests$failures <- c(.tests$failures, sprintf("[%s] %s%s", .tests$context, label,
                                                  if (nzchar(detail)) paste0(" -- ", detail) else ""))
    cat(sprintf("  FAIL  %s%s\n", label, if (nzchar(detail)) paste0("  <- ", detail) else ""))
  }
  invisible(ok)
}

expect_true <- function(cond, label) {
  ok <- isTRUE(tryCatch(isTRUE(cond), error = function(e) FALSE))
  .record(ok, label, if (!ok) "condition was not TRUE" else "")
}

expect_equal_num <- function(actual, expected, label, tol = 1e-9) {
  ok <- tryCatch({
    a <- as.numeric(actual); e <- as.numeric(expected)
    length(a) == length(e) && all(is.finite(a) == is.finite(e)) &&
      all(abs(a[is.finite(a)] - e[is.finite(e)]) <= tol)
  }, error = function(e) FALSE)
  detail <- if (!ok) {
    sprintf("actual=%s expected=%s tol=%g",
            paste(signif(suppressWarnings(as.numeric(actual)), 10), collapse = ","),
            paste(signif(suppressWarnings(as.numeric(expected)), 10), collapse = ","),
            tol)
  } else ""
  .record(ok, label, detail)
}

test_skip <- function(label, reason) {
  .tests$skip <- .tests$skip + 1L
  cat(sprintf("  SKIP  %s  <- %s\n", label, reason))
}


#==============================================================================
# 2. Run Test Files
#==============================================================================

test_dir <- here::here("02_Code", "95_tests")
test_files <- sort(list.files(test_dir, pattern = "^test_.*\\.R$", full.names = TRUE))

if (length(test_files) == 0L) {
  stop("[ERROR] no test files found in 02_Code/95_tests", call. = FALSE)
}

cat(sprintf("Running %d test file(s)\n", length(test_files)))

for (tf in test_files) {
  # Each file runs in its own environment so helper objects cannot leak between
  # files, matching the isolation run_all.R gives pipeline steps.
  env <- new.env(parent = globalenv())
  tryCatch(
    sys.source(tf, envir = env),
    error = function(e) {
      .tests$fail <- .tests$fail + 1L
      .tests$failures <- c(.tests$failures, sprintf("[%s] file aborted: %s", basename(tf), conditionMessage(e)))
      cat(sprintf("  FAIL  %s aborted: %s\n", basename(tf), conditionMessage(e)))
    }
  )
}


#==============================================================================
# 3. Report
#==============================================================================

cat(sprintf(
  "\n----------------------------------------\nPASS %d | FAIL %d | SKIP %d\n",
  .tests$pass, .tests$fail, .tests$skip
))

if (.tests$fail > 0L) {
  cat("\nFailures:\n")
  cat(sprintf("  - %s\n", .tests$failures), sep = "")
  quit(status = 1L)
}

cat("[ALL PASS]\n")
quit(status = 0L)
