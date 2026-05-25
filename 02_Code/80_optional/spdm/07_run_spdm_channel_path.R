#==============================================================================
# Script    : 07_run_spdm_channel_path.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the optional SPDM channel path sidecar for
#             resident aging -> floating aging -> commercial vitality.
# Author    : Codex
# Created   : 2026-03-27
# Status    : QUARTERLY_OPTIONAL / manual SPDM channel path sidecar
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, W_queen.rds
# Outputs   : spdm_channel_models.csv, spdm_channel_impacts.csv,
#             spdm_channel_controls_used.csv,
#             spdm_channel_path_effects.csv, spdm_channel_bootstrap_draws.csv,
#             spdm_channel_diagnostics.csv
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
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 07_run_spdm_channel_path", timestamp()))

path_channel_models <- value_or(cfg$paths$spdm_channel_models, file.path(cfg$dir_tables, "spdm_channel_models.csv"))
path_channel_impacts <- value_or(cfg$paths$spdm_channel_impacts, file.path(cfg$dir_tables, "spdm_channel_impacts.csv"))
path_channel_controls <- value_or(cfg$paths$spdm_channel_controls_used, file.path(cfg$dir_tables, "spdm_channel_controls_used.csv"))
path_channel_path_effects <- value_or(cfg$paths$spdm_channel_path_effects, file.path(cfg$dir_tables, "spdm_channel_path_effects.csv"))
path_channel_bootstrap_draws <- value_or(cfg$paths$spdm_channel_bootstrap_draws, file.path(cfg$dir_tables, "spdm_channel_bootstrap_draws.csv"))
path_channel_diagnostics <- value_or(cfg$paths$spdm_channel_diagnostics, file.path(cfg$dir_tables, "spdm_channel_diagnostics.csv"))

if (!file.exists(cfg$paths$panel_main) || !file.exists(cfg$paths$w_queen)) {
  stop("[ERROR] Missing panel or W", call. = FALSE)
}

requested_x_vars <- value_or(cfg$spdm_main_exposure_vars, "age60_resident_share")
requested_m_vars <- value_or(cfg$spdm_channel_vars, "age60_floating_share")

channel_read_cols <- unique(c(
  requested_x_vars,
  requested_m_vars,
  "vitality_sub_economic", "vitality_sub_temporal", "vitality_sub_stability",
  "vitality_index_base"
))
panel <- read_panel_main_view("spdm", extra_cols = channel_read_cols)
panel$adm_cd <- as.character(panel$adm_cd)

x_candidates <- intersect(requested_x_vars, names(panel))
x_var <- if (length(x_candidates) > 0L) x_candidates[[1]] else NA_character_
m_candidates <- intersect(requested_m_vars, names(panel))
m_var <- if (length(m_candidates) > 0L) m_candidates[[1]] else NA_character_

requested_channel_outcomes <- unique(as.character(value_or(
  cfg$spdm_channel_outcomes,
  c("vitality_sub_economic", "vitality_sub_temporal", "vitality_sub_stability", "vitality_index_base")
)))
overlap_outcomes <- unique(c(value_or(cfg$floating_exposure_overlap_outcomes, character()), "vitality_sub_social"))
channel_outcomes <- setdiff(intersect(requested_channel_outcomes, names(panel)), overlap_outcomes)

base_registry <- get_outcome_registry(include_robustness = TRUE)
outcome_registry <- tibble::tibble(outcome = channel_outcomes) |>
  dplyr::left_join(base_registry, by = "outcome") |>
  dplyr::mutate(
    outcome_group = dplyr::coalesce(outcome_group, "optional_channel_path"),
    outcome_order = dplyr::coalesce(
      outcome_order,
      max(base_registry$outcome_order, na.rm = TRUE) + dplyr::row_number()
    )
  ) |>
  dplyr::arrange(outcome_order)
outcomes <- outcome_registry$outcome

control_candidates <- spdm_main_control_candidate_cols()
control_screen_outcomes <- unique(stats::na.omit(c(outcomes, m_var)))
control_screen <- resolve_outcome_control_screen(
  panel,
  outcomes = control_screen_outcomes,
  candidates = control_candidates,
  min_finite = 500L
)
assert_spdm_main_controls_current(
  control_screen,
  context = "07_run_spdm_channel_path",
  control_col = "control",
  selected_col = "selected"
)
control_contracts <- resolve_outcome_control_contracts(control_screen, outcomes = control_screen_outcomes)

impact_sim_R <- as.integer(value_or(cfg$spdm_channel_impact_sim_R, value_or(cfg$spdm_impact_sim_R, 1000L)))
impact_sim_method <- as.character(value_or(cfg$spdm_impact_sim_method, "manual_true_sdm_matrix"))
impact_empirical <- isTRUE(value_or(cfg$spdm_impact_empirical, FALSE))
w_type_main <- as.character(value_or(cfg$default_w, "queen"))
channel_delta_inference_method <- "delta_independent_approx"
run_channel_bootstrap_enabled <- isTRUE(value_or(cfg$run_spdm_channel_bootstrap, FALSE))
channel_bootstrap_R <- as.integer(value_or(cfg$spdm_channel_bootstrap_R, 199L))
channel_bootstrap_cores <- as.integer(value_or(cfg$spdm_channel_bootstrap_cores, 1L))
channel_bootstrap_seed <- as.integer(value_or(cfg$spdm_channel_bootstrap_seed, cfg$esda_seed))
channel_bootstrap_method <- as.character(value_or(cfg$spdm_channel_bootstrap_method, "adm_cd_wild_residual"))
channel_impact_cores <- as.integer(value_or(cfg$spdm_channel_impact_cores, 1L))
if (is.finite(channel_impact_cores) && channel_impact_cores > 1L) {
  options(spdm_impact_cores = channel_impact_cores)
}


