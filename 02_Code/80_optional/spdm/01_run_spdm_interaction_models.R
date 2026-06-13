#==============================================================================
# Script    : 01_run_spdm_interaction_models.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the supplementary/manual SPDM COVID interaction appendix and
#             export coefficients,
#             impacts, effect summaries, and selected controls.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-03-29
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, W_queen.rds
# Outputs   : spdm_interaction_models.csv, spdm_interaction_impacts.csv,
#             spdm_interaction_effect_summary.csv,
#             spdm_interaction_controls_used.csv,
#             spdm_interaction_diagnostics.csv
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

append_log(cfg$logs$model_run, sprintf("\n## [%s] 01_run_spdm_interaction_models", timestamp()))

path_interaction_models <- value_or(cfg$paths$spdm_interaction_models, file.path(cfg$dir_tables, "spdm_interaction_models.csv"))
path_interaction_impacts <- value_or(cfg$paths$spdm_interaction_impacts, file.path(cfg$dir_tables, "spdm_interaction_impacts.csv"))
path_interaction_summary <- value_or(cfg$paths$spdm_interaction_effect_summary, file.path(cfg$dir_tables, "spdm_interaction_effect_summary.csv"))
path_interaction_controls <- value_or(cfg$paths$spdm_interaction_controls_used, file.path(cfg$dir_tables, "spdm_interaction_controls_used.csv"))
path_interaction_diagnostics <- value_or(cfg$paths$spdm_interaction_diagnostics, file.path(cfg$dir_tables, "spdm_interaction_diagnostics.csv"))

if (!file.exists(cfg$paths$panel_main) || !file.exists(cfg$paths$w_queen)) {
  stop("[ERROR] Missing panel or W", call. = FALSE)
}

panel <- read_panel_main_view("spdm", extra_cols = "covid_period")
panel$adm_cd <- as.character(panel$adm_cd)
if (!"covid_period" %in% names(panel)) {
  panel$covid_period <- NA_real_
} else {
  panel$covid_period <- suppressWarnings(as.numeric(panel$covid_period))
}

outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = value_or(cfg$spdm_interaction_outcomes, value_or(cfg$spdm_main_outcomes, c(
    "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability", "vitality_index_base"
  ))),
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome
main_exposure <- intersect(
  value_or(cfg$spdm_main_exposure_vars, c("lag4_age60_resident_share")),
  names(panel)
)

control_candidates <- spdm_main_control_candidate_cols()
control_screen <- resolve_outcome_control_screen(
  panel,
  outcomes = outcomes,
  candidates = control_candidates,
  min_finite = 500L
)
assert_spdm_main_controls_current(
  control_screen,
  context = "01_run_spdm_interaction_models",
  control_col = "control",
  selected_col = "selected"
)
control_contracts <- resolve_outcome_control_contracts(control_screen, outcomes = outcomes)


#==============================================================================
# 1. Helpers
#==============================================================================

build_control_rows <- function(spec_id,
                               interaction_family,
                               outcome,
                               requested_controls,
                               usable_controls,
                               balanced_controls,
                               selected_controls,
                               status,
                               message) {
  if (length(requested_controls) == 0L) {
    return(tibble::tibble(
      spec_id = character(),
      interaction_family = character(),
      outcome = character(),
      control_var = character(),
      control_order = integer(),
      requested = logical(),
      usable = logical(),
      balanced_candidate = logical(),
      selected = logical(),
      status = character(),
      message = character()
    ))
  }

  tibble::tibble(
    spec_id = spec_id,
    interaction_family = interaction_family,
    outcome = outcome,
    control_var = requested_controls,
    control_order = seq_along(requested_controls),
    requested = TRUE,
    usable = requested_controls %in% usable_controls,
    balanced_candidate = requested_controls %in% balanced_controls,
    selected = requested_controls %in% selected_controls,
    status = status,
    message = as.character(message)
  )
}

infer_summary_scope <- function(effect_kind) {
  dplyr::case_when(
    effect_kind == "coefficient" ~ "coefficient_delta_method",
    effect_kind %in% c("direct", "indirect", "total") ~ "descriptive_point_estimate",
    TRUE ~ "not_available"
  )
}

