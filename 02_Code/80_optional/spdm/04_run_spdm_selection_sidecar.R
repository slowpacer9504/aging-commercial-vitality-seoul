#==============================================================================
# Script    : 04_run_spdm_selection_sidecar.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run appendix selection diagnostics for SEM vs SDM on the same
#             Queen sample/control contract used by the main resident-only SPDM.
# Author    : Codex
# Created   : 2026-03-30
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, W_queen.rds, spdm_main_diagnostics.csv,
#             spdm_controls_used.csv
# Outputs   : spdm_selection_tests.csv, spdm_selection_family_comparison.csv
# DependsOn : 01_build_spatial_weights.R, 02_run_spdm_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spdm.R"))
load_project_packages(extra = "MASS")

append_log(cfg$logs$model_run, sprintf("\n## [%s] 04_run_spdm_selection_sidecar", timestamp()))


#==============================================================================
# 1. Local Helpers
#==============================================================================

selection_empty_tests_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    w_type = character(),
    selected_controls = character(),
    n_units = integer(),
    n_periods = integer(),
    n_obs = integer(),
    test_name = character(),
    statistic = numeric(),
    df = numeric(),
    p.value = numeric(),
    null_hypothesis = character(),
    decision = character(),
    status = character(),
    message = character()
  )
}

selection_empty_family_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    family = character(),
    engine = character(),
    w_type = character(),
    status = character(),
    selected_controls = character(),
    n_units = integer(),
    n_periods = integer(),
    n_obs = integer(),
    sample_min_yq = character(),
    sample_max_yq = character(),
    focal_term = character(),
    focal_estimate = numeric(),
    focal_se = numeric(),
    focal_p = numeric(),
    lag_param_name = character(),
    lag_param_estimate = numeric(),
    lag_param_se = numeric(),
    lag_param_p = numeric(),
    error_param_name = character(),
    error_param_estimate = numeric(),
    error_param_se = numeric(),
    error_param_p = numeric(),
    n_lag_x_terms = integer(),
    time_fe_included = logical(),
    message = character()
  )
}

write_selection_outputs <- function(tests_tbl, family_tbl) {
  finalized_tests <- tests_tbl |>
    annotate_outcomes(include_robustness = FALSE) |>
    dplyr::arrange(outcome_order, exposure, spec_id, test_name)

  finalized_family <- family_tbl |>
    annotate_outcomes(include_robustness = FALSE) |>
    dplyr::arrange(outcome_order, exposure, spec_id, family)

  write_csv_safe(finalized_tests, cfg$paths$spdm_selection_tests)
  write_csv_safe(finalized_family, cfg$paths$spdm_selection_family_comparison)
}

split_collapsed_controls <- function(x) {
  if (length(x) == 0L || all(is.na(x))) return(character())
  vals <- unlist(strsplit(as.character(x[[1]]), ";", fixed = TRUE), use.names = FALSE)
  vals <- trimws(vals)
  vals[!is.na(vals) & nzchar(vals)]
}

selected_controls_from_main_contract <- function(controls_tbl, spec_id) {
  rows <- controls_tbl |>
    dplyr::filter(spec_id == !!spec_id, selected %in% TRUE)
  if (nrow(rows) == 0L) return(character())
  rows |>
    dplyr::arrange(control_order) |>
    dplyr::pull(control_var) |>
    unique()
}

add_selection_test_row <- function(spec_id,
                                   outcome,
                                   exposure,
                                   w_type,
                                   selected_controls,
                                   n_units,
                                   n_periods,
                                   n_obs,
                                   test_name,
                                   null_hypothesis,
                                   statistic = NA_real_,
                                   df = NA_real_,
                                   p_value = NA_real_,
                                   decision = NA_character_,
                                   status = "success",
                                   message = NA_character_) {
  selection_empty_tests_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      w_type = w_type,
      selected_controls = collapse_chr(selected_controls),
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      test_name = test_name,
      statistic = statistic,
      df = df,
      p.value = p_value,
      null_hypothesis = null_hypothesis,
      decision = as.character(decision),
      status = status,
      message = as.character(message)
    )
}