#==============================================================================
# 1. Helpers
#==============================================================================

channel_empty_path_effects_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    mediator = character(),
    effect_scale = character(),
    a_estimate = numeric(),
    a_se = numeric(),
    b_estimate = numeric(),
    b_se = numeric(),
    c_total_estimate = numeric(),
    c_total_se = numeric(),
    c_total_p = numeric(),
    c_total_ci_low = numeric(),
    c_total_ci_high = numeric(),
    c_prime_estimate = numeric(),
    c_prime_se = numeric(),
    c_prime_p = numeric(),
    c_prime_ci_low = numeric(),
    c_prime_ci_high = numeric(),
    direct_attenuation = numeric(),
    indirect_effect = numeric(),
    indirect_se = numeric(),
    indirect_z = numeric(),
    indirect_p = numeric(),
    indirect_ci_low = numeric(),
    indirect_ci_high = numeric(),
    delta_indirect_se = numeric(),
    delta_indirect_z = numeric(),
    delta_indirect_p = numeric(),
    delta_indirect_ci_low = numeric(),
    delta_indirect_ci_high = numeric(),
    bootstrap_se = numeric(),
    bootstrap_p = numeric(),
    bootstrap_ci_low = numeric(),
    bootstrap_ci_high = numeric(),
    bootstrap_valid_draws = integer(),
    bootstrap_R = integer(),
    bootstrap_method = character(),
    mediated_share_vs_cprime = numeric(),
    status = character(),
    n_units = integer(),
    n_periods = integer(),
    n_obs = integer(),
    sample_min_yq = character(),
    sample_max_yq = character(),
    model_family = character(),
    w_type = character(),
    inference_method = character(),
    message = character()
  )
}

channel_empty_bootstrap_draws_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    mediator = character(),
    draw_id = integer(),
    effect_scale = character(),
    a = numeric(),
    b = numeric(),
    c_total = numeric(),
    c_prime = numeric(),
    indirect_effect = numeric(),
    status = character(),
    model_family = character(),
    w_type = character(),
    bootstrap_method = character(),
    message = character()
  )
}

channel_empty_diagnostics_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    equation = character(),
    path = character(),
    exposure = character(),
    mediator = character(),
    model_family = character(),
    w_type = character(),
    status = character(),
    impacts_status = character(),
    n_units = integer(),
    n_periods = integer(),
    n_obs = integer(),
    sample_min_yq = character(),
    sample_max_yq = character(),
    selected_controls = character(),
    spatial_lagged_terms = character(),
    n_wx_terms = integer(),
    sdm_implementation = character(),
    impact_method = character(),
    spatial_param_name = character(),
    spatial_param_estimate = numeric(),
    spatial_param_se = numeric(),
    spatial_param_p = numeric(),
    logLik = numeric(),
    AIC = numeric(),
    BIC = numeric(),
    message = character()
  )
}

empty_channel_outputs <- function(message = NA_character_) {
  list(
    coefs = spdm_empty_coef_tbl() |> dplyr::mutate(target_outcome = character(), equation = character(), path = character(), mediator = character()),
    impacts = spdm_empty_impacts_tbl() |> dplyr::mutate(target_outcome = character(), equation = character(), path = character(), mediator = character()),
    controls = spdm_empty_controls_tbl() |> dplyr::mutate(mediator = character(), equation_scope = character()),
    path_effects = channel_empty_path_effects_tbl(),
    bootstrap_draws = channel_empty_bootstrap_draws_tbl(),
    diagnostics = channel_empty_diagnostics_tbl()
  )
}

assess_path_dims <- function(data, w_ids) {
  assess_spdm_balanced_dims(data, w_ids, required_periods = spdm_required_periods())
}

choose_controls_for_path <- function(panel, outcome, exposure, mediator, control_pool, w_ids) {
  if (length(control_pool) == 0L) return(character())

  selected <- character()
  for (ctrl in control_pool) {
    trial <- c(selected, ctrl)
    vars <- unique(c("adm_cd", "year", "quarter", "yq", outcome, exposure, mediator, trial))
    d_try <- panel |>
      dplyr::select(dplyr::all_of(vars)) |>
      tidyr::drop_na()
    dims <- assess_path_dims(d_try, w_ids)
    if (isTRUE(dims$ok)) selected <- trial
  }
  selected
}

prepare_path_sample <- function(panel, outcome, exposure, mediator, selected_controls, lw, w_ids) {
  needed <- unique(c("adm_cd", "year", "quarter", "yq", outcome, exposure, mediator, selected_controls))
  missing_vars <- setdiff(needed, names(panel))
  if (length(missing_vars) > 0L) {
    return(list(status = "failed", message = paste("missing vars:", paste(missing_vars, collapse = ", "))))
  }

  d_try <- panel |>
    dplyr::select(dplyr::all_of(needed)) |>
    tidyr::drop_na()
  if (nrow(d_try) < 400L) {
    return(list(status = "failed", message = "insufficient sample after drop_na"))
  }

  dims <- assess_path_dims(d_try, w_ids)
  if (!isTRUE(dims$ok)) {
    return(list(status = "failed", message = "insufficient balanced units for SPDM channel path"))
  }

  keep_ids <- dims$keep_ids
  lw_sub <- tryCatch(
    spdep::subset.listw(lw, subset = w_ids %in% keep_ids, zero.policy = TRUE),
    error = function(e) e
  )
  if (inherits(lw_sub, "error") || is.null(lw_sub)) {
    return(list(
      status = "failed",
      message = if (inherits(lw_sub, "error")) paste("failed to subset listw:", lw_sub$message) else "failed to subset listw"
    ))
  }

  period_levels <- spdm_required_periods()
  pdat <- d_try |>
    dplyr::filter(adm_cd %in% keep_ids) |>
    dplyr::mutate(
      adm_cd = factor(adm_cd, levels = keep_ids),
      year = as.integer(year),
      quarter = as.integer(quarter),
      yq = as.character(yq),
      time_id = as.integer(factor(yq, levels = period_levels))
    ) |>
    dplyr::arrange(adm_cd, time_id)

  list(
    status = "success",
    message = sprintf("controls_used=%s", if (length(selected_controls) == 0L) "none" else paste(selected_controls, collapse = ";")),
    pdat = pdat,
    lw_sub = lw_sub,
    n_units = as.integer(dplyr::n_distinct(pdat$adm_cd)),
    n_periods = as.integer(dplyr::n_distinct(pdat$time_id)),
    n_obs = as.integer(nrow(pdat)),
    sample_min_yq = as.character(min(pdat$yq, na.rm = TRUE)),
    sample_max_yq = as.character(max(pdat$yq, na.rm = TRUE))
  )
}

