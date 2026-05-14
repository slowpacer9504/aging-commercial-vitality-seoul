#==============================================================================
# Script    : utils_model.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide shared helpers for TWFE estimation, control screening,
#             and model-output tidying.
# Author    : Codex
# Created   : 2026-02-28
# Type      : utility
# Inputs    : panel data frames, model variable names, model lists
# Outputs   : fitted models or tidy coefficient tables
# DependsOn : fixest, broom, dplyr, purrr, tibble
#==============================================================================

#==============================================================================
# 1. TWFE Estimation Helpers
#==============================================================================

# 이 helper 파일은 모델 스크립트들이 공통으로 쓰는 최소 함수만 둔다.
# 스펙 선택 로직은 각 스크립트에 남기고, 여기서는 “주어진 입력으로
# 안전하게 추정/선별/정리하는 일”만 맡는다.
value_or <- function(x, default) {
  if (is.null(x) || length(x) == 0L) default else x
}

collapse_chr <- function(x) {
  vals <- unique(as.character(x))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  if (length(vals) == 0L) return(NA_character_)
  paste(vals, collapse = ";")
}

has_group_variation <- function(data, var, group_var, min_sd = 1e-8) {
  if (!all(c(var, group_var) %in% names(data))) return(FALSE)

  x <- suppressWarnings(as.numeric(data[[var]]))
  grp <- data[[group_var]]
  ok <- is.finite(x) & !is.na(grp)
  if (sum(ok) < 2L) return(FALSE)

  split_x <- split(x[ok], grp[ok])
  any(vapply(split_x, function(v) {
    vv <- v[is.finite(v)]
    if (length(vv) < 2L) return(FALSE)
    sdx <- stats::sd(vv, na.rm = TRUE)
    is.finite(sdx) && sdx > min_sd
  }, logical(1)))
}

screen_control_candidates <- function(data,
                                      candidates,
                                      min_finite = 500L,
                                      min_sd = 1e-8,
                                      fe_aware = FALSE,
                                      fe_unit = "adm_cd",
                                      fe_time = "year") {
  vars <- unique(as.character(candidates))
  if (length(vars) == 0L) return(tibble::tibble())

  purrr::map_dfr(vars, function(v) {
    if (!v %in% names(data)) {
      return(tibble::tibble(
        control = v,
        selected = FALSE,
        reason = "missing_from_data",
        finite_n = 0L,
        global_sd = NA_real_,
        has_within_unit_variation = if (fe_aware) FALSE else NA,
        has_within_time_variation = if (fe_aware) FALSE else NA,
        lacks_fe_identification = if (fe_aware) TRUE else NA
      ))
    }

    x <- suppressWarnings(as.numeric(data[[v]]))
    ok <- is.finite(x)
    finite_n <- sum(ok)
    global_sd <- if (finite_n >= 2L) stats::sd(x[ok], na.rm = TRUE) else NA_real_
    has_unit_var <- if (fe_aware) has_group_variation(data, v, fe_unit, min_sd = min_sd) else NA
    has_time_var <- if (fe_aware) has_group_variation(data, v, fe_time, min_sd = min_sd) else NA
    lacks_fe_id <- if (fe_aware) !(isTRUE(has_unit_var) && isTRUE(has_time_var)) else NA

    selected <- TRUE
    reason <- "selected"
    if (finite_n < min_finite) {
      selected <- FALSE
      reason <- "insufficient_finite"
    } else if (!is.finite(global_sd) || global_sd <= min_sd) {
      selected <- FALSE
      reason <- "near_zero_sd"
    } else if (fe_aware && !isTRUE(has_unit_var) && !isTRUE(has_time_var)) {
      selected <- FALSE
      reason <- "no_within_unit_or_time_variation"
    } else if (fe_aware && !isTRUE(has_unit_var)) {
      selected <- FALSE
      reason <- "no_within_unit_variation"
    } else if (fe_aware && !isTRUE(has_time_var)) {
      selected <- FALSE
      reason <- "no_within_time_variation"
    }

    tibble::tibble(
      control = v,
      selected = selected,
      reason = reason,
      finite_n = as.integer(finite_n),
      global_sd = global_sd,
      has_within_unit_variation = has_unit_var,
      has_within_time_variation = has_time_var,
      lacks_fe_identification = lacks_fe_id
    )
  })
}