add_selection_family_row <- function(spec_id,
                                     outcome,
                                     exposure,
                                     family,
                                     selected_controls,
                                     n_units,
                                     n_periods,
                                     n_obs,
                                     sample_min_yq,
                                     sample_max_yq,
                                     focal_term = exposure,
                                     focal_estimate = NA_real_,
                                     focal_se = NA_real_,
                                     focal_p = NA_real_,
                                     lag_param_name = NA_character_,
                                     lag_param_estimate = NA_real_,
                                     lag_param_se = NA_real_,
                                     lag_param_p = NA_real_,
                                     error_param_name = NA_character_,
                                     error_param_estimate = NA_real_,
                                     error_param_se = NA_real_,
                                     error_param_p = NA_real_,
                                     n_lag_x_terms = 0L,
                                     status = "success",
                                     message = NA_character_,
                                     w_type = "queen") {
  selection_empty_family_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      family = family,
      engine = "spgm",
      w_type = w_type,
      status = status,
      selected_controls = collapse_chr(selected_controls),
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
      focal_term = as.character(focal_term),
      focal_estimate = focal_estimate,
      focal_se = focal_se,
      focal_p = focal_p,
      lag_param_name = as.character(lag_param_name),
      lag_param_estimate = lag_param_estimate,
      lag_param_se = lag_param_se,
      lag_param_p = lag_param_p,
      error_param_name = as.character(error_param_name),
      error_param_estimate = error_param_estimate,
      error_param_se = error_param_se,
      error_param_p = error_param_p,
      n_lag_x_terms = as.integer(n_lag_x_terms),
      time_fe_included = TRUE,
      message = as.character(message)
    )
}

extract_htest_stat <- function(obj) {
  val <- suppressWarnings(as.numeric(unname(value_or(obj$statistic, NA_real_))))
  if (length(val) == 0L || !is.finite(val[[1]])) NA_real_ else val[[1]]
}

extract_htest_df <- function(obj) {
  val <- suppressWarnings(as.numeric(unname(value_or(obj$parameter, NA_real_))))
  if (length(val) == 0L || !is.finite(val[[1]])) NA_real_ else val[[1]]
}

build_spgm_formula <- function(outcome, exposure, controls, include_time_fe = TRUE) {
  rhs <- unique(c(exposure, controls, if (isTRUE(include_time_fe)) "factor(year)" else character()))
  stats::as.formula(sprintf("%s ~ %s", outcome, paste(rhs, collapse = " + ")))
}

fit_spgm_selection_model <- function(data, listw, outcome, exposure, controls, family) {
  family <- as.character(family)
  fm <- build_spgm_formula(outcome = outcome, exposure = exposure, controls = controls, include_time_fe = TRUE)

  model_args <- switch(
    family,
    sar_gm = list(lag = TRUE, spatial.error = FALSE, Durbin = FALSE),
    sdm_gm = list(lag = TRUE, spatial.error = FALSE, Durbin = TRUE),
    sem_gm = list(lag = FALSE, spatial.error = TRUE, Durbin = FALSE),
    stop(sprintf("unsupported selection family: %s", family), call. = FALSE)
  )

  tryCatch(
    do.call(
      splm::spgm,
      c(
        list(
          formula = fm,
          data = data,
          listw = listw,
          model = "within",
          moments = "fullweights",
          index = c("adm_cd", "time_id")
        ),
        model_args
      )
    ),
    error = function(e) e
  )
}

extract_spgm_coef_table <- function(mod) {
  sm <- summary(mod)
  coef_tbl <- tryCatch(as.data.frame(sm$CoefTable), error = function(e) NULL)
  if (is.null(coef_tbl) || nrow(coef_tbl) == 0L) return(tibble::tibble())

  coef_tbl$term <- rownames(coef_tbl)
  rownames(coef_tbl) <- NULL
  names(coef_tbl)[seq_len(min(4L, ncol(coef_tbl)))] <- c("estimate", "std.error", "statistic", "p.value")[seq_len(min(4L, ncol(coef_tbl)))]

  tibble::as_tibble(coef_tbl) |>
    dplyr::select(dplyr::all_of(c("term", "estimate", "std.error", "statistic", "p.value"))) |>
    dplyr::filter(!grepl("^factor\\(year\\)", term))
}