fit_sdm_rhs <- function(pdat, outcome, rhs_vars, lw_sub) {
  rhs <- unique(as.character(rhs_vars))
  wx_obj <- build_spdm_wx_terms(pdat, rhs, lw_sub)
  pdat_model <- wx_obj$data
  fm <- stats::as.formula(sprintf("%s ~ %s", outcome, paste(c(rhs, wx_obj$wx_terms), collapse = " + ")))

  fit <- tryCatch(
    splm::spml(
      formula = fm,
      data = pdat_model,
      listw = lw_sub,
      model = "within",
      lag = TRUE,
      spatial.error = "none",
      effect = "twoways",
      index = c("adm_cd", "time_id")
    ),
    error = function(e) e
  )

  if (!inherits(fit, "error")) {
    if (is.null(attr(fit, "have_factor_preds"))) attr(fit, "have_factor_preds") <- FALSE
    attr(fit, "spdm_model_family") <- "sdm"
    attr(fit, "spdm_rhs_vars") <- rhs
    attr(fit, "spdm_wx_terms") <- wx_obj$wx_terms
    attr(fit, "spdm_wx_map") <- wx_obj$wx_map
    attr(fit, "spdm_true_sdm") <- TRUE
    attr(fit, "spdm_implementation") <- "manual_wx_true_sdm"
  }

  fit
}

extract_channel_diag <- function(spec_id, outcome, equation, path, exposure, mediator, prep, mod, impacts_res, message) {
  spatial_param <- extract_spdm_spatial_param(mod)
  fit_stats <- extract_spdm_fit_stats(mod)
  wx_terms <- value_or(attr(mod, "spdm_wx_terms", exact = TRUE), character())
  sdm_implementation <- value_or(attr(mod, "spdm_implementation", exact = TRUE), NA_character_)
  impact_method <- if (nrow(impacts_res$row) > 0L) value_or(impacts_res$row$sim_method[[1]], NA_character_) else NA_character_

  channel_empty_diagnostics_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      equation = equation,
      path = path,
      exposure = exposure,
      mediator = mediator,
      model_family = "sdm",
      w_type = w_type_main,
      status = "success",
      impacts_status = impacts_res$status,
      n_units = prep$n_units,
      n_periods = prep$n_periods,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      selected_controls = collapse_chr(prep$selected_controls),
      spatial_lagged_terms = collapse_chr(wx_terms),
      n_wx_terms = length(wx_terms),
      sdm_implementation = sdm_implementation,
      impact_method = impact_method,
      spatial_param_name = spatial_param$spatial_param_name,
      spatial_param_estimate = spatial_param$spatial_param_estimate,
      spatial_param_se = spatial_param$spatial_param_se,
      spatial_param_p = spatial_param$spatial_param_p,
      logLik = fit_stats$logLik,
      AIC = fit_stats$AIC,
      BIC = fit_stats$BIC,
      message = message
    )
}

build_fail_result <- function(spec_id,
                              outcome,
                              exposure,
                              mediator,
                              message,
                              requested_controls = character(),
                              usable_controls = character(),
                              balanced_controls = character(),
                              selected_controls = character()) {
  controls_out <- build_spdm_control_rows(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    requested_controls = requested_controls,
    usable_controls = usable_controls,
    balanced_controls = balanced_controls,
    selected_controls = selected_controls,
    status = "failed",
    message = message,
    model_family = "sdm",
    w_type = w_type_main
  ) |>
    dplyr::mutate(mediator = mediator, equation_scope = "common_path_sample")

  coefs_out <- spdm_empty_coef_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      status = "failed",
      model_family = "sdm",
      w_type = w_type_main,
      message = as.character(message)
    ) |>
    dplyr::mutate(target_outcome = outcome, equation = NA_character_, path = NA_character_, mediator = mediator)

  impacts_out <- spdm_empty_impacts_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = exposure,
      status = "failed",
      model_family = "sdm",
      w_type = w_type_main,
      sim_R = impact_sim_R,
      sim_method = impact_sim_method,
      message = as.character(message)
    ) |>
    dplyr::mutate(target_outcome = outcome, equation = NA_character_, path = NA_character_, mediator = mediator)

  diag_out <- channel_empty_diagnostics_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      equation = "path",
      path = "failed",
      exposure = exposure,
      mediator = mediator,
      model_family = "sdm",
      w_type = w_type_main,
      status = "failed",
      impacts_status = "failed",
      selected_controls = collapse_chr(selected_controls),
      message = as.character(message)
    )

  path_out <- channel_empty_path_effects_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      mediator = mediator,
      effect_scale = "total",
      status = "failed",
      model_family = "sdm",
      w_type = w_type_main,
      inference_method = channel_delta_inference_method,
      message = as.character(message)
    )

  list(
    coefs = coefs_out,
    impacts = impacts_out,
    controls = controls_out,
    path_effects = path_out,
    bootstrap_draws = channel_empty_bootstrap_draws_tbl(),
    diagnostics = diag_out
  )
}

