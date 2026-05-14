#==============================================================================
# Script    : utils_spdm.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide shared helpers for SPDM preparation, estimation,
#             impacts inference, and diagnostics.
# Author    : Codex
# Created   : 2026-03-29
# Type      : utility
# Inputs    : panel data, listw objects, model metadata
# Outputs   : standardized SPDM tables and helper objects
# DependsOn : splm, spdep, dplyr, tidyr, tibble
#==============================================================================

#==============================================================================
# 1. Empty Tables
#==============================================================================

spdm_cfg_value <- function(name, default) {
  if (exists("cfg", inherits = TRUE) && !is.null(get("cfg", inherits = TRUE)[[name]])) {
    return(get("cfg", inherits = TRUE)[[name]])
  }
  default
}

spdm_coef_se_method <- function() {
  as.character(spdm_cfg_value("spdm_coef_se_method", "model_based_asymptotic_ml_vcov"))
}

spdm_spatial_param_se_method <- function() {
  as.character(spdm_cfg_value("spdm_spatial_param_se_method", spdm_coef_se_method()))
}

spdm_impact_se_method <- function() {
  as.character(spdm_cfg_value("spdm_impact_se_method", "simulation_from_model_based_ml_vcov"))
}

spdm_empty_coef_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    term = character(),
    estimate = numeric(),
    std.error = numeric(),
    statistic = numeric(),
    p.value = numeric(),
    se_method = character(),
    status = character(),
    n_units = integer(),
    n_periods = integer(),
    n_obs = integer(),
    sample_min_year = integer(),
    sample_max_year = integer(),
    model_family = character(),
    w_type = character(),
    message = character()
  )
}

spdm_empty_impacts_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    focal_var = character(),
    direct = numeric(),
    direct_se = numeric(),
    direct_z = numeric(),
    direct_p = numeric(),
    direct_ci_low = numeric(),
    direct_ci_high = numeric(),
    indirect = numeric(),
    indirect_se = numeric(),
    indirect_z = numeric(),
    indirect_p = numeric(),
    indirect_ci_low = numeric(),
    indirect_ci_high = numeric(),
    total = numeric(),
    total_se = numeric(),
    total_z = numeric(),
    total_p = numeric(),
    total_ci_low = numeric(),
    total_ci_high = numeric(),
    status = character(),
    n_units = integer(),
    n_periods = integer(),
    n_obs = integer(),
    sample_min_year = integer(),
    sample_max_year = integer(),
    model_family = character(),
    w_type = character(),
    sim_R = integer(),
    sim_method = character(),
    impact_se_method = character(),
    message = character()
  )
}

spdm_empty_controls_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    control_var = character(),
    control_order = integer(),
    requested = logical(),
    usable = logical(),
    balanced_candidate = logical(),
    selected = logical(),
    status = character(),
    model_family = character(),
    w_type = character(),
    message = character()
  )
}

spdm_empty_diag_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    model_family = character(),
    w_type = character(),
    status = character(),
    n_units = integer(),
    n_periods = integer(),
    n_obs = integer(),
    sample_min_year = integer(),
    sample_max_year = integer(),
    selected_controls = character(),
    spatial_lagged_terms = character(),
    n_wx_terms = integer(),
    sdm_implementation = character(),
    impact_method = character(),
    coef_se_method = character(),
    spatial_param_se_method = character(),
    impact_se_method = character(),
    spatial_param_name = character(),
    spatial_param_estimate = numeric(),
    spatial_param_se = numeric(),
    spatial_param_p = numeric(),
    logLik = numeric(),
    AIC = numeric(),
    BIC = numeric(),
    impacts_status = character(),
    message = character()
  )
}

spdm_empty_family_comparison_tbl <- function() {
  tibble::tibble(
    spec_id = character(),
    outcome = character(),
    exposure = character(),
    family = character(),
    w_type = character(),
    status = character(),
    impacts_status = character(),
    n_units = integer(),
    n_periods = integer(),
    n_obs = integer(),
    sample_min_year = integer(),
    sample_max_year = integer(),
    selected_controls = character(),
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
    spatial_param_estimate = numeric(),
    spatial_param_p = numeric(),
    logLik = numeric(),
    AIC = numeric(),
    BIC = numeric(),
    direct = numeric(),
    indirect = numeric(),
    total = numeric(),
    direct_p = numeric(),
    indirect_p = numeric(),
    total_p = numeric(),
    direct_ci_low = numeric(),
    direct_ci_high = numeric(),
    indirect_ci_low = numeric(),
    indirect_ci_high = numeric(),
    total_ci_low = numeric(),
    total_ci_high = numeric(),
    message = character()
  )
}

normalize_spatial_family <- function(model_family) {
  fam <- tolower(as.character(value_or(model_family, NA_character_)))
  dplyr::case_when(
    fam %in% c("sac", "sarar", "sarar/sac") ~ "sarar_sac",
    fam %in% c("gns", "sac_durbin", "sarar_durbin") ~ "gns",
    fam %in% c("slx", "sar", "sdm", "sem", "sdem", "sarar_sac", "gns", "twfe_common") ~ fam,
    TRUE ~ fam
  )
}

spatial_family_supports_impacts <- function(model_family) {
  normalize_spatial_family(model_family) %in% c("slx", "sar", "sdm", "sdem", "sarar_sac", "gns")
}

get_main_spatial_families <- function() {
  c("slx", "sar", "sdm", "sem", "sdem", "sarar_sac", "gns")
}

spdm_required_years <- function() {
  seq.int(as.integer(cfg$short_start), as.integer(cfg$short_end))
}

spdm_wx_name <- function(var) {
  paste0("w_", make.names(as.character(var)))
}

spdm_main_control_candidate_cols <- function() {
  default_controls <- c(
    "ln_resident_pop",
    "ln_apartment_household_count", "ln_official_land_price", "transit_accessibility",
    "hospital_count_aux_core", "mall_count_aux_core"
  )
  controls <- spdm_cfg_value("spdm_main_control_cols", default_controls)
  controls <- unique(as.character(value_or(controls, default_controls)))
  controls[!is.na(controls) & nzchar(controls)]
}

spdm_retired_control_cols <- function() {
  c(
    "ln_worker_pop", "ln_floating_pop",
    "bus_stop_count_aux", "subway_station_count_aux",
    "apartment_count", "ln_apartment_count"
  )
}

spdm_selected_flag <- function(x) {
  dplyr::case_when(
    is.logical(x) ~ x,
    is.numeric(x) ~ x != 0,
    TRUE ~ tolower(trimws(as.character(x))) %in% c("true", "t", "1", "yes", "y")
  )
}

spdm_split_collapsed_controls <- function(x) {
  vals <- unique(unlist(strsplit(as.character(value_or(x, character())), ";", fixed = TRUE)))
  vals <- trimws(vals)
  vals <- vals[!is.na(vals) & nzchar(vals)]
  setdiff(vals, c("none", "NA", "NaN", "NULL"))
}

assert_spdm_main_controls_current <- function(control_screen,
                                              context = "SPDM sidecar",
                                              allowed_controls = spdm_main_control_candidate_cols(),
                                              control_col = "control_var",
                                              selected_col = "selected") {
  required_cols <- c(control_col, selected_col)
  missing_cols <- setdiff(required_cols, names(control_screen))
  if (length(missing_cols) > 0L) {
    stop(
      sprintf("[ERROR] %s SPDM control trace missing required column(s): %s", context, collapse_chr(missing_cols)),
      call. = FALSE
    )
  }

  allowed_controls <- unique(as.character(value_or(allowed_controls, character())))
  allowed_controls <- allowed_controls[!is.na(allowed_controls) & nzchar(allowed_controls)]
  retired_controls <- spdm_retired_control_cols()

  retired_allowed <- intersect(allowed_controls, retired_controls)
  if (length(retired_allowed) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s current SPDM config still allows retired control(s): %s.",
        context,
        collapse_chr(retired_allowed)
      ),
      call. = FALSE
    )
  }

  requested_controls <- unique(as.character(control_screen[[control_col]]))
  requested_controls <- requested_controls[!is.na(requested_controls) & nzchar(requested_controls)]
  stale_requested <- setdiff(requested_controls, allowed_controls)
  if (length(stale_requested) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s is using stale SPDM control candidates: %s. Re-run 02_run_spdm_main.R under the current config before SPDM sidecars.",
        context,
        collapse_chr(stale_requested)
      ),
      call. = FALSE
    )
  }

  selected_raw <- control_screen[[selected_col]]
  selected_controls <- unique(as.character(control_screen[[control_col]][spdm_selected_flag(selected_raw)]))
  selected_controls <- selected_controls[!is.na(selected_controls) & nzchar(selected_controls)]
  forbidden_controls <- intersect(selected_controls, retired_controls)
  if (length(forbidden_controls) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s selected retired SPDM control(s): %s. Use the current six-control SPDM contract.",
        context,
        collapse_chr(forbidden_controls)
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_spdm_main_diagnostics_controls_current <- function(diagnostics,
                                                          context = "SPDM sidecar",
                                                          selected_col = "selected_controls",
                                                          allowed_controls = spdm_main_control_candidate_cols()) {
  if (!selected_col %in% names(diagnostics)) {
    stop(
      sprintf("[ERROR] %s SPDM diagnostics missing required column: %s", context, selected_col),
      call. = FALSE
    )
  }

  allowed_controls <- unique(as.character(value_or(allowed_controls, character())))
  allowed_controls <- allowed_controls[!is.na(allowed_controls) & nzchar(allowed_controls)]
  selected_controls <- spdm_split_collapsed_controls(diagnostics[[selected_col]])

  stale_selected <- setdiff(selected_controls, allowed_controls)
  if (length(stale_selected) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s inherited stale SPDM diagnostic control(s): %s. Re-run 02_run_spdm_main.R under the current config before SPDM sidecars.",
        context,
        collapse_chr(stale_selected)
      ),
      call. = FALSE
    )
  }

  forbidden_controls <- intersect(selected_controls, spdm_retired_control_cols())
  if (length(forbidden_controls) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s inherited retired SPDM diagnostic control(s): %s. Use the current six-control SPDM contract.",
        context,
        collapse_chr(forbidden_controls)
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}