extract_spgm_lag_param <- function(coef_tbl) {
  hit <- coef_tbl |>
    dplyr::filter(tolower(term) == "lambda") |>
    dplyr::slice(1)

  if (nrow(hit) == 0L) {
    return(list(name = NA_character_, estimate = NA_real_, se = NA_real_, p = NA_real_))
  }

  list(
    name = "lambda",
    estimate = suppressWarnings(as.numeric(hit$estimate[[1]])),
    se = suppressWarnings(as.numeric(hit$std.error[[1]])),
    p = suppressWarnings(as.numeric(hit$p.value[[1]]))
  )
}

extract_spgm_error_param <- function(mod) {
  sm <- summary(mod)
  rho_obj <- value_or(sm$rho, sm$errcomp)
  if (is.null(rho_obj) || length(rho_obj) == 0L) {
    return(list(name = NA_character_, estimate = NA_real_, se = NA_real_, p = NA_real_))
  }

  rho_tbl <- tryCatch(as.data.frame(rho_obj), error = function(e) NULL)
  if (is.null(rho_tbl) || nrow(rho_tbl) == 0L) {
    est <- suppressWarnings(as.numeric(rho_obj[[1]]))
    return(list(name = "rho", estimate = est, se = NA_real_, p = NA_real_))
  }

  rn <- rownames(rho_tbl)
  rho_row <- if (!is.null(rn) && "rho" %in% rn) rho_tbl["rho", , drop = FALSE] else rho_tbl[1, , drop = FALSE]

  list(
    name = "rho",
    estimate = suppressWarnings(as.numeric(rho_row[[1, 1]])),
    se = if (ncol(rho_row) >= 2L) suppressWarnings(as.numeric(rho_row[[1, 2]])) else NA_real_,
    p = if (ncol(rho_row) >= 4L) suppressWarnings(as.numeric(rho_row[[1, 4]])) else NA_real_
  )
}

run_slm_selection_test <- function(formula,
                                   data,
                                   listw,
                                   index,
                                   test_name,
                                   null_hypothesis) {
  test_obj <- tryCatch(
    splm::slmtest(
      formula,
      data = data,
      listw = listw,
      index = index,
      model = "within",
      effect = "twoways",
      test = sub("^slm_", "", test_name)
    ),
    error = function(e) e
  )

  if (inherits(test_obj, "error")) {
    return(list(
      statistic = NA_real_,
      df = NA_real_,
      p.value = NA_real_,
      decision = "failed",
      status = "failed",
      message = paste("test error:", test_obj$message)
    ))
  }

  p_val <- suppressWarnings(as.numeric(test_obj$p.value))
  list(
    statistic = extract_htest_stat(test_obj),
    df = extract_htest_df(test_obj),
    p.value = p_val,
    decision = if (is.finite(p_val) && p_val < 0.05) "reject_null" else "not_rejected",
    status = "success",
    message = null_hypothesis
  )
}

run_rw_rho_test <- function(formula,
                            data,
                            w_matrix,
                            index,
                            replications,
                            seed) {
  test_obj <- tryCatch(
    splm::rwtest(
      formula,
      data = data,
      w = w_matrix,
      index = index,
      model = "within",
      effect = "twoways",
      replications = replications,
      seed = seed,
      test = "rho"
    ),
    error = function(e) e
  )

  if (inherits(test_obj, "error")) {
    return(list(
      statistic = NA_real_,
      df = NA_real_,
      p.value = NA_real_,
      decision = "failed",
      status = "failed",
      message = paste("test error:", test_obj$message)
    ))
  }

  p_val <- suppressWarnings(as.numeric(test_obj$p.value))
  list(
    statistic = extract_htest_stat(test_obj),
    df = extract_htest_df(test_obj),
    p.value = p_val,
    decision = if (is.finite(p_val) && p_val < 0.05) "reject_null" else "not_rejected",
    status = "success",
    message = "no randomized spatial correlation of order 1"
  )
}

