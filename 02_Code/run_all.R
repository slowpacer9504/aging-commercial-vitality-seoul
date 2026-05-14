#!/usr/bin/env Rscript

#==============================================================================
# Script    : run_all.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Orchestrate the end-to-end pipeline in the intended execution
#             order and write a stepwise run log.
# Author    : Codex
# Created   : 2026-02-28
# Type      : reporting
# Inputs    : all upstream scripts and their declared input contracts;
#             Env: KAKAO_REST_API_KEY when step 05 must geocode uncached
#             records through the Kakao local API
#             (eg: Sys.setenv(KAKAO_REST_API_KEY = "your_kakao_rest_api_key"))
# Outputs   : model_run_log.md and all pipeline products
# DependsOn : all scripts listed in `scripts`
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# `run_all`은 각 스크립트의 내부 로직을 대체하지 않는다.
# 정해진 순서대로 호출하고, 각 단계의 성공/실패/소요시간을 로그에 남기는
# orchestration 역할만 맡는다.
options(scipen = 999)
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))

load_project_packages()
ensure_dirs(cfg$required_dirs)

append_log(cfg$logs$model_run, sprintf("\n# Pipeline Start: %s", timestamp()))


#==============================================================================
# 1. Ordered Pipeline Scripts
#==============================================================================

# 배열 순서 자체가 canonical pipeline order다.
# default run은 active annual panel -> ESDA -> TWFE -> SPDM main ->
# SPDM channel path -> robustness -> QC -> reporting 흐름에 설정된 optional sidecar를 append한다.
# appendix interaction families,
# manual QC scripts in 06_qc, and retired GTWR/GWR appendix families는
# repo에 남아 있어도 default success contract에 포함하지 않는다.
# Living-population inflow build는 월별 ZIP 처리 비용이 크므로 default에서는
# 실행하지 않고, RUN_LIVING_POP_INFLOW=TRUE일 때만 auxiliary build 다음에 삽입한다.
# resident-only GTWR는 비용이 큰 local-analysis sidecar이므로
# cfg$run_gtwr_main_sidecar 값에 따라 main pipeline에 conditionally append한다.
# Fresh auxiliary geocoding requires KAKAO_REST_API_KEY only when the
# existing cache files do not already resolve all needed addresses or queries.
scripts <- cfg$canonical_pipeline_scripts

if (isTRUE(cfg$run_living_pop_inflow)) {
  insert_after <- match("02_Code/01_preprocess/03_build_auxiliary_covariates.R", scripts)
  if (is.na(insert_after)) {
    scripts <- c(cfg$optional_sidecar_scripts$living_pop_inflow, scripts)
  } else {
    scripts <- append(scripts, cfg$optional_sidecar_scripts$living_pop_inflow, after = insert_after)
  }
}

if (isTRUE(cfg$run_gtwr_main_sidecar)) {
  insert_after <- match("02_Code/04_robustness/01_run_spdm_w_robustness.R", scripts)
  if (is.na(insert_after)) {
    scripts <- c(scripts, cfg$optional_sidecar_scripts$gtwr_main)
  } else {
    scripts <- append(scripts, cfg$optional_sidecar_scripts$gtwr_main, after = insert_after)
  }
}


#==============================================================================
# 2. Sequential Execution
#==============================================================================

# 각 스텝을 별도 child environment에서 실행하는 이유는,
# 스크립트 내부 객체가 `run_all` 상태를 덮어쓰지 않게 하기 위해서다.
# 또한 step별 성공/실패를 개별 로그 row로 남겨야,
# 긴 파이프라인이 중간에서 멈춰도 어느 지점까지 끝났는지 바로 확인할 수 있다.
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
      # `sys.source()`를 쓰면 각 스크립트를 그대로 재사용하면서도,
      # 함수 정의/중간 객체를 현재 orchestration 환경과 분리할 수 있다.
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
  # 순차 실행을 강제하는 이유는, 대부분의 스크립트가 바로 앞 단계의
  # canonical output을 입력으로 삼기 때문이다.
  run_pipeline_step(sc)
}


#==============================================================================
# 3. Finalize Run Log
#==============================================================================

# 최종 로그는 사람이 파이프라인 전체 성공 여부를 훑어보는 audit trail이다.
append_log(cfg$logs$model_run, sprintf("\n# Pipeline End: %s", timestamp()))
message("[ALL DONE] Pipeline completed")