#==============================================================================
# 2. Control and Sample Preparation
#==============================================================================

build_spdm_control_rows <- function(spec_id,
                                    outcome,
                                    exposure,
                                    requested_controls,
                                    usable_controls,
                                    balanced_controls,
                                    selected_controls,
                                    status,
                                    message,
                                    model_family = NA_character_,
                                    w_type = NA_character_) {
  if (length(requested_controls) == 0L) {
    return(spdm_empty_controls_tbl())
  }

  tibble::tibble(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    control_var = requested_controls,
    control_order = seq_along(requested_controls),
    requested = TRUE,
    usable = requested_controls %in% usable_controls,
    balanced_candidate = requested_controls %in% balanced_controls,
    selected = requested_controls %in% selected_controls,
    status = status,
    model_family = as.character(model_family),
    w_type = as.character(w_type),
    message = as.character(message)
  )
}

assess_spdm_balanced_dims <- function(data, w_ids, required_years = spdm_required_years()) {
  if (nrow(data) == 0L) {
    return(list(ok = FALSE, keep_ids = character(), n_units = 0L, n_periods = 0L))
  }

  required_years <- sort(unique(suppressWarnings(as.integer(required_years))))
  required_years <- required_years[is.finite(required_years)]

  annual_counts <- data |>
    dplyr::mutate(year = suppressWarnings(as.integer(year))) |>
    dplyr::filter(is.finite(year)) |>
    dplyr::distinct(adm_cd, year) |>
    dplyr::group_by(adm_cd) |>
    dplyr::summarise(
      n_t = dplyr::n(),
      has_required_years = if (length(required_years) == 0L) TRUE else all(required_years %in% year),
      .groups = "drop"
    )

  if (nrow(annual_counts) == 0L) {
    return(list(ok = FALSE, keep_ids = character(), n_units = 0L, n_periods = 0L))
  }

  if (length(required_years) > 0L) {
    full_t <- length(required_years)
    adm_balanced <- annual_counts |>
      dplyr::filter(n_t >= full_t, has_required_years) |>
      dplyr::pull(adm_cd)
  } else {
    full_t <- max(annual_counts$n_t, na.rm = TRUE)
    adm_balanced <- annual_counts |>
      dplyr::filter(n_t == full_t) |>
      dplyr::pull(adm_cd)
  }

  keep_ids <- intersect(as.character(w_ids), as.character(adm_balanced))
  list(
    ok = (length(keep_ids) >= 20L && full_t >= as.integer(value_or(cfg$spdm_min_periods, 4L))),
    keep_ids = keep_ids,
    n_units = as.integer(length(keep_ids)),
    n_periods = as.integer(full_t)
  )
}

choose_spdm_controls_for_spec <- function(panel,
                                          outcome,
                                          exposure,
                                          control_pool,
                                          w_ids) {
  if (length(control_pool) == 0L) return(character())

  selected <- character()
  for (ctrl in control_pool) {
    trial <- c(selected, ctrl)
    vars <- unique(c("adm_cd", "year", outcome, exposure, trial))
    d_try <- panel |>
      dplyr::select(dplyr::all_of(vars)) |>
      tidyr::drop_na()
    dims <- assess_spdm_balanced_dims(d_try, w_ids)
    if (isTRUE(dims$ok)) {
      selected <- trial
    }
  }
  selected
}

make_spdm_control_ladder <- function(controls) {
  k <- length(controls)
  lapply(seq(k, 0L), function(i) {
    if (i == 0L) character() else controls[seq_len(i)]
  })
}

build_spdm_wx_terms <- function(pdat, vars, lw_sub) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(pdat)]
  if (length(vars) == 0L) {
    return(list(data = pdat, wx_terms = character(), wx_map = stats::setNames(character(), character())))
  }

  region_ids <- attr(lw_sub$neighbours, "region.id")
  if (is.null(region_ids) || length(region_ids) == 0L) {
    region_ids <- levels(pdat$adm_cd)
  }
  region_ids <- as.character(region_ids)
  if (length(region_ids) == 0L || anyNA(region_ids)) {
    stop("region.id missing for W X construction", call. = FALSE)
  }

  out <- pdat
  wx_terms <- spdm_wx_name(vars)
  wx_map <- stats::setNames(vars, wx_terms)

  for (var in vars) {
    wx_var <- spdm_wx_name(var)
    out[[wx_var]] <- NA_real_

    for (tt in sort(unique(out$time_id))) {
      idx_t <- which(out$time_id == tt)
      unit_order <- match(region_ids, as.character(out$adm_cd[idx_t]))
      if (anyNA(unit_order) || length(unit_order) != length(region_ids)) {
        stop("panel/W ordering mismatch during W X construction", call. = FALSE)
      }

      ordered_rows <- idx_t[unit_order]
      x <- suppressWarnings(as.numeric(out[[var]][ordered_rows]))
      if (anyNA(x)) {
        stop(sprintf("missing values in %s during W X construction", var), call. = FALSE)
      }

      out[[wx_var]][ordered_rows] <- as.numeric(
        spdep::lag.listw(lw_sub, x, zero.policy = TRUE, NAOK = FALSE)
      )
    }
  }

  list(data = out, wx_terms = wx_terms, wx_map = wx_map)
}

fit_spdm_model <- function(pdat, outcome, exposure, controls, lw_sub, model_family = "sdm") {
  rhs <- unique(c(exposure, controls))
  family <- normalize_spatial_family(model_family)
  pdat_model <- pdat
  wx_terms <- character()
  wx_map <- stats::setNames(character(), character())

  if (family %in% c("slx", "sdm", "sdem", "gns")) {
    wx_obj <- build_spdm_wx_terms(pdat_model, rhs, lw_sub)
    pdat_model <- wx_obj$data
    wx_terms <- wx_obj$wx_terms
    wx_map <- wx_obj$wx_map
  }

  rhs_formula <- unique(c(rhs, wx_terms))
  rhs_text <- paste(rhs_formula, collapse = " + ")

  if (identical(family, "slx")) {
    fm <- stats::as.formula(sprintf("%s ~ %s | adm_cd + year", outcome, rhs_text))
    fit <- tryCatch(
      fixest::feols(fm, data = pdat_model, cluster = ~ adm_cd, data.save = TRUE),
      error = function(e) e
    )
    if (!inherits(fit, "error")) {
      fit <- set_twfe_meta(
        fit,
        outcome = outcome,
        exposure = exposure,
        requested_controls = controls,
        retained_controls = controls,
        dropped_terms = character(),
        interaction = NULL,
        initial_nobs = nrow(pdat_model)
      )
      attr(fit, "spdm_model_family") <- family
      attr(fit, "spdm_rhs_vars") <- rhs
      attr(fit, "spdm_wx_terms") <- wx_terms
      attr(fit, "spdm_wx_map") <- wx_map
      attr(fit, "spdm_true_sdm") <- FALSE
      attr(fit, "spdm_implementation") <- "manual_wx_slx_twfe"
    }
    return(fit)
  }

  fm <- stats::as.formula(sprintf("%s ~ %s", outcome, rhs_text))

  model_args <- switch(
    family,
    sar = list(lag = TRUE, spatial.error = "none"),
    sdm = list(lag = TRUE, spatial.error = "none"),
    sem = list(lag = FALSE, spatial.error = "b"),
    sdem = list(lag = FALSE, spatial.error = "b"),
    sarar_sac = list(lag = TRUE, spatial.error = "b", listw2 = lw_sub),
    gns = list(lag = TRUE, spatial.error = "b", listw2 = lw_sub),
    stop(sprintf("unsupported spatial family: %s", family), call. = FALSE)
  )

  fit <- tryCatch(
    do.call(
      splm::spml,
      c(
        list(
          formula = fm,
          data = pdat_model,
          listw = lw_sub,
          model = "within",
          effect = "twoways",
          index = c("adm_cd", "time_id")
        ),
        model_args
      )
    ),
    error = function(e) e
  )

  if (!inherits(fit, "error")) {
    if (is.null(attr(fit, "have_factor_preds"))) {
      attr(fit, "have_factor_preds") <- FALSE
    }
    attr(fit, "spdm_model_family") <- family
    attr(fit, "spdm_rhs_vars") <- rhs
    attr(fit, "spdm_wx_terms") <- wx_terms
    attr(fit, "spdm_wx_map") <- wx_map
    attr(fit, "spdm_true_sdm") <- family %in% c("sdm", "gns")
    attr(fit, "spdm_implementation") <- if (identical(family, "sdm")) {
      "manual_wx_true_sdm"
    } else if (identical(family, "sdem")) {
      "manual_wx_sdem_spatial_error"
    } else if (identical(family, "gns")) {
      "manual_wx_gns_sarar_durbin"
    } else {
      "splm_builtin_spatial_panel"
    }
  }

  fit
}