infer_covid_baseline_label <- function(sample_quarter_index, sample_covid) {
  sample_quarter_index <- suppressWarnings(as.integer(sample_quarter_index))
  sample_covid <- suppressWarnings(as.numeric(sample_covid))
  covid_start_idx <- suppressWarnings(as.integer(cfg$covid_start_idx))
  covid_end_idx <- suppressWarnings(as.integer(cfg$covid_end_idx))
  non_covid_qidx <- sample_quarter_index[
    !is.na(sample_quarter_index) & !is.na(sample_covid) & sample_covid == 0
  ]
  if (length(non_covid_qidx) == 0L) {
    return("non_covid_in_sample")
  }

  if (all(non_covid_qidx < covid_start_idx)) {
    return("pre_covid")
  }
  if (all(non_covid_qidx > covid_end_idx)) {
    return("post_covid")
  }
  if (any(non_covid_qidx < covid_start_idx) && any(non_covid_qidx > covid_end_idx)) {
    return("non_covid_mixed_sample")
  }

  "non_covid_in_sample"
}

resolve_effect_definition <- function(interaction_family, rhs_vars, sample_quarter_index = NULL, sample_covid = NULL) {
  baseline_label <- infer_covid_baseline_label(
    sample_quarter_index = sample_quarter_index,
    sample_covid = sample_covid
  )
  effect_defs <- list(
    stats::setNames(1, rhs_vars[[1]]),
    covid_period = stats::setNames(c(1, 1), rhs_vars[1:2])
  )
  names(effect_defs)[[1]] <- baseline_label
  list(
    effect_defs = effect_defs,
    baseline_period_label = baseline_label,
    covid_period_label = "covid_period",
    effect_label_definition = sprintf(
      "covid_period denotes realized sample observations within %s; %s denotes realized non-COVID observations outside that quarter window.",
      cfg$covid_period_label,
      baseline_label
    )
  )
}

build_interaction_diag_row <- function(spec_id,
                                       interaction_family,
                                       outcome,
                                       status,
                                       sample_yq = character(),
                                       sample_quarter_index = integer(),
                                       sample_covid = numeric(),
                                       n_units = NA_integer_,
                                       n_periods = NA_integer_,
                                       n_obs = NA_integer_,
                                       selected_controls = character(),
                                       baseline_period_label = NA_character_,
                                       covid_period_label = NA_character_,
                                       effect_label_definition = NA_character_,
                                       message = NA_character_) {
  sample_yq <- as.character(sample_yq)
  sample_quarter_index <- suppressWarnings(as.integer(sample_quarter_index))
  sample_covid <- suppressWarnings(as.numeric(sample_covid))
  has_yq <- length(sample_yq) > 0L
  has_quarter_index <- length(sample_quarter_index) > 0L

  tibble::tibble(
    spec_id = spec_id,
    interaction_family = interaction_family,
    outcome = outcome,
    status = as.character(status),
    n_units = as.integer(n_units),
    n_periods = as.integer(n_periods),
    n_obs = as.integer(n_obs),
    sample_min_yq = if (has_yq) as.character(min(sample_yq, na.rm = TRUE)) else NA_character_,
    sample_max_yq = if (has_yq) as.character(max(sample_yq, na.rm = TRUE)) else NA_character_,
    n_covid_obs = if (has_quarter_index) as.integer(sum(sample_covid == 1, na.rm = TRUE)) else NA_integer_,
    n_non_covid_obs = if (has_quarter_index) as.integer(sum(sample_covid == 0, na.rm = TRUE)) else NA_integer_,
    n_pre_covid_obs = if (has_quarter_index) {
      as.integer(sum(sample_covid == 0 & sample_quarter_index < cfg$covid_start_idx, na.rm = TRUE))
    } else {
      NA_integer_
    },
    n_post_covid_obs = if (has_quarter_index) {
      as.integer(sum(sample_covid == 0 & sample_quarter_index > cfg$covid_end_idx, na.rm = TRUE))
    } else {
      NA_integer_
    },
    baseline_period_label = as.character(baseline_period_label),
    covid_period_label = as.character(covid_period_label),
    effect_label_definition = as.character(effect_label_definition),
    selected_controls = if (length(selected_controls) == 0L) "none" else paste(selected_controls, collapse = ";"),
    message = as.character(message)
  )
}

