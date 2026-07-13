#!/usr/bin/env Rscript

#==============================================================================
# Script    : run_all.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Orchestrate the end-to-end pipeline in the intended execution
#             order and write a stepwise run log.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-02-28
# Type      : reporting
# Inputs    : all upstream scripts and their declared input contracts;
#             KAKAO_REST_API_KEY, NAVER_CLIENT_ID, and NAVER_CLIENT_SECRET
#             when step 03 must geocode uncached records through Kakao and Naver APIs
#             (eg: Sys.setenv(KAKAO_REST_API_KEY = "key", NAVER_CLIENT_ID = "id", NAVER_CLIENT_SECRET = "secret"))
# Outputs   : model_run_log.md and all pipeline products
# DependsOn : all scripts listed in `scripts`
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# run_all only orchestrates the canonical scripts; each step keeps its own
# transformation or modeling contract and reports step-level status here.
options(scipen = 999)
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))

load_project_packages()
ensure_dirs(cfg$required_dirs)

append_log(cfg$logs$model_run, sprintf("\n# Pipeline Start: %s", timestamp()))


#==============================================================================
# 1. Ordered Pipeline Scripts
#==============================================================================

# The vector order is the canonical active pipeline order: quarterly panel,
# ESDA, TWFE, SPDM main, W robustness, robustness, QC, and reporting. Optional
# sidecars stay outside default run_all success and required test contracts.
# Fresh auxiliary geocoding requires KAKAO_REST_API_KEY, NAVER_CLIENT_ID, and NAVER_CLIENT_SECRET only when the
# existing cache files do not already resolve all needed addresses or queries.
scripts <- cfg$canonical_pipeline_scripts


#==============================================================================
# 2. Sequential Execution
#==============================================================================

# Each step runs in a child environment so script-local objects cannot overwrite
# orchestration state, while the log keeps a resumable audit trail.
run_pipeline_step <- function(sc) {
  abs <- here::here(sc)
  if (!file.exists(abs)) stop(sprintf("[ERROR] missing script: %s", sc), call. = FALSE)

  step_started_at <- Sys.time()
  append_log(cfg$logs$model_run, sprintf("\n## RUN %s (%s)", sc, timestamp()))

  # Evaluate each step in its own child environment so script-local objects do
  # not overwrite the orchestration state in run_all.R.
  step_env <- new.env(parent = globalenv())

  tryCatch(
    {
      # sys.source() reuses each script directly while isolating function and
      # intermediate-object definitions inside the step environment.
      sys.source(abs, envir = step_env)
      step_finished_at <- Sys.time()
      append_log(
        cfg$logs$model_run,
        sprintf(
          "- DONE: %s (%.2f sec)",
          sc,
          as.numeric(difftime(step_finished_at, step_started_at, units = "secs"))
        )
      )
    },
    error = function(e) {
      step_finished_at <- Sys.time()
      append_log(
        cfg$logs$model_run,
        sprintf(
          "- FAIL: %s (%.2f sec)",
          sc,
          as.numeric(difftime(step_finished_at, step_started_at, units = "secs"))
        )
      )
      append_log(cfg$logs$model_run, sprintf("- ERROR: %s", e$message))
      stop(e)
    }
  )
}

for (sc in scripts) {
  # Sequential execution is required because most steps consume the immediately
  # preceding canonical output.
  run_pipeline_step(sc)
}


#==============================================================================
# 3. Finalize Run Log
#==============================================================================

# The final log marker makes whole-pipeline success easy to audit manually.
append_log(cfg$logs$model_run, sprintf("\n# Pipeline End: %s", timestamp()))
message("[ALL DONE] Pipeline completed")