fit_twfe_common_model <- function(pdat, outcome, exposure, controls) {
  rhs <- unique(c(exposure, controls))
  fm <- stats::as.formula(sprintf("%s ~ %s | adm_cd + year", outcome, paste(rhs, collapse = " + ")))

  fit <- tryCatch(
    fixest::feols(fm, data = pdat, cluster = ~ adm_cd, data.save = TRUE),
    error = function(e) e
  )
  if (inherits(fit, "error")) return(fit)

  set_twfe_meta(
    fit,
    outcome = outcome,
    exposure = exposure,
    requested_controls = controls,
    retained_controls = controls,
    dropped_terms = character(),
    interaction = NULL,
    initial_nobs = nrow(pdat)
  )
}

prepare_spdm_spec <- function(panel,
                              outcome,
                              exposure,
                              lw,
                              w_ids,
                              requested_controls,
                              usable_controls,
                              model_family = "sdm") {
  spec_controls <- choose_spdm_controls_for_spec(panel, outcome, exposure, usable_controls, w_ids)
  control_ladder <- make_spdm_control_ladder(spec_controls)

  prep <- list(
    status = "failed",
    message = "no estimable control set",
    selected_controls = character(),
    balanced_controls = spec_controls,
    pdat = NULL,
    lw_sub = NULL,
    mod = NULL,
    n_units = NA_integer_,
    n_periods = NA_integer_,
    n_obs = NA_integer_,
    sample_min_year = NA_integer_,
    sample_max_year = NA_integer_
  )

  for (ctrl_try in control_ladder) {
    vars <- unique(c("adm_cd", "year", outcome, exposure, ctrl_try))
    d_try <- panel |>
      dplyr::select(dplyr::all_of(vars)) |>
      tidyr::drop_na()
    if (nrow(d_try) < 400L) {
      prep$message <- "insufficient sample after drop_na"
      next
    }

    dims <- assess_spdm_balanced_dims(d_try, w_ids)
    keep_ids <- dims$keep_ids
    if (!isTRUE(dims$ok)) {
      prep$message <- "insufficient balanced units for SPDM"
      next
    }

    lw_try <- tryCatch(
      spdep::subset.listw(lw, subset = w_ids %in% keep_ids, zero.policy = TRUE),
      error = function(e) e
    )
    if (inherits(lw_try, "error") || is.null(lw_try)) {
      prep$message <- if (inherits(lw_try, "error")) {
        paste("failed to subset listw:", lw_try$message)
      } else {
        "failed to subset listw"
      }
      next
    }

    year_levels <- sort(unique(suppressWarnings(as.integer(d_try$year))))
    pdat_try <- d_try |>
      dplyr::filter(adm_cd %in% keep_ids) |>
      dplyr::mutate(
        adm_cd = factor(adm_cd, levels = keep_ids),
        year = as.integer(year),
        time_id = as.integer(factor(year, levels = year_levels))
      ) |>
      dplyr::arrange(adm_cd, time_id)

    n_units_try <- dplyr::n_distinct(pdat_try$adm_cd)
    n_periods_try <- dplyr::n_distinct(pdat_try$time_id)
    n_obs_try <- nrow(pdat_try)
    if (n_units_try < 20L || n_periods_try < cfg$spdm_min_periods) {
      prep$message <- "insufficient aligned panel dimensions"
      next
    }

    mod_try <- tryCatch(
      fit_spdm_model(
        pdat = pdat_try,
        outcome = outcome,
        exposure = exposure,
        controls = ctrl_try,
        lw_sub = lw_try,
        model_family = model_family
      ),
      error = function(e) e
    )
    if (inherits(mod_try, "error")) {
      prep$message <- paste("SPDM estimation/WX construction error:", mod_try$message)
      next
    }

    prep$status <- "success"
    prep$message <- sprintf(
      "controls_used=%s",
      if (length(ctrl_try) == 0L) "none" else paste(ctrl_try, collapse = ";")
    )
    prep$selected_controls <- ctrl_try
    prep$pdat <- pdat_try
    prep$lw_sub <- lw_try
    prep$mod <- mod_try
    prep$n_units <- as.integer(n_units_try)
    prep$n_periods <- as.integer(n_periods_try)
    prep$n_obs <- as.integer(n_obs_try)
    prep$sample_min_year <- suppressWarnings(as.integer(min(pdat_try$year, na.rm = TRUE)))
    prep$sample_max_year <- suppressWarnings(as.integer(max(pdat_try$year, na.rm = TRUE)))
    return(prep)
  }

  prep
}

rebuild_main_spdm_sample <- function(panel,
                                     outcome,
                                     exposure,
                                     selected_controls,
                                     lw,
                                     w_ids,
                                     expected_row,
                                     context_label = "main SPDM") {
  needed <- unique(c("adm_cd", "year", outcome, exposure, selected_controls))
  missing_vars <- setdiff(needed, names(panel))
  if (length(missing_vars) > 0L) {
    return(list(
      status = "failed",
      message = paste("missing vars:", paste(missing_vars, collapse = ", "))
    ))
  }

  d_try <- panel |>
    dplyr::select(dplyr::all_of(needed)) |>
    tidyr::drop_na()

  if (nrow(d_try) < 400L) {
    return(list(status = "failed", message = "insufficient sample after drop_na"))
  }

  dims <- assess_spdm_balanced_dims(d_try, w_ids)
  if (!isTRUE(dims$ok)) {
    return(list(
      status = "failed",
      message = sprintf("insufficient balanced units for %s", context_label)
    ))
  }

  lw_sub <- tryCatch(
    spdep::subset.listw(lw, subset = w_ids %in% dims$keep_ids, zero.policy = TRUE),
    error = function(e) e
  )
  if (inherits(lw_sub, "error") || is.null(lw_sub)) {
    return(list(
      status = "failed",
      message = if (inherits(lw_sub, "error")) paste("failed to subset listw:", lw_sub$message) else "failed to subset listw"
    ))
  }

  pdat <- d_try |>
    dplyr::filter(adm_cd %in% dims$keep_ids) |>
    dplyr::mutate(
      adm_cd = factor(adm_cd, levels = dims$keep_ids),
      time_id = as.integer(factor(year, levels = sort(unique(year))))
    ) |>
    dplyr::arrange(adm_cd, time_id)

  n_units <- dplyr::n_distinct(pdat$adm_cd)
  n_periods <- dplyr::n_distinct(pdat$time_id)
  n_obs <- nrow(pdat)
  sample_min_year <- suppressWarnings(as.integer(min(pdat$year, na.rm = TRUE)))
  sample_max_year <- suppressWarnings(as.integer(max(pdat$year, na.rm = TRUE)))

  mismatch <- character()
  if (is.finite(expected_row$n_units[[1]]) && !identical(as.integer(n_units), as.integer(expected_row$n_units[[1]]))) {
    mismatch <- c(mismatch, sprintf("n_units expected %s got %s", expected_row$n_units[[1]], n_units))
  }
  if (is.finite(expected_row$n_periods[[1]]) && !identical(as.integer(n_periods), as.integer(expected_row$n_periods[[1]]))) {
    mismatch <- c(mismatch, sprintf("n_periods expected %s got %s", expected_row$n_periods[[1]], n_periods))
  }
  if (is.finite(expected_row$n_obs[[1]]) && !identical(as.integer(n_obs), as.integer(expected_row$n_obs[[1]]))) {
    mismatch <- c(mismatch, sprintf("n_obs expected %s got %s", expected_row$n_obs[[1]], n_obs))
  }
  expected_min_year <- suppressWarnings(as.integer(expected_row$sample_min_year[[1]]))
  expected_max_year <- suppressWarnings(as.integer(expected_row$sample_max_year[[1]]))
  if (is.finite(expected_min_year) && !identical(sample_min_year, expected_min_year)) {
    mismatch <- c(mismatch, sprintf("sample_min_year expected %s got %s", expected_row$sample_min_year[[1]], sample_min_year))
  }
  if (is.finite(expected_max_year) && !identical(sample_max_year, expected_max_year)) {
    mismatch <- c(mismatch, sprintf("sample_max_year expected %s got %s", expected_row$sample_max_year[[1]], sample_max_year))
  }

  if (length(mismatch) > 0L) {
    return(list(
      status = "failed",
      message = paste(sprintf("%s sample mismatch:", context_label), paste(mismatch, collapse = " | "))
    ))
  }

  list(
    status = "success",
    message = sprintf(
      "matched_main_controls=%s",
      if (length(selected_controls) == 0L) "none" else paste(selected_controls, collapse = ";")
    ),
    data = pdat,
    lw_sub = lw_sub,
    w_matrix = spdep::listw2mat(lw_sub),
    n_units = as.integer(n_units),
    n_periods = as.integer(n_periods),
    n_obs = as.integer(n_obs),
    sample_min_year = sample_min_year,
    sample_max_year = sample_max_year
  )
}