build_fail_summary_rows <- function(spec_id, interaction_family, outcome, effect_defs, message) {
  effect_labels <- names(effect_defs)
  if (length(effect_labels) == 0L) {
    return(tibble::tibble(
      spec_id = character(),
      interaction_family = character(),
      outcome = character(),
      effect_label = character(),
      effect_kind = character(),
      estimate = numeric(),
      std.error = numeric(),
      statistic = numeric(),
      p.value = numeric(),
      inference_scope = character(),
      effect_label_definition = character(),
      source_terms = character(),
      status = character(),
      message = character()
    ))
  }

  effect_kind <- rep(c("coefficient", "direct", "indirect", "total"), times = length(effect_labels))

  tibble::tibble(
    spec_id = spec_id,
    interaction_family = interaction_family,
    outcome = outcome,
    effect_label = rep(effect_labels, each = 4L),
    effect_kind = effect_kind,
    estimate = NA_real_,
    std.error = NA_real_,
    statistic = NA_real_,
    p.value = NA_real_,
    inference_scope = infer_summary_scope(effect_kind),
    effect_label_definition = NA_character_,
    source_terms = rep(vapply(effect_defs, function(x) paste(names(x), collapse = " + "), character(1)), each = 4L),
    status = "failed",
    message = as.character(message)
  )
}

make_fail <- function(spec_id,
                      interaction_family,
                      outcome,
                      focal_vars,
                      effect_defs,
                      message,
                      requested_controls = character(),
                      usable_controls = character(),
                      balanced_controls = character(),
                      selected_controls = character()) {
  list(
    coefs = tibble::tibble(
      spec_id = spec_id,
      interaction_family = interaction_family,
      outcome = outcome,
      term = NA_character_,
      estimate = NA_real_,
      std.error = NA_real_,
      statistic = NA_real_,
      p.value = NA_real_,
      status = "failed",
      n_units = NA_integer_,
      n_periods = NA_integer_,
      n_obs = NA_integer_,
      message = as.character(message)
    ),
    impacts = tibble::tibble(
      spec_id = spec_id,
      interaction_family = interaction_family,
      outcome = outcome,
      focal_var = focal_vars,
      direct = NA_real_,
      indirect = NA_real_,
      total = NA_real_,
      inference_scope = "not_available",
      status = "failed",
      message = as.character(message)
    ),
    summary = build_fail_summary_rows(spec_id, interaction_family, outcome, effect_defs, message),
    diagnostics = build_interaction_diag_row(
      spec_id = spec_id,
      interaction_family = interaction_family,
      outcome = outcome,
      status = "failed",
      selected_controls = selected_controls,
      message = message
    ),
    controls = build_control_rows(
      spec_id = spec_id,
      interaction_family = interaction_family,
      outcome = outcome,
      requested_controls = requested_controls,
      usable_controls = usable_controls,
      balanced_controls = balanced_controls,
      selected_controls = selected_controls,
      status = "failed",
      message = message
    )
  )
}

pick_effect_value <- function(df, key) {
  nms <- names(df)
  hit <- nms[tolower(nms) == tolower(key)]
  if (length(hit) == 0L) return(NA_real_)
  suppressWarnings(as.numeric(df[[hit[[1]]]]))
}

assess_balanced_dims <- function(d, w_ids) {
  if (nrow(d) == 0) {
    return(list(ok = FALSE, keep_ids = character(), n_units = 0L, n_periods = 0L))
  }

  balanced <- d |>
    dplyr::count(adm_cd, name = "n_t")
  full_t <- max(balanced$n_t)
  adm_balanced <- balanced |>
    dplyr::filter(n_t == full_t) |>
    dplyr::pull(adm_cd)

  keep_ids <- intersect(w_ids, adm_balanced)
  list(
    ok = (length(keep_ids) >= 20L && full_t >= cfg$spdm_min_periods),
    keep_ids = keep_ids,
    n_units = as.integer(length(keep_ids)),
    n_periods = as.integer(full_t)
  )
}

choose_controls_for_spec_multi <- function(panel, outcome, rhs_vars, control_pool, w_ids) {
  if (length(control_pool) == 0L) return(character())

  selected <- character()
  for (ctrl in control_pool) {
    trial <- c(selected, ctrl)
    vars <- unique(c("adm_cd", "year", outcome, rhs_vars, trial))
    d_try <- panel |>
      dplyr::select(dplyr::all_of(vars)) |>
      tidyr::drop_na()
    dims <- assess_balanced_dims(d_try, w_ids)
    if (isTRUE(dims$ok)) {
      selected <- trial
    }
  }
  selected
}