effect_value <- function(row, scale, suffix = "") {
  col <- paste0(scale, suffix)
  if (!col %in% names(row)) return(NA_real_)
  suppressWarnings(as.numeric(row[[col]][[1]]))
}

effect_p_value <- function(row, scale) {
  effect_value(row, scale, "_p")
}

effect_ci_value <- function(row, scale, side) {
  effect_value(row, scale, paste0("_ci_", side))
}

compute_channel_point_impacts <- function(mod, lw_sub, focal_var) {
  coef_vec <- spdm_get_coef_vector(mod)
  needed <- c("lambda", focal_var, spdm_wx_name(focal_var))
  if (is.null(coef_vec) || any(!needed %in% names(coef_vec))) {
    return(c(direct = NA_real_, indirect = NA_real_, total = NA_real_))
  }
  W <- tryCatch(spdep::listw2mat(lw_sub), error = function(e) e)
  if (inherits(W, "error")) return(c(direct = NA_real_, indirect = NA_real_, total = NA_real_))
  out <- tryCatch(
    compute_true_sdm_effects(
      W = W,
      rho = suppressWarnings(as.numeric(coef_vec[["lambda"]])),
      beta = suppressWarnings(as.numeric(coef_vec[[focal_var]])),
      theta = suppressWarnings(as.numeric(coef_vec[[spdm_wx_name(focal_var)]]))
    ),
    error = function(e) c(direct = NA_real_, indirect = NA_real_, total = NA_real_)
  )
  out[c("direct", "indirect", "total")]
}

extract_bootstrap_base <- function(mod, n_obs) {
  fitted_values <- tryCatch(as.numeric(stats::fitted(mod)), error = function(e) numeric())
  residual_values <- tryCatch(as.numeric(stats::residuals(mod)), error = function(e) numeric())
  if (length(fitted_values) != n_obs || length(residual_values) != n_obs) {
    return(list(status = "failed", message = "fitted/residual length mismatch"))
  }
  if (any(!is.finite(fitted_values)) || any(!is.finite(residual_values))) {
    return(list(status = "failed", message = "non-finite fitted/residual values"))
  }
  list(status = "success", fitted = fitted_values, residual = residual_values, message = "ok")
}

summarise_bootstrap_indirect <- function(draws, point) {
  draws <- suppressWarnings(as.numeric(draws))
  draws <- draws[is.finite(draws)]
  if (length(draws) <= 1L || !is.finite(point)) {
    return(list(
      se = NA_real_, p = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
      valid_draws = length(draws)
    ))
  }
  p_lower <- mean(draws <= 0, na.rm = TRUE)
  p_upper <- mean(draws >= 0, na.rm = TRUE)
  list(
    se = stats::sd(draws, na.rm = TRUE),
    p = min(1, 2 * min(p_lower, p_upper)),
    ci_low = stats::quantile(draws, 0.025, na.rm = TRUE, names = FALSE),
    ci_high = stats::quantile(draws, 0.975, na.rm = TRUE, names = FALSE),
    valid_draws = length(draws)
  )
}