prepare_spatial_family_spec <- function(panel,
                                        outcome,
                                        exposure,
                                        lw,
                                        w_ids,
                                        requested_controls,
                                        usable_controls,
                                        model_families = get_main_spatial_families()) {
  model_families <- unique(normalize_spatial_family(model_families))
  spec_controls <- choose_spdm_controls_for_spec(panel, outcome, exposure, usable_controls, w_ids)
  control_ladder <- make_spdm_control_ladder(spec_controls)

  prep <- list(
    status = "failed",
    message = "no common estimable control set",
    selected_controls = character(),
    balanced_controls = spec_controls,
    pdat = NULL,
    lw_sub = NULL,
    mods = list(),
    twfe_mod = NULL,
    n_units = NA_integer_,
    n_periods = NA_integer_,
    n_obs = NA_integer_,
    sample_min_year = NA_integer_,
    sample_max_year = NA_integer_
  )

  for (ctrl_try in control_ladder) {
    vars <- unique(c("adm_cd", "year", outcome, exposure, ctrl_try))
    d_try <- panel |>
      dplyr::select(dplyr::all_of(vars)) |>
      tidyr::drop_na()
    if (nrow(d_try) < 400L) {
      prep$message <- "insufficient sample after drop_na"
      next
    }

    dims <- assess_spdm_balanced_dims(d_try, w_ids)
    keep_ids <- dims$keep_ids
    if (!isTRUE(dims$ok)) {
      prep$message <- "insufficient balanced units for spatial family comparison"
      next
    }

    lw_try <- tryCatch(
      spdep::subset.listw(lw, subset = w_ids %in% keep_ids, zero.policy = TRUE),
      error = function(e) e
    )
    if (inherits(lw_try, "error") || is.null(lw_try)) {
      prep$message <- if (inherits(lw_try, "error")) {
        paste("failed to subset listw:", lw_try$message)
      } else {
        "failed to subset listw"
      }
      next
    }

    year_levels <- sort(unique(suppressWarnings(as.integer(d_try$year))))
    pdat_try <- d_try |>
      dplyr::filter(adm_cd %in% keep_ids) |>
      dplyr::mutate(
        adm_cd = factor(adm_cd, levels = keep_ids),
        year = as.integer(year),
        time_id = as.integer(factor(year, levels = year_levels))
      ) |>
      dplyr::arrange(adm_cd, time_id)

    n_units_try <- dplyr::n_distinct(pdat_try$adm_cd)
    n_periods_try <- dplyr::n_distinct(pdat_try$time_id)
    n_obs_try <- nrow(pdat_try)
    if (n_units_try < 20L || n_periods_try < cfg$spdm_min_periods) {
      prep$message <- "insufficient aligned panel dimensions"
      next
    }

    fit_messages <- character()
    mods_try <- list()
    ok <- TRUE
    for (family in model_families) {
      mod_try <- fit_spdm_model(
        pdat = pdat_try,
        outcome = outcome,
        exposure = exposure,
        controls = ctrl_try,
        lw_sub = lw_try,
        model_family = family
      )
      if (inherits(mod_try, "error")) {
        ok <- FALSE
        fit_messages <- c(fit_messages, sprintf("%s=%s", family, mod_try$message))
        break
      }
      mods_try[[family]] <- mod_try
    }
    if (!ok) {
      prep$message <- paste("common family fit failed:", paste(fit_messages, collapse = " | "))
      next
    }

    twfe_try <- fit_twfe_common_model(
      pdat = pdat_try,
      outcome = outcome,
      exposure = exposure,
      controls = ctrl_try
    )
    if (inherits(twfe_try, "error") || is.null(twfe_try)) {
      prep$message <- if (inherits(twfe_try, "error")) {
        paste("common twfe error:", twfe_try$message)
      } else {
        "common twfe unavailable"
      }
      next
    }

    prep$status <- "success"
    prep$message <- sprintf(
      "common_controls=%s",
      if (length(ctrl_try) == 0L) "none" else paste(ctrl_try, collapse = ";")
    )
    prep$selected_controls <- ctrl_try
    prep$pdat <- pdat_try
    prep$lw_sub <- lw_try
    prep$mods <- mods_try
    prep$twfe_mod <- twfe_try
    prep$n_units <- as.integer(n_units_try)
    prep$n_periods <- as.integer(n_periods_try)
    prep$n_obs <- as.integer(n_obs_try)
    prep$sample_min_year <- suppressWarnings(as.integer(min(pdat_try$year, na.rm = TRUE)))
    prep$sample_max_year <- suppressWarnings(as.integer(max(pdat_try$year, na.rm = TRUE)))
    return(prep)
  }

  prep
}


#==============================================================================
# 3. Impacts Inference Helpers
#==============================================================================

normalize_impact_term <- function(x) {
  sub(" dy/dx$", "", as.character(x))
}

match_impact_position <- function(impact_summary, focal_var, impact_obj) {
  row_candidates <- rownames(impact_summary$semat)
  if (!is.null(row_candidates) && length(row_candidates) > 0L) {
    idx <- which(normalize_impact_term(row_candidates) == focal_var)
    if (length(idx) > 0L) return(idx[[1]])
  }

  direct_names <- names(impact_obj$res$direct)
  if (!is.null(direct_names) && length(direct_names) > 0L) {
    idx <- which(normalize_impact_term(direct_names) == focal_var)
    if (length(idx) > 0L) return(idx[[1]])
  }

  1L
}

extract_impact_matrix_value <- function(mat, focal_var, effect_col) {
  if (is.null(mat) || length(mat) == 0L) return(NA_real_)
  rn <- rownames(mat)
  cn <- colnames(mat)
  if (is.null(rn) || is.null(cn)) return(NA_real_)

  row_idx <- which(normalize_impact_term(rn) == focal_var)
  col_idx <- which(tolower(cn) == tolower(effect_col))
  if (length(row_idx) == 0L || length(col_idx) == 0L) return(NA_real_)
  suppressWarnings(as.numeric(mat[row_idx[[1]], col_idx[[1]]]))
}

extract_impact_quantiles <- function(draws_obj, focal_var) {
  if (is.null(draws_obj)) {
    return(c(NA_real_, NA_real_))
  }

  if (inherits(draws_obj, "summary.mcmc") && !is.null(draws_obj$quantiles)) {
    qmat <- draws_obj$quantiles
    rn <- rownames(qmat)
    cn <- colnames(qmat)
    if (!is.null(rn) && !is.null(cn)) {
      row_idx <- which(normalize_impact_term(rn) == focal_var)
      low_idx <- which(cn == "2.5%")
      high_idx <- which(cn == "97.5%")
      if (length(row_idx) > 0L && length(low_idx) > 0L && length(high_idx) > 0L) {
        return(c(
          suppressWarnings(as.numeric(qmat[row_idx[[1]], low_idx[[1]]])),
          suppressWarnings(as.numeric(qmat[row_idx[[1]], high_idx[[1]]]))
        ))
      }
    }
  }

  draw_mat <- as.matrix(draws_obj)
  if (length(draw_mat) == 0L) {
    return(c(NA_real_, NA_real_))
  }
  if (is.null(dim(draw_mat))) {
    draw_mat <- matrix(draw_mat, ncol = 1L)
  }

  draw_names <- colnames(draw_mat)
  if (is.null(draw_names) || length(draw_names) == 0L) {
    col_idx <- 1L
  } else {
    hit <- which(normalize_impact_term(draw_names) == focal_var)
    col_idx <- if (length(hit) > 0L) hit[[1]] else 1L
  }

  stats::quantile(
    as.numeric(draw_mat[, col_idx]),
    probs = c(0.025, 0.975),
    na.rm = TRUE,
    names = FALSE
  )
}

build_spdm_not_applicable_impacts_row <- function(spec_id,
                                                  outcome,
                                                  exposure,
                                                  focal_var,
                                                  n_units,
                                                  n_periods,
                                                  n_obs,
                                                  sample_min_year,
                                                  sample_max_year,
                                                  model_family,
                                                  w_type,
                                                  sim_R = NA_integer_,
                                                  sim_method = NA_character_,
                                                  message = "impacts not applicable") {
  spdm_empty_impacts_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = focal_var,
      status = "not_applicable",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = sample_min_year,
      sample_max_year = sample_max_year,
      model_family = model_family,
      w_type = w_type,
      sim_R = as.integer(sim_R),
      sim_method = as.character(sim_method),
      impact_se_method = NA_character_,
      message = as.character(message)
    )
}