make_control_ladder <- function(controls) {
  k <- length(controls)
  lapply(seq(k, 0L), function(i) {
    if (i == 0L) character() else controls[seq_len(i)]
  })
}

build_effect_summary <- function(spec_id,
                                 interaction_family,
                                 outcome,
                                 coef_tbl,
                                 mod,
                                 impacts_tbl,
                                 effect_defs,
                                 effect_label_definition,
                                 default_message) {
  coef_named <- stats::setNames(coef_tbl$estimate, coef_tbl$term)
  vc <- tryCatch(stats::vcov(mod), error = function(e) NULL)
  vc_names <- if (!is.null(vc)) rownames(vc) else character()
  if (!is.null(vc) && (is.null(vc_names) || all(is.na(vc_names)) || all(vc_names == "")) && nrow(vc) == nrow(coef_tbl)) {
    vc_names <- coef_tbl$term
    rownames(vc) <- vc_names
    colnames(vc) <- vc_names
  }

  coef_rows <- purrr::imap_dfr(effect_defs, function(weights, effect_label) {
    terms <- names(weights)
    missing_terms <- setdiff(terms, names(coef_named))
    source_terms <- paste(terms, collapse = " + ")
    if (length(missing_terms) > 0L) {
      return(tibble::tibble(
        spec_id = spec_id,
        interaction_family = interaction_family,
        outcome = outcome,
        effect_label = effect_label,
        effect_kind = "coefficient",
        estimate = NA_real_,
        std.error = NA_real_,
        statistic = NA_real_,
        p.value = NA_real_,
        inference_scope = "not_available",
        effect_label_definition = as.character(effect_label_definition),
        source_terms = source_terms,
        status = "failed",
        message = paste("coefficient terms missing:", paste(missing_terms, collapse = ", "))
      ))
    }

    estimate <- sum(unname(weights) * coef_named[terms])
    se <- NA_real_
    stat <- NA_real_
    pval <- NA_real_
    msg <- default_message
    if (!is.null(vc) && all(terms %in% vc_names)) {
      vc_sub <- vc[terms, terms, drop = FALSE]
      w <- matrix(unname(weights), ncol = 1L)
      var_hat <- as.numeric(t(w) %*% vc_sub %*% w)
      if (is.finite(var_hat) && var_hat >= 0) {
        se <- sqrt(var_hat)
        if (is.finite(se) && se > 0) {
          stat <- estimate / se
          pval <- 2 * stats::pnorm(-abs(stat))
        }
      }
    } else {
      msg <- paste(default_message, "| delta-method unavailable")
    }

    tibble::tibble(
      spec_id = spec_id,
      interaction_family = interaction_family,
      outcome = outcome,
      effect_label = effect_label,
      effect_kind = "coefficient",
      estimate = estimate,
      std.error = se,
      statistic = stat,
      p.value = pval,
      inference_scope = infer_summary_scope("coefficient"),
      effect_label_definition = as.character(effect_label_definition),
      source_terms = source_terms,
      status = "success",
      message = msg
    )
  })

  impact_rows <- purrr::imap_dfr(effect_defs, function(weights, effect_label) {
    terms <- names(weights)
    source_terms <- paste(terms, collapse = " + ")
    sub <- impacts_tbl |>
      dplyr::filter(focal_var %in% terms)
    if (nrow(sub) != length(terms) || any(sub$status != "success")) {
      return(tibble::tibble(
        spec_id = spec_id,
        interaction_family = interaction_family,
        outcome = outcome,
        effect_label = effect_label,
        effect_kind = c("direct", "indirect", "total"),
        estimate = NA_real_,
        std.error = NA_real_,
        statistic = NA_real_,
        p.value = NA_real_,
        inference_scope = infer_summary_scope(c("direct", "indirect", "total")),
        effect_label_definition = as.character(effect_label_definition),
        source_terms = source_terms,
        status = "failed",
        message = "impact rows unavailable for all source terms"
      ))
    }

    sub <- sub[match(terms, sub$focal_var), , drop = FALSE]
    weights_vec <- unname(weights)
    effect_kind <- c("direct", "indirect", "total")
    tibble::tibble(
      spec_id = spec_id,
      interaction_family = interaction_family,
      outcome = outcome,
      effect_label = effect_label,
      effect_kind = effect_kind,
      estimate = c(
        sum(weights_vec * sub$direct),
        sum(weights_vec * sub$indirect),
        sum(weights_vec * sub$total)
      ),
      std.error = NA_real_,
      statistic = NA_real_,
      p.value = NA_real_,
      inference_scope = infer_summary_scope(effect_kind),
      effect_label_definition = as.character(effect_label_definition),
      source_terms = source_terms,
      status = "success",
      message = default_message
    )
  })

  dplyr::bind_rows(coef_rows, impact_rows)
}