run_channel_bootstrap <- function(spec_id,
                                  outcome,
                                  exposure,
                                  mediator,
                                  prep,
                                  selected_controls,
                                  mediator_mod,
                                  outcome_mod) {
  if (!isTRUE(run_channel_bootstrap_enabled) || !is.finite(channel_bootstrap_R) || channel_bootstrap_R < 1L) {
    return(channel_empty_bootstrap_draws_tbl())
  }

  med_base <- extract_bootstrap_base(mediator_mod, prep$n_obs)
  out_base <- extract_bootstrap_base(outcome_mod, prep$n_obs)
  if (!identical(med_base$status, "success") || !identical(out_base$status, "success")) {
    return(channel_empty_bootstrap_draws_tbl() |>
      dplyr::add_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        mediator = mediator,
        draw_id = NA_integer_,
        effect_scale = NA_character_,
        status = "failed",
        model_family = "sdm",
        w_type = w_type_main,
        bootstrap_method = channel_bootstrap_method,
        message = paste("bootstrap base unavailable:", med_base$message, out_base$message)
      ))
  }

  unit_ids <- levels(prep$pdat$adm_cd)
  if (is.null(unit_ids)) unit_ids <- unique(as.character(prep$pdat$adm_cd))
  spec_offset <- suppressWarnings(as.integer(gsub("\\D+", "", spec_id)))
  if (!is.finite(spec_offset)) spec_offset <- 0L
  logical_cores <- suppressWarnings(parallel::detectCores(logical = TRUE))
  if (!is.finite(logical_cores) || logical_cores < 1L) logical_cores <- 1L
  bootstrap_cores <- min(
    as.integer(channel_bootstrap_cores),
    as.integer(channel_bootstrap_R),
    max(1L, logical_cores - 1L)
  )
  if (!is.finite(bootstrap_cores) || bootstrap_cores < 1L) bootstrap_cores <- 1L

  fail_draw_row <- function(draw_id, message) {
    channel_empty_bootstrap_draws_tbl() |>
      dplyr::add_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        mediator = mediator,
        draw_id = draw_id,
        effect_scale = NA_character_,
        status = "failed",
        model_family = "sdm",
        w_type = w_type_main,
        bootstrap_method = channel_bootstrap_method,
        message = as.character(message)
      )
  }

  run_one_draw <- function(draw_id) {
    tryCatch({
      set.seed(as.integer(channel_bootstrap_seed + spec_offset * 100000L + draw_id))
      weight_vec <- sample(c(-1, 1), length(unit_ids), replace = TRUE)
      names(weight_vec) <- unit_ids
      row_weight <- unname(weight_vec[as.character(prep$pdat$adm_cd)])

      pdat_b <- prep$pdat
      pdat_b[[mediator]] <- med_base$fitted + med_base$residual * row_weight
      pdat_b[[outcome]] <- out_base$fitted + out_base$residual * row_weight

      mediator_b <- tryCatch(
        fit_sdm_rhs(pdat_b, mediator, c(exposure, selected_controls), prep$lw_sub),
        error = function(e) e
      )
      c_total_b <- tryCatch(
        fit_sdm_rhs(pdat_b, outcome, c(exposure, selected_controls), prep$lw_sub),
        error = function(e) e
      )
      outcome_b <- tryCatch(
        fit_sdm_rhs(pdat_b, outcome, c(exposure, mediator, selected_controls), prep$lw_sub),
        error = function(e) e
      )

      if (inherits(mediator_b, "error") || inherits(c_total_b, "error") || inherits(outcome_b, "error")) {
        err_msg <- paste(c(
          if (inherits(mediator_b, "error")) paste0("a: ", mediator_b$message) else character(),
          if (inherits(c_total_b, "error")) paste0("c: ", c_total_b$message) else character(),
          if (inherits(outcome_b, "error")) paste0("b_cprime: ", outcome_b$message) else character()
        ), collapse = "; ")
        return(fail_draw_row(draw_id, paste("bootstrap refit failed", err_msg)))
      }

      a_eff <- compute_channel_point_impacts(mediator_b, prep$lw_sub, exposure)
      b_eff <- compute_channel_point_impacts(outcome_b, prep$lw_sub, mediator)
      c_total_eff <- compute_channel_point_impacts(c_total_b, prep$lw_sub, exposure)
      c_prime_eff <- compute_channel_point_impacts(outcome_b, prep$lw_sub, exposure)

      purrr::map_dfr(c("direct", "indirect", "total"), function(effect_scale) {
        a <- suppressWarnings(as.numeric(a_eff[[effect_scale]]))
        b <- suppressWarnings(as.numeric(b_eff[[effect_scale]]))
        c_total <- suppressWarnings(as.numeric(c_total_eff[[effect_scale]]))
        c_prime <- suppressWarnings(as.numeric(c_prime_eff[[effect_scale]]))
        channel_empty_bootstrap_draws_tbl() |>
          dplyr::add_row(
            spec_id = spec_id,
            outcome = outcome,
            exposure = exposure,
            mediator = mediator,
            draw_id = draw_id,
            effect_scale = effect_scale,
            a = a,
            b = b,
            c_total = c_total,
            c_prime = c_prime,
            indirect_effect = a * b,
            status = if (all(is.finite(c(a, b, c_total, c_prime)))) "success" else "failed",
            model_family = "sdm",
            w_type = w_type_main,
            bootstrap_method = channel_bootstrap_method,
            message = "adm_cd wild residual bootstrap draw"
          )
      })
    }, error = function(e) {
      fail_draw_row(draw_id, paste("bootstrap draw error:", e$message))
    })
  }

  draw_rows <- if (bootstrap_cores > 1L && .Platform$OS.type != "windows") {
    parallel::mclapply(seq_len(channel_bootstrap_R), run_one_draw, mc.cores = bootstrap_cores, mc.preschedule = FALSE)
  } else {
    lapply(seq_len(channel_bootstrap_R), run_one_draw)
  }

  dplyr::bind_rows(draw_rows)
}