build_twfe_formula <- function(outcome, exposure, controls = NULL, interaction = NULL) {
  rhs <- c(exposure, controls)
  if (!is.null(interaction)) rhs <- c(rhs, sprintf("%s:%s", exposure, interaction))
  stats::as.formula(sprintf("%s ~ %s | adm_cd + year", outcome, paste(rhs, collapse = " + ")))
}

build_twfe_sample <- function(data, outcome, exposure, controls = NULL, interaction = NULL) {
  need <- unique(c("adm_cd", "year", outcome, exposure, controls, interaction))
  need <- need[!is.na(need) & nzchar(need)]
  keep <- stats::complete.cases(data[, intersect(need, names(data)), drop = FALSE])
  data[keep, , drop = FALSE]
}

build_twfe_formula_multi <- function(outcome, exposures, controls = NULL, interaction = NULL) {
  exposure_vec <- unique(as.character(exposures))
  exposure_vec <- exposure_vec[!is.na(exposure_vec) & nzchar(exposure_vec)]
  rhs <- c(exposure_vec, controls)
  if (!is.null(interaction)) rhs <- c(rhs, sprintf("%s:%s", exposure_vec, interaction))
  stats::as.formula(sprintf("%s ~ %s | adm_cd + year", outcome, paste(rhs, collapse = " + ")))
}

build_twfe_sample_multi <- function(data, outcome, exposures, controls = NULL, interaction = NULL) {
  exposure_vec <- unique(as.character(exposures))
  exposure_vec <- exposure_vec[!is.na(exposure_vec) & nzchar(exposure_vec)]
  need <- unique(c("adm_cd", "year", outcome, exposure_vec, controls, interaction))
  need <- need[!is.na(need) & nzchar(need)]
  keep <- stats::complete.cases(data[, intersect(need, names(data)), drop = FALSE])
  data[keep, , drop = FALSE]
}

set_twfe_meta <- function(model,
                          outcome,
                          exposure,
                          requested_controls,
                          retained_controls,
                          dropped_terms,
                          interaction,
                          initial_nobs) {
  model$twfe_meta <- list(
    outcome = outcome,
    exposure = collapse_chr(exposure),
    requested_controls = requested_controls,
    retained_controls = retained_controls,
    dropped_collinear_controls = intersect(dropped_terms, requested_controls),
    dropped_collinear_terms = dropped_terms,
    interaction_var = value_or(interaction, NA_character_),
    initial_nobs = as.integer(initial_nobs),
    nobs = suppressWarnings(as.integer(stats::nobs(model)))
  )
  model
}

model_meta_tibble <- function(model) {
  meta <- value_or(model$twfe_meta, list())
  tibble::tibble(
    outcome = value_or(meta$outcome, NA_character_),
    exposure = value_or(meta$exposure, NA_character_),
    nobs = suppressWarnings(as.integer(value_or(meta$nobs, stats::nobs(model)))),
    initial_nobs = suppressWarnings(as.integer(value_or(meta$initial_nobs, NA_integer_))),
    requested_controls = collapse_chr(value_or(meta$requested_controls, character(0))),
    retained_controls = collapse_chr(value_or(meta$retained_controls, character(0))),
    dropped_collinear_controls = collapse_chr(value_or(meta$dropped_collinear_controls, character(0))),
    dropped_collinear_terms = collapse_chr(value_or(meta$dropped_collinear_terms, character(0))),
    interaction_var = value_or(meta$interaction_var, NA_character_)
  )
}

get_outcome_registry <- function(requested_outcomes = NULL, include_robustness = TRUE) {
  reg <- value_or(cfg$outcome_registry, data.frame(
    outcome = character(),
    outcome_group = character(),
    outcome_order = integer(),
    stringsAsFactors = FALSE
  ))
  reg <- tibble::as_tibble(reg)

  if (!isTRUE(include_robustness)) {
    reg <- reg |>
      dplyr::filter(!outcome_group %in% c("appendix_component", "supplementary_vitality_robustness"))
  }
  if (!is.null(requested_outcomes) && length(requested_outcomes) > 0L) {
    reg <- reg |>
      dplyr::filter(outcome %in% unique(as.character(requested_outcomes)))
  }

  reg |>
    dplyr::arrange(outcome_order)
}