compute_spdm_impacts_row_splm_builtin <- function(spec_id,
                                                  outcome,
                                                  exposure,
                                                  focal_var,
                                                  mod,
                                                  lw_sub,
                                                  n_periods,
                                                  n_units,
                                                  n_obs,
                                                  sample_min_year,
                                                  sample_max_year,
                                                  model_family = "sdm",
                                                  w_type = "queen",
                                                  sim_R = 1000L,
                                                  sim_method = "mult",
                                                  empirical = FALSE,
                                                  seed = NULL,
                                                  message = NA_character_) {
  if (!spatial_family_supports_impacts(model_family)) {
    return(list(
      row = build_spdm_not_applicable_impacts_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        focal_var = focal_var,
        n_units = n_units,
        n_periods = n_periods,
        n_obs = n_obs,
        sample_min_year = sample_min_year,
        sample_max_year = sample_max_year,
        model_family = model_family,
        w_type = w_type,
        sim_R = sim_R,
        sim_method = sim_method,
        message = if (is.na(message)) "impacts not applicable" else message
      ),
      status = "not_applicable",
      message = if (is.na(message)) "impacts not applicable" else as.character(message)
    ))
  }

  if (!is.null(seed) && is.finite(seed)) {
    set.seed(as.integer(seed))
  }

  imp <- tryCatch(
    splm::impacts(
      mod,
      listw = lw_sub,
      time = n_periods,
      R = sim_R,
      type = sim_method,
      empirical = empirical
    ),
    error = function(e) e
  )

  if (inherits(imp, "error") || is.null(imp$res)) {
    return(list(
      row = spdm_empty_impacts_tbl() |>
        dplyr::add_row(
          spec_id = spec_id,
          outcome = outcome,
          exposure = exposure,
          focal_var = focal_var,
          status = "failed",
          n_units = as.integer(n_units),
          n_periods = as.integer(n_periods),
          n_obs = as.integer(n_obs),
          sample_min_year = sample_min_year,
          sample_max_year = sample_max_year,
          model_family = model_family,
          w_type = w_type,
          sim_R = as.integer(sim_R),
          sim_method = sim_method,
          impact_se_method = spdm_impact_se_method(),
          message = if (inherits(imp, "error")) paste("impacts error:", imp$message) else "impacts unavailable"
        ),
      status = "failed",
      message = if (inherits(imp, "error")) paste("impacts error:", imp$message) else "impacts unavailable"
    ))
  }

  imp_summary <- tryCatch(summary(imp, zstats = TRUE), error = function(e) e)
  if (inherits(imp_summary, "error")) {
    return(list(
      row = spdm_empty_impacts_tbl() |>
        dplyr::add_row(
          spec_id = spec_id,
          outcome = outcome,
          exposure = exposure,
          focal_var = focal_var,
          status = "failed",
          n_units = as.integer(n_units),
          n_periods = as.integer(n_periods),
          n_obs = as.integer(n_obs),
          sample_min_year = sample_min_year,
          sample_max_year = sample_max_year,
          model_family = model_family,
          w_type = w_type,
          sim_R = as.integer(sim_R),
          sim_method = sim_method,
          impact_se_method = spdm_impact_se_method(),
          message = paste("impacts summary error:", imp_summary$message)
        ),
      status = "failed",
      message = paste("impacts summary error:", imp_summary$message)
    ))
  }

  idx <- match_impact_position(imp_summary, focal_var, imp)
  direct <- suppressWarnings(as.numeric(imp$res$direct[[idx]]))
  indirect <- suppressWarnings(as.numeric(imp$res$indirect[[idx]]))
  total <- suppressWarnings(as.numeric(imp$res$total[[idx]]))

  direct_ci <- extract_impact_quantiles(imp_summary$direct, focal_var)
  indirect_ci <- extract_impact_quantiles(imp_summary$indirect, focal_var)
  total_ci <- extract_impact_quantiles(imp_summary$total, focal_var)

  row <- spdm_empty_impacts_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = focal_var,
      direct = direct,
      direct_se = extract_impact_matrix_value(imp_summary$semat, focal_var, "Direct"),
      direct_z = extract_impact_matrix_value(imp_summary$zmat, focal_var, "Direct"),
      direct_p = extract_impact_matrix_value(imp_summary$pzmat, focal_var, "Direct"),
      direct_ci_low = direct_ci[[1]],
      direct_ci_high = direct_ci[[2]],
      indirect = indirect,
      indirect_se = extract_impact_matrix_value(imp_summary$semat, focal_var, "Indirect"),
      indirect_z = extract_impact_matrix_value(imp_summary$zmat, focal_var, "Indirect"),
      indirect_p = extract_impact_matrix_value(imp_summary$pzmat, focal_var, "Indirect"),
      indirect_ci_low = indirect_ci[[1]],
      indirect_ci_high = indirect_ci[[2]],
      total = total,
      total_se = extract_impact_matrix_value(imp_summary$semat, focal_var, "Total"),
      total_z = extract_impact_matrix_value(imp_summary$zmat, focal_var, "Total"),
      total_p = extract_impact_matrix_value(imp_summary$pzmat, focal_var, "Total"),
      total_ci_low = total_ci[[1]],
      total_ci_high = total_ci[[2]],
      status = "success",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = sample_min_year,
      sample_max_year = sample_max_year,
      model_family = model_family,
      w_type = w_type,
      sim_R = as.integer(sim_R),
      sim_method = sim_method,
      impact_se_method = spdm_impact_se_method(),
      message = as.character(message)
    )

  list(row = row, status = "success", message = as.character(message))
}

spdm_get_coef_vector <- function(mod) {
  coef_vec <- tryCatch(stats::coef(mod), error = function(e) NULL)
  if (is.null(coef_vec) || length(coef_vec) == 0L) {
    sm <- tryCatch(summary(mod), error = function(e) NULL)
    coef_tbl <- tryCatch(as.data.frame(sm$CoefTable), error = function(e) NULL)
    if (!is.null(coef_tbl) && nrow(coef_tbl) > 0L) {
      coef_vec <- suppressWarnings(as.numeric(coef_tbl[[1]]))
      names(coef_vec) <- rownames(coef_tbl)
    }
  }
  coef_vec
}

spdm_get_vcov_matrix <- function(mod, coef_names) {
  vc <- tryCatch(stats::vcov(mod), error = function(e) NULL)
  if (is.null(vc) || length(vc) == 0L) {
    vc <- tryCatch(mod$vcov, error = function(e) NULL)
  }
  if (is.null(vc) || length(vc) == 0L) return(NULL)

  vc <- as.matrix(vc)
  if (is.null(rownames(vc)) && nrow(vc) == length(coef_names)) {
    rownames(vc) <- coef_names
  }
  if (is.null(colnames(vc)) && ncol(vc) == length(coef_names)) {
    colnames(vc) <- coef_names
  }
  vc
}

spdm_make_psd_covariance <- function(Sigma, floor = 1e-10) {
  Sigma <- as.matrix(Sigma)
  Sigma <- (Sigma + t(Sigma)) / 2
  eig <- eigen(Sigma, symmetric = TRUE)
  adjusted <- any(eig$values < floor)
  vals <- pmax(eig$values, floor)
  out <- eig$vectors %*% diag(vals, nrow = length(vals)) %*% t(eig$vectors)
  dimnames(out) <- dimnames(Sigma)
  list(Sigma = out, adjusted = adjusted)
}

compute_true_sdm_effects <- function(W, rho, beta, theta) {
  n <- nrow(W)
  I_n <- diag(n)
  S <- solve(I_n - rho * W)
  M <- S %*% (beta * I_n + theta * W)
  direct <- mean(diag(M), na.rm = TRUE)
  total <- mean(rowSums(M), na.rm = TRUE)
  c(direct = direct, indirect = total - direct, total = total)
}

summarise_sdm_impact_draws <- function(point, draws) {
  draws <- suppressWarnings(as.numeric(draws))
  draws <- draws[is.finite(draws)]
  se <- if (length(draws) > 1L) stats::sd(draws) else NA_real_
  z <- if (is.finite(se) && se > 0) point / se else NA_real_
  p <- if (is.finite(z)) 2 * stats::pnorm(abs(z), lower.tail = FALSE) else NA_real_
  ci <- if (length(draws) > 1L) {
    stats::quantile(draws, probs = c(0.025, 0.975), na.rm = TRUE, names = FALSE)
  } else {
    c(NA_real_, NA_real_)
  }
  list(se = se, z = z, p = p, ci_low = ci[[1]], ci_high = ci[[2]])
}

summarise_linear_wx_effect <- function(point, se) {
  se <- suppressWarnings(as.numeric(se))
  if (length(se) == 0L || !is.finite(se[[1]]) || se[[1]] <= 0) {
    return(list(se = NA_real_, z = NA_real_, p = NA_real_, ci_low = NA_real_, ci_high = NA_real_))
  }
  se <- se[[1]]
  z <- point / se
  p <- 2 * stats::pnorm(abs(z), lower.tail = FALSE)
  list(
    se = se,
    z = z,
    p = p,
    ci_low = point - 1.96 * se,
    ci_high = point + 1.96 * se
  )
}