build_path_effect_rows <- function(spec_id, outcome, exposure, mediator, a_row, b_row, c_prime_row, c_total_row, bootstrap_draws = NULL) {
  purrr::map_dfr(c("direct", "indirect", "total"), function(effect_scale) {
    a_est <- effect_value(a_row, effect_scale)
    b_est <- effect_value(b_row, effect_scale)
    c_total_est <- effect_value(c_total_row, effect_scale)
    c_prime_est <- effect_value(c_prime_row, effect_scale)
    a_se <- effect_value(a_row, effect_scale, "_se")
    b_se <- effect_value(b_row, effect_scale, "_se")
    c_total_se <- effect_value(c_total_row, effect_scale, "_se")
    c_prime_se <- effect_value(c_prime_row, effect_scale, "_se")
    ab <- a_est * b_est
    delta_ab_se <- sqrt((b_est^2 * a_se^2) + (a_est^2 * b_se^2))
    delta_ab_z <- ab / delta_ab_se
    delta_ab_p <- 2 * stats::pnorm(-abs(delta_ab_z))
    delta_ab_ci_low <- ab - stats::qnorm(0.975) * delta_ab_se
    delta_ab_ci_high <- ab + stats::qnorm(0.975) * delta_ab_se

    boot_summary <- NULL
    if (!is.null(bootstrap_draws) && nrow(bootstrap_draws) > 0L) {
      boot_summary <- bootstrap_draws |>
        dplyr::filter(effect_scale == .env$effect_scale, status == "success") |>
        dplyr::pull(indirect_effect) |>
        summarise_bootstrap_indirect(point = ab)
    } else {
      boot_summary <- list(se = NA_real_, p = NA_real_, ci_low = NA_real_, ci_high = NA_real_, valid_draws = 0L)
    }

    use_bootstrap <- isTRUE(run_channel_bootstrap_enabled) && is.finite(boot_summary$se) && boot_summary$valid_draws > 1L
    primary_se <- if (use_bootstrap) boot_summary$se else delta_ab_se
    primary_z <- if (is.finite(primary_se) && primary_se > 0) ab / primary_se else NA_real_
    primary_p <- if (use_bootstrap) boot_summary$p else delta_ab_p
    primary_ci_low <- if (use_bootstrap) boot_summary$ci_low else delta_ab_ci_low
    primary_ci_high <- if (use_bootstrap) boot_summary$ci_high else delta_ab_ci_high
    inference_method <- if (use_bootstrap) channel_bootstrap_method else channel_delta_inference_method
    denom <- ab + c_prime_est

    channel_empty_path_effects_tbl() |>
      dplyr::add_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        mediator = mediator,
        effect_scale = effect_scale,
        a_estimate = a_est,
        a_se = a_se,
        b_estimate = b_est,
        b_se = b_se,
        c_total_estimate = c_total_est,
        c_total_se = c_total_se,
        c_total_p = effect_p_value(c_total_row, effect_scale),
        c_total_ci_low = effect_ci_value(c_total_row, effect_scale, "low"),
        c_total_ci_high = effect_ci_value(c_total_row, effect_scale, "high"),
        c_prime_estimate = c_prime_est,
        c_prime_se = c_prime_se,
        c_prime_p = effect_p_value(c_prime_row, effect_scale),
        c_prime_ci_low = effect_ci_value(c_prime_row, effect_scale, "low"),
        c_prime_ci_high = effect_ci_value(c_prime_row, effect_scale, "high"),
        direct_attenuation = c_total_est - c_prime_est,
        indirect_effect = ab,
        indirect_se = primary_se,
        indirect_z = primary_z,
        indirect_p = primary_p,
        indirect_ci_low = primary_ci_low,
        indirect_ci_high = primary_ci_high,
        delta_indirect_se = delta_ab_se,
        delta_indirect_z = delta_ab_z,
        delta_indirect_p = delta_ab_p,
        delta_indirect_ci_low = delta_ab_ci_low,
        delta_indirect_ci_high = delta_ab_ci_high,
        bootstrap_se = boot_summary$se,
        bootstrap_p = boot_summary$p,
        bootstrap_ci_low = boot_summary$ci_low,
        bootstrap_ci_high = boot_summary$ci_high,
        bootstrap_valid_draws = as.integer(boot_summary$valid_draws),
        bootstrap_R = if (isTRUE(run_channel_bootstrap_enabled)) as.integer(channel_bootstrap_R) else 0L,
        bootstrap_method = if (isTRUE(run_channel_bootstrap_enabled)) channel_bootstrap_method else NA_character_,
        mediated_share_vs_cprime = if (is.finite(denom) && abs(denom) > 1e-12) ab / denom else NA_real_,
        status = if (all(is.finite(c(a_est, b_est, ab, primary_se)))) "success" else "failed",
        n_units = suppressWarnings(as.integer(a_row$n_units[[1]])),
        n_periods = suppressWarnings(as.integer(a_row$n_periods[[1]])),
        n_obs = suppressWarnings(as.integer(a_row$n_obs[[1]])),
        sample_min_yq = as.character(a_row$sample_min_yq[[1]]),
        sample_max_yq = as.character(a_row$sample_max_yq[[1]]),
        model_family = "sdm",
        w_type = w_type_main,
        inference_method = inference_method,
        message = if (use_bootstrap) {
          "product-of-SPDM-impacts; adm_cd wild residual bootstrap inference"
        } else {
          "product-of-SPDM-impacts; delta-method assumes independent a and b impact estimates"
        }
      )
  })
}

finalize_channel_outputs <- function(out_coef, out_imp, out_ctrl, out_path, out_bootstrap, out_diag) {
  registry <- get_outcome_registry(include_robustness = TRUE) |>
    dplyr::distinct(outcome, .keep_all = TRUE)

  annotate_channel <- function(df) {
    if (!"outcome" %in% names(df)) return(df)
    df |>
      dplyr::left_join(registry, by = "outcome") |>
      dplyr::mutate(
        outcome_group = dplyr::coalesce(outcome_group, dplyr::if_else(outcome == m_var, "mediator", NA_character_)),
        outcome_order = dplyr::coalesce(outcome_order, ifelse(outcome == m_var, 0L, NA_integer_))
      )
  }

  list(
    coefs = annotate_channel(out_coef) |>
      dplyr::arrange(outcome_order, spec_id, equation, term),
    impacts = annotate_channel(out_imp) |>
      dplyr::arrange(outcome_order, spec_id, path, focal_var),
    controls = annotate_channel(out_ctrl) |>
      dplyr::arrange(outcome_order, spec_id, control_order),
    path_effects = annotate_channel(out_path) |>
      dplyr::arrange(outcome_order, spec_id, effect_scale),
    bootstrap_draws = annotate_channel(out_bootstrap) |>
      dplyr::arrange(outcome_order, spec_id, draw_id, effect_scale),
    diagnostics = annotate_channel(out_diag) |>
      dplyr::arrange(outcome_order, spec_id, equation)
  )
}