resolve_model_outcomes <- function(data_or_names, requested_outcomes = NULL, include_robustness = TRUE) {
  available_names <- if (is.data.frame(data_or_names)) names(data_or_names) else as.character(data_or_names)

  get_outcome_registry(
    requested_outcomes = requested_outcomes,
    include_robustness = include_robustness
  ) |>
    dplyr::filter(outcome %in% available_names) |>
    dplyr::arrange(outcome_order)
}

annotate_outcomes <- function(df, include_robustness = TRUE) {
  if (!"outcome" %in% names(df)) return(df)

  df |>
    dplyr::left_join(
      get_outcome_registry(include_robustness = include_robustness),
      by = "outcome"
    )
}

run_twfe <- function(data, outcome, exposure, controls = NULL, interaction = NULL) {
  # 이 helper는 "이미 결정된 한 specification"을 실제 `feols` 호출로 옮긴다.
  # 스펙 선택 자체는 호출 스크립트가 맡고, 여기서는
  # 1) RHS 조립
  # 2) complete-case 표본 제한
  # 3) FE 회귀 실행
  # 4) 실패 시 NULL 반환
  # 까지만 처리한다.
  requested_controls <- unique(intersect(as.character(value_or(controls, character(0))), names(data)))
  retained_controls <- requested_controls
  initial_d <- build_twfe_sample(data, outcome, exposure, requested_controls, interaction)
  initial_nobs <- nrow(initial_d)

  # usable row가 너무 적으면 무리하게 적합하지 않고 NULL을 반환해
  # 호출 스크립트가 해당 스펙을 건너뛰게 한다.
  if (initial_nobs < 50) return(NULL)

  dropped_terms <- character()
  fit <- NULL

  for (iter in seq_len(20L)) {
    d <- build_twfe_sample(data, outcome, exposure, retained_controls, interaction)
    if (nrow(d) < 50) return(NULL)

    # 모든 메인 FE 회귀는 `adm_cd + year` 고정효과를 공유한다.
    # 따라서 helper 수준에서 FE 구조를 통일해 두면 스크립트별 drift를 줄일 수 있다.
    fm <- build_twfe_formula(outcome, exposure, retained_controls, interaction)

    fit <- tryCatch(
      fixest::feols(fm, data = d, cluster = ~ adm_cd, data.save = TRUE),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)

    collin_terms <- unique(as.character(value_or(fit$collin.var, character(0))))
    collin_terms <- collin_terms[!is.na(collin_terms) & nzchar(collin_terms)]
    dropped_terms <- unique(c(dropped_terms, collin_terms))

    if (exposure %in% collin_terms) return(NULL)

    dropped_controls_iter <- intersect(collin_terms, retained_controls)
    if (length(dropped_controls_iter) == 0L) {
      return(set_twfe_meta(
        fit,
        outcome = outcome,
        exposure = exposure,
        requested_controls = requested_controls,
        retained_controls = retained_controls,
        dropped_terms = dropped_terms,
        interaction = interaction,
        initial_nobs = initial_nobs
      ))
    }

    retained_controls <- setdiff(retained_controls, dropped_controls_iter)
    if (length(retained_controls) == 0L && length(dropped_controls_iter) > 0L) {
      # 모든 control이 FE에서 떨어지면 control 없는 spec으로 한 번 더 재추정한다.
      next
    }
  }

  set_twfe_meta(
    fit,
    outcome = outcome,
    exposure = exposure,
    requested_controls = requested_controls,
    retained_controls = retained_controls,
    dropped_terms = dropped_terms,
    interaction = interaction,
    initial_nobs = initial_nobs
  )
}