compute_wx_linear_impacts_row <- function(spec_id,
                                          outcome,
                                          exposure,
                                          focal_var,
                                          mod,
                                          n_units,
                                          n_periods,
                                          n_obs,
                                          sample_min_year,
                                          sample_max_year,
                                          model_family = "slx",
                                          w_type = "queen",
                                          message = NA_character_) {
  fail_row <- function(fail_msg) {
    list(
      row = spdm_empty_impacts_tbl() |>
        dplyr::add_row(
          spec_id = spec_id,
          outcome = outcome,
          exposure = exposure,
          focal_var = focal_var,
          status = "failed",
          n_units = as.integer(n_units),
          n_periods = as.integer(n_periods),
          n_obs = as.integer(n_obs),
          sample_min_year = suppressWarnings(as.integer(sample_min_year)),
          sample_max_year = suppressWarnings(as.integer(sample_max_year)),
          model_family = model_family,
          w_type = w_type,
          sim_method = "manual_wx_linear_delta",
          impact_se_method = NA_character_,
          message = fail_msg
        ),
      status = "failed",
      message = fail_msg
    )
  }

  family <- normalize_spatial_family(model_family)
  coef_vec <- spdm_get_coef_vector(mod)
  if (is.null(coef_vec) || length(coef_vec) == 0L || is.null(names(coef_vec))) {
    return(fail_row("WX linear effects unavailable: named coefficient vector missing"))
  }

  beta_name <- as.character(focal_var)
  theta_name <- spdm_wx_name(focal_var)
  needed <- c(beta_name, theta_name)
  missing_terms <- setdiff(needed, names(coef_vec))
  if (length(missing_terms) > 0L) {
    return(fail_row(paste("WX linear effects unavailable: missing coefficient(s)", paste(missing_terms, collapse = ", "))))
  }

  beta <- suppressWarnings(as.numeric(coef_vec[[beta_name]]))
  theta <- suppressWarnings(as.numeric(coef_vec[[theta_name]]))
  point <- c(direct = beta, indirect = theta, total = beta + theta)

  vc <- spdm_get_vcov_matrix(mod, names(coef_vec))
  direct_s <- indirect_s <- total_s <- list(se = NA_real_, z = NA_real_, p = NA_real_, ci_low = NA_real_, ci_high = NA_real_)
  vcov_message <- NA_character_
  if (!is.null(vc) && all(needed %in% rownames(vc)) && all(needed %in% colnames(vc))) {
    direct_s <- summarise_linear_wx_effect(point[["direct"]], sqrt(pmax(suppressWarnings(as.numeric(vc[beta_name, beta_name])), 0)))
    indirect_s <- summarise_linear_wx_effect(point[["indirect"]], sqrt(pmax(suppressWarnings(as.numeric(vc[theta_name, theta_name])), 0)))
    total_var <- suppressWarnings(as.numeric(vc[beta_name, beta_name] + vc[theta_name, theta_name] + 2 * vc[beta_name, theta_name]))
    total_s <- summarise_linear_wx_effect(point[["total"]], sqrt(pmax(total_var, 0)))
  } else {
    vcov_message <- "vcov unavailable for WX delta-method inference"
  }

  impact_se_method <- if (identical(family, "slx")) {
    "clustered_by_adm_cd_delta_method_wx_only"
  } else {
    "model_based_ml_vcov_delta_method_wx_only"
  }
  out_message <- paste(
    stats::na.omit(c(
      if (is.na(message)) NA_character_ else as.character(message),
      sprintf("%s_wx_only_effects direct=beta indirect=theta total=beta_plus_theta", family),
      "no endogenous Wy feedback multiplier",
      vcov_message
    )),
    collapse = " | "
  )

  row <- spdm_empty_impacts_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = focal_var,
      direct = point[["direct"]],
      direct_se = direct_s$se,
      direct_z = direct_s$z,
      direct_p = direct_s$p,
      direct_ci_low = direct_s$ci_low,
      direct_ci_high = direct_s$ci_high,
      indirect = point[["indirect"]],
      indirect_se = indirect_s$se,
      indirect_z = indirect_s$z,
      indirect_p = indirect_s$p,
      indirect_ci_low = indirect_s$ci_low,
      indirect_ci_high = indirect_s$ci_high,
      total = point[["total"]],
      total_se = total_s$se,
      total_z = total_s$z,
      total_p = total_s$p,
      total_ci_low = total_s$ci_low,
      total_ci_high = total_s$ci_high,
      status = "success",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = suppressWarnings(as.integer(sample_min_year)),
      sample_max_year = suppressWarnings(as.integer(sample_max_year)),
      model_family = model_family,
      w_type = w_type,
      sim_method = "manual_wx_linear_delta",
      impact_se_method = impact_se_method,
      message = out_message
    )

  list(row = row, status = "success", message = out_message)
}

compute_true_sdm_impacts_row <- function(spec_id,
                                         outcome,
                                         exposure,
                                         focal_var,
                                         mod,
                                         lw_sub,
                                         n_units,
                                         n_periods,
                                         n_obs,
                                         sample_min_year,
                                         sample_max_year,
                                         model_family = "sdm",
                                         w_type = "queen",
                                         sim_R = 1000L,
                                         empirical = FALSE,
                                         seed = NULL,
                                         message = NA_character_) {
  fail_row <- function(fail_msg) {
    list(
      row = spdm_empty_impacts_tbl() |>
        dplyr::add_row(
          spec_id = spec_id,
          outcome = outcome,
          exposure = exposure,
          focal_var = focal_var,
          status = "failed",
          n_units = as.integer(n_units),
          n_periods = as.integer(n_periods),
          n_obs = as.integer(n_obs),
          sample_min_year = suppressWarnings(as.integer(sample_min_year)),
          sample_max_year = suppressWarnings(as.integer(sample_max_year)),
          model_family = model_family,
          w_type = w_type,
          sim_R = as.integer(sim_R),
          sim_method = "manual_true_sdm_matrix",
          impact_se_method = spdm_impact_se_method(),
          message = fail_msg
        ),
      status = "failed",
      message = fail_msg
    )
  }

  coef_vec <- spdm_get_coef_vector(mod)
  if (is.null(coef_vec) || length(coef_vec) == 0L || is.null(names(coef_vec))) {
    return(fail_row("true SDM impacts unavailable: named coefficient vector missing"))
  }

  rho_name <- "lambda"
  beta_name <- as.character(focal_var)
  theta_name <- spdm_wx_name(focal_var)
  needed <- c(rho_name, beta_name, theta_name)
  missing_terms <- setdiff(needed, names(coef_vec))
  if (length(missing_terms) > 0L) {
    return(fail_row(paste("true SDM impacts unavailable: missing coefficient(s)", paste(missing_terms, collapse = ", "))))
  }

  W <- tryCatch(spdep::listw2mat(lw_sub), error = function(e) e)
  if (inherits(W, "error")) {
    return(fail_row(paste("true SDM impacts unavailable: listw2mat error:", W$message)))
  }

  point <- tryCatch(
    compute_true_sdm_effects(
      W = W,
      rho = suppressWarnings(as.numeric(coef_vec[[rho_name]])),
      beta = suppressWarnings(as.numeric(coef_vec[[beta_name]])),
      theta = suppressWarnings(as.numeric(coef_vec[[theta_name]]))
    ),
    error = function(e) e
  )
  if (inherits(point, "error") || any(!is.finite(point))) {
    return(fail_row(if (inherits(point, "error")) {
      paste("true SDM impacts unavailable:", point$message)
    } else {
      "true SDM impacts unavailable: non-finite point impacts"
    }))
  }

  vc <- spdm_get_vcov_matrix(mod, names(coef_vec))
  if (is.null(vc) || any(!needed %in% rownames(vc)) || any(!needed %in% colnames(vc))) {
    return(fail_row("true SDM impacts unavailable: covariance matrix missing required terms"))
  }

  mu <- suppressWarnings(as.numeric(coef_vec[needed]))
  names(mu) <- needed
  cov_obj <- spdm_make_psd_covariance(vc[needed, needed, drop = FALSE])

  if (!is.null(seed) && is.finite(seed)) {
    set.seed(as.integer(seed))
  }
  sim_R <- as.integer(sim_R)
  draws <- tryCatch(
    MASS::mvrnorm(n = sim_R, mu = mu, Sigma = cov_obj$Sigma, empirical = empirical),
    error = function(e) e
  )
  if (inherits(draws, "error")) {
    return(fail_row(paste("true SDM impact simulation error:", draws$message)))
  }

  draws <- as.matrix(draws)
  colnames(draws) <- needed
  impact_draw_fn <- function(i) {
    draw <- draws[i, ]
    tryCatch(
      compute_true_sdm_effects(W, rho = draw[[rho_name]], beta = draw[[beta_name]], theta = draw[[theta_name]]),
      error = function(e) c(direct = NA_real_, indirect = NA_real_, total = NA_real_)
    )
  }
  impact_cores <- suppressWarnings(as.integer(getOption("spdm_impact_cores", 1L)))
  if (!is.finite(impact_cores) || impact_cores < 1L) impact_cores <- 1L
  impact_cores <- min(impact_cores, nrow(draws), max(1L, parallel::detectCores(logical = FALSE) - 1L))
  impact_draws <- if (impact_cores > 1L && .Platform$OS.type != "windows") {
    do.call(rbind, parallel::mclapply(seq_len(nrow(draws)), impact_draw_fn, mc.cores = impact_cores, mc.preschedule = TRUE))
  } else {
    t(vapply(seq_len(nrow(draws)), impact_draw_fn, FUN.VALUE = c(direct = NA_real_, indirect = NA_real_, total = NA_real_)))
  }
  impact_draws <- as.matrix(impact_draws)
  valid_draws <- stats::complete.cases(impact_draws)
  impact_draws <- impact_draws[valid_draws, , drop = FALSE]
  if (nrow(impact_draws) == 0L) {
    return(fail_row(sprintf("true SDM impact simulation produced 0 valid draws out of %d", sim_R)))
  }

  direct_s <- summarise_sdm_impact_draws(point[["direct"]], impact_draws[, "direct"])
  indirect_s <- summarise_sdm_impact_draws(point[["indirect"]], impact_draws[, "indirect"])
  total_s <- summarise_sdm_impact_draws(point[["total"]], impact_draws[, "total"])

  out_message <- paste(
    stats::na.omit(c(
      if (is.na(message)) NA_character_ else as.character(message),
      sprintf("%s_manual_wx_matrix_impacts valid_draws=%d/%d", normalize_spatial_family(model_family), nrow(impact_draws), sim_R),
      if (isTRUE(cov_obj$adjusted)) "vcov_psd_adjusted" else NA_character_
    )),
    collapse = " | "
  )

  row <- spdm_empty_impacts_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = focal_var,
      direct = point[["direct"]],
      direct_se = direct_s$se,
      direct_z = direct_s$z,
      direct_p = direct_s$p,
      direct_ci_low = direct_s$ci_low,
      direct_ci_high = direct_s$ci_high,
      indirect = point[["indirect"]],
      indirect_se = indirect_s$se,
      indirect_z = indirect_s$z,
      indirect_p = indirect_s$p,
      indirect_ci_low = indirect_s$ci_low,
      indirect_ci_high = indirect_s$ci_high,
      total = point[["total"]],
      total_se = total_s$se,
      total_z = total_s$z,
      total_p = total_s$p,
      total_ci_low = total_s$ci_low,
      total_ci_high = total_s$ci_high,
      status = "success",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = suppressWarnings(as.integer(sample_min_year)),
      sample_max_year = suppressWarnings(as.integer(sample_max_year)),
      model_family = model_family,
      w_type = w_type,
      sim_R = sim_R,
      sim_method = "manual_true_sdm_matrix",
      impact_se_method = spdm_impact_se_method(),
      message = out_message
    )

  list(row = row, status = "success", message = out_message)
}