finalize_spdm_interaction_outputs <- function(out_coef, out_imp, out_sum, out_ctrl, out_diag) {
  list(
    coefs = out_coef |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, interaction_family, spec_id, term),
    impacts = out_imp |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, interaction_family, spec_id, focal_var),
    summary = out_sum |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, interaction_family, spec_id, effect_label, effect_kind),
    diagnostics = out_diag |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, interaction_family, spec_id),
    controls = out_ctrl |>
      annotate_outcomes(include_robustness = FALSE) |>
      dplyr::arrange(outcome_order, interaction_family, spec_id, control_order)
  )
}

run_one_spec <- function(spec_id,
                         interaction_family,
                         outcome,
                         rhs_vars,
                         effect_defs,
                         panel,
                         lw,
                         w_ids,
                         requested_controls,
                         usable_controls) {
  missing_rhs <- setdiff(rhs_vars, names(panel))
  if (length(missing_rhs) > 0L) {
    return(make_fail(
      spec_id, interaction_family, outcome, rhs_vars, effect_defs,
      paste("missing interaction vars:", paste(missing_rhs, collapse = ", ")),
      requested_controls = requested_controls,
      usable_controls = usable_controls
    ))
  }

  spec_controls <- choose_controls_for_spec_multi(panel, outcome, rhs_vars, usable_controls, w_ids)
  control_ladder <- make_control_ladder(spec_controls)
  mod <- NULL
  mod_err_message <- "no estimable control set"
  used_controls <- character()
  lw_sub <- NULL
  n_units <- NA_integer_
  n_periods <- NA_integer_
  n_obs <- NA_integer_

  for (ctrl_try in control_ladder) {
    vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "covid_period", outcome, rhs_vars, ctrl_try))
    d_try <- panel |>
      dplyr::select(dplyr::all_of(vars)) |>
      tidyr::drop_na()
    if (nrow(d_try) < 400L) {
      mod_err_message <- "insufficient sample after drop_na"
      next
    }

    dims <- assess_balanced_dims(d_try, w_ids)
    keep_ids <- dims$keep_ids
    if (!isTRUE(dims$ok)) {
      mod_err_message <- "insufficient balanced units for SPDM"
      next
    }

    lw_try <- tryCatch(
      spdep::subset.listw(lw, subset = w_ids %in% keep_ids, zero.policy = TRUE),
      error = function(e) e
    )
    if (inherits(lw_try, "error") || is.null(lw_try)) {
      mod_err_message <- if (inherits(lw_try, "error")) paste("failed to subset listw:", lw_try$message) else "failed to subset listw"
      next
    }

    yq_levels <- d_try |>
      dplyr::distinct(yq, quarter_index) |>
      dplyr::arrange(quarter_index, yq) |>
      dplyr::pull(yq) |>
      as.character()

    pdat_try <- d_try |>
      dplyr::filter(adm_cd %in% keep_ids) |>
      dplyr::mutate(
        adm_cd = factor(adm_cd, levels = keep_ids),
        yq = as.character(yq),
        time_id = as.integer(factor(yq, levels = yq_levels))
      ) |>
      dplyr::arrange(adm_cd, time_id)

    n_units_try <- dplyr::n_distinct(pdat_try$adm_cd)
    n_periods_try <- dplyr::n_distinct(pdat_try$time_id)
    n_obs_try <- nrow(pdat_try)
    if (n_units_try < 20L || n_periods_try < cfg$spdm_min_periods) {
      mod_err_message <- "insufficient aligned panel dimensions"
      next
    }

    rhs <- c(rhs_vars, ctrl_try)
    wx_obj <- tryCatch(build_spdm_wx_terms(pdat_try, rhs, lw_try), error = function(e) e)
    if (inherits(wx_obj, "error")) {
      mod_err_message <- paste("W X construction error:", wx_obj$message)
      next
    }
    pdat_model <- wx_obj$data
    fm <- stats::as.formula(sprintf("%s ~ %s", outcome, paste(c(rhs, wx_obj$wx_terms), collapse = " + ")))
    mod_try <- tryCatch(
      splm::spml(
        formula = fm,
        data = pdat_model,
        listw = lw_try,
        model = "within",
        lag = TRUE,
        spatial.error = "none",
        effect = "twoways",
        index = c("adm_cd", "time_id")
      ),
      error = function(e) e
    )
    if (!inherits(mod_try, "error")) {
      attr(mod_try, "spdm_model_family") <- "sdm"
      attr(mod_try, "spdm_rhs_vars") <- rhs
      attr(mod_try, "spdm_wx_terms") <- wx_obj$wx_terms
      attr(mod_try, "spdm_wx_map") <- wx_obj$wx_map
      attr(mod_try, "spdm_true_sdm") <- TRUE
      attr(mod_try, "spdm_implementation") <- "manual_wx_true_sdm"
      mod <- mod_try
      used_controls <- ctrl_try
      lw_sub <- lw_try
      n_units <- as.integer(n_units_try)
      n_periods <- as.integer(n_periods_try)
      n_obs <- as.integer(n_obs_try)
      break
    }
    mod_err_message <- paste("spml error:", mod_try$message)
  }

  if (is.null(mod)) {
    return(make_fail(
      spec_id, interaction_family, outcome, rhs_vars, effect_defs, mod_err_message,
      requested_controls = requested_controls,
      usable_controls = usable_controls,
      balanced_controls = spec_controls,
      selected_controls = used_controls
    ))
  }

  sm <- summary(mod)
  coef_tbl <- tryCatch(as.data.frame(sm$CoefTable), error = function(e) NULL)
  if (is.null(coef_tbl) || nrow(coef_tbl) == 0L) {
    return(make_fail(
      spec_id, interaction_family, outcome, rhs_vars, effect_defs, "CoefTable unavailable from SPDM",
      requested_controls = requested_controls,
      usable_controls = usable_controls,
      balanced_controls = spec_controls,
      selected_controls = used_controls
    ))
  }

  coef_tbl$term <- rownames(coef_tbl)
  rownames(coef_tbl) <- NULL
  names(coef_tbl) <- c("estimate", "std.error", "statistic", "p.value", "term")
  coef_tbl <- coef_tbl[, c("term", "estimate", "std.error", "statistic", "p.value")]

  lambda_idx <- which(tolower(coef_tbl$term) == "lambda")
  if (length(lambda_idx) == 0L && !is.null(sm$spat.coef) && length(sm$spat.coef) > 0L) {
    coef_tbl <- dplyr::bind_rows(
      tibble::tibble(term = "lambda", estimate = as.numeric(sm$spat.coef[[1]]), std.error = NA_real_, statistic = NA_real_, p.value = NA_real_),
      coef_tbl
    )
  }

  controls_message <- sprintf(
    "controls_used=%s",
    if (length(used_controls) == 0L) "none" else paste(used_controls, collapse = ";")
  )

  coefs <- coef_tbl |>
    dplyr::mutate(
      spec_id = spec_id,
      interaction_family = interaction_family,
      outcome = outcome,
      status = "success",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      message = controls_message,
      .before = 1
    ) |>
    dplyr::select(spec_id, interaction_family, outcome, term, estimate, std.error, statistic, p.value, status, n_units, n_periods, n_obs, message)

  if (is.null(attr(mod, "have_factor_preds"))) attr(mod, "have_factor_preds") <- FALSE

  effect_info <- resolve_effect_definition(
    interaction_family = interaction_family,
    rhs_vars = rhs_vars,
    sample_quarter_index = pdat_try$quarter_index,
    sample_covid = pdat_try$covid_period
  )

  impacts <- purrr::map_dfr(rhs_vars, function(focal_var) {
    impact_res <- compute_spdm_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = focal_var,
      focal_var = focal_var,
      mod = mod,
      lw_sub = lw_sub,
      n_periods = n_periods,
      n_units = n_units,
      n_obs = n_obs,
      sample_min_yq = as.character(min(pdat_try$yq, na.rm = TRUE)),
      sample_max_yq = as.character(max(pdat_try$yq, na.rm = TRUE)),
      model_family = "sdm",
      w_type = "queen",
      sim_R = as.integer(value_or(cfg$spdm_impact_sim_R, 1000L)),
      sim_method = as.character(value_or(cfg$spdm_impact_sim_type, "mult")),
      empirical = isTRUE(value_or(cfg$spdm_impact_empirical, FALSE)),
      seed = cfg$esda_seed,
      message = controls_message
    )
    impact_res$row |>
      dplyr::mutate(
        interaction_family = interaction_family,
        inference_scope = ifelse(status == "success", "simulated_true_sdm_matrix", "not_available"),
        .after = spec_id
      )
  })

  summary_tbl <- build_effect_summary(
    spec_id = spec_id,
    interaction_family = interaction_family,
    outcome = outcome,
    coef_tbl = coef_tbl,
    mod = mod,
    impacts_tbl = impacts,
    effect_defs = effect_info$effect_defs,
    effect_label_definition = effect_info$effect_label_definition,
    default_message = controls_message
  )

  diagnostics_tbl <- build_interaction_diag_row(
    spec_id = spec_id,
    interaction_family = interaction_family,
    outcome = outcome,
    status = "success",
    sample_yq = pdat_try$yq,
    sample_quarter_index = pdat_try$quarter_index,
    sample_covid = pdat_try$covid_period,
    n_units = n_units,
    n_periods = n_periods,
    n_obs = n_obs,
    selected_controls = used_controls,
    baseline_period_label = effect_info$baseline_period_label,
    covid_period_label = effect_info$covid_period_label,
    effect_label_definition = effect_info$effect_label_definition,
    message = controls_message
  )

  controls_out <- build_control_rows(
    spec_id = spec_id,
    interaction_family = interaction_family,
    outcome = outcome,
    requested_controls = requested_controls,
    usable_controls = usable_controls,
    balanced_controls = spec_controls,
    selected_controls = used_controls,
    status = "success",
    message = controls_message
  )

  list(coefs = coefs, impacts = impacts, summary = summary_tbl, diagnostics = diagnostics_tbl, controls = controls_out)
}