run_twfe_multi <- function(data, outcome, exposures, controls = NULL, interaction = NULL) {
  exposure_vec <- unique(intersect(as.character(value_or(exposures, character(0))), names(data)))
  requested_controls <- unique(intersect(as.character(value_or(controls, character(0))), names(data)))
  retained_controls <- requested_controls
  initial_d <- build_twfe_sample_multi(data, outcome, exposure_vec, requested_controls, interaction)
  initial_nobs <- nrow(initial_d)

  if (length(exposure_vec) == 0L || initial_nobs < 50L) return(NULL)

  dropped_terms <- character()
  fit <- NULL

  for (iter in seq_len(20L)) {
    d <- build_twfe_sample_multi(data, outcome, exposure_vec, retained_controls, interaction)
    if (nrow(d) < 50L) return(NULL)

    fm <- build_twfe_formula_multi(outcome, exposure_vec, retained_controls, interaction)

    fit <- tryCatch(
      fixest::feols(fm, data = d, cluster = ~ adm_cd, data.save = TRUE),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)

    collin_terms <- unique(as.character(value_or(fit$collin.var, character(0))))
    collin_terms <- collin_terms[!is.na(collin_terms) & nzchar(collin_terms)]
    dropped_terms <- unique(c(dropped_terms, collin_terms))

    if (length(intersect(exposure_vec, collin_terms)) > 0L) return(NULL)

    dropped_controls_iter <- intersect(collin_terms, retained_controls)
    if (length(dropped_controls_iter) == 0L) {
      return(set_twfe_meta(
        fit,
        outcome = outcome,
        exposure = exposure_vec,
        requested_controls = requested_controls,
        retained_controls = retained_controls,
        dropped_terms = dropped_terms,
        interaction = interaction,
        initial_nobs = initial_nobs
      ))
    }

    retained_controls <- setdiff(retained_controls, dropped_controls_iter)
    if (length(retained_controls) == 0L && length(dropped_controls_iter) > 0L) {
      next
    }
  }

  set_twfe_meta(
    fit,
    outcome = outcome,
    exposure = exposure_vec,
    requested_controls = requested_controls,
    retained_controls = retained_controls,
    dropped_terms = dropped_terms,
    interaction = interaction,
    initial_nobs = initial_nobs
  )
}


#==============================================================================
# 2. Control Screening
#==============================================================================

# control screening은 “이론적으로 필요한 후보” 중
# 실제 데이터 지원이 충분한 변수만 추리는 단계다.
# 분산이 거의 없거나 유효값이 너무 적으면 회귀를 불안정하게 만든다.
select_usable_controls <- function(data,
                                   candidates,
                                   min_finite = 500L,
                                   min_sd = 1e-8,
                                   fe_aware = FALSE,
                                   fe_unit = "adm_cd",
                                   fe_time = "year") {
  select_usable_controls_with_details(
    data,
    candidates,
    min_finite = min_finite,
    min_sd = min_sd,
    fe_aware = fe_aware,
    fe_unit = fe_unit,
    fe_time = fe_time
  ) |>
    dplyr::filter(selected) |>
    dplyr::pull(control)
}

select_usable_controls_with_details <- function(data,
                                                candidates,
                                                min_finite = 500L,
                                                min_sd = 1e-8,
                                                fe_aware = FALSE,
                                                fe_unit = "adm_cd",
                                                fe_time = "year") {
  screen_control_candidates(
    data,
    candidates,
    min_finite = min_finite,
    min_sd = min_sd,
    fe_aware = fe_aware,
    fe_unit = fe_unit,
    fe_time = fe_time
  )
}

is_overlap_outcome <- function(outcome,
                               registry = value_or(cfg$floating_exposure_overlap_outcomes, character())) {
  outcome_key <- as.character(value_or(outcome, NA_character_)[[1]])
  outcome_vals <- if (is.list(registry)) names(registry) else as.character(registry)
  outcome_vals <- outcome_vals[!is.na(outcome_vals) & nzchar(outcome_vals)]

  is.character(outcome_key) && !is.na(outcome_key) && nzchar(outcome_key) && outcome_key %in% outcome_vals
}

is_floating_share_var <- function(vars) {
  # Match canonical names such as `age60_floating_share` and age-mix variants
  # like `age20_floating_share`, while still allowing suffixed variants.
  grepl("(^|_)floating_share($|_)", as.character(value_or(vars, character(0))))
}

has_floating_share_exposure <- function(exposures) {
  vars <- unique(as.character(value_or(exposures, character(0))))
  vars <- vars[!is.na(vars) & nzchar(vars)]
  if (length(vars) == 0L) {
    return(FALSE)
  }
  any(is_floating_share_var(vars))
}