compute_spdm_impacts_row <- function(spec_id,
                                     outcome,
                                     exposure,
                                     focal_var,
                                     mod,
                                     lw_sub,
                                     n_periods,
                                     n_units,
                                     n_obs,
                                     sample_min_year,
                                     sample_max_year,
                                     model_family = "sdm",
                                     w_type = "queen",
                                     sim_R = 1000L,
                                     sim_method = "mult",
                                     empirical = FALSE,
                                     seed = NULL,
                                     message = NA_character_) {
  family <- normalize_spatial_family(model_family)
  if (family %in% c("slx", "sdem")) {
    return(compute_wx_linear_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = focal_var,
      mod = mod,
      n_units = n_units,
      n_periods = n_periods,
      n_obs = n_obs,
      sample_min_year = sample_min_year,
      sample_max_year = sample_max_year,
      model_family = model_family,
      w_type = w_type,
      message = message
    ))
  }

  if (family %in% c("sdm", "gns") && isTRUE(attr(mod, "spdm_true_sdm"))) {
    return(compute_true_sdm_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      focal_var = focal_var,
      mod = mod,
      lw_sub = lw_sub,
      n_units = n_units,
      n_periods = n_periods,
      n_obs = n_obs,
      sample_min_year = sample_min_year,
      sample_max_year = sample_max_year,
      model_family = model_family,
      w_type = w_type,
      sim_R = sim_R,
      empirical = empirical,
      seed = seed,
      message = message
    ))
  }

  compute_spdm_impacts_row_splm_builtin(
    spec_id = spec_id,
    outcome = outcome,
    exposure = exposure,
    focal_var = focal_var,
    mod = mod,
    lw_sub = lw_sub,
    n_periods = n_periods,
    n_units = n_units,
    n_obs = n_obs,
    sample_min_year = sample_min_year,
    sample_max_year = sample_max_year,
    model_family = model_family,
    w_type = w_type,
    sim_R = sim_R,
    sim_method = sim_method,
    empirical = empirical,
    seed = seed,
    message = message
  )
}


#==============================================================================
# 4. Coefficients and Diagnostics
#==============================================================================

extract_spdm_coef_table <- function(mod,
                                    spec_id,
                                    outcome,
                                    exposure,
                                    n_units,
                                    n_periods,
                                    n_obs,
                                    sample_min_year,
                                    sample_max_year,
                                    model_family = "sdm",
                                    w_type = "queen",
                                    message = NA_character_) {
  sm <- summary(mod)
  coef_tbl <- tryCatch(as.data.frame(sm$CoefTable), error = function(e) NULL)
  if (is.null(coef_tbl) || nrow(coef_tbl) == 0L) {
    return(spdm_empty_coef_tbl() |>
      dplyr::add_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        status = "failed",
        n_units = as.integer(n_units),
        n_periods = as.integer(n_periods),
        n_obs = as.integer(n_obs),
        sample_min_year = sample_min_year,
        sample_max_year = sample_max_year,
        model_family = model_family,
        w_type = w_type,
        se_method = spdm_coef_se_method(),
        message = "CoefTable unavailable from SPDM"
      ))
  }

  coef_tbl$term <- rownames(coef_tbl)
  rownames(coef_tbl) <- NULL
  names(coef_tbl) <- c("estimate", "std.error", "statistic", "p.value", "term")

  tibble::as_tibble(coef_tbl[, c("term", "estimate", "std.error", "statistic", "p.value")]) |>
    dplyr::mutate(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      status = "success",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = sample_min_year,
      sample_max_year = sample_max_year,
      model_family = model_family,
      w_type = w_type,
      se_method = spdm_coef_se_method(),
      message = as.character(message),
      .before = 1
    )
}

extract_twfe_common_coef_table <- function(mod,
                                          spec_id,
                                          outcome,
                                          exposure,
                                          n_units,
                                          n_periods,
                                          n_obs,
                                          sample_min_year,
                                          sample_max_year,
                                          model_family = "twfe_common",
                                          w_type = "queen",
                                          message = NA_character_) {
  coef_tbl <- tryCatch(broom::tidy(mod), error = function(e) NULL)
  if (is.null(coef_tbl) || nrow(coef_tbl) == 0L) {
    return(spdm_empty_coef_tbl() |>
      dplyr::add_row(
        spec_id = spec_id,
        outcome = outcome,
        exposure = exposure,
        status = "failed",
        n_units = as.integer(n_units),
        n_periods = as.integer(n_periods),
        n_obs = as.integer(n_obs),
        sample_min_year = sample_min_year,
        sample_max_year = sample_max_year,
        model_family = model_family,
        w_type = w_type,
        se_method = "clustered_by_adm_cd",
        message = "CoefTable unavailable from TWFE"
      ))
  }

  tibble::as_tibble(coef_tbl[, c("term", "estimate", "std.error", "statistic", "p.value")]) |>
    dplyr::mutate(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      status = "success",
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = sample_min_year,
      sample_max_year = sample_max_year,
      model_family = model_family,
      w_type = w_type,
      se_method = "clustered_by_adm_cd",
      message = as.character(message),
      .before = 1
    )
}

extract_focal_term_stats <- function(coef_tbl, focal_term) {
  if (is.null(coef_tbl) || nrow(coef_tbl) == 0L || !"term" %in% names(coef_tbl)) {
    return(list(
      focal_term = as.character(focal_term),
      focal_estimate = NA_real_,
      focal_se = NA_real_,
      focal_p = NA_real_
    ))
  }

  hit <- coef_tbl |>
    dplyr::filter(term == focal_term) |>
    dplyr::slice(1)

  if (nrow(hit) == 0L) {
    return(list(
      focal_term = as.character(focal_term),
      focal_estimate = NA_real_,
      focal_se = NA_real_,
      focal_p = NA_real_
    ))
  }

  list(
    focal_term = as.character(focal_term),
    focal_estimate = suppressWarnings(as.numeric(hit$estimate[[1]])),
    focal_se = suppressWarnings(as.numeric(hit$std.error[[1]])),
    focal_p = suppressWarnings(as.numeric(hit$p.value[[1]]))
  )
}