#==============================================================================
# 2. Run SPDM Interaction Models and Save Outputs
#==============================================================================

empty_coefs <- tibble::tibble(
  spec_id = character(), interaction_family = character(), outcome = character(), term = character(),
  estimate = numeric(), std.error = numeric(), statistic = numeric(), p.value = numeric(),
  status = character(), n_units = integer(), n_periods = integer(), n_obs = integer(), message = character()
)
empty_impacts <- spdm_empty_impacts_tbl() |>
  dplyr::mutate(
    interaction_family = character(),
    inference_scope = character(),
    .after = spec_id
  )
empty_summary <- tibble::tibble(
  spec_id = character(), interaction_family = character(), outcome = character(), effect_label = character(),
  effect_kind = character(), estimate = numeric(), std.error = numeric(), statistic = numeric(), p.value = numeric(),
  inference_scope = character(), effect_label_definition = character(),
  source_terms = character(), status = character(), message = character()
)
empty_diag <- tibble::tibble(
  spec_id = character(), interaction_family = character(), outcome = character(), status = character(),
  n_units = integer(), n_periods = integer(), n_obs = integer(), sample_min_yq = character(), sample_max_yq = character(),
  n_covid_obs = integer(), n_non_covid_obs = integer(), n_pre_covid_obs = integer(), n_post_covid_obs = integer(),
  baseline_period_label = character(), covid_period_label = character(), effect_label_definition = character(),
  selected_controls = character(), message = character()
)
empty_controls <- tibble::tibble(
  spec_id = character(), interaction_family = character(), outcome = character(), control_var = character(), control_order = integer(),
  requested = logical(), usable = logical(), balanced_candidate = logical(), selected = logical(),
  status = character(), message = character()
)