run_path_spec <- function(spec_id, outcome, exposure, mediator, panel, lw, w_ids, requested_controls, usable_controls) {
  target_outcome <- outcome
  control_pool <- intersect(usable_controls, names(panel))
  selected_controls <- choose_controls_for_path(panel, outcome, exposure, mediator, control_pool, w_ids)
  control_ladder <- make_spdm_control_ladder(selected_controls)
  last_message <- "no estimable control set"

  for (ctrl_try in control_ladder) {
    prep <- prepare_path_sample(panel, outcome, exposure, mediator, ctrl_try, lw, w_ids)
    prep$selected_controls <- ctrl_try
    if (!identical(prep$status, "success")) {
      last_message <- prep$message
      next
    }

    mediator_rhs <- c(exposure, ctrl_try)
    mediator_mod <- tryCatch(fit_sdm_rhs(prep$pdat, mediator, mediator_rhs, prep$lw_sub), error = function(e) e)
    if (inherits(mediator_mod, "error")) {
      last_message <- paste("mediator equation error:", mediator_mod$message)
      next
    }

    c_total_rhs <- c(exposure, ctrl_try)
    c_total_mod <- tryCatch(fit_sdm_rhs(prep$pdat, outcome, c_total_rhs, prep$lw_sub), error = function(e) e)
    if (inherits(c_total_mod, "error")) {
      last_message <- paste("c-total equation error:", c_total_mod$message)
      next
    }

    outcome_rhs <- c(exposure, mediator, ctrl_try)
    outcome_mod <- tryCatch(fit_sdm_rhs(prep$pdat, outcome, outcome_rhs, prep$lw_sub), error = function(e) e)
    if (inherits(outcome_mod, "error")) {
      last_message <- paste("outcome equation error:", outcome_mod$message)
      next
    }

    a_imp <- compute_spdm_impacts_row(
      spec_id = spec_id,
      outcome = mediator,
      exposure = exposure,
      focal_var = exposure,
      mod = mediator_mod,
      lw_sub = prep$lw_sub,
      n_periods = prep$n_periods,
      n_units = prep$n_units,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "sdm",
      w_type = w_type_main,
      sim_R = impact_sim_R,
      sim_method = impact_sim_method,
      empirical = impact_empirical,
      seed = cfg$esda_seed,
      message = prep$message
    )

    b_imp <- compute_spdm_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = mediator,
      focal_var = mediator,
      mod = outcome_mod,
      lw_sub = prep$lw_sub,
      n_periods = prep$n_periods,
      n_units = prep$n_units,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "sdm",
      w_type = w_type_main,
      sim_R = impact_sim_R,
      sim_method = impact_sim_method,
      empirical = impact_empirical,
      seed = cfg$esda_seed,
      message = prep$message
    )

    c_total_imp <- compute_spdm_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = exposure,
      mod = c_total_mod,
      lw_sub = prep$lw_sub,
      n_periods = prep$n_periods,
      n_units = prep$n_units,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "sdm",
      w_type = w_type_main,
      sim_R = impact_sim_R,
      sim_method = impact_sim_method,
      empirical = impact_empirical,
      seed = cfg$esda_seed,
      message = prep$message
    )

    c_imp <- compute_spdm_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = exposure,
      mod = outcome_mod,
      lw_sub = prep$lw_sub,
      n_periods = prep$n_periods,
      n_units = prep$n_units,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "sdm",
      w_type = w_type_main,
      sim_R = impact_sim_R,
      sim_method = impact_sim_method,
      empirical = impact_empirical,
      seed = cfg$esda_seed,
      message = prep$message
    )

    if (!identical(a_imp$status, "success") || !identical(b_imp$status, "success") ||
        !identical(c_total_imp$status, "success") || !identical(c_imp$status, "success")) {
      last_message <- paste(
        "impact failure:",
        paste(c(a = a_imp$message, b = b_imp$message, c_total = c_total_imp$message, c_prime = c_imp$message), collapse = " | ")
      )
      next
    }

    mediator_coef <- extract_spdm_coef_table(
      mod = mediator_mod,
      spec_id = spec_id,
      outcome = mediator,
      exposure = exposure,
      n_units = prep$n_units,
      n_periods = prep$n_periods,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "sdm",
      w_type = w_type_main,
      message = prep$message
    ) |>
      dplyr::mutate(target_outcome = .env$target_outcome, equation = "mediator", path = "a_x_to_m", mediator = mediator)

    c_total_coef <- extract_spdm_coef_table(
      mod = c_total_mod,
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      n_units = prep$n_units,
      n_periods = prep$n_periods,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "sdm",
      w_type = w_type_main,
      message = prep$message
    ) |>
      dplyr::mutate(target_outcome = .env$target_outcome, equation = "outcome_total", path = "c_total_x_to_y", mediator = mediator)

    outcome_coef <- extract_spdm_coef_table(
      mod = outcome_mod,
      spec_id = spec_id,
      outcome = outcome,
      exposure = paste(c(exposure, mediator), collapse = " + "),
      n_units = prep$n_units,
      n_periods = prep$n_periods,
      n_obs = prep$n_obs,
      sample_min_yq = prep$sample_min_yq,
      sample_max_yq = prep$sample_max_yq,
      model_family = "sdm",
      w_type = w_type_main,
      message = prep$message
    ) |>
      dplyr::mutate(target_outcome = .env$target_outcome, equation = "outcome", path = "b_m_and_cprime_x_to_y", mediator = mediator)

    impacts_out <- dplyr::bind_rows(
      a_imp$row |> dplyr::mutate(target_outcome = .env$target_outcome, equation = "mediator", path = "a_x_to_m", mediator = mediator),
      c_total_imp$row |> dplyr::mutate(target_outcome = .env$target_outcome, equation = "outcome_total", path = "c_total_x_to_y", mediator = mediator),
      b_imp$row |> dplyr::mutate(target_outcome = .env$target_outcome, equation = "outcome", path = "b_m_to_y", mediator = mediator),
      c_imp$row |> dplyr::mutate(target_outcome = .env$target_outcome, equation = "outcome", path = "c_prime_x_to_y", mediator = mediator)
    )

    controls_out <- build_spdm_control_rows(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      requested_controls = requested_controls,
      usable_controls = usable_controls,
      balanced_controls = selected_controls,
      selected_controls = ctrl_try,
      status = "success",
      message = prep$message,
      model_family = "sdm",
      w_type = w_type_main
    ) |>
      dplyr::mutate(mediator = mediator, equation_scope = "common_path_sample")

    diagnostics_out <- dplyr::bind_rows(
      extract_channel_diag(spec_id, outcome, "mediator", "a_x_to_m", exposure, mediator, prep, mediator_mod, a_imp, a_imp$message),
      extract_channel_diag(spec_id, outcome, "outcome_total", "c_total_x_to_y", exposure, mediator, prep, c_total_mod, c_total_imp, c_total_imp$message),
      extract_channel_diag(spec_id, outcome, "outcome", "b_m_and_cprime_x_to_y", exposure, mediator, prep, outcome_mod, b_imp, b_imp$message)
    )

    bootstrap_draws_out <- run_channel_bootstrap(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      mediator = mediator,
      prep = prep,
      selected_controls = ctrl_try,
      mediator_mod = mediator_mod,
      outcome_mod = outcome_mod
    )

    path_effects_out <- build_path_effect_rows(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      mediator = mediator,
      a_row = a_imp$row,
      b_row = b_imp$row,
      c_prime_row = c_imp$row,
      c_total_row = c_total_imp$row,
      bootstrap_draws = bootstrap_draws_out
    )

    return(list(
      coefs = dplyr::bind_rows(mediator_coef, c_total_coef, outcome_coef),
      impacts = impacts_out,
      controls = controls_out,
      path_effects = path_effects_out,
      bootstrap_draws = bootstrap_draws_out,
      diagnostics = diagnostics_out
    ))
  }

  build_fail_result(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    mediator = mediator,
    message = last_message,
    requested_controls = requested_controls,
    usable_controls = usable_controls,
    balanced_controls = selected_controls,
    selected_controls = character()
  )
}