extract_spdm_spatial_param <- function(mod) {
  sm <- summary(mod)
  coef_tbl <- tryCatch(as.data.frame(sm$CoefTable), error = function(e) NULL)
  lag_row <- NULL
  error_row <- NULL

  if (!is.null(coef_tbl) && nrow(coef_tbl) > 0L) {
    rn <- tolower(rownames(coef_tbl))
    lag_row <- coef_tbl[rn == "lambda", , drop = FALSE]
    error_row <- coef_tbl[rn == "rho", , drop = FALSE]
  }

  lag_name <- if (!is.null(lag_row) && nrow(lag_row) == 1L) "lambda" else NA_character_
  lag_est <- if (!is.null(lag_row) && nrow(lag_row) == 1L) suppressWarnings(as.numeric(lag_row[[1, 1]])) else NA_real_
  lag_se <- if (!is.null(lag_row) && nrow(lag_row) == 1L) suppressWarnings(as.numeric(lag_row[[1, 2]])) else NA_real_
  lag_p <- if (!is.null(lag_row) && nrow(lag_row) == 1L) suppressWarnings(as.numeric(lag_row[[1, 4]])) else NA_real_

  error_name <- if (!is.null(error_row) && nrow(error_row) == 1L) "rho" else NA_character_
  error_est <- if (!is.null(error_row) && nrow(error_row) == 1L) suppressWarnings(as.numeric(error_row[[1, 1]])) else NA_real_
  error_se <- if (!is.null(error_row) && nrow(error_row) == 1L) suppressWarnings(as.numeric(error_row[[1, 2]])) else NA_real_
  error_p <- if (!is.null(error_row) && nrow(error_row) == 1L) suppressWarnings(as.numeric(error_row[[1, 4]])) else NA_real_

  if (!is.finite(lag_est) && !is.finite(error_est) && !is.null(sm$spat.coef) && length(sm$spat.coef) > 0L) {
    spat_name <- names(sm$spat.coef)[[1]]
    spat_est <- suppressWarnings(as.numeric(sm$spat.coef[[1]]))
    if (identical(tolower(spat_name), "lambda")) {
      lag_name <- spat_name
      lag_est <- spat_est
    } else if (identical(tolower(spat_name), "rho")) {
      error_name <- spat_name
      error_est <- spat_est
    }
  }

  spatial_name <- if (is.finite(lag_est)) lag_name else error_name
  spatial_est <- if (is.finite(lag_est)) lag_est else error_est
  spatial_se <- if (is.finite(lag_est)) lag_se else error_se
  spatial_p <- if (is.finite(lag_est)) lag_p else error_p

  list(
    spatial_param_name = spatial_name,
    spatial_param_estimate = spatial_est,
    spatial_param_se = spatial_se,
    spatial_param_p = spatial_p,
    lag_param_name = lag_name,
    lag_param_estimate = lag_est,
    lag_param_se = lag_se,
    lag_param_p = lag_p,
    error_param_name = error_name,
    error_param_estimate = error_est,
    error_param_se = error_se,
    error_param_p = error_p
  )
}

normalize_scalar_numeric <- function(x) {
  val <- suppressWarnings(as.numeric(x))
  if (length(val) == 0L || !is.finite(val[[1]])) return(NA_real_)
  val[[1]]
}

extract_spdm_fit_stats <- function(mod) {
  sm <- summary(mod)
  loglik_val <- normalize_scalar_numeric(sm$logLik)
  if (!is.finite(loglik_val)) {
    loglik_val <- tryCatch(normalize_scalar_numeric(stats::logLik(mod)), error = function(e) NA_real_)
  }

  aic_val <- tryCatch(normalize_scalar_numeric(stats::AIC(mod)), error = function(e) NA_real_)
  bic_val <- tryCatch(normalize_scalar_numeric(stats::BIC(mod)), error = function(e) NA_real_)

  list(
    logLik = if (is.finite(loglik_val)) loglik_val else NA_real_,
    AIC = if (is.finite(aic_val)) aic_val else NA_real_,
    BIC = if (is.finite(bic_val)) bic_val else NA_real_
  )
}

extract_twfe_fit_stats <- function(mod) {
  loglik_val <- tryCatch(normalize_scalar_numeric(stats::logLik(mod)), error = function(e) NA_real_)
  aic_val <- tryCatch(normalize_scalar_numeric(stats::AIC(mod)), error = function(e) NA_real_)
  bic_val <- tryCatch(normalize_scalar_numeric(stats::BIC(mod)), error = function(e) NA_real_)

  list(
    logLik = if (is.finite(loglik_val)) loglik_val else NA_real_,
    AIC = if (is.finite(aic_val)) aic_val else NA_real_,
    BIC = if (is.finite(bic_val)) bic_val else NA_real_
  )
}

build_spdm_diagnostics_row <- function(spec_id,
                                       outcome,
                                       exposure,
                                       model_family,
                                       w_type,
                                       status,
                                       n_units,
                                       n_periods,
                                       n_obs,
                                       sample_min_year,
                                       sample_max_year,
                                       selected_controls,
                                       spatial_lagged_terms = NA_character_,
                                       n_wx_terms = NA_integer_,
                                       sdm_implementation = NA_character_,
                                       impact_method = NA_character_,
                                       coef_se_method = spdm_coef_se_method(),
                                       spatial_param_se_method = spdm_spatial_param_se_method(),
                                       impact_se_method = spdm_impact_se_method(),
                                       spatial_param_name = NA_character_,
                                       spatial_param_estimate = NA_real_,
                                       spatial_param_se = NA_real_,
                                       spatial_param_p = NA_real_,
                                       logLik = NA_real_,
                                       AIC = NA_real_,
                                       BIC = NA_real_,
                                       impacts_status = NA_character_,
                                       message = NA_character_) {
  spdm_empty_diag_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      model_family = model_family,
      w_type = w_type,
      status = status,
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = suppressWarnings(as.integer(sample_min_year)),
      sample_max_year = suppressWarnings(as.integer(sample_max_year)),
      selected_controls = collapse_chr(selected_controls),
      spatial_lagged_terms = as.character(spatial_lagged_terms),
      n_wx_terms = suppressWarnings(as.integer(n_wx_terms)),
      sdm_implementation = as.character(sdm_implementation),
      impact_method = as.character(impact_method),
      coef_se_method = as.character(coef_se_method),
      spatial_param_se_method = as.character(spatial_param_se_method),
      impact_se_method = as.character(impact_se_method),
      spatial_param_name = spatial_param_name,
      spatial_param_estimate = spatial_param_estimate,
      spatial_param_se = spatial_param_se,
      spatial_param_p = spatial_param_p,
      logLik = logLik,
      AIC = AIC,
      BIC = BIC,
      impacts_status = impacts_status,
      message = as.character(message)
    )
}

build_spdm_family_comparison_row <- function(spec_id,
                                             outcome,
                                             exposure,
                                             family,
                                             w_type,
                                             status,
                                             impacts_status = NA_character_,
                                             n_units,
                                             n_periods,
                                             n_obs,
                                             sample_min_year,
                                             sample_max_year,
                                             selected_controls,
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
                                             spatial_param_estimate = NA_real_,
                                             spatial_param_p = NA_real_,
                                             logLik = NA_real_,
                                             AIC = NA_real_,
                                             BIC = NA_real_,
                                             impacts_row = NULL,
                                             message = NA_character_) {
  if (is.null(impacts_row) || nrow(impacts_row) == 0L) {
    impacts_row <- spdm_empty_impacts_tbl() |>
      dplyr::add_row(status = "failed")
  }

  spdm_empty_family_comparison_tbl() |>
    dplyr::add_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure,
      family = family,
      w_type = w_type,
      status = status,
      impacts_status = impacts_status,
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sample_min_year = suppressWarnings(as.integer(sample_min_year)),
      sample_max_year = suppressWarnings(as.integer(sample_max_year)),
      selected_controls = collapse_chr(selected_controls),
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
      spatial_param_estimate = spatial_param_estimate,
      spatial_param_p = spatial_param_p,
      logLik = logLik,
      AIC = AIC,
      BIC = BIC,
      direct = impacts_row$direct[[1]],
      indirect = impacts_row$indirect[[1]],
      total = impacts_row$total[[1]],
      direct_p = impacts_row$direct_p[[1]],
      indirect_p = impacts_row$indirect_p[[1]],
      total_p = impacts_row$total_p[[1]],
      direct_ci_low = impacts_row$direct_ci_low[[1]],
      direct_ci_high = impacts_row$direct_ci_high[[1]],
      indirect_ci_low = impacts_row$indirect_ci_low[[1]],
      indirect_ci_high = impacts_row$indirect_ci_high[[1]],
      total_ci_low = impacts_row$total_ci_low[[1]],
      total_ci_high = impacts_row$total_ci_high[[1]],
      message = as.character(message)
    )
}