run_common_factor_wald_test <- function(mod, exposure, controls) {
  coef_vec <- stats::coef(mod)
  coef_names <- names(coef_vec)
  if (is.null(coef_names) || length(coef_names) == 0L) {
    return(list(
      statistic = NA_real_,
      df = NA_real_,
      p.value = NA_real_,
      decision = "failed",
      status = "failed",
      message = "coef names unavailable from true SDM"
    ))
  }

  base_terms <- unique(c(exposure, controls))
  lag_terms <- paste0("lag_", base_terms)
  needed <- c("lambda", base_terms, lag_terms)
  missing_terms <- setdiff(needed, coef_names)
  if (length(missing_terms) > 0L) {
    return(list(
      statistic = NA_real_,
      df = NA_real_,
      p.value = NA_real_,
      decision = "failed",
      status = "failed",
      message = paste("missing common-factor terms:", paste(missing_terms, collapse = ", "))
    ))
  }

  vc <- tryCatch(stats::vcov(mod), error = function(e) e)
  if (inherits(vc, "error") || is.null(vc)) {
    return(list(
      statistic = NA_real_,
      df = NA_real_,
      p.value = NA_real_,
      decision = "failed",
      status = "failed",
      message = if (inherits(vc, "error")) paste("vcov error:", vc$message) else "vcov unavailable"
    ))
  }

  if (!is.matrix(vc)) vc <- as.matrix(vc)
  if (nrow(vc) != length(coef_vec) || ncol(vc) != length(coef_vec)) {
    return(list(
      statistic = NA_real_,
      df = NA_real_,
      p.value = NA_real_,
      decision = "failed",
      status = "failed",
      message = "vcov dimension mismatch"
    ))
  }
  dimnames(vc) <- list(coef_names, coef_names)

  rho_hat <- suppressWarnings(as.numeric(coef_vec[["lambda"]]))
  g_vec <- vapply(base_terms, function(term) {
    suppressWarnings(as.numeric(coef_vec[[paste0("lag_", term)]] + rho_hat * coef_vec[[term]]))
  }, numeric(1))

  jac <- matrix(0, nrow = length(base_terms), ncol = length(coef_vec), dimnames = list(base_terms, coef_names))
  for (term in base_terms) {
    jac[term, paste0("lag_", term)] <- 1
    jac[term, "lambda"] <- suppressWarnings(as.numeric(coef_vec[[term]]))
    jac[term, term] <- rho_hat
  }

  middle <- jac %*% vc %*% t(jac)
  inv_middle <- tryCatch(solve(middle), error = function(e) NULL)
  if (is.null(inv_middle)) {
    inv_middle <- tryCatch(MASS::ginv(middle), error = function(e) NULL)
  }
  if (is.null(inv_middle)) {
    return(list(
      statistic = NA_real_,
      df = as.numeric(length(base_terms)),
      p.value = NA_real_,
      decision = "failed",
      status = "failed",
      message = "failed to invert common-factor covariance"
    ))
  }

  stat <- suppressWarnings(as.numeric(t(g_vec) %*% inv_middle %*% g_vec))
  df <- as.numeric(length(base_terms))
  p_val <- if (is.finite(stat)) stats::pchisq(stat, df = df, lower.tail = FALSE) else NA_real_

  list(
    statistic = stat,
    df = df,
    p.value = p_val,
    decision = if (is.finite(p_val) && p_val < 0.05) "reject_sem_restriction" else "sem_restriction_not_rejected",
    status = "success",
    message = "common-factor restriction holds (SEM restriction)"
  )
}

build_failed_result <- function(spec_id,
                                outcome,
                                exposure,
                                selected_controls,
                                test_names,
                                family_names,
                                message,
                                w_type = "queen") {
  tests_tbl <- purrr::map_dfr(test_names, function(test_name) {
    null_hypothesis <- dplyr::case_when(
      identical(test_name, "slm_lml") ~ "no spatial lag dependence",
      identical(test_name, "slm_lme") ~ "no spatial error dependence",
      identical(test_name, "slm_rlml") ~ "no spatial lag dependence conditional on possible spatial error",
      identical(test_name, "slm_rlme") ~ "no spatial error dependence conditional on possible spatial lag",
      identical(test_name, "rw_rho") ~ "no randomized spatial correlation of order 1",
      identical(test_name, "common_factor_wald_full_rhs") ~ "common-factor restriction holds (SEM restriction)",
      TRUE ~ NA_character_
    )

    add_selection_test_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      w_type = w_type,
      selected_controls = selected_controls,
      n_units = NA_integer_,
      n_periods = NA_integer_,
      n_obs = NA_integer_,
      test_name = test_name,
      null_hypothesis = null_hypothesis,
      decision = "failed",
      status = "failed",
      message = message
    )
  })

  family_tbl <- purrr::map_dfr(family_names, function(family) {
    add_selection_family_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      family = family,
      selected_controls = selected_controls,
      n_units = NA_integer_,
      n_periods = NA_integer_,
      n_obs = NA_integer_,
      sample_min_yq = NA_character_,
      sample_max_yq = NA_character_,
      status = "failed",
      message = message,
      w_type = w_type
    )
  })

  list(tests = tests_tbl, family = family_tbl)
}