floating_overlap_skip_reason <- function(outcome,
                                         exposures,
                                         registry = value_or(cfg$floating_exposure_overlap_outcomes, character())) {
  if (!is_overlap_outcome(outcome, registry = registry) || !has_floating_share_exposure(exposures)) {
    return(NA_character_)
  }
  "not_estimated_floating_outcome_overlap"
}

floating_overlap_skip_message <- function(outcome,
                                          exposures,
                                          registry = value_or(cfg$floating_exposure_overlap_outcomes, character())) {
  reason <- floating_overlap_skip_reason(outcome, exposures, registry = registry)
  if (is.na(reason)) {
    return(NA_character_)
  }

  floating_vars <- unique(as.character(value_or(exposures, character(0))))
  floating_vars <- floating_vars[is_floating_share_var(floating_vars)]
  sprintf(
    "%s: %s uses floating-source outcome and floating-share exposure(s) %s",
    reason,
    as.character(outcome[[1]]),
    collapse_chr(floating_vars)
  )
}

should_skip_floating_overlap_spec <- function(outcome,
                                              exposures,
                                              registry = value_or(cfg$floating_exposure_overlap_outcomes, character())) {
  !is.na(floating_overlap_skip_reason(outcome, exposures, registry = registry))
}

screen_outcome_control_candidates <- function(data,
                                              outcome,
                                              candidates,
                                              min_finite = 500L,
                                              min_sd = 1e-8,
                                              fe_aware = FALSE,
                                              fe_unit = "adm_cd",
                                              fe_time = "year") {
  vars <- unique(as.character(candidates))
  vars <- vars[!is.na(vars) & nzchar(vars)]
  if (length(vars) == 0L) {
    return(tibble::tibble(
      control = character(),
      selected = logical(),
      reason = character(),
      finite_n = integer(),
      global_sd = numeric(),
      has_within_unit_variation = logical(),
      has_within_time_variation = logical(),
      lacks_fe_identification = logical()
    ))
  }

  screened <- select_usable_controls_with_details(
    data,
    vars,
    min_finite = min_finite,
    min_sd = min_sd,
    fe_aware = fe_aware,
    fe_unit = fe_unit,
    fe_time = fe_time
  )

  screened |>
    dplyr::mutate(control = as.character(control)) |>
    dplyr::arrange(match(control, vars))
}

select_outcome_controls_with_details <- function(data,
                                                 outcome,
                                                 candidates,
                                                 min_finite = 500L,
                                                 min_sd = 1e-8,
                                                 fe_aware = FALSE,
                                                 fe_unit = "adm_cd",
                                                 fe_time = "year") {
  screen_outcome_control_candidates(
    data,
    outcome,
    candidates,
    min_finite = min_finite,
    min_sd = min_sd,
    fe_aware = fe_aware,
    fe_unit = fe_unit,
    fe_time = fe_time
  )
}

select_outcome_controls <- function(data,
                                    outcome,
                                    candidates,
                                    min_finite = 500L,
                                    min_sd = 1e-8,
                                    fe_aware = FALSE,
                                    fe_unit = "adm_cd",
                                    fe_time = "year") {
  select_outcome_controls_with_details(
    data,
    outcome,
    candidates,
    min_finite = min_finite,
    min_sd = min_sd,
    fe_aware = fe_aware,
    fe_unit = fe_unit,
    fe_time = fe_time
  ) |>
    dplyr::filter(selected) |>
    dplyr::pull(control)
}

resolve_outcome_control_screen <- function(data,
                                           outcomes,
                                           candidates,
                                           min_finite = 500L,
                                           min_sd = 1e-8,
                                           fe_aware = FALSE,
                                           fe_unit = "adm_cd",
                                           fe_time = "year") {
  outcome_vals <- unique(as.character(value_or(outcomes, character())))
  outcome_vals <- outcome_vals[!is.na(outcome_vals) & nzchar(outcome_vals)]

  if (length(outcome_vals) == 0L) {
    return(tibble::tibble(
      outcome = character(),
      control = character(),
      selected = logical(),
      reason = character(),
      finite_n = integer(),
      global_sd = numeric(),
      has_within_unit_variation = logical(),
      has_within_time_variation = logical(),
      lacks_fe_identification = logical()
    ))
  }

  purrr::map_dfr(outcome_vals, function(outcome_nm) {
    select_outcome_controls_with_details(
      data,
      outcome = outcome_nm,
      candidates = candidates,
      min_finite = min_finite,
      min_sd = min_sd,
      fe_aware = fe_aware,
      fe_unit = fe_unit,
      fe_time = fe_time
    ) |>
      dplyr::mutate(outcome = outcome_nm, .before = 1)
  })
}