#==============================================================================
# 2. Run Canonical SPDM Channel Path and Save Outputs
#==============================================================================

if (length(outcomes) == 0L || length(x_var) == 0L || length(m_var) == 0L || !all(c(x_var, m_var) %in% names(panel))) {
  finalized <- finalize_channel_outputs(
    empty_channel_outputs()$coefs,
    empty_channel_outputs()$impacts,
    empty_channel_outputs()$controls,
    empty_channel_outputs()$path_effects,
    empty_channel_outputs()$bootstrap_draws,
    empty_channel_outputs()$diagnostics
  )
  write_csv_safe(finalized$coefs, path_channel_models)
  write_csv_safe(finalized$impacts, path_channel_impacts)
  write_csv_safe(finalized$controls, path_channel_controls)
  write_csv_safe(finalized$path_effects, path_channel_path_effects)
  write_csv_safe(finalized$bootstrap_draws, path_channel_bootstrap_draws)
  write_csv_safe(finalized$diagnostics, path_channel_diagnostics)
  append_log(cfg$logs$model_run, "- Skipped: missing SPDM channel path outcomes/exposure/mediator")
} else {
  lw <- readRDS(cfg$paths$w_queen)
  w_ids <- attr(lw$neighbours, "region.id")

  if (is.null(w_ids)) {
    finalized <- finalize_channel_outputs(
      empty_channel_outputs()$coefs,
      empty_channel_outputs()$impacts,
      empty_channel_outputs()$controls,
      empty_channel_outputs()$path_effects,
      empty_channel_outputs()$bootstrap_draws,
      empty_channel_outputs()$diagnostics
    )
    write_csv_safe(finalized$coefs, path_channel_models)
    write_csv_safe(finalized$impacts, path_channel_impacts)
    write_csv_safe(finalized$controls, path_channel_controls)
    write_csv_safe(finalized$path_effects, path_channel_path_effects)
    write_csv_safe(finalized$bootstrap_draws, path_channel_bootstrap_draws)
    write_csv_safe(finalized$diagnostics, path_channel_diagnostics)
    append_log(cfg$logs$model_run, "- Skipped: region.id missing in W")
  } else {
    w_ids <- as.character(w_ids)

    spec_grid <- outcome_registry |>
      dplyr::select(outcome, outcome_group, outcome_order) |>
      dplyr::mutate(spec_id = sprintf("SC%02d", dplyr::row_number()))

    mediator_contract <- control_contracts[[m_var]]
    res <- purrr::pmap(
      list(spec_grid$spec_id, spec_grid$outcome),
      function(spec_id, outcome) {
        outcome_contract <- control_contracts[[outcome]]
        run_path_spec(
          spec_id = spec_id,
          outcome = outcome,
          exposure = x_var,
          mediator = m_var,
          panel = panel,
          lw = lw,
          w_ids = w_ids,
          requested_controls = control_candidates,
          usable_controls = intersect(outcome_contract$usable_controls, mediator_contract$usable_controls)
        )
      }
    )

    finalized <- finalize_channel_outputs(
      dplyr::bind_rows(purrr::map(res, "coefs")),
      dplyr::bind_rows(purrr::map(res, "impacts")),
      dplyr::bind_rows(purrr::map(res, "controls")),
      dplyr::bind_rows(purrr::map(res, "path_effects")),
      dplyr::bind_rows(purrr::map(res, "bootstrap_draws")),
      dplyr::bind_rows(purrr::map(res, "diagnostics"))
    )

    write_csv_safe(finalized$coefs, path_channel_models)
    write_csv_safe(finalized$impacts, path_channel_impacts)
    write_csv_safe(finalized$controls, path_channel_controls)
    write_csv_safe(finalized$path_effects, path_channel_path_effects)
    write_csv_safe(finalized$bootstrap_draws, path_channel_bootstrap_draws)
    write_csv_safe(finalized$diagnostics, path_channel_diagnostics)

    n_success <- sum(finalized$path_effects$status == "success" & finalized$path_effects$effect_scale == "total", na.rm = TRUE)
    n_fail <- sum(finalized$path_effects$status != "success" & finalized$path_effects$effect_scale == "total", na.rm = TRUE)
    append_log(
      cfg$logs$model_run,
      sprintf("- SPDM channel path specs attempted: %d (total indirect effects success=%d, failed=%d)", nrow(spec_grid), n_success, n_fail)
    )
  }
}