#==============================================================================
# 2. Run Selection Sidecar
#==============================================================================

empty_tests <- selection_empty_tests_tbl()
empty_family <- selection_empty_family_tbl()

if (!file.exists(cfg$paths$panel_main) ||
    !file.exists(cfg$paths$w_queen) ||
    !file.exists(cfg$paths$spdm_main_diagnostics) ||
    !file.exists(cfg$paths$spdm_controls_used)) {
  stop("[ERROR] Missing panel, W, or main SPDM diagnostics/control outputs", call. = FALSE)
}

panel <- read_panel_main_view("spdm")
panel$adm_cd <- as.character(panel$adm_cd)

main_diag <- readr::read_csv(cfg$paths$spdm_main_diagnostics, show_col_types = FALSE) |>
  dplyr::mutate(
    spec_id = as.character(spec_id),
    outcome = as.character(outcome),
    exposure = as.character(exposure),
    model_family = as.character(model_family),
    w_type = as.character(w_type)
  )

main_controls <- readr::read_csv(cfg$paths$spdm_controls_used, show_col_types = FALSE) |>
  dplyr::mutate(
    spec_id = as.character(spec_id),
    outcome = as.character(outcome),
    exposure = as.character(exposure),
    model_family = as.character(model_family),
    w_type = as.character(w_type),
    control_var = as.character(control_var)
  )

assert_spdm_main_controls_current(
  main_controls,
  context = "04_run_spdm_selection_sidecar",
  control_col = "control_var",
  selected_col = "selected"
)
assert_spdm_main_diagnostics_controls_current(
  main_diag,
  context = "04_run_spdm_selection_sidecar"
)

outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = value_or(cfg$spdm_main_outcomes, c(
    "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability", "vitality_index_base"
  )),
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome
exposures <- intersect(value_or(cfg$spdm_main_exposure_vars, c("age60_resident_share")), names(panel))
w_type_main <- as.character(value_or(cfg$default_w, "queen"))

test_names <- c("slm_lml", "slm_lme", "slm_rlml", "slm_rlme", "rw_rho", "common_factor_wald_full_rhs")
family_names <- c("sar_gm", "sdm_gm", "sem_gm")