resolve_outcome_control_contracts <- function(control_screen,
                                              outcomes = unique(as.character(value_or(control_screen$outcome, character()))),
                                              control_col = "control",
                                              selected_col = "selected") {
  outcome_vals <- unique(as.character(value_or(outcomes, character())))
  outcome_vals <- outcome_vals[!is.na(outcome_vals) & nzchar(outcome_vals)]
  if (!all(c("outcome", control_col, selected_col) %in% names(control_screen))) {
    stop("[ERROR] control_screen missing required outcome/control/selected columns", call. = FALSE)
  }

  stats::setNames(
    lapply(outcome_vals, function(outcome_nm) {
      rows <- control_screen |>
        dplyr::filter(outcome == outcome_nm)
      list(
        requested_controls = rows[[control_col]],
        usable_controls = rows |>
          dplyr::filter(.data[[selected_col]]) |>
          dplyr::pull(.data[[control_col]])
      )
    }),
    outcome_vals
  )
}

read_twfe_main_controls_used <- function(path = cfg$paths$twfe_main_controls_used) {
  if (!file.exists(path)) {
    stop("[ERROR] twfe_main_controls_used.csv missing. Run 01_run_twfe_main.R before TWFE sidecars.", call. = FALSE)
  }

  controls <- readr::read_csv(path, show_col_types = FALSE) |>
    tibble::as_tibble()
  required_cols <- c("outcome", "control", "selected")
  missing_cols <- setdiff(required_cols, names(controls))
  if (length(missing_cols) > 0L) {
    stop(
      sprintf("[ERROR] twfe_main_controls_used.csv missing required column(s): %s", collapse_chr(missing_cols)),
      call. = FALSE
    )
  }

  controls |>
    dplyr::mutate(
      outcome = as.character(outcome),
      control = as.character(control),
      selected = dplyr::case_when(
        is.logical(selected) ~ selected,
        is.numeric(selected) ~ selected != 0,
        TRUE ~ tolower(trimws(as.character(selected))) %in% c("true", "t", "1", "yes", "y")
      ),
      control_source = "twfe_main_controls_used"
    )
}

twfe_main_control_candidate_cols <- function() {
  value_or(cfg$twfe_main_control_cols, c(
    "ln_resident_pop",
    "ln_apartment_household_count", "ln_official_land_price", "transit_accessibility",
    "hospital_count_aux_core", "mall_count_aux_core"
  ))
}