if (length(outcomes) == 0L || length(main_exposure) == 0L || sum(is.finite(panel$covid_period), na.rm = TRUE) == 0L) {
  finalized <- finalize_spdm_interaction_outputs(empty_coefs, empty_impacts, empty_summary, empty_controls, empty_diag)
  write_csv_safe(finalized$coefs, path_interaction_models)
  write_csv_safe(finalized$impacts, path_interaction_impacts)
  write_csv_safe(finalized$summary, path_interaction_summary)
  write_csv_safe(finalized$controls, path_interaction_controls)
  write_csv_safe(finalized$diagnostics, path_interaction_diagnostics)
  append_log(cfg$logs$model_run, "- Skipped: missing SPDM interaction outcomes, exposure, or covid_period")
} else {
  main_exposure <- main_exposure[[1]]
  covid_term <- paste0(main_exposure, "_x_covid_period")

  panel[[covid_term]] <- panel[[main_exposure]] * panel$covid_period

  interaction_registry <- tibble::tibble(
    interaction_family = "m4_covid",
    rhs_vars = list(
      c(main_exposure, covid_term)
    ),
    effect_defs = list(
      list(
        non_covid_in_sample = stats::setNames(1, main_exposure),
        covid_period = stats::setNames(c(1, 1), c(main_exposure, covid_term))
      )
    )
  )

  lw <- readRDS(cfg$paths$w_queen)
  w_ids <- attr(lw$neighbours, "region.id")

  if (is.null(w_ids)) {
    finalized <- finalize_spdm_interaction_outputs(empty_coefs, empty_impacts, empty_summary, empty_controls, empty_diag)
    write_csv_safe(finalized$coefs, path_interaction_models)
    write_csv_safe(finalized$impacts, path_interaction_impacts)
    write_csv_safe(finalized$summary, path_interaction_summary)
    write_csv_safe(finalized$controls, path_interaction_controls)
    write_csv_safe(finalized$diagnostics, path_interaction_diagnostics)
    append_log(cfg$logs$model_run, "- Skipped: region.id missing in W")
  } else {
    w_ids <- as.character(w_ids)
    spec_grid <- tidyr::crossing(
      interaction_registry,
      outcome_registry |>
        dplyr::select(outcome, outcome_group, outcome_order)
    ) |>
      dplyr::arrange(interaction_family, outcome_order) |>
      dplyr::mutate(spec_id = sprintf("SI%02d", dplyr::row_number()))

    spec_jobs <- purrr::pmap(
      list(
        spec_id = spec_grid$spec_id,
        interaction_family = spec_grid$interaction_family,
        outcome = spec_grid$outcome,
        rhs_vars = spec_grid$rhs_vars,
        effect_defs = spec_grid$effect_defs
      ),
      function(spec_id, interaction_family, outcome, rhs_vars, effect_defs) {
        list(
          spec_id = spec_id,
          interaction_family = interaction_family,
          outcome = outcome,
          rhs_vars = rhs_vars,
          effect_defs = effect_defs
        )
      }
    )

    res <- run_spdm_optional_spec_jobs(
      spec_jobs,
      function(job) {
        do.call(
          run_one_spec,
          c(
            job,
            list(
              panel = panel,
              lw = lw,
              w_ids = w_ids,
              requested_controls = control_contracts[[job$outcome]]$requested_controls,
              usable_controls = control_contracts[[job$outcome]]$usable_controls
            )
          )
        )
      },
      label = "SPDM interaction specs"
    )

    out_coef <- dplyr::bind_rows(purrr::map(res, "coefs"))
    out_imp <- dplyr::bind_rows(purrr::map(res, "impacts"))
    out_sum <- dplyr::bind_rows(purrr::map(res, "summary"))
    out_diag <- dplyr::bind_rows(purrr::map(res, "diagnostics"))
    out_ctrl <- dplyr::bind_rows(purrr::map(res, "controls"))

    finalized <- finalize_spdm_interaction_outputs(out_coef, out_imp, out_sum, out_ctrl, out_diag)
    write_csv_safe(finalized$coefs, path_interaction_models)
    write_csv_safe(finalized$impacts, path_interaction_impacts)
    write_csv_safe(finalized$summary, path_interaction_summary)
    write_csv_safe(finalized$controls, path_interaction_controls)
    write_csv_safe(finalized$diagnostics, path_interaction_diagnostics)

    n_success <- sum(out_imp$status == "success", na.rm = TRUE)
    n_fail <- sum(out_imp$status != "success", na.rm = TRUE)
    append_log(
      cfg$logs$model_run,
      sprintf("- SPDM interaction specs attempted: %d (impact rows success=%d, failed=%d)", nrow(spec_grid), n_success, n_fail)
    )
  }
}