if (length(outcomes) == 0L || length(exposures) == 0L) {
  write_selection_outputs(empty_tests, empty_family)
  append_log(cfg$logs$model_run, "- SPDM selection sidecar skipped: missing outcomes or exposures")
} else {
  lw <- readRDS(cfg$paths$w_queen)
  w_ids <- as.character(attr(lw$neighbours, "region.id"))
  if (length(w_ids) == 0L || all(is.na(w_ids))) {
    write_selection_outputs(empty_tests, empty_family)
    append_log(cfg$logs$model_run, "- SPDM selection sidecar skipped: region.id missing in W")
  } else {
    tests_out <- selection_empty_tests_tbl()
    family_out <- selection_empty_family_tbl()

    for (outcome in outcomes) {
      for (exposure in exposures) {
        spec_id <- sprintf("%s__%s__selection", outcome, exposure)
        main_row <- main_diag |>
          dplyr::filter(
            model_family == "sdm",
            outcome == !!outcome,
            exposure == !!exposure,
            w_type == !!w_type_main
          ) |>
          dplyr::slice(1)

        if (nrow(main_row) == 0L) {
          failed <- build_failed_result(
            spec_id = spec_id,
            outcome = outcome,
            exposure = exposure,
            selected_controls = character(),
            test_names = test_names,
            family_names = family_names,
            message = "main SPDM diagnostics row unavailable",
            w_type = w_type_main
          )
          tests_out <- dplyr::bind_rows(tests_out, failed$tests)
          family_out <- dplyr::bind_rows(family_out, failed$family)
          next
        }

        selected_controls <- split_collapsed_controls(main_row$selected_controls)
        selected_controls_from_controls <- selected_controls_from_main_contract(
          main_controls,
          as.character(main_row$spec_id[[1]])
        )
        if (length(selected_controls_from_controls) > 0L &&
            !identical(selected_controls_from_controls, selected_controls)) {
          failed <- build_failed_result(
            spec_id = spec_id,
            outcome = outcome,
            exposure = exposure,
            selected_controls = selected_controls,
            test_names = test_names,
            family_names = family_names,
            message = "main SPDM control contract mismatch between diagnostics and controls output",
            w_type = w_type_main
          )
          tests_out <- dplyr::bind_rows(tests_out, failed$tests)
          family_out <- dplyr::bind_rows(family_out, failed$family)
          next
        }

        if (!identical(as.character(main_row$status[[1]]), "success")) {
          failed <- build_failed_result(
            spec_id = spec_id,
            outcome = outcome,
            exposure = exposure,
            selected_controls = selected_controls,
            test_names = test_names,
            family_names = family_names,
            message = paste("main SPDM status:", main_row$status[[1]]),
            w_type = w_type_main
          )
          tests_out <- dplyr::bind_rows(tests_out, failed$tests)
          family_out <- dplyr::bind_rows(family_out, failed$family)
          next
        }

        prep <- rebuild_main_spdm_sample(
          panel = panel,
          outcome = outcome,
          exposure = exposure,
          selected_controls = selected_controls,
          lw = lw,
          w_ids = w_ids,
          expected_row = main_row,
          context_label = "selection sidecar"
        )

        if (!identical(prep$status, "success")) {
          failed <- build_failed_result(
            spec_id = spec_id,
            outcome = outcome,
            exposure = exposure,
            selected_controls = selected_controls,
            test_names = test_names,
            family_names = family_names,
            message = prep$message,
            w_type = w_type_main
          )
          tests_out <- dplyr::bind_rows(tests_out, failed$tests)
          family_out <- dplyr::bind_rows(family_out, failed$family)
          next
        }

        base_formula <- stats::as.formula(sprintf(
          "%s ~ %s",
          outcome,
          paste(unique(c(exposure, selected_controls)), collapse = " + ")
        ))

        slm_specs <- list(
          slm_lml = "no spatial lag dependence",
          slm_lme = "no spatial error dependence",
          slm_rlml = "no spatial lag dependence conditional on possible spatial error",
          slm_rlme = "no spatial error dependence conditional on possible spatial lag"
        )

        for (test_name in names(slm_specs)) {
          test_res <- run_slm_selection_test(
            formula = base_formula,
            data = prep$data,
            listw = prep$lw_sub,
            index = c("adm_cd", "time_id"),
            test_name = test_name,
            null_hypothesis = slm_specs[[test_name]]
          )

          tests_out <- dplyr::bind_rows(
            tests_out,
            add_selection_test_row(
              spec_id = spec_id,
              outcome = outcome,
              exposure = exposure,
              w_type = w_type_main,
              selected_controls = selected_controls,
              n_units = prep$n_units,
              n_periods = prep$n_periods,
              n_obs = prep$n_obs,
              test_name = test_name,
              null_hypothesis = slm_specs[[test_name]],
              statistic = test_res$statistic,
              df = test_res$df,
              p_value = test_res$p.value,
              decision = test_res$decision,
              status = test_res$status,
              message = test_res$message
            )
          )
        }

        rw_res <- run_rw_rho_test(
          formula = base_formula,
          data = prep$data,
          w_matrix = prep$w_matrix,
          index = c("adm_cd", "time_id"),
          replications = 499L,
          seed = cfg$esda_seed
        )
        tests_out <- dplyr::bind_rows(
          tests_out,
          add_selection_test_row(
            spec_id = spec_id,
            outcome = outcome,
            exposure = exposure,
            w_type = w_type_main,
            selected_controls = selected_controls,
            n_units = prep$n_units,
            n_periods = prep$n_periods,
            n_obs = prep$n_obs,
            test_name = "rw_rho",
            null_hypothesis = "no randomized spatial correlation of order 1",
            statistic = rw_res$statistic,
            df = rw_res$df,
            p_value = rw_res$p.value,
            decision = rw_res$decision,
            status = rw_res$status,
            message = rw_res$message
          )
        )

        gm_models <- list()
        for (family in family_names) {
          gm_fit <- fit_spgm_selection_model(
            data = prep$data,
            listw = prep$lw_sub,
            outcome = outcome,
            exposure = exposure,
            controls = selected_controls,
            family = family
          )
          gm_models[[family]] <- gm_fit

          if (inherits(gm_fit, "error")) {
            family_out <- dplyr::bind_rows(
              family_out,
              add_selection_family_row(
                spec_id = spec_id,
                outcome = outcome,
                exposure = exposure,
                family = family,
                selected_controls = selected_controls,
                n_units = prep$n_units,
                n_periods = prep$n_periods,
                n_obs = prep$n_obs,
                sample_min_yq = prep$sample_min_yq,
                sample_max_yq = prep$sample_max_yq,
                status = "failed",
                message = paste("spgm error:", gm_fit$message),
                w_type = w_type_main
              )
            )
            next
          }

          coef_tbl <- extract_spgm_coef_table(gm_fit)
          focal_stats <- extract_focal_term_stats(coef_tbl, exposure)
          lag_param <- extract_spgm_lag_param(coef_tbl)
          error_param <- if (identical(family, "sem_gm")) extract_spgm_error_param(gm_fit) else list(
            name = NA_character_,
            estimate = NA_real_,
            se = NA_real_,
            p = NA_real_
          )

          family_out <- dplyr::bind_rows(
            family_out,
            add_selection_family_row(
              spec_id = spec_id,
              outcome = outcome,
              exposure = exposure,
              family = family,
              selected_controls = selected_controls,
              n_units = prep$n_units,
              n_periods = prep$n_periods,
              n_obs = prep$n_obs,
              sample_min_yq = prep$sample_min_yq,
              sample_max_yq = prep$sample_max_yq,
              focal_term = focal_stats$focal_term,
              focal_estimate = focal_stats$focal_estimate,
              focal_se = focal_stats$focal_se,
              focal_p = focal_stats$focal_p,
              lag_param_name = lag_param$name,
              lag_param_estimate = lag_param$estimate,
              lag_param_se = lag_param$se,
              lag_param_p = lag_param$p,
              error_param_name = error_param$name,
              error_param_estimate = error_param$estimate,
              error_param_se = error_param$se,
              error_param_p = error_param$p,
              n_lag_x_terms = sum(startsWith(coef_tbl$term, "lag_")),
              status = "success",
              message = prep$message,
              w_type = w_type_main
            )
          )
        }

        wald_res <- if (!inherits(gm_models[["sdm_gm"]], "error") && !is.null(gm_models[["sdm_gm"]])) {
          run_common_factor_wald_test(
            mod = gm_models[["sdm_gm"]],
            exposure = exposure,
            controls = selected_controls
          )
        } else {
          list(
            statistic = NA_real_,
            df = NA_real_,
            p.value = NA_real_,
            decision = "failed",
            status = "failed",
            message = "true SDM unavailable for common-factor Wald test"
          )
        }

        tests_out <- dplyr::bind_rows(
          tests_out,
          add_selection_test_row(
            spec_id = spec_id,
            outcome = outcome,
            exposure = exposure,
            w_type = w_type_main,
            selected_controls = selected_controls,
            n_units = prep$n_units,
            n_periods = prep$n_periods,
            n_obs = prep$n_obs,
            test_name = "common_factor_wald_full_rhs",
            null_hypothesis = "common-factor restriction holds (SEM restriction)",
            statistic = wald_res$statistic,
            df = wald_res$df,
            p_value = wald_res$p.value,
            decision = wald_res$decision,
            status = wald_res$status,
            message = wald_res$message
          )
        )
      }
    }

    write_selection_outputs(tests_out, family_out)
    append_log(
      cfg$logs$model_run,
      sprintf(
        "- SPDM selection sidecar completed: %d tests, %d family rows",
        nrow(tests_out),
        nrow(family_out)
      )
    )
  }
}