assert_twfe_main_controls_current <- function(control_screen,
                                              context = "TWFE sidecar",
                                              allowed_controls = twfe_main_control_candidate_cols(),
                                              control_col = "control",
                                              selected_col = "selected") {
  required_cols <- c("outcome", control_col, selected_col)
  missing_cols <- setdiff(required_cols, names(control_screen))
  if (length(missing_cols) > 0L) {
    stop(
      sprintf("[ERROR] %s control trace missing required column(s): %s", context, collapse_chr(missing_cols)),
      call. = FALSE
    )
  }

  allowed_controls <- unique(as.character(value_or(allowed_controls, character())))
  allowed_controls <- allowed_controls[!is.na(allowed_controls) & nzchar(allowed_controls)]
  requested_controls <- unique(as.character(control_screen[[control_col]]))
  requested_controls <- requested_controls[!is.na(requested_controls) & nzchar(requested_controls)]

  stale_requested <- setdiff(requested_controls, allowed_controls)
  if (length(stale_requested) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s is using stale TWFE main control candidates: %s. Re-run 01_run_twfe_main.R under the current config before TWFE sidecars.",
        context,
        collapse_chr(stale_requested)
      ),
      call. = FALSE
    )
  }

  selected_raw <- control_screen[[selected_col]]
  selected_flag <- dplyr::case_when(
    is.logical(selected_raw) ~ selected_raw,
    is.numeric(selected_raw) ~ selected_raw != 0,
    TRUE ~ tolower(trimws(as.character(selected_raw))) %in% c("true", "t", "1", "yes", "y")
  )
  selected_controls <- unique(as.character(control_screen[[control_col]][selected_flag]))
  selected_controls <- selected_controls[!is.na(selected_controls) & nzchar(selected_controls)]

  forbidden_controls <- intersect(
    selected_controls,
    c("ln_worker_pop", "ln_floating_pop", "bus_stop_count_aux", "subway_station_count_aux", "apartment_count")
  )
  if (length(forbidden_controls) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s selected retired control(s): %s. Use the current six-control TWFE contract.",
        context,
        collapse_chr(forbidden_controls)
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

load_twfe_main_control_contracts <- function(outcomes,
                                             path = cfg$paths$twfe_main_controls_used,
                                             require_all = TRUE) {
  outcome_vals <- unique(as.character(value_or(outcomes, character())))
  outcome_vals <- outcome_vals[!is.na(outcome_vals) & nzchar(outcome_vals)]
  controls <- read_twfe_main_controls_used(path)

  if (isTRUE(require_all)) {
    missing_outcomes <- setdiff(outcome_vals, unique(controls$outcome))
    if (length(missing_outcomes) > 0L) {
      stop(
        sprintf("[ERROR] Missing outcome(s) in twfe_main_controls_used.csv: %s", collapse_chr(missing_outcomes)),
        call. = FALSE
      )
    }
  }

  list(
    screen = controls |>
      dplyr::filter(outcome %in% outcome_vals),
    contracts = resolve_outcome_control_contracts(
      controls,
      outcomes = outcome_vals,
      control_col = "control",
      selected_col = "selected"
    )
  )
}

resolve_floating_overlap_spec_meta <- function(outcomes,
                                               exposures,
                                               registry = value_or(cfg$floating_exposure_overlap_outcomes, character())) {
  outcome_vals <- as.character(value_or(outcomes, character()))
  outcome_vals <- outcome_vals[!is.na(outcome_vals) & nzchar(outcome_vals)]

  if (length(outcome_vals) == 0L) {
    return(tibble::tibble(
      outcome = character(),
      skip_reason = character(),
      skip_message = character(),
      skip_spec = logical()
    ))
  }

  exposure_list <- if (is.list(exposures)) {
    exposures
  } else {
    rep(list(as.character(value_or(exposures, character()))), length.out = length(outcome_vals))
  }
  if (length(exposure_list) == 0L) {
    exposure_list <- rep(list(character()), length.out = length(outcome_vals))
  }
  if (length(exposure_list) != length(outcome_vals)) {
    exposure_list <- rep(exposure_list, length.out = length(outcome_vals))
  }

  tibble::tibble(
    outcome = outcome_vals,
    exposures = exposure_list
  ) |>
    dplyr::mutate(
      skip_reason = purrr::map2_chr(outcome, exposures, floating_overlap_skip_reason, registry = registry),
      skip_message = purrr::map2_chr(outcome, exposures, floating_overlap_skip_message, registry = registry),
      skip_spec = !is.na(skip_reason)
    ) |>
    dplyr::select(-exposures)
}


#==============================================================================
# 3. Model Output Tidying
#==============================================================================

# 모델마다 다른 객체 클래스를 후속 csv export에 맞는
# long tidy table로 일관되게 바꾼다.
tidy_models <- function(models) {
  mods <- models[!vapply(models, is.null, logical(1))]
  if (length(mods) == 0) return(tibble::tibble())
  # list 이름을 `model_name`으로 보존해야, 이후 csv/plot 단계에서
  # 어떤 outcome/exposure/spec 조합에서 나온 계수인지 역추적할 수 있다.
  purrr::imap_dfr(mods, ~ {
    meta <- model_meta_tibble(.x)
    td <- broom::tidy(.x)
    td |>
      dplyr::bind_cols(meta[rep(1L, nrow(td)), , drop = FALSE]) |>
      dplyr::mutate(model_name = .y, .before = 1)
  })
}

summarize_model_diagnostics <- function(models) {
  mods <- models[!vapply(models, is.null, logical(1))]
  if (length(mods) == 0) return(tibble::tibble())

  purrr::imap_dfr(mods, ~ {
    model_meta_tibble(.x) |>
      dplyr::mutate(
        model_name = .y,
        status = "success",
        .before = 1
      )
  })
}
