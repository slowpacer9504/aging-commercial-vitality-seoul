#==============================================================================
# Script    : utils_gtwr_main.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide reusable helpers for the resident-only quarterly GTWR
#             optional sidecar.
# Author    : Codex
# Created   : 2026-04-27
# Type      : utility
# Inputs    : panel data frames, GTWR config, GTWR model objects
# Outputs   : GTWR helper tables, cache payloads, diagnostics
# DependsOn : config.R, utils_io.R, utils_model.R, utils_spatial.R
#==============================================================================

normalize_control_set_main <- function(x) {
  control_set <- tolower(trimws(as.character(x[[1]])))
  if (!control_set %in% c("lean", "extended")) "lean" else control_set
}

split_gtwr_tokens <- function(x) {
  x <- as.character(x[[1]])
  if (length(x) == 0L || is.na(x)) return(character())
  x <- trimws(x)
  if (!nzchar(x)) return(character())
  toks <- unlist(strsplit(x, "[,;|[:space:]]+"))
  toks[nzchar(toks)]
}

clean_gtwr_control_vector <- function(x) {
  vals <- unique(unlist(lapply(as.list(value_or(x, character())), split_gtwr_tokens)))
  vals <- trimws(as.character(vals))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  vals[!tolower(vals) %in% c("none", "na", "nan", "null")]
}

gtwr_retired_control_cols <- function() {
  c(
    "ln_worker_pop", "ln_floating_pop",
    "bus_stop_count_aux", "subway_station_count_aux",
    "apartment_count", "ln_apartment_count",
    "ln_apartment_household_count", "hospital_count_aux_core", "mall_count_aux_core"
  )
}

gtwr_main_control_candidate_cols <- function() {
  default_controls <- c("ln_resident_pop", "ln_official_land_price")
  controls <- value_or(cfg$gtwr_main_control_cols, default_controls)
  clean_gtwr_control_vector(controls)
}

gwr_delta_control_candidate_cols <- function() {
  controls <- value_or(cfg$gwr_delta_control_cols, gtwr_main_control_candidate_cols())
  clean_gtwr_control_vector(controls)
}

assert_gtwr_control_vector_current <- function(controls,
                                               context = "GTWR sidecar",
                                               allowed_controls = gtwr_main_control_candidate_cols()) {
  controls <- clean_gtwr_control_vector(controls)
  allowed_controls <- clean_gtwr_control_vector(allowed_controls)
  retired_controls <- gtwr_retired_control_cols()

  retired_allowed <- intersect(allowed_controls, retired_controls)
  if (length(retired_allowed) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s current GTWR config still allows retired control(s): %s.",
        context,
        collapse_chr(retired_allowed)
      ),
      call. = FALSE
    )
  }

  stale_controls <- setdiff(controls, allowed_controls)
  if (length(stale_controls) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s is using stale GTWR control candidate(s): %s. Use the current GTWR control contract.",
        context,
        collapse_chr(stale_controls)
      ),
      call. = FALSE
    )
  }

  retired_controls_used <- intersect(controls, retired_controls)
  if (length(retired_controls_used) > 0L) {
    stop(
      sprintf(
        "[ERROR] %s selected retired GTWR control(s): %s. Use the current GTWR control contract.",
        context,
        collapse_chr(retired_controls_used)
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assert_gtwr_controls_trace_current <- function(tbl,
                                               context = "GTWR controls trace",
                                               allowed_controls = gtwr_main_control_candidate_cols(),
                                               control_cols = c(
                                                 "required_controls",
                                                 "optional_candidates",
                                                 "global_usable_optional_controls",
                                                 "final_scope_usable_optional_controls",
                                                 "selected_controls",
                                                 "selected_optional_controls"
                                               )) {
  if (nrow(tbl) == 0L) return(invisible(TRUE))

  present_cols <- intersect(control_cols, names(tbl))
  if (length(present_cols) == 0L) return(invisible(TRUE))

  trace_controls <- unique(unlist(lapply(present_cols, function(col) {
    clean_gtwr_control_vector(tbl[[col]])
  })))
  assert_gtwr_control_vector_current(
    trace_controls,
    context = context,
    allowed_controls = allowed_controls
  )
}

repair_gtwr_controls_trace <- function(tbl) {
  required_cols <- c("optional_candidates", "selected_controls")
  if (nrow(tbl) == 0L || !all(required_cols %in% names(tbl))) return(tbl)

  tbl |>
    dplyr::mutate(
      unselected_controls = purrr::map2_chr(
        .data$optional_candidates,
        .data$selected_controls,
        ~ collapse_chr(base::setdiff(split_gtwr_tokens(.x), split_gtwr_tokens(.y)))
      )
    )
}

gtwr_controls_used_core_cols <- function() {
  c(
    "outcome",
    "focal_var",
    "control_set",
    "optional_candidates",
    "selected_controls",
    "unselected_controls",
    "base_n_obs",
    "base_n_units",
    "selected_n_obs",
    "selected_n_units",
    "retention_ratio",
    "retention_floor",
    "selection_status",
    "selection_strategy",
    "fit_scope",
    "recent_period_n",
    "location_frac",
    "location_n",
    "bw_obs_n",
    "bw_source",
    "control_origin",
    "bandwidth_origin",
    "frozen_spec_status",
    "frozen_spec_reason",
    "status",
    "message"
  )
}

standardize_gtwr_controls_used_tbl <- function(tbl) {
  if (nrow(tbl) == 0L) {
    return(empty_gtwr_controls_used_tbl())
  }
  cols <- c(
    gtwr_controls_used_core_cols(),
    intersect(c("outcome_group", "outcome_order"), names(tbl))
  )
  missing_cols <- setdiff(cols, names(tbl))
  for (col in missing_cols) {
    tbl[[col]] <- NA
  }
  dplyr::select(tbl, dplyr::all_of(cols))
}

parse_gtwr_numeric_grid <- function(x, default) {
  vals <- suppressWarnings(as.numeric(split_gtwr_tokens(x)))
  vals <- vals[is.finite(vals) & vals >= 0]
  if (length(vals) == 0L) vals <- default
  sort(unique(vals))
}

format_gtwr_num_token <- function(x) {
  token <- formatC(suppressWarnings(as.numeric(x[[1]])), format = "fg", digits = 10)
  token <- gsub("-", "m", token, fixed = TRUE)
  token <- gsub("[.]", "p", token)
  gsub("[^A-Za-z0-9_]+", "_", token)
}

gtwr_control_origin_label <- function() {
  sprintf("quarterly_gtwr_%s_control_pool", cfg$gtwr_control_set)
}

gtwr_control_selection_label <- function() {
  sprintf("%s_control_pool", cfg$gtwr_control_set)
}

empty_gtwr_main_tbl <- function() {
  tibble::tibble(
    method = character(),
    outcome = character(),
    focal_var = character(),
    exposure = character(),
    target_yq = character(),
    estimate_type = character(),
    earliest_yq = character(),
    latest_yq = character(),
    window_scope = character(),
    n_locations = integer(),
    n_valid = integer(),
    mean_beta = numeric(),
    sd_beta = numeric(),
    p25_beta = numeric(),
    p50_beta = numeric(),
	    p75_beta = numeric(),
	    share_positive = numeric(),
	    st_bw = numeric(),
	    global_lm_r2 = numeric(),
	    global_lm_r2_adj = numeric(),
	    gtw_aic = numeric(),
	    gtw_aicc = numeric(),
	    gtw_enp = numeric(),
	    gtw_edf = numeric(),
	    collinearity_warn_n = integer(),
	    collinearity_warn_share = numeric(),
	    latest_missing_n = integer(),
	    latest_coverage_share = numeric(),
	    max_local_cn_gtwr = numeric(),
    control_set = character(),
    fit_scope = character(),
    recent_period_n = integer(),
    location_frac = numeric(),
    location_n = integer(),
    n_obs_fit = integer(),
    bw_obs_n = integer(),
    bw_source = character(),
    control_origin = character(),
    bandwidth_origin = character(),
    frozen_spec_status = character(),
    frozen_spec_reason = character(),
    elapsed_sec = numeric(),
    status = character(),
    message = character()
  )
}

empty_gtwr_local_tbl <- function() {
  tibble::tibble(
    adm_cd = character(),
    outcome = character(),
    focal_var = character(),
    estimate = numeric(),
    earliest_estimate = numeric(),
    latest_estimate = numeric(),
    estimate_type = character(),
    earliest_yq = character(),
    latest_yq = character(),
    window_scope = character(),
    status = character(),
    message = character(),
    n_obs = integer(),
    n_eff = integer(),
    target_yq = character(),
    method = character(),
    control_set = character(),
    fit_scope = character(),
    recent_period_n = integer(),
    location_frac = numeric(),
    location_n = integer(),
    bw_obs_n = integer(),
    bw_source = character(),
	    local_cn_gtwr_earliest = numeric(),
	    local_cn_gtwr_latest = numeric(),
    collinearity_warn_earliest = logical(),
    collinearity_warn_latest = logical(),
    collinearity_warn_flag = logical(),
    collinearity_warn_stage = character(),
    collinearity_warn_metric = character(),
    collinearity_warn_threshold = numeric(),
    collinearity_diag_status = character(),
    collinearity_diag_message = character()
  )
}

empty_gtwr_local_beta_panel_tbl <- function() {
  tibble::tibble(
    adm_cd = character(),
    year = integer(),
    quarter = integer(),
    yq = character(),
    quarter_index = integer(),
    time_id = integer(),
    outcome = character(),
    focal_var = character(),
    estimate = numeric(),
    estimate_type = character(),
    window_scope = character(),
    status = character(),
    message = character(),
    n_obs = integer(),
    n_eff = integer(),
    target_yq = character(),
    method = character(),
    control_set = character(),
    fit_scope = character(),
    recent_period_n = integer(),
    location_frac = numeric(),
    location_n = integer(),
    bw_obs_n = integer(),
    bw_source = character()
  )
}

empty_gtwr_controls_used_tbl <- function() {
  tibble::tibble(
    outcome = character(),
    focal_var = character(),
    control_set = character(),
    optional_candidates = character(),
    selected_controls = character(),
    unselected_controls = character(),
    base_n_obs = integer(),
    base_n_units = integer(),
    selected_n_obs = integer(),
    selected_n_units = integer(),
    retention_ratio = numeric(),
    retention_floor = numeric(),
    selection_status = character(),
    selection_strategy = character(),
    fit_scope = character(),
    recent_period_n = integer(),
    location_frac = numeric(),
    location_n = integer(),
    bw_obs_n = integer(),
    bw_source = character(),
    control_origin = character(),
    bandwidth_origin = character(),
    frozen_spec_status = character(),
    frozen_spec_reason = character(),
    status = character(),
    message = character()
  )
}

empty_gtwr_frozen_spec_tbl <- function() {
  tibble::tibble(
    outcome = character(),
    focal_var = character(),
    control_set = character(),
    fit_scope = character(),
    formula = character(),
    selected_controls = character(),
    st_bw = numeric(),
    kernel = character(),
    adaptive = logical(),
    lamda = numeric(),
    ksi = numeric(),
    bw_source = character(),
    status = character(),
    message = character()
  )
}

empty_gtwr_lamda_sensitivity_tbl <- function() {
  tibble::tibble(
    method = character(),
    outcome = character(),
    focal_var = character(),
    exposure = character(),
    control_set = character(),
    lamda = numeric(),
    baseline_lamda = numeric(),
    ksi = numeric(),
    is_baseline_lamda = logical(),
    target_yq = character(),
    earliest_yq = character(),
    latest_yq = character(),
    window_scope = character(),
    n_locations = integer(),
    n_valid = integer(),
    n_obs_fit = integer(),
    st_bw = numeric(),
    bw_source = character(),
    bw_obs_n = integer(),
    global_lm_r2 = numeric(),
    global_lm_r2_adj = numeric(),
    gtw_aic = numeric(),
    gtw_aicc = numeric(),
    gtw_enp = numeric(),
    gtw_edf = numeric(),
    mean_beta = numeric(),
    sd_beta = numeric(),
    p25_beta = numeric(),
    p50_beta = numeric(),
    p75_beta = numeric(),
    share_positive = numeric(),
    max_local_cn_gtwr = numeric(),
    collinearity_warn_n = integer(),
    collinearity_warn_share = numeric(),
    n_compare_with_main = integer(),
    beta_corr_with_main = numeric(),
    mean_abs_delta_vs_main = numeric(),
    p50_abs_delta_vs_main = numeric(),
    max_abs_delta_vs_main = numeric(),
    sign_flip_share_vs_main = numeric(),
    status = character(),
    message = character(),
    elapsed_sec = numeric()
  )
}

empty_gtwr_bandwidth_sensitivity_tbl <- function() {
  tibble::tibble(
    method = character(),
    outcome = character(),
    focal_var = character(),
    exposure = character(),
    control_set = character(),
    st_bw = integer(),
    baseline_st_bw = integer(),
    is_baseline_st_bw = logical(),
    lamda = numeric(),
    ksi = numeric(),
    target_yq = character(),
    earliest_yq = character(),
    latest_yq = character(),
    window_scope = character(),
    n_locations = integer(),
    n_valid = integer(),
    n_obs_fit = integer(),
    bw_source = character(),
    bw_obs_n = integer(),
    global_lm_r2 = numeric(),
    global_lm_r2_adj = numeric(),
    gtw_aic = numeric(),
    gtw_aicc = numeric(),
    gtw_enp = numeric(),
    gtw_edf = numeric(),
    mean_beta = numeric(),
    sd_beta = numeric(),
    p25_beta = numeric(),
    p50_beta = numeric(),
    p75_beta = numeric(),
    share_positive = numeric(),
    max_local_cn_gtwr = numeric(),
    collinearity_warn_n = integer(),
    collinearity_warn_share = numeric(),
    n_compare_with_main = integer(),
    beta_corr_with_main = numeric(),
    mean_abs_delta_vs_main = numeric(),
    p50_abs_delta_vs_main = numeric(),
    max_abs_delta_vs_main = numeric(),
    sign_flip_share_vs_main = numeric(),
    status = character(),
    message = character(),
    elapsed_sec = numeric()
  )
}

build_gtwr_deferred_main_row <- function(outcome,
                                         focal_var,
                                         control_set,
                                         fit_scope,
                                         n_obs_fit,
                                         n_units,
                                         n_periods,
                                         sample_min_yq = NA_character_,
                                         sample_max_yq = NA_character_,
                                         control_origin,
                                         bandwidth_origin,
                                         message,
                                         selected_st_bw = NA_real_,
                                         elapsed_sec = NA_real_) {
  empty_gtwr_main_tbl() |>
    dplyr::add_row(
      method = "GWmodel::gtwr",
      outcome = outcome,
      focal_var = focal_var,
      exposure = focal_var,
      target_yq = as.character(sample_max_yq),
      estimate_type = "latest",
      earliest_yq = as.character(sample_min_yq),
      latest_yq = as.character(sample_max_yq),
      window_scope = "quarterly_full_window",
      n_locations = as.integer(n_units),
      n_valid = 0L,
      st_bw = selected_st_bw,
      control_set = control_set,
      fit_scope = fit_scope,
      recent_period_n = as.integer(n_periods),
      location_frac = 1,
      location_n = as.integer(n_units),
      n_obs_fit = as.integer(n_obs_fit),
      bw_obs_n = suppressWarnings(as.integer(selected_st_bw)),
      bw_source = bandwidth_origin,
      control_origin = control_origin,
      bandwidth_origin = bandwidth_origin,
      frozen_spec_status = "not_estimated",
      frozen_spec_reason = message,
      elapsed_sec = elapsed_sec,
      status = "not_estimated",
      message = message
    )
}

build_gtwr_deferred_controls_row <- function(outcome,
                                             focal_var,
                                             control_candidates,
                                             usable_controls,
                                             control_set = cfg$gtwr_control_set,
                                             n_obs_fit,
                                             n_units,
                                             n_periods,
                                             message,
                                             selected_st_bw = NA_real_,
                                             fit_scope = "quarterly_deferred",
                                             bandwidth_origin = "deferred") {
  unselected_controls_text <- collapse_chr(base::setdiff(control_candidates, usable_controls))

  empty_gtwr_controls_used_tbl() |>
    dplyr::add_row(
      outcome = outcome,
      focal_var = focal_var,
      control_set = control_set,
      optional_candidates = collapse_chr(control_candidates),
      selected_controls = collapse_chr(usable_controls),
      unselected_controls = unselected_controls_text,
      base_n_obs = as.integer(n_obs_fit),
      base_n_units = as.integer(n_units),
      selected_n_obs = as.integer(n_obs_fit),
      selected_n_units = as.integer(n_units),
	      retention_ratio = 1,
	      retention_floor = 1,
	      selection_status = "quarterly_not_estimated",
	      selection_strategy = gtwr_control_selection_label(),
      fit_scope = fit_scope,
      recent_period_n = as.integer(n_periods),
      location_frac = 1,
      location_n = as.integer(n_units),
      bw_obs_n = suppressWarnings(as.integer(selected_st_bw)),
      bw_source = bandwidth_origin,
	      control_origin = gtwr_control_origin_label(),
      bandwidth_origin = bandwidth_origin,
      frozen_spec_status = "not_estimated",
      frozen_spec_reason = message,
      status = "not_estimated",
      message = message
    )
}

prepare_gtwr_points <- function(panel) {
  boundary <- load_commercial_boundary(cfg$dir_boundary, cfg$target_crs)
  boundary_pts <- sf::st_point_on_surface(sf::st_geometry(boundary))
  xy <- sf::st_coordinates(boundary_pts)

  coord_tbl <- boundary |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      adm_cd = as.character(.data$adm_cd),
      x = as.numeric(xy[, 1]),
      y = as.numeric(xy[, 2])
    ) |>
    dplyr::distinct(adm_cd, .keep_all = TRUE)

  period_order <- panel |>
    dplyr::distinct(.data$yq, .data$quarter_index) |>
    dplyr::arrange(.data$quarter_index, .data$yq) |>
    dplyr::pull(.data$yq) |>
    as.character()
  panel |>
    dplyr::mutate(
      adm_cd = as.character(.data$adm_cd),
      year = suppressWarnings(as.integer(.data$year)),
      quarter = suppressWarnings(as.integer(.data$quarter)),
      yq = as.character(.data$yq),
      quarter_index = suppressWarnings(as.integer(.data$quarter_index)),
      time_id = as.integer(match(.data$yq, period_order))
    ) |>
    dplyr::left_join(coord_tbl, by = "adm_cd")
}

build_gtwr_st_dmat <- function(d_fit, lamda = cfg$gtwr_lamda, ksi = cfg$gtwr_ksi) {
  coords <- as.matrix(d_fit[, c("x", "y")])
  out <- tryCatch(
    GWmodel::st.dist(
      dp.locat = coords,
      obs.tv = d_fit$time_id,
      p = 2,
      theta = 0,
      longlat = FALSE,
      lamda = lamda,
      ksi = ksi
    ),
    error = function(e) NULL
  )
  if (is.null(out) || !is.matrix(out) || any(dim(out) != nrow(d_fit))) {
    return(NULL)
  }
  out
}

weighted_design_cn <- function(model_matrix, weights) {
  # Mirrors GWmodel::gwr.collin.diagno() local_CN, but uses the GTWR
  # spatiotemporal weights generated from st.dist/gw.weight.
  if (is.null(model_matrix) || nrow(model_matrix) == 0L || ncol(model_matrix) == 0L) {
    return(NA_real_)
  }

  mm <- suppressWarnings(as.matrix(model_matrix))
  w <- suppressWarnings(as.numeric(weights))
  if (length(w) != nrow(mm)) return(NA_real_)
  keep <- stats::complete.cases(mm) & is.finite(w) & w >= 0
  if (!any(keep)) return(NA_real_)

  mm <- mm[keep, , drop = FALSE]
  w <- w[keep]
  if (sum(w) <= .Machine$double.eps) return(NA_real_)
  if (sum(w > sqrt(.Machine$double.eps)) < ncol(mm) + 1L) return(NA_real_)

  wi <- w / sum(w)
  xw <- sweep(mm, 1, wi, "*")
  col_norm <- sqrt(colSums(xw^2, na.rm = TRUE))
  if (any(!is.finite(col_norm) | col_norm <= .Machine$double.eps)) return(Inf)

  x_scaled <- sweep(xw, 2, col_norm, "/")
  sv <- tryCatch(svd(x_scaled, nu = 0, nv = 0)$d, error = function(e) NA_real_)
  sv <- suppressWarnings(as.numeric(sv))
  sv <- sv[is.finite(sv)]
  if (length(sv) == 0L) return(NA_real_)
  if (min(sv) <= .Machine$double.eps) return(Inf)
  max(sv) / min(sv)
}

compute_gtwr_local_cn <- function(d_fit, rhs_vars, st_bw, st_dmat, target_idx) {
  if (length(target_idx) == 0L) return(numeric(0))
  if (is.null(st_dmat) || !is.matrix(st_dmat) || any(dim(st_dmat) != nrow(d_fit))) {
    return(rep(NA_real_, length(target_idx)))
  }

  mm <- tryCatch(
    stats::model.matrix(stats::reformulate(rhs_vars), data = d_fit),
    error = function(e) NULL
  )
  if (is.null(mm) || ncol(mm) <= 1L) return(rep(NA_real_, length(target_idx)))

  vapply(target_idx, function(i) {
    weights <- tryCatch(
      GWmodel::gw.weight(
        vdist = st_dmat[, i],
        bw = st_bw,
        kernel = cfg$gtwr_kernel,
        adaptive = isTRUE(cfg$gtwr_adaptive)
      ),
      error = function(e) rep(NA_real_, nrow(d_fit))
    )
    weighted_design_cn(mm, weights)
  }, numeric(1))
}

gtwr_period_id <- function(d_fit) {
  if ("time_id" %in% names(d_fit)) {
    out <- suppressWarnings(as.integer(d_fit$time_id))
    if (any(is.finite(out))) return(out)
  }
  if ("quarter_index" %in% names(d_fit)) {
    out <- suppressWarnings(as.integer(d_fit$quarter_index))
    if (any(is.finite(out))) return(out)
  }
  if ("yq" %in% names(d_fit)) {
    yq <- as.character(d_fit$yq)
    levels <- sort(unique(yq[!is.na(yq) & nzchar(yq)]))
    return(as.integer(factor(yq, levels = levels)))
  }
  suppressWarnings(as.integer(d_fit$year))
}

gtwr_period_meta <- function(d_fit) {
  period_id <- gtwr_period_id(d_fit)
  valid_ids <- period_id[is.finite(period_id)]
  period_levels <- sort(unique(valid_ids))
  if (length(period_levels) == 0L) {
    return(list(
      period_id = period_id,
      n_periods = 0L,
      earliest_period_id = NA_integer_,
      latest_period_id = NA_integer_,
      earliest_year = NA_integer_,
      latest_year = NA_integer_,
      earliest_yq = NA_character_,
      latest_yq = NA_character_
    ))
  }

  pick_idx <- function(period_value) {
    idx <- which(period_id == period_value)
    if (length(idx) == 0L) NA_integer_ else idx[[1L]]
  }
  earliest_id <- period_levels[[1L]]
  latest_id <- period_levels[[length(period_levels)]]
  earliest_idx <- pick_idx(earliest_id)
  latest_idx <- pick_idx(latest_id)

  get_int <- function(col, idx) {
    if (!col %in% names(d_fit) || !is.finite(idx)) return(NA_integer_)
    suppressWarnings(as.integer(d_fit[[col]][[idx]]))
  }
  get_chr <- function(col, idx) {
    if (!col %in% names(d_fit) || !is.finite(idx)) return(NA_character_)
    val <- as.character(d_fit[[col]][[idx]])
    if (length(val) == 0L || is.na(val) || !nzchar(val)) NA_character_ else val
  }

  list(
    period_id = period_id,
    n_periods = as.integer(length(period_levels)),
    earliest_period_id = as.integer(earliest_id),
    latest_period_id = as.integer(latest_id),
    earliest_year = get_int("year", earliest_idx),
    latest_year = get_int("year", latest_idx),
    earliest_yq = get_chr("yq", earliest_idx),
    latest_yq = get_chr("yq", latest_idx)
  )
}

local_cn_for_window <- function(d_fit, rhs_vars, st_bw, st_dmat, threshold) {
  period_meta <- gtwr_period_meta(d_fit)
  period_id <- period_meta$period_id

  build_period_cn <- function(target_period_id, suffix) {
    target_idx <- which(period_id == target_period_id)
    target_idx <- target_idx[order(d_fit$adm_cd[target_idx])]

    cn <- if (length(target_idx) == 0L) {
      numeric(0)
    } else {
      compute_gtwr_local_cn(
        d_fit = d_fit,
        rhs_vars = rhs_vars,
        st_bw = st_bw,
        st_dmat = st_dmat,
        target_idx = target_idx
      )
    }

	    tibble::tibble(
	      adm_cd = d_fit$adm_cd[target_idx],
	      !!paste0("local_cn_gtwr_", suffix) := cn,
	      !!paste0("collinearity_warn_", suffix) := is.finite(cn) & cn >= threshold
	    )
  }

  dplyr::full_join(
    build_period_cn(period_meta$earliest_period_id, "earliest"),
    build_period_cn(period_meta$latest_period_id, "latest"),
    by = "adm_cd"
  )
}

pick_period_value <- function(x, period_id, target_period_id) {
  idx <- which(period_id == target_period_id & is.finite(x))
  if (length(idx) == 0L) return(NA_real_)
  suppressWarnings(as.numeric(x[[idx[[1]]]]))
}

extract_gtwr_diagnostics <- function(model) {
	  lm_r2 <- NA_real_
	  lm_r2_adj <- NA_real_
	  gtw_aic <- NA_real_
	  gtw_aicc <- NA_real_
	  gtw_enp <- NA_real_
	  gtw_edf <- NA_real_

	  lm_obj <- model$lm
	  if (!is.null(lm_obj)) {
	    sm <- tryCatch(summary(lm_obj), error = function(e) NULL)
	    if (!is.null(sm)) {
	      lm_r2 <- suppressWarnings(as.numeric(value_or(sm$r.squared, NA_real_)[[1]]))
	      lm_r2_adj <- suppressWarnings(as.numeric(value_or(sm$adj.r.squared, NA_real_)[[1]]))
	    }
	  }

	  diag_obj <- model$GTW.diagnostic
	  if (!is.null(diag_obj)) {
	    diag_vec <- suppressWarnings(unlist(diag_obj))
	    find_diag <- function(pattern) {
	      idx <- grep(pattern, names(diag_vec), ignore.case = TRUE)
	      if (length(idx) == 0L) return(NA_real_)
	      suppressWarnings(as.numeric(diag_vec[[idx[[1]]]]))
	    }
	    gtw_aicc <- find_diag("aicc")
	    gtw_aic <- find_diag("^aic$|\\baic\\b")
	    gtw_enp <- find_diag("enp")
	    gtw_edf <- find_diag("edf")
	  }

	  tibble::tibble(
	    global_lm_r2 = if (is.finite(lm_r2)) lm_r2 else NA_real_,
	    global_lm_r2_adj = if (is.finite(lm_r2_adj)) lm_r2_adj else NA_real_,
	    gtw_aic = if (is.finite(gtw_aic)) gtw_aic else NA_real_,
	    gtw_aicc = if (is.finite(gtw_aicc)) gtw_aicc else NA_real_,
	    gtw_enp = if (is.finite(gtw_enp)) gtw_enp else NA_real_,
	    gtw_edf = if (is.finite(gtw_edf)) gtw_edf else NA_real_
	  )
	}

summarise_numeric <- function(x) {
  vals <- suppressWarnings(as.numeric(x))
  vals <- vals[is.finite(vals)]
  if (length(vals) == 0L) {
    return(list(
      n_valid = 0L,
      mean_beta = NA_real_,
      sd_beta = NA_real_,
      p25_beta = NA_real_,
      p50_beta = NA_real_,
      p75_beta = NA_real_,
      share_positive = NA_real_
    ))
  }

  list(
    n_valid = as.integer(length(vals)),
    mean_beta = mean(vals),
    sd_beta = if (length(vals) >= 2L) stats::sd(vals) else NA_real_,
    p25_beta = as.numeric(stats::quantile(vals, 0.25, names = FALSE, na.rm = TRUE)),
    p50_beta = as.numeric(stats::quantile(vals, 0.50, names = FALSE, na.rm = TRUE)),
    p75_beta = as.numeric(stats::quantile(vals, 0.75, names = FALSE, na.rm = TRUE)),
    share_positive = mean(vals > 0)
  )
}

build_frozen_spec_row <- function(outcome,
                                  focal_var,
                                  control_set,
                                  fit_scope,
                                  formula_text,
                                  selected_controls,
                                  st_bw,
                                  bw_source,
                                  status,
                                  message) {
  empty_gtwr_frozen_spec_tbl() |>
    dplyr::add_row(
      outcome = outcome,
      focal_var = focal_var,
      control_set = control_set,
      fit_scope = fit_scope,
      formula = formula_text,
      selected_controls = collapse_chr(selected_controls),
      st_bw = suppressWarnings(as.numeric(st_bw)),
      kernel = cfg$gtwr_kernel,
      adaptive = isTRUE(cfg$gtwr_adaptive),
      lamda = suppressWarnings(as.numeric(cfg$gtwr_lamda)),
      ksi = suppressWarnings(as.numeric(cfg$gtwr_ksi)),
      bw_source = bw_source,
      status = status,
      message = message
    )
}

sanitize_gtwr_cache_token <- function(x) {
  token <- gsub("[^A-Za-z0-9_]+", "_", as.character(x[[1]]))
  gsub("_+", "_", token)
}

build_gtwr_spec_id <- function(outcome, focal_var) {
  paste(sanitize_gtwr_cache_token(outcome), sanitize_gtwr_cache_token(focal_var), sep = "__")
}

build_gtwr_panel_cache_stamp <- function() {
  if (!file.exists(cfg$paths$panel_main)) return("panel_main_missing")
  info <- file.info(cfg$paths$panel_main)
  paste0(
    basename(cfg$paths$panel_main),
    "|size=", as.character(info$size[[1]]),
    "|mtime=", format(info$mtime[[1]], "%Y-%m-%d %H:%M:%OS6 %z")
  )
}

build_gtwr_spec_signature <- function(outcome,
                                      focal_var,
                                      selected_controls,
                                      control_set,
                                      cache_context = "main",
                                      extra_cache_stamp = NULL) {
  paste(
    c(
      "quarterly_gtwr_spec_cache_v6_gwmodel_local_cn",
      paste("cache_context", cache_context, sep = "="),
      if (!is.null(extra_cache_stamp)) paste("extra_cache_stamp", extra_cache_stamp, sep = "=") else NULL,
      paste("panel", build_gtwr_panel_cache_stamp(), sep = "="),
      paste("outcome", outcome, sep = "="),
      paste("focal_var", focal_var, sep = "="),
      paste("control_set", as.character(control_set), sep = "="),
      paste("controls", paste(selected_controls, collapse = ";"), sep = "="),
      paste("bw_strategy", as.character(cfg$gtwr_bandwidth_strategy), sep = "="),
      paste("bw_anchor_yq", as.character(value_or(cfg$gtwr_bw_anchor_yq, NA_character_)), sep = "="),
      paste("bw_approach", as.character(cfg$gtwr_bw_approach), sep = "="),
      paste("fallback_st_bw", as.character(cfg$gtwr_st_bw), sep = "="),
      paste("kernel", as.character(cfg$gtwr_kernel), sep = "="),
      paste("adaptive", as.character(isTRUE(cfg$gtwr_adaptive)), sep = "="),
      paste("lamda", as.character(cfg$gtwr_lamda), sep = "="),
      paste("ksi", as.character(cfg$gtwr_ksi), sep = "=")
    ),
    collapse = "|"
  )
}

build_gtwr_bandwidth_signature <- function(outcome,
                                           focal_var,
                                           selected_controls,
                                           control_set,
                                           bandwidth_scope,
                                           bandwidth_periods,
                                           lamda = cfg$gtwr_lamda,
                                           ksi = cfg$gtwr_ksi,
                                           cache_context = "main") {
	  paste(
	    c(
	      "quarterly_gtwr_main_bandwidth_cache_v3_st_dmat",
      paste("cache_context", cache_context, sep = "="),
	      paste("panel", build_gtwr_panel_cache_stamp(), sep = "="),
	      paste("outcome", outcome, sep = "="),
	      paste("focal_var", focal_var, sep = "="),
	      paste("control_set", as.character(control_set), sep = "="),
	      paste("controls", paste(selected_controls, collapse = ";"), sep = "="),
	      paste("bw_strategy", as.character(cfg$gtwr_bandwidth_strategy), sep = "="),
	      paste("bandwidth_scope", as.character(bandwidth_scope), sep = "="),
		      paste("bandwidth_periods", paste(as.character(bandwidth_periods), collapse = ";"), sep = "="),
		      paste("anchor_yq", as.character(value_or(cfg$gtwr_bw_anchor_yq, NA_character_)), sep = "="),
	      paste("approach", as.character(cfg$gtwr_bw_approach), sep = "="),
      paste("kernel", as.character(cfg$gtwr_kernel), sep = "="),
      paste("adaptive", as.character(isTRUE(cfg$gtwr_adaptive)), sep = "="),
      paste("lamda", as.character(lamda), sep = "="),
      paste("ksi", as.character(ksi), sep = "=")
    ),
    collapse = "|"
  )
}

get_gtwr_spec_cache_path <- function(cache_dir, outcome, focal_var) {
  file.path(cache_dir, paste0(build_gtwr_spec_id(outcome, focal_var), ".rds"))
}

get_gtwr_bandwidth_cache_path <- function(cache_dir, outcome, focal_var, cache_context = "main") {
  suffix <- if (identical(cache_context, "main")) "" else paste0("__", sanitize_gtwr_cache_token(cache_context))
  file.path(cache_dir, paste0(build_gtwr_spec_id(outcome, focal_var), suffix, ".rds"))
}

is_valid_gtwr_payload <- function(payload) {
  is.list(payload) &&
    all(c("summary", "local", "panel", "controls", "frozen") %in% names(payload)) &&
    is.data.frame(payload$summary) &&
    is.data.frame(payload$local) &&
    is.data.frame(payload$panel) &&
    is.data.frame(payload$controls) &&
    is.data.frame(payload$frozen) &&
    nrow(payload$summary) > 0L &&
    "status" %in% names(payload$summary)
}

add_gtwr_constant_cols <- function(tbl, values) {
  values <- values[!vapply(values, is.null, logical(1))]
  if (length(values) == 0L) return(tbl)

  for (nm in names(values)) {
    val <- values[[nm]]
    if (length(val) == 0L) val <- NA_character_
    tbl[[nm]] <- if (nrow(tbl) == 0L) val[0] else rep(val[[1]], nrow(tbl))
  }
  tbl
}

add_gtwr_payload_metadata <- function(payload, metadata) {
  if (!is_valid_gtwr_payload(payload)) return(payload)
  payload$summary <- add_gtwr_constant_cols(payload$summary, metadata)
  payload$local <- add_gtwr_constant_cols(payload$local, metadata)
  payload$panel <- add_gtwr_constant_cols(payload$panel, metadata)
  payload$controls <- add_gtwr_constant_cols(payload$controls, metadata)
  payload$frozen <- add_gtwr_constant_cols(payload$frozen, metadata)
  payload
}

read_gtwr_spec_cache <- function(path, signature) {
  if (!file.exists(path)) return(NULL)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.list(obj) || !identical(obj$signature, signature)) return(NULL)
  if (!is_valid_gtwr_payload(obj$payload)) return(NULL)
  obj$payload
}

write_gtwr_spec_cache <- function(path, signature, payload) {
  save_rds_safe(
    list(
      signature = signature,
      saved_at = timestamp(),
      payload = payload
    ),
    path
  )
  invisible(path)
}

is_valid_gtwr_bandwidth_payload <- function(payload) {
  is.list(payload) &&
    "st_bw" %in% names(payload) &&
    is.finite(suppressWarnings(as.numeric(payload$st_bw[[1]])))
}

read_gtwr_bandwidth_cache <- function(path, signature) {
  if (!file.exists(path)) return(NULL)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.list(obj) || !identical(obj$signature, signature)) return(NULL)
  if (!is_valid_gtwr_bandwidth_payload(obj$payload)) return(NULL)
  obj$payload
}

write_gtwr_bandwidth_cache <- function(path, signature, payload) {
  save_rds_safe(
    list(
      signature = signature,
      saved_at = timestamp(),
      payload = payload
    ),
    path
  )
  invisible(path)
}

build_gtwr_lamda_sensitivity_signature <- function(outcome, focal_var, selected_controls, control_set, lamda, ksi) {
  paste(
    c(
      "quarterly_gtwr_lamda_sensitivity_cache_v2",
      paste("panel", build_gtwr_panel_cache_stamp(), sep = "="),
      paste("outcome", outcome, sep = "="),
      paste("focal_var", focal_var, sep = "="),
      paste("control_set", as.character(control_set), sep = "="),
      paste("controls", paste(selected_controls, collapse = ";"), sep = "="),
      paste("bw_strategy", as.character(cfg$gtwr_bandwidth_strategy), sep = "="),
      paste("bw_anchor_yq", as.character(value_or(cfg$gtwr_bw_anchor_yq, NA_character_)), sep = "="),
      paste("bw_approach", as.character(cfg$gtwr_bw_approach), sep = "="),
      paste("fallback_st_bw", as.character(cfg$gtwr_st_bw), sep = "="),
      paste("kernel", as.character(cfg$gtwr_kernel), sep = "="),
      paste("adaptive", as.character(isTRUE(cfg$gtwr_adaptive)), sep = "="),
      paste("lamda", as.character(lamda), sep = "="),
      paste("baseline_lamda", as.character(cfg$gtwr_lamda), sep = "="),
      paste("ksi", as.character(ksi), sep = "=")
    ),
    collapse = "|"
  )
}

get_gtwr_lamda_sensitivity_cache_path <- function(cache_dir, outcome, focal_var, lamda, ksi) {
  suffix <- paste0(
    "__lamda_", format_gtwr_num_token(lamda),
    "__ksi_", format_gtwr_num_token(ksi)
  )
  file.path(cache_dir, paste0(build_gtwr_spec_id(outcome, focal_var), suffix, ".rds"))
}

is_valid_gtwr_lamda_sensitivity_payload <- function(payload) {
  if (!is.data.frame(payload) || nrow(payload) == 0L) return(FALSE)
  if (!all(c("outcome", "focal_var", "lamda", "status", "n_valid") %in% names(payload))) return(FALSE)

  status <- as.character(payload$status)
  n_valid <- suppressWarnings(as.integer(payload$n_valid))
  if (any(status == "success" & (!is.finite(n_valid) | n_valid <= 0L), na.rm = TRUE)) {
    return(FALSE)
  }

  TRUE
}

read_gtwr_lamda_sensitivity_cache <- function(path, signature) {
  if (!file.exists(path)) return(NULL)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.list(obj) || !identical(obj$signature, signature)) return(NULL)
  if (!is_valid_gtwr_lamda_sensitivity_payload(obj$payload)) return(NULL)
  obj$payload
}

write_gtwr_lamda_sensitivity_cache <- function(path, signature, payload) {
  save_rds_safe(
    list(
      signature = signature,
      saved_at = timestamp(),
      payload = payload
    ),
    path
  )
  invisible(path)
}

build_gtwr_bandwidth_sensitivity_signature <- function(outcome, focal_var, selected_controls, control_set, st_bw, baseline_st_bw, lamda, ksi) {
  paste(
    c(
      "quarterly_gtwr_bandwidth_sensitivity_cache_v1",
      paste("panel", build_gtwr_panel_cache_stamp(), sep = "="),
      paste("outcome", outcome, sep = "="),
      paste("focal_var", focal_var, sep = "="),
      paste("control_set", as.character(control_set), sep = "="),
      paste("controls", paste(selected_controls, collapse = ";"), sep = "="),
      paste("st_bw", as.character(st_bw), sep = "="),
      paste("baseline_st_bw", as.character(baseline_st_bw), sep = "="),
      paste("kernel", as.character(cfg$gtwr_kernel), sep = "="),
      paste("adaptive", as.character(isTRUE(cfg$gtwr_adaptive)), sep = "="),
      paste("lamda", as.character(lamda), sep = "="),
      paste("ksi", as.character(ksi), sep = "=")
    ),
    collapse = "|"
  )
}

get_gtwr_bandwidth_sensitivity_cache_path <- function(cache_dir, outcome, focal_var, st_bw, lamda, ksi) {
  suffix <- paste0(
    "__st_bw_", format_gtwr_num_token(st_bw),
    "__lamda_", format_gtwr_num_token(lamda),
    "__ksi_", format_gtwr_num_token(ksi)
  )
  file.path(cache_dir, paste0(build_gtwr_spec_id(outcome, focal_var), suffix, ".rds"))
}

is_valid_gtwr_bandwidth_sensitivity_payload <- function(payload) {
  if (!is.data.frame(payload) || nrow(payload) == 0L) return(FALSE)
  if (!all(c("outcome", "focal_var", "st_bw", "status", "n_valid") %in% names(payload))) return(FALSE)

  status <- as.character(payload$status)
  n_valid <- suppressWarnings(as.integer(payload$n_valid))
  if (any(status == "success" & (!is.finite(n_valid) | n_valid <= 0L), na.rm = TRUE)) {
    return(FALSE)
  }

  TRUE
}

read_gtwr_bandwidth_sensitivity_cache <- function(path, signature) {
  if (!file.exists(path)) return(NULL)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.list(obj) || !identical(obj$signature, signature)) return(NULL)
  if (!is_valid_gtwr_bandwidth_sensitivity_payload(obj$payload)) return(NULL)
  obj$payload
}

write_gtwr_bandwidth_sensitivity_cache <- function(path, signature, payload) {
  save_rds_safe(
    list(
      signature = signature,
      saved_at = timestamp(),
      payload = payload
    ),
    path
  )
  invisible(path)
}

clamp_gtwr_st_bw <- function(st_bw, n_obs_fit, rhs_vars) {
  st_bw <- suppressWarnings(as.integer(round(as.numeric(st_bw[[1]]))))
  if (!is.finite(st_bw)) st_bw <- suppressWarnings(as.integer(cfg$gtwr_st_bw))
  min_bw <- max(30L, length(rhs_vars) + 2L)
  max_bw <- max(as.integer(n_obs_fit) - 1L, 1L)
  min(max(st_bw, min_bw), max_bw)
}

resolve_fixed_gtwr_st_bw <- function(n_obs_fit, rhs_vars) {
  clamp_gtwr_st_bw(cfg$gtwr_st_bw, n_obs_fit, rhs_vars)
}

resolve_gtwr_st_bw <- function(d_fit,
	                               formula_obj,
	                               rhs_vars,
	                               outcome,
	                               focal_var,
	                               selected_controls,
	                               control_set,
                               st_dmat = NULL,
                               lamda = cfg$gtwr_lamda,
                               ksi = cfg$gtwr_ksi,
                               cache_context = "main",
                               bw_cache_dir = NULL) {
	  n_obs_fit <- nrow(d_fit)
	  fallback_st_bw <- resolve_fixed_gtwr_st_bw(n_obs_fit, rhs_vars)
	  strategy <- as.character(cfg$gtwr_bandwidth_strategy[[1]])
	  if (identical(strategy, "fixed")) {
	    return(list(st_bw = fallback_st_bw, bw_source = "fixed_env_or_default", bw_raw = NA_real_, bw_obs_n = NA_integer_))
	  }

	  if (identical(strategy, "anchor_quarter_bw_gtwr")) {
	    anchor_yq <- as.character(value_or(cfg$gtwr_bw_anchor_yq, NA_character_)[[1]])
	    bw_idx <- which(as.character(d_fit$yq) == anchor_yq)
	    d_bw <- d_fit[bw_idx, , drop = FALSE]
	    st_dmat_bw <- if (!is.null(st_dmat) && length(bw_idx) > 0L) st_dmat[bw_idx, bw_idx, drop = FALSE] else NULL
	    bandwidth_scope <- sprintf("anchor_quarter_%s", anchor_yq)
	    bandwidth_periods <- anchor_yq
	  } else {
	    d_bw <- d_fit
	    st_dmat_bw <- st_dmat
	    bandwidth_scope <- "full_panel"
	    bandwidth_periods <- sort(unique(as.character(d_fit$yq)))
	  }
	  min_bw_obs <- max(30L, length(rhs_vars) + 3L)
	  if (nrow(d_bw) < min_bw_obs) {
	    return(list(
	      st_bw = fallback_st_bw,
	      bw_source = sprintf("fixed_fallback_%s_insufficient", bandwidth_scope),
	      bw_raw = NA_real_,
	      bw_obs_n = nrow(d_bw)
	    ))
	  }

  cache_dir <- if (is.null(bw_cache_dir)) {
    cfg$get_gtwr_main_bw_cache_dir(control_set)
  } else {
    bw_cache_dir
  }
  ensure_dirs(cache_dir)
  signature <- build_gtwr_bandwidth_signature(
    outcome = outcome,
	    focal_var = focal_var,
	    selected_controls = selected_controls,
	    control_set = control_set,
	    bandwidth_scope = bandwidth_scope,
	    bandwidth_periods = bandwidth_periods,
    lamda = lamda,
    ksi = ksi,
    cache_context = cache_context
	  )
	  cache_path <- get_gtwr_bandwidth_cache_path(cache_dir, outcome, focal_var, cache_context = cache_context)
	  cached <- if (!isTRUE(cfg$gtwr_refresh_bw_cache)) read_gtwr_bandwidth_cache(cache_path, signature) else NULL
	  if (!is.null(cached)) {
	    return(list(
	      st_bw = suppressWarnings(as.numeric(cached$st_bw[[1]])),
	      bw_source = sprintf("bw.gtwr_%s_cache", bandwidth_scope),
	      bw_raw = suppressWarnings(as.numeric(cached$bw_raw[[1]])),
	      bw_obs_n = if ("n_bandwidth_obs" %in% names(cached)) {
	        suppressWarnings(as.integer(cached$n_bandwidth_obs[[1]]))
	      } else {
	        NA_integer_
	      }
	    ))
	  }

  coords <- as.matrix(d_bw[, c("x", "y")])
  spdf_bw <- sp::SpatialPointsDataFrame(
    coords = coords,
    data = as.data.frame(d_bw |> dplyr::select(-x, -y)),
    proj4string = sp::CRS(SRS_string = sprintf("EPSG:%s", cfg$target_crs))
  )
  bw_args <- list(
    formula = formula_obj,
    data = spdf_bw,
    obs.tv = d_bw$time_id,
	    approach = cfg$gtwr_bw_approach,
	    kernel = cfg$gtwr_kernel,
	    adaptive = isTRUE(cfg$gtwr_adaptive),
	    lamda = lamda,
	    ksi = ksi,
	    verbose = FALSE
  )
  if (!is.null(st_dmat_bw) && is.matrix(st_dmat_bw) && all(dim(st_dmat_bw) == nrow(d_bw))) {
    bw_args$st.dMat <- st_dmat_bw
  }
  bw_raw <- tryCatch(
    do.call(GWmodel::bw.gtwr, bw_args),
    error = function(e) e
  )

	  if (inherits(bw_raw, "error") || !is.finite(suppressWarnings(as.numeric(bw_raw[[1]])))) {
	    return(list(
	      st_bw = fallback_st_bw,
	      bw_source = sprintf("fixed_fallback_bw.gtwr_%s_error", bandwidth_scope),
	      bw_raw = NA_real_,
	      bw_obs_n = nrow(d_bw)
	    ))
	  }

  bw_raw_num <- suppressWarnings(as.numeric(bw_raw[[1]]))
  if (isTRUE(cfg$gtwr_adaptive)) {
    st_bw <- min(max(as.integer(round(bw_raw_num)), max(30L, length(rhs_vars) + 2L)), max(n_obs_fit - 1L, 1L))
  } else {
    st_bw <- bw_raw_num
  }

  write_gtwr_bandwidth_cache(
    cache_path,
    signature,
	    list(
	      st_bw = st_bw,
	      bw_raw = bw_raw_num,
	      bw_source = sprintf("bw.gtwr_%s_search", bandwidth_scope),
		      bandwidth_strategy = strategy,
		      bandwidth_scope = bandwidth_scope,
		      bandwidth_periods = bandwidth_periods,
	      approach = cfg$gtwr_bw_approach,
      lamda = lamda,
      ksi = ksi,
      cache_context = cache_context,
	      n_bandwidth_obs = nrow(d_bw),
	      n_fit_obs = n_obs_fit,
	      rhs_vars = rhs_vars
	    )
  )

	  list(
	    st_bw = st_bw,
	    bw_source = sprintf("bw.gtwr_%s_search", bandwidth_scope),
	    bw_raw = bw_raw_num,
	    bw_obs_n = nrow(d_bw)
	  )
	}

resolve_gtwr_worker_count <- function(n_jobs) {
  if (n_jobs <= 0L) return(0L)
  requested <- suppressWarnings(as.integer(cfg$gtwr_parallel_specs[[1]]))
  if (!is.finite(requested) || requested < 1L) requested <- 1L
  physical_cores <- suppressWarnings(parallel::detectCores(logical = FALSE))
  if (!is.finite(physical_cores) || physical_cores < 1L) {
    physical_cores <- suppressWarnings(parallel::detectCores(logical = TRUE))
  }
  if (!is.finite(physical_cores) || physical_cores < 1L) physical_cores <- 1L
  as.integer(max(1L, min(requested, n_jobs, max(1L, physical_cores - 1L))))
}

run_gtwr_spec_cache_job <- function(job, panel_xy) {
  options(gtwr_suppress_spec_log = TRUE)
  payload <- run_actual_gtwr_spec_safe(
    panel_xy = panel_xy,
    outcome = job$outcome,
    focal_var = job$focal_var,
    control_candidates = job$control_candidates,
    selected_controls = job$selected_controls,
    control_set = job$control_set,
    cache_context = value_or(job$cache_context, "main"),
    bw_cache_dir = value_or(job$bw_cache_dir, NULL)
  )
  write_gtwr_spec_cache(job$cache_path, job$signature, payload)
  payload
}

run_gtwr_pending_jobs <- function(jobs, workers, panel_xy) {
  if (length(jobs) == 0L) return(list())
  if (workers > 1L && !identical(.Platform$OS.type, "windows")) {
    return(parallel::mclapply(
      jobs,
      run_gtwr_spec_cache_job,
      panel_xy = panel_xy,
      mc.cores = workers,
      mc.preschedule = FALSE
    ))
  }
  lapply(jobs, run_gtwr_spec_cache_job, panel_xy = panel_xy)
}

build_gtwr_lamda_sensitivity_deferred_row <- function(outcome,
                                                       focal_var,
                                                       control_set,
                                                       lamda,
                                                       ksi,
                                                       n_obs_fit,
                                                       n_units,
                                         sample_min_yq = NA_character_,
                                         sample_max_yq = NA_character_,
                                                       st_bw,
                                                       bw_source,
                                                       bw_obs_n,
                                                       status,
                                                       message,
                                                       elapsed_sec = NA_real_) {
  empty_gtwr_lamda_sensitivity_tbl() |>
    dplyr::add_row(
      method = "GWmodel::gtwr",
      outcome = outcome,
      focal_var = focal_var,
      exposure = focal_var,
      control_set = control_set,
      lamda = suppressWarnings(as.numeric(lamda)),
      baseline_lamda = suppressWarnings(as.numeric(cfg$gtwr_lamda)),
      ksi = suppressWarnings(as.numeric(ksi)),
      is_baseline_lamda = isTRUE(all.equal(
        suppressWarnings(as.numeric(lamda)),
        suppressWarnings(as.numeric(cfg$gtwr_lamda)),
        tolerance = 1e-12
      )),
      target_yq = as.character(sample_max_yq),
      earliest_yq = as.character(sample_min_yq),
      latest_yq = as.character(sample_max_yq),
      window_scope = "quarterly_full_window",
      n_locations = as.integer(n_units),
      n_valid = 0L,
      n_obs_fit = as.integer(n_obs_fit),
      st_bw = suppressWarnings(as.numeric(st_bw)),
      bw_source = bw_source,
      bw_obs_n = suppressWarnings(as.integer(bw_obs_n)),
      status = status,
      message = message,
      elapsed_sec = elapsed_sec
    )
}

summarise_main_beta_comparison <- function(latest_beta, baseline_latest) {
  empty <- list(
    n_compare_with_main = 0L,
    beta_corr_with_main = NA_real_,
    mean_abs_delta_vs_main = NA_real_,
    p50_abs_delta_vs_main = NA_real_,
    max_abs_delta_vs_main = NA_real_,
    sign_flip_share_vs_main = NA_real_
  )
  if (is.null(baseline_latest) || nrow(baseline_latest) == 0L || nrow(latest_beta) == 0L) {
    return(empty)
  }

  cmp <- latest_beta |>
    dplyr::inner_join(
      baseline_latest,
      by = c("adm_cd", "outcome", "focal_var")
    ) |>
    dplyr::mutate(
      estimate = suppressWarnings(as.numeric(.data$estimate)),
      main_estimate = suppressWarnings(as.numeric(.data$main_estimate)),
      abs_delta = abs(.data$estimate - .data$main_estimate)
    ) |>
    dplyr::filter(is.finite(.data$estimate), is.finite(.data$main_estimate))

  n_compare <- nrow(cmp)
  if (n_compare == 0L) return(empty)

  corr <- if (n_compare >= 3L &&
              stats::sd(cmp$estimate, na.rm = TRUE) > .Machine$double.eps &&
              stats::sd(cmp$main_estimate, na.rm = TRUE) > .Machine$double.eps) {
    suppressWarnings(stats::cor(cmp$estimate, cmp$main_estimate, use = "complete.obs"))
  } else {
    NA_real_
  }

  list(
    n_compare_with_main = as.integer(n_compare),
    beta_corr_with_main = corr,
    mean_abs_delta_vs_main = mean(cmp$abs_delta, na.rm = TRUE),
    p50_abs_delta_vs_main = as.numeric(stats::median(cmp$abs_delta, na.rm = TRUE)),
    max_abs_delta_vs_main = max(cmp$abs_delta, na.rm = TRUE),
    sign_flip_share_vs_main = mean(sign(cmp$estimate) != sign(cmp$main_estimate), na.rm = TRUE)
  )
}

build_gtwr_lamda_baseline_rows <- function(summary_tbl) {
  if (nrow(summary_tbl) == 0L) return(empty_gtwr_lamda_sensitivity_tbl())

  summary_tbl |>
    dplyr::transmute(
      method,
      outcome,
      focal_var,
      exposure,
      control_set,
      lamda = suppressWarnings(as.numeric(cfg$gtwr_lamda)),
      baseline_lamda = suppressWarnings(as.numeric(cfg$gtwr_lamda)),
      ksi = suppressWarnings(as.numeric(cfg$gtwr_ksi)),
      is_baseline_lamda = TRUE,
      target_yq = if ("target_yq" %in% names(summary_tbl)) .data$target_yq else NA_character_,
      earliest_yq = if ("earliest_yq" %in% names(summary_tbl)) .data$earliest_yq else NA_character_,
      latest_yq = if ("latest_yq" %in% names(summary_tbl)) .data$latest_yq else NA_character_,
      window_scope,
      n_locations,
      n_valid,
      n_obs_fit,
      st_bw,
      bw_source,
      bw_obs_n,
      global_lm_r2,
      global_lm_r2_adj,
      gtw_aic,
      gtw_aicc,
      gtw_enp,
      gtw_edf,
      mean_beta,
      sd_beta,
      p25_beta,
      p50_beta,
      p75_beta,
      share_positive,
      max_local_cn_gtwr,
      collinearity_warn_n,
      collinearity_warn_share,
      n_compare_with_main = dplyr::if_else(.data$status == "success", as.integer(.data$n_valid), 0L),
      beta_corr_with_main = dplyr::if_else(.data$status == "success", 1, NA_real_),
      mean_abs_delta_vs_main = dplyr::if_else(.data$status == "success", 0, NA_real_),
      p50_abs_delta_vs_main = dplyr::if_else(.data$status == "success", 0, NA_real_),
      max_abs_delta_vs_main = dplyr::if_else(.data$status == "success", 0, NA_real_),
      sign_flip_share_vs_main = dplyr::if_else(.data$status == "success", 0, NA_real_),
      status,
      message = dplyr::if_else(
        .data$status == "success",
        "baseline_main_gtwr_reused_for_lamda_sensitivity",
        .data$message
      ),
      elapsed_sec = 0
    ) |>
    dplyr::select(dplyr::all_of(names(empty_gtwr_lamda_sensitivity_tbl())))
}

build_gtwr_bandwidth_sensitivity_deferred_row <- function(outcome,
                                                          focal_var,
                                                          control_set,
                                                          st_bw,
                                                          baseline_st_bw,
                                                          lamda,
                                                          ksi,
                                                          n_obs_fit,
                                                          n_units,
                                         sample_min_yq = NA_character_,
                                         sample_max_yq = NA_character_,
                                                          bw_source,
                                                          bw_obs_n,
                                                          status,
                                                          message,
                                                          elapsed_sec = NA_real_) {
  empty_gtwr_bandwidth_sensitivity_tbl() |>
    dplyr::add_row(
      method = "GWmodel::gtwr",
      outcome = outcome,
      focal_var = focal_var,
      exposure = focal_var,
      control_set = control_set,
      st_bw = suppressWarnings(as.integer(st_bw)),
      baseline_st_bw = suppressWarnings(as.integer(baseline_st_bw)),
      is_baseline_st_bw = isTRUE(suppressWarnings(as.integer(st_bw)) == suppressWarnings(as.integer(baseline_st_bw))),
      lamda = suppressWarnings(as.numeric(lamda)),
      ksi = suppressWarnings(as.numeric(ksi)),
      target_yq = as.character(sample_max_yq),
      earliest_yq = as.character(sample_min_yq),
      latest_yq = as.character(sample_max_yq),
      window_scope = "quarterly_full_window",
      n_locations = as.integer(n_units),
      n_valid = 0L,
      n_obs_fit = as.integer(n_obs_fit),
      bw_source = bw_source,
      bw_obs_n = suppressWarnings(as.integer(bw_obs_n)),
      status = status,
      message = message,
      elapsed_sec = elapsed_sec
    )
}

build_gtwr_bandwidth_baseline_rows <- function(summary_tbl) {
  if (nrow(summary_tbl) == 0L) return(empty_gtwr_bandwidth_sensitivity_tbl())

  summary_tbl |>
    dplyr::transmute(
      method,
      outcome,
      focal_var,
      exposure,
      control_set,
      st_bw = suppressWarnings(as.integer(round(.data$st_bw))),
      baseline_st_bw = suppressWarnings(as.integer(cfg$gtwr_st_bw)),
      is_baseline_st_bw = TRUE,
      lamda = suppressWarnings(as.numeric(cfg$gtwr_lamda)),
      ksi = suppressWarnings(as.numeric(cfg$gtwr_ksi)),
      target_yq = if ("target_yq" %in% names(summary_tbl)) .data$target_yq else NA_character_,
      earliest_yq = if ("earliest_yq" %in% names(summary_tbl)) .data$earliest_yq else NA_character_,
      latest_yq = if ("latest_yq" %in% names(summary_tbl)) .data$latest_yq else NA_character_,
      window_scope,
      n_locations,
      n_valid,
      n_obs_fit,
      bw_source,
      bw_obs_n,
      global_lm_r2,
      global_lm_r2_adj,
      gtw_aic,
      gtw_aicc,
      gtw_enp,
      gtw_edf,
      mean_beta,
      sd_beta,
      p25_beta,
      p50_beta,
      p75_beta,
      share_positive,
      max_local_cn_gtwr,
      collinearity_warn_n,
      collinearity_warn_share,
      n_compare_with_main = dplyr::if_else(.data$status == "success", as.integer(.data$n_valid), 0L),
      beta_corr_with_main = dplyr::if_else(.data$status == "success", 1, NA_real_),
      mean_abs_delta_vs_main = dplyr::if_else(.data$status == "success", 0, NA_real_),
      p50_abs_delta_vs_main = dplyr::if_else(.data$status == "success", 0, NA_real_),
      max_abs_delta_vs_main = dplyr::if_else(.data$status == "success", 0, NA_real_),
      sign_flip_share_vs_main = dplyr::if_else(.data$status == "success", 0, NA_real_),
      status,
      message = dplyr::if_else(
        .data$status == "success",
        "baseline_main_gtwr_reused_for_bandwidth_sensitivity",
        .data$message
      ),
      elapsed_sec = 0
    ) |>
    dplyr::select(dplyr::all_of(names(empty_gtwr_bandwidth_sensitivity_tbl())))
}

build_gtwr_bandwidth_sensitivity_row_from_payload <- function(payload,
                                                              outcome,
                                                              focal_var,
                                                              control_set,
                                                              st_bw,
                                                              baseline_st_bw,
                                                              baseline_latest) {
  if (!is_valid_gtwr_payload(payload) || nrow(payload$summary) == 0L) {
    return(build_gtwr_bandwidth_sensitivity_deferred_row(
      outcome = outcome,
      focal_var = focal_var,
      control_set = control_set,
      st_bw = st_bw,
      baseline_st_bw = baseline_st_bw,
      lamda = cfg$gtwr_lamda,
      ksi = cfg$gtwr_ksi,
      n_obs_fit = 0L,
      n_units = 0L,
      sample_min_yq = NA_character_,
      sample_max_yq = NA_character_,
      bw_source = "not_estimated",
      bw_obs_n = NA_integer_,
      status = "not_estimated",
      message = "quarterly_gtwr_bandwidth_sensitivity_deferred: invalid GTWR payload"
    ))
  }

  summary <- payload$summary[1, , drop = FALSE]
  latest_beta <- payload$local |>
    dplyr::filter(.data$status == "success", is.finite(.data$estimate)) |>
    dplyr::transmute(
      adm_cd,
      outcome,
      focal_var,
      estimate = suppressWarnings(as.numeric(.data$estimate))
    )
  cmp_stats <- summarise_main_beta_comparison(latest_beta, baseline_latest)
  status <- as.character(summary$status[[1]])
  n_valid <- suppressWarnings(as.integer(summary$n_valid[[1]]))
  if (identical(status, "success") && (!is.finite(n_valid) || n_valid <= 0L)) {
    status <- "not_estimated"
  }

  empty_gtwr_bandwidth_sensitivity_tbl() |>
    dplyr::add_row(
      method = as.character(summary$method[[1]]),
      outcome = outcome,
      focal_var = focal_var,
      exposure = focal_var,
      control_set = control_set,
      st_bw = suppressWarnings(as.integer(round(summary$st_bw[[1]]))),
      baseline_st_bw = suppressWarnings(as.integer(baseline_st_bw)),
      is_baseline_st_bw = isTRUE(suppressWarnings(as.integer(round(summary$st_bw[[1]]))) == suppressWarnings(as.integer(baseline_st_bw))),
      lamda = suppressWarnings(as.numeric(cfg$gtwr_lamda)),
      ksi = suppressWarnings(as.numeric(cfg$gtwr_ksi)),
      target_yq = if ("target_yq" %in% names(summary)) as.character(summary$target_yq[[1]]) else NA_character_,
      earliest_yq = if ("earliest_yq" %in% names(summary)) as.character(summary$earliest_yq[[1]]) else NA_character_,
      latest_yq = if ("latest_yq" %in% names(summary)) as.character(summary$latest_yq[[1]]) else NA_character_,
      window_scope = as.character(summary$window_scope[[1]]),
      n_locations = suppressWarnings(as.integer(summary$n_locations[[1]])),
      n_valid = if (is.finite(n_valid)) n_valid else 0L,
      n_obs_fit = suppressWarnings(as.integer(summary$n_obs_fit[[1]])),
      bw_source = as.character(summary$bw_source[[1]]),
      bw_obs_n = suppressWarnings(as.integer(summary$bw_obs_n[[1]])),
      global_lm_r2 = suppressWarnings(as.numeric(summary$global_lm_r2[[1]])),
      global_lm_r2_adj = suppressWarnings(as.numeric(summary$global_lm_r2_adj[[1]])),
      gtw_aic = suppressWarnings(as.numeric(summary$gtw_aic[[1]])),
      gtw_aicc = suppressWarnings(as.numeric(summary$gtw_aicc[[1]])),
      gtw_enp = suppressWarnings(as.numeric(summary$gtw_enp[[1]])),
      gtw_edf = suppressWarnings(as.numeric(summary$gtw_edf[[1]])),
      mean_beta = suppressWarnings(as.numeric(summary$mean_beta[[1]])),
      sd_beta = suppressWarnings(as.numeric(summary$sd_beta[[1]])),
      p25_beta = suppressWarnings(as.numeric(summary$p25_beta[[1]])),
      p50_beta = suppressWarnings(as.numeric(summary$p50_beta[[1]])),
      p75_beta = suppressWarnings(as.numeric(summary$p75_beta[[1]])),
      share_positive = suppressWarnings(as.numeric(summary$share_positive[[1]])),
      max_local_cn_gtwr = suppressWarnings(as.numeric(summary$max_local_cn_gtwr[[1]])),
      collinearity_warn_n = suppressWarnings(as.integer(summary$collinearity_warn_n[[1]])),
      collinearity_warn_share = suppressWarnings(as.numeric(summary$collinearity_warn_share[[1]])),
      n_compare_with_main = if (identical(status, "success")) cmp_stats$n_compare_with_main else 0L,
      beta_corr_with_main = if (identical(status, "success")) cmp_stats$beta_corr_with_main else NA_real_,
      mean_abs_delta_vs_main = if (identical(status, "success")) cmp_stats$mean_abs_delta_vs_main else NA_real_,
      p50_abs_delta_vs_main = if (identical(status, "success")) cmp_stats$p50_abs_delta_vs_main else NA_real_,
      max_abs_delta_vs_main = if (identical(status, "success")) cmp_stats$max_abs_delta_vs_main else NA_real_,
      sign_flip_share_vs_main = if (identical(status, "success")) cmp_stats$sign_flip_share_vs_main else NA_real_,
      status = status,
      message = dplyr::case_when(
        status == "success" ~ "actual_gtwr_bandwidth_sensitivity_estimated",
        TRUE ~ as.character(summary$message[[1]])
      ),
      elapsed_sec = suppressWarnings(as.numeric(summary$elapsed_sec[[1]]))
    ) |>
    dplyr::select(dplyr::all_of(names(empty_gtwr_bandwidth_sensitivity_tbl())))
}

run_gtwr_lamda_sensitivity_spec <- function(panel_xy,
                                            outcome,
                                            focal_var,
                                            control_candidates,
                                            selected_controls,
                                            control_set,
                                            lamda,
                                            ksi,
                                            baseline_latest) {
  start_time <- Sys.time()
  rhs_vars <- unique(c(focal_var, selected_controls))
  vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "time_id", "x", "y", outcome, rhs_vars))
  d_fit <- panel_xy |>
    dplyr::select(dplyr::all_of(vars)) |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(c(outcome, rhs_vars, "x", "y")), ~ suppressWarnings(as.numeric(.x)))
    ) |>
    tidyr::drop_na() |>
    dplyr::arrange(.data$time_id, .data$adm_cd)

  period_meta <- gtwr_period_meta(d_fit)
  n_units <- dplyr::n_distinct(d_fit$adm_cd)
  n_periods <- period_meta$n_periods
  n_obs_fit <- nrow(d_fit)
  sample_min_yq <- period_meta$earliest_yq
  sample_max_yq <- period_meta$latest_yq
  min_required_obs <- max(400L, length(rhs_vars) + 30L)
  formula_obj <- stats::reformulate(rhs_vars, response = outcome)
  st_bw <- resolve_fixed_gtwr_st_bw(n_obs_fit, rhs_vars)

  if (n_obs_fit < min_required_obs || n_units < cfg$gtwr_control_min_units || n_periods < cfg$spdm_min_periods) {
    return(build_gtwr_lamda_sensitivity_deferred_row(
      outcome = outcome,
      focal_var = focal_var,
      control_set = control_set,
      lamda = lamda,
      ksi = ksi,
      n_obs_fit = n_obs_fit,
      n_units = n_units,
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
      st_bw = st_bw,
      bw_source = "not_estimated",
      bw_obs_n = NA_integer_,
      status = "not_estimated",
      message = "quarterly_gtwr_lamda_sensitivity_deferred: insufficient complete-case sample",
      elapsed_sec = as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    ))
  }

  st_dmat <- build_gtwr_st_dmat(d_fit, lamda = lamda, ksi = ksi)
  cache_context <- paste0(
    "lamda_sensitivity_lamda_", format_gtwr_num_token(lamda),
    "_ksi_", format_gtwr_num_token(ksi)
  )
  bw_selection <- resolve_gtwr_st_bw(
    d_fit = d_fit,
    formula_obj = formula_obj,
    rhs_vars = rhs_vars,
    outcome = outcome,
    focal_var = focal_var,
    selected_controls = selected_controls,
    control_set = control_set,
    st_dmat = st_dmat,
    lamda = lamda,
    ksi = ksi,
    cache_context = cache_context
  )
  st_bw <- bw_selection$st_bw
  bw_source <- bw_selection$bw_source
  bw_obs_n <- suppressWarnings(as.integer(bw_selection$bw_obs_n[[1]]))

  coords <- as.matrix(d_fit[, c("x", "y")])
  spdf <- sp::SpatialPointsDataFrame(
    coords = coords,
    data = as.data.frame(d_fit |> dplyr::select(-x, -y)),
    proj4string = sp::CRS(SRS_string = sprintf("EPSG:%s", cfg$target_crs))
  )

  gtwr_args <- list(
    formula = formula_obj,
    data = spdf,
    obs.tv = d_fit$time_id,
    st.bw = st_bw,
    kernel = cfg$gtwr_kernel,
    adaptive = isTRUE(cfg$gtwr_adaptive),
    lamda = lamda,
    ksi = ksi
  )
  if (!is.null(st_dmat) && is.matrix(st_dmat) && all(dim(st_dmat) == nrow(d_fit))) {
    gtwr_args$st.dMat <- st_dmat
  }
  fit <- tryCatch(
    do.call(GWmodel::gtwr, gtwr_args),
    error = function(e) e
  )

  elapsed_sec <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  if (inherits(fit, "error")) {
    return(build_gtwr_lamda_sensitivity_deferred_row(
      outcome = outcome,
      focal_var = focal_var,
      control_set = control_set,
      lamda = lamda,
      ksi = ksi,
      n_obs_fit = n_obs_fit,
      n_units = n_units,
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
      st_bw = st_bw,
      bw_source = bw_source,
      bw_obs_n = bw_obs_n,
      status = "not_estimated",
      message = sprintf("quarterly_gtwr_lamda_sensitivity_deferred: GTWR failed (%s)", fit$message),
      elapsed_sec = elapsed_sec
    ))
  }

  sdf <- tryCatch(as.data.frame(fit$SDF), error = function(e) NULL)
  if (is.null(sdf) || !focal_var %in% names(sdf) || nrow(sdf) != nrow(d_fit)) {
    return(build_gtwr_lamda_sensitivity_deferred_row(
      outcome = outcome,
      focal_var = focal_var,
      control_set = control_set,
      lamda = lamda,
      ksi = ksi,
      n_obs_fit = n_obs_fit,
      n_units = n_units,
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
      st_bw = st_bw,
      bw_source = bw_source,
      bw_obs_n = bw_obs_n,
      status = "not_estimated",
      message = "quarterly_gtwr_lamda_sensitivity_deferred: focal coefficient extraction failed",
      elapsed_sec = elapsed_sec
    ))
  }

  focal_coef <- suppressWarnings(as.numeric(sdf[[focal_var]]))
  period_id <- period_meta$period_id
  latest_beta <- d_fit |>
    dplyr::transmute(
      adm_cd,
      outcome = .env$outcome,
      focal_var = .env$focal_var,
      period_id = .env$period_id,
      estimate = .env$focal_coef
    ) |>
    dplyr::filter(.data$period_id == .env$period_meta$latest_period_id) |>
    dplyr::select(adm_cd, outcome, focal_var, estimate)

  cn_tbl <- local_cn_for_window(
    d_fit,
    rhs_vars = rhs_vars,
    st_bw = st_bw,
    st_dmat = st_dmat,
    threshold = cfg$gtwr_local_cn_warn_threshold
  )
  cn_vals <- cn_tbl$local_cn_gtwr_latest
  warn_vals <- cn_tbl$collinearity_warn_latest
  warn_n <- sum(warn_vals %in% TRUE, na.rm = TRUE)
  warn_denom <- sum(!is.na(warn_vals))

  beta_stats <- summarise_numeric(latest_beta$estimate)
  if (beta_stats$n_valid == 0L) {
    return(build_gtwr_lamda_sensitivity_deferred_row(
      outcome = outcome,
      focal_var = focal_var,
      control_set = control_set,
      lamda = lamda,
      ksi = ksi,
      n_obs_fit = n_obs_fit,
      n_units = n_units,
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
      st_bw = st_bw,
      bw_source = bw_source,
      bw_obs_n = bw_obs_n,
      status = "not_estimated",
      message = "quarterly_gtwr_lamda_sensitivity_deferred: no valid latest-quarter focal coefficients",
      elapsed_sec = elapsed_sec
    ))
  }

  diag_tbl <- extract_gtwr_diagnostics(fit)
  cmp_stats <- summarise_main_beta_comparison(latest_beta, baseline_latest)

  empty_gtwr_lamda_sensitivity_tbl() |>
    dplyr::add_row(
      method = "GWmodel::gtwr",
      outcome = outcome,
      focal_var = focal_var,
      exposure = focal_var,
      control_set = control_set,
      lamda = suppressWarnings(as.numeric(lamda)),
      baseline_lamda = suppressWarnings(as.numeric(cfg$gtwr_lamda)),
      ksi = suppressWarnings(as.numeric(ksi)),
      is_baseline_lamda = isTRUE(all.equal(
        suppressWarnings(as.numeric(lamda)),
        suppressWarnings(as.numeric(cfg$gtwr_lamda)),
        tolerance = 1e-12
      )),
      target_yq = as.character(sample_max_yq),
      earliest_yq = as.character(sample_min_yq),
      latest_yq = as.character(sample_max_yq),
      window_scope = "quarterly_full_window",
      n_locations = as.integer(n_units),
      n_valid = beta_stats$n_valid,
      n_obs_fit = as.integer(n_obs_fit),
      st_bw = as.numeric(st_bw),
      bw_source = bw_source,
      bw_obs_n = as.integer(bw_obs_n),
      global_lm_r2 = diag_tbl$global_lm_r2[[1]],
      global_lm_r2_adj = diag_tbl$global_lm_r2_adj[[1]],
      gtw_aic = diag_tbl$gtw_aic[[1]],
      gtw_aicc = diag_tbl$gtw_aicc[[1]],
      gtw_enp = diag_tbl$gtw_enp[[1]],
      gtw_edf = diag_tbl$gtw_edf[[1]],
      mean_beta = beta_stats$mean_beta,
      sd_beta = beta_stats$sd_beta,
      p25_beta = beta_stats$p25_beta,
      p50_beta = beta_stats$p50_beta,
      p75_beta = beta_stats$p75_beta,
      share_positive = beta_stats$share_positive,
      max_local_cn_gtwr = if (any(is.finite(cn_vals))) max(cn_vals[is.finite(cn_vals)]) else NA_real_,
      collinearity_warn_n = as.integer(warn_n),
      collinearity_warn_share = if (warn_denom > 0L) warn_n / warn_denom else NA_real_,
      n_compare_with_main = cmp_stats$n_compare_with_main,
      beta_corr_with_main = cmp_stats$beta_corr_with_main,
      mean_abs_delta_vs_main = cmp_stats$mean_abs_delta_vs_main,
      p50_abs_delta_vs_main = cmp_stats$p50_abs_delta_vs_main,
      max_abs_delta_vs_main = cmp_stats$max_abs_delta_vs_main,
      sign_flip_share_vs_main = cmp_stats$sign_flip_share_vs_main,
      status = "success",
      message = "actual_gtwr_lamda_sensitivity_estimated",
      elapsed_sec = elapsed_sec
    )
}

run_gtwr_lamda_sensitivity_spec_safe <- function(panel_xy,
                                                 outcome,
                                                 focal_var,
                                                 control_candidates,
                                                 selected_controls,
                                                 control_set,
                                                 lamda,
                                                 ksi,
                                                 baseline_latest) {
  tryCatch(
    run_gtwr_lamda_sensitivity_spec(
      panel_xy = panel_xy,
      outcome = outcome,
      focal_var = focal_var,
      control_candidates = control_candidates,
      selected_controls = selected_controls,
      control_set = control_set,
      lamda = lamda,
      ksi = ksi,
      baseline_latest = baseline_latest
    ),
    error = function(e) {
      vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "time_id", outcome, focal_var, selected_controls))
      d_fit <- panel_xy |>
        dplyr::select(dplyr::all_of(intersect(vars, names(panel_xy)))) |>
        tidyr::drop_na()
      n_obs_fit <- nrow(d_fit)
      n_units <- dplyr::n_distinct(d_fit$adm_cd)
      period_meta <- gtwr_period_meta(d_fit)
      build_gtwr_lamda_sensitivity_deferred_row(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        lamda = lamda,
        ksi = ksi,
        n_obs_fit = n_obs_fit,
        n_units = n_units,
        sample_min_yq = period_meta$earliest_yq,
        sample_max_yq = period_meta$latest_yq,
        st_bw = resolve_fixed_gtwr_st_bw(n_obs_fit, unique(c(focal_var, selected_controls))),
        bw_source = "not_estimated",
        bw_obs_n = NA_integer_,
        status = "not_estimated",
        message = sprintf("quarterly_gtwr_lamda_sensitivity_deferred: unexpected runtime error (%s)", e$message)
      )
    }
  )
}

run_gtwr_lamda_sensitivity_cache_job <- function(job) {
  options(gtwr_suppress_spec_log = TRUE)
  payload <- run_gtwr_lamda_sensitivity_spec_safe(
    panel_xy = panel_xy,
    outcome = job$outcome,
    focal_var = job$focal_var,
    control_candidates = job$control_candidates,
    selected_controls = job$selected_controls,
    control_set = job$control_set,
    lamda = job$lamda,
    ksi = job$ksi,
    baseline_latest = job$baseline_latest
  )
  write_gtwr_lamda_sensitivity_cache(job$cache_path, job$signature, payload)
  payload
}

run_gtwr_lamda_sensitivity_pending_jobs <- function(jobs, workers) {
  if (length(jobs) == 0L) return(list())
  if (workers > 1L && !identical(.Platform$OS.type, "windows")) {
    return(parallel::mclapply(
      jobs,
      run_gtwr_lamda_sensitivity_cache_job,
      mc.cores = workers,
      mc.preschedule = FALSE
    ))
  }
  lapply(jobs, run_gtwr_lamda_sensitivity_cache_job)
}

run_actual_gtwr_spec <- function(panel_xy,
                                 outcome,
                                 focal_var,
                                 control_candidates,
                                 selected_controls,
                                 control_set,
                                 st_bw_override = NULL,
                                 bw_source_override = NULL,
                                 cache_context = "main",
                                 bw_cache_dir = NULL) {
  start_time <- Sys.time()
  rhs_vars <- unique(c(focal_var, selected_controls))
  vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "time_id", "x", "y", outcome, rhs_vars))
  d_fit <- panel_xy |>
    dplyr::select(dplyr::all_of(vars)) |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(c(outcome, rhs_vars, "x", "y")), ~ suppressWarnings(as.numeric(.x)))
    ) |>
    tidyr::drop_na() |>
    dplyr::arrange(.data$time_id, .data$adm_cd)

  period_meta <- gtwr_period_meta(d_fit)
  n_units <- dplyr::n_distinct(d_fit$adm_cd)
  n_periods <- period_meta$n_periods
  n_obs_fit <- nrow(d_fit)
  sample_min_yq <- period_meta$earliest_yq
  sample_max_yq <- period_meta$latest_yq
  min_required_obs <- max(400L, length(rhs_vars) + 30L)
  formula_obj <- stats::reformulate(rhs_vars, response = outcome)
  formula_text <- paste(deparse(formula_obj), collapse = " ")

  st_bw <- if (is.null(st_bw_override)) {
    resolve_fixed_gtwr_st_bw(n_obs_fit, rhs_vars)
  } else {
    clamp_gtwr_st_bw(st_bw_override, n_obs_fit, rhs_vars)
  }
  bw_source <- "fixed_env_or_default"

  if (n_obs_fit < min_required_obs || n_units < cfg$gtwr_control_min_units || n_periods < cfg$spdm_min_periods) {
    message <- "quarterly_gtwr_deferred: insufficient quarterly complete-case sample for actual GTWR estimation"
    return(list(
      summary = build_gtwr_deferred_main_row(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        fit_scope = "quarterly_deferred_insufficient_sample",
        n_obs_fit = n_obs_fit,
        n_units = n_units,
        n_periods = n_periods,
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
        control_origin = gtwr_control_origin_label(),
        bandwidth_origin = "not_estimated",
        message = message,
        selected_st_bw = st_bw,
        elapsed_sec = as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      ),
      local = empty_gtwr_local_tbl(),
      panel = empty_gtwr_local_beta_panel_tbl(),
      controls = build_gtwr_deferred_controls_row(
        outcome = outcome,
        focal_var = focal_var,
        control_candidates = control_candidates,
        usable_controls = selected_controls,
        control_set = control_set,
        n_obs_fit = n_obs_fit,
        n_units = n_units,
        n_periods = n_periods,
        message = message,
        selected_st_bw = st_bw,
        fit_scope = "quarterly_deferred_insufficient_sample",
        bandwidth_origin = "not_estimated"
      ),
      frozen = build_frozen_spec_row(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        fit_scope = "quarterly_deferred_insufficient_sample",
        formula_text = formula_text,
        selected_controls = selected_controls,
        st_bw = st_bw,
        bw_source = "not_estimated",
        status = "not_estimated",
        message = message
      )
    ))
  }

  st_dmat <- build_gtwr_st_dmat(d_fit)
  if (is.null(st_bw_override)) {
    bw_selection <- resolve_gtwr_st_bw(
      d_fit = d_fit,
      formula_obj = formula_obj,
      rhs_vars = rhs_vars,
      outcome = outcome,
      focal_var = focal_var,
      selected_controls = selected_controls,
      control_set = control_set,
      st_dmat = st_dmat,
      cache_context = cache_context,
      bw_cache_dir = bw_cache_dir
    )
    st_bw <- bw_selection$st_bw
    bw_source <- bw_selection$bw_source
    bw_obs_n <- suppressWarnings(as.integer(bw_selection$bw_obs_n[[1]]))
  } else {
    bw_source <- if (is.null(bw_source_override)) "fixed_bandwidth_sensitivity" else as.character(bw_source_override[[1]])
    bw_obs_n <- NA_integer_
  }

  if (!isTRUE(getOption("gtwr_suppress_spec_log", FALSE))) {
    append_log(
      cfg$logs$model_run,
      sprintf(
        "- GTWR actual fitting started: outcome=%s, focal=%s, controls=%s, n=%d, units=%d, periods=%d, st_bw=%s, bw_source=%s",
        outcome,
        focal_var,
        collapse_chr(selected_controls),
        n_obs_fit,
        n_units,
        n_periods,
        as.character(st_bw),
        bw_source
      )
    )
  }

  coords <- as.matrix(d_fit[, c("x", "y")])
  spdf <- sp::SpatialPointsDataFrame(
    coords = coords,
    data = as.data.frame(d_fit |> dplyr::select(-x, -y)),
    proj4string = sp::CRS(SRS_string = sprintf("EPSG:%s", cfg$target_crs))
  )

  gtwr_args <- list(
    formula = formula_obj,
    data = spdf,
    obs.tv = d_fit$time_id,
    st.bw = st_bw,
    kernel = cfg$gtwr_kernel,
    adaptive = isTRUE(cfg$gtwr_adaptive),
    lamda = cfg$gtwr_lamda,
    ksi = cfg$gtwr_ksi
  )
  if (!is.null(st_dmat) && is.matrix(st_dmat) && all(dim(st_dmat) == nrow(d_fit))) {
    gtwr_args$st.dMat <- st_dmat
  }
  fit <- tryCatch(
    do.call(GWmodel::gtwr, gtwr_args),
    error = function(e) e
  )

  elapsed_sec <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  if (inherits(fit, "error")) {
    message <- sprintf("quarterly_gtwr_deferred: GWmodel::gtwr failed for optional sidecar (%s)", fit$message)
    return(list(
      summary = build_gtwr_deferred_main_row(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        fit_scope = "quarterly_deferred_gtwr_error",
        n_obs_fit = n_obs_fit,
        n_units = n_units,
        n_periods = n_periods,
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
        control_origin = gtwr_control_origin_label(),
        bandwidth_origin = bw_source,
        message = message,
        selected_st_bw = st_bw,
        elapsed_sec = elapsed_sec
      ),
      local = empty_gtwr_local_tbl(),
      panel = empty_gtwr_local_beta_panel_tbl(),
      controls = build_gtwr_deferred_controls_row(
        outcome = outcome,
        focal_var = focal_var,
        control_candidates = control_candidates,
        usable_controls = selected_controls,
        control_set = control_set,
        n_obs_fit = n_obs_fit,
        n_units = n_units,
        n_periods = n_periods,
        message = message,
        selected_st_bw = st_bw,
        fit_scope = "quarterly_deferred_gtwr_error",
        bandwidth_origin = bw_source
      ),
      frozen = build_frozen_spec_row(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        fit_scope = "quarterly_deferred_gtwr_error",
        formula_text = formula_text,
        selected_controls = selected_controls,
        st_bw = st_bw,
        bw_source = bw_source,
        status = "not_estimated",
        message = message
      )
    ))
  }

  sdf <- tryCatch(as.data.frame(fit$SDF), error = function(e) NULL)
  if (is.null(sdf) || !focal_var %in% names(sdf) || nrow(sdf) != nrow(d_fit)) {
    message <- "quarterly_gtwr_deferred: GTWR fit completed but focal coefficient extraction failed"
    return(list(
      summary = build_gtwr_deferred_main_row(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        fit_scope = "quarterly_deferred_gtwr_extract_error",
        n_obs_fit = n_obs_fit,
        n_units = n_units,
        n_periods = n_periods,
      sample_min_yq = sample_min_yq,
      sample_max_yq = sample_max_yq,
        control_origin = gtwr_control_origin_label(),
        bandwidth_origin = bw_source,
        message = message,
        selected_st_bw = st_bw,
        elapsed_sec = elapsed_sec
      ),
      local = empty_gtwr_local_tbl(),
      panel = empty_gtwr_local_beta_panel_tbl(),
      controls = build_gtwr_deferred_controls_row(
        outcome = outcome,
        focal_var = focal_var,
        control_candidates = control_candidates,
        usable_controls = selected_controls,
        control_set = control_set,
        n_obs_fit = n_obs_fit,
        n_units = n_units,
        n_periods = n_periods,
        message = message,
        selected_st_bw = st_bw,
        fit_scope = "quarterly_deferred_gtwr_extract_error",
        bandwidth_origin = bw_source
      ),
      frozen = build_frozen_spec_row(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        fit_scope = "quarterly_deferred_gtwr_extract_error",
        formula_text = formula_text,
        selected_controls = selected_controls,
        st_bw = st_bw,
        bw_source = bw_source,
        status = "not_estimated",
        message = message
      )
    ))
  }

  focal_coef <- suppressWarnings(as.numeric(sdf[[focal_var]]))
  period_id <- period_meta$period_id
  beta_panel <- d_fit |>
    dplyr::transmute(
      adm_cd,
      year,
      quarter,
      yq,
      quarter_index,
      time_id,
      outcome = .env$outcome,
      focal_var = .env$focal_var,
      estimate = .env$focal_coef,
      estimate_type = "local_beta",
      window_scope = "quarterly_full_window",
      status = "success",
      message = "actual_gtwr_estimated",
      n_obs = as.integer(n_obs_fit),
      n_eff = as.integer(st_bw),
      target_yq = as.character(sample_max_yq),
      method = "GWmodel::gtwr",
      control_set = control_set,
      fit_scope = "quarterly_actual",
      recent_period_n = as.integer(n_periods),
      location_frac = 1,
      location_n = as.integer(n_units),
      bw_obs_n = as.integer(bw_obs_n),
      bw_source = bw_source
    )

  cn_tbl <- local_cn_for_window(
    d_fit,
    rhs_vars = rhs_vars,
    st_bw = st_bw,
    st_dmat = st_dmat,
    threshold = cfg$gtwr_local_cn_warn_threshold
  )

  local_tbl <- beta_panel |>
    dplyr::group_by(adm_cd, outcome, focal_var) |>
    dplyr::summarise(
      earliest_estimate = pick_period_value(estimate, time_id, .env$period_meta$earliest_period_id),
      latest_estimate = pick_period_value(estimate, time_id, .env$period_meta$latest_period_id),
      .groups = "drop"
	    ) |>
	    dplyr::mutate(
	      estimate = .data$latest_estimate,
	      estimate_type = "latest",
	      earliest_yq = as.character(sample_min_yq),
	      latest_yq = as.character(sample_max_yq),
	      window_scope = "quarterly_full_window",
	      status = dplyr::case_when(
	        is.finite(.data$latest_estimate) ~ "success",
	        TRUE ~ "missing_latest_estimate"
	      ),
	      message = dplyr::case_when(
	        .data$status == "success" ~ "actual_gtwr_estimated",
	        TRUE ~ "actual_gtwr_estimated_but_latest_quarter_coefficient_missing"
	      ),
	      n_obs = as.integer(n_obs_fit),
      n_eff = as.integer(st_bw),
      target_yq = as.character(sample_max_yq),
      method = "GWmodel::gtwr",
      control_set = control_set,
      fit_scope = "quarterly_actual",
      recent_period_n = as.integer(n_periods),
      location_frac = 1,
      location_n = as.integer(n_units),
      bw_obs_n = as.integer(bw_obs_n),
      bw_source = bw_source
    ) |>
    dplyr::left_join(cn_tbl, by = "adm_cd") |>
    dplyr::mutate(
	      collinearity_warn_earliest = dplyr::coalesce(.data$collinearity_warn_earliest, FALSE),
	      collinearity_warn_latest = dplyr::coalesce(.data$collinearity_warn_latest, FALSE),
	      collinearity_warn_flag = .data$status == "success" & .data$collinearity_warn_latest,
	      collinearity_warn_stage = dplyr::case_when(
	        .data$status == "success" & .data$collinearity_warn_latest ~ "latest",
	        TRUE ~ NA_character_
	      ),
	      collinearity_warn_metric = "gtwr_spatiotemporal_local_cn_gwmodel_style",
	      collinearity_warn_threshold = cfg$gtwr_local_cn_warn_threshold,
	      collinearity_diag_status = dplyr::case_when(
	        is.null(.env$st_dmat) ~ "not_computed_st_dmat_error",
	        TRUE ~ "computed_gtwr_spatiotemporal"
	      ),
	      collinearity_diag_message = dplyr::case_when(
	        is.null(.env$st_dmat) ~ "GTWR local CN not computed because spatiotemporal distance matrix construction failed",
	        TRUE ~ "local_cn_gtwr mirrors GWmodel::gwr.collin.diagno local_CN using GTWR spatiotemporal weights"
	      )
	    ) |>
    dplyr::select(dplyr::all_of(names(empty_gtwr_local_tbl())))

	  success_local <- local_tbl |>
	    dplyr::filter(.data$status == "success", is.finite(.data$estimate))
	  beta_stats <- summarise_numeric(success_local$estimate)
	  diag_tbl <- extract_gtwr_diagnostics(fit)
	  warn_vals <- local_tbl$collinearity_warn_flag
	  cn_vals <- local_tbl$local_cn_gtwr_latest
	  warn_n <- sum(warn_vals %in% TRUE, na.rm = TRUE)
	  warn_denom <- sum(local_tbl$status == "success" & !is.na(warn_vals))
	  latest_missing_n <- sum(!is.finite(local_tbl$latest_estimate))
	  latest_coverage_share <- if (nrow(local_tbl) > 0L) {
	    mean(is.finite(local_tbl$latest_estimate))
	  } else {
	    NA_real_
	  }

  summary_tbl <- empty_gtwr_main_tbl() |>
    dplyr::add_row(
      method = "GWmodel::gtwr",
      outcome = outcome,
      focal_var = focal_var,
      exposure = focal_var,
      target_yq = as.character(sample_max_yq),
      estimate_type = "latest",
      earliest_yq = as.character(sample_min_yq),
      latest_yq = as.character(sample_max_yq),
      window_scope = "quarterly_full_window",
      n_locations = as.integer(n_units),
      n_valid = beta_stats$n_valid,
      mean_beta = beta_stats$mean_beta,
      sd_beta = beta_stats$sd_beta,
      p25_beta = beta_stats$p25_beta,
      p50_beta = beta_stats$p50_beta,
      p75_beta = beta_stats$p75_beta,
      share_positive = beta_stats$share_positive,
      st_bw = as.numeric(st_bw),
	      global_lm_r2 = diag_tbl$global_lm_r2[[1]],
	      global_lm_r2_adj = diag_tbl$global_lm_r2_adj[[1]],
	      gtw_aic = diag_tbl$gtw_aic[[1]],
	      gtw_aicc = diag_tbl$gtw_aicc[[1]],
	      gtw_enp = diag_tbl$gtw_enp[[1]],
	      gtw_edf = diag_tbl$gtw_edf[[1]],
	      collinearity_warn_n = as.integer(warn_n),
	      collinearity_warn_share = if (warn_denom > 0L) warn_n / warn_denom else NA_real_,
	      latest_missing_n = as.integer(latest_missing_n),
	      latest_coverage_share = latest_coverage_share,
	      max_local_cn_gtwr = if (any(is.finite(cn_vals))) max(cn_vals[is.finite(cn_vals)]) else NA_real_,
      control_set = control_set,
      fit_scope = "quarterly_actual",
      recent_period_n = as.integer(n_periods),
      location_frac = 1,
      location_n = as.integer(n_units),
      n_obs_fit = as.integer(n_obs_fit),
      bw_obs_n = as.integer(bw_obs_n),
      bw_source = bw_source,
      control_origin = gtwr_control_origin_label(),
      bandwidth_origin = bw_source,
      frozen_spec_status = "estimated",
      frozen_spec_reason = "actual_gtwr_estimated_each_active_execution",
      elapsed_sec = elapsed_sec,
      status = "success",
      message = "actual_gtwr_estimated"
    )

  unselected_controls_text <- collapse_chr(base::setdiff(control_candidates, selected_controls))

  controls_tbl <- empty_gtwr_controls_used_tbl() |>
    dplyr::add_row(
      outcome = outcome,
      focal_var = focal_var,
      control_set = control_set,
      optional_candidates = collapse_chr(control_candidates),
      selected_controls = collapse_chr(selected_controls),
      unselected_controls = unselected_controls_text,
      base_n_obs = as.integer(n_obs_fit),
      base_n_units = as.integer(n_units),
      selected_n_obs = as.integer(n_obs_fit),
      selected_n_units = as.integer(n_units),
      retention_ratio = 1,
      retention_floor = cfg$gtwr_control_min_sample_retention,
      selection_status = "success",
      selection_strategy = gtwr_control_selection_label(),
      fit_scope = "quarterly_actual",
      recent_period_n = as.integer(n_periods),
      location_frac = 1,
      location_n = as.integer(n_units),
      bw_obs_n = as.integer(bw_obs_n),
      bw_source = bw_source,
      control_origin = gtwr_control_origin_label(),
      bandwidth_origin = bw_source,
      frozen_spec_status = "estimated",
      frozen_spec_reason = "actual_gtwr_estimated_each_active_execution",
      status = "success",
      message = "actual_gtwr_estimated"
    )

  frozen_tbl <- build_frozen_spec_row(
    outcome = outcome,
    focal_var = focal_var,
    control_set = control_set,
    fit_scope = "quarterly_actual",
    formula_text = formula_text,
    selected_controls = selected_controls,
    st_bw = st_bw,
    bw_source = bw_source,
    status = "success",
    message = "actual_gtwr_estimated"
  )

  list(
    summary = summary_tbl,
    local = local_tbl,
    panel = beta_panel,
    controls = controls_tbl,
    frozen = frozen_tbl
  )
}

run_actual_gtwr_spec_safe <- function(panel_xy,
                                      outcome,
                                      focal_var,
                                      control_candidates,
                                      selected_controls,
                                      control_set,
                                      st_bw_override = NULL,
                                      bw_source_override = NULL,
                                      cache_context = "main",
                                      bw_cache_dir = NULL) {
  tryCatch(
    run_actual_gtwr_spec(
      panel_xy = panel_xy,
      outcome = outcome,
      focal_var = focal_var,
      control_candidates = control_candidates,
      selected_controls = selected_controls,
      control_set = control_set,
      st_bw_override = st_bw_override,
      bw_source_override = bw_source_override,
      cache_context = cache_context,
      bw_cache_dir = bw_cache_dir
    ),
    error = function(e) {
      vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "time_id", outcome, focal_var, selected_controls))
      d_fit <- panel_xy |>
        dplyr::select(dplyr::all_of(intersect(vars, names(panel_xy)))) |>
        tidyr::drop_na()
      n_units <- dplyr::n_distinct(d_fit$adm_cd)
      period_meta <- gtwr_period_meta(d_fit)
      n_periods <- period_meta$n_periods
      n_obs_fit <- nrow(d_fit)
      st_bw <- if (is.null(st_bw_override)) {
        resolve_fixed_gtwr_st_bw(n_obs_fit, unique(c(focal_var, selected_controls)))
      } else {
        clamp_gtwr_st_bw(st_bw_override, n_obs_fit, unique(c(focal_var, selected_controls)))
      }
      formula_text <- paste(deparse(stats::reformulate(unique(c(focal_var, selected_controls)), response = outcome)), collapse = " ")
      message <- sprintf("quarterly_gtwr_deferred: unexpected optional GTWR export/runtime error (%s)", e$message)
      bandwidth_origin <- if (is.null(bw_source_override)) "fixed_env_or_default" else as.character(bw_source_override[[1]])

      list(
        summary = build_gtwr_deferred_main_row(
          outcome = outcome,
          focal_var = focal_var,
          control_set = control_set,
          fit_scope = "quarterly_deferred_unexpected_error",
          n_obs_fit = n_obs_fit,
          n_units = n_units,
          n_periods = n_periods,
        sample_min_yq = period_meta$earliest_yq,
        sample_max_yq = period_meta$latest_yq,
          control_origin = gtwr_control_origin_label(),
          bandwidth_origin = bandwidth_origin,
          message = message,
          selected_st_bw = st_bw
        ),
        local = empty_gtwr_local_tbl(),
        panel = empty_gtwr_local_beta_panel_tbl(),
        controls = build_gtwr_deferred_controls_row(
          outcome = outcome,
          focal_var = focal_var,
          control_candidates = control_candidates,
          usable_controls = selected_controls,
          control_set = control_set,
          n_obs_fit = n_obs_fit,
          n_units = n_units,
          n_periods = n_periods,
          message = message,
          selected_st_bw = st_bw,
          fit_scope = "quarterly_deferred_unexpected_error",
          bandwidth_origin = bandwidth_origin
        ),
        frozen = build_frozen_spec_row(
          outcome = outcome,
          focal_var = focal_var,
          control_set = control_set,
          fit_scope = "quarterly_deferred_unexpected_error",
          formula_text = formula_text,
          selected_controls = selected_controls,
          st_bw = st_bw,
          bw_source = bandwidth_origin,
          status = "not_estimated",
          message = message
        )
      )
    }
  )
}

run_gtwr_bandwidth_sensitivity_spec_safe <- function(panel_xy,
                                                     outcome,
                                                     focal_var,
                                                     control_candidates,
                                                     selected_controls,
                                                     control_set,
                                                     st_bw,
                                                     baseline_st_bw,
                                                     baseline_latest) {
  tryCatch(
    {
      rhs_vars <- unique(c(focal_var, selected_controls))
      vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "time_id", "x", "y", outcome, rhs_vars))
      d_fit <- panel_xy |>
        dplyr::select(dplyr::all_of(vars)) |>
        dplyr::mutate(
          dplyr::across(dplyr::all_of(c(outcome, rhs_vars, "x", "y")), ~ suppressWarnings(as.numeric(.x)))
        ) |>
        tidyr::drop_na()
      n_obs_fit <- nrow(d_fit)
      st_bw_resolved <- clamp_gtwr_st_bw(st_bw, n_obs_fit, rhs_vars)
      payload <- run_actual_gtwr_spec_safe(
        panel_xy = panel_xy,
        outcome = outcome,
        focal_var = focal_var,
        control_candidates = control_candidates,
        selected_controls = selected_controls,
        control_set = control_set,
        st_bw_override = st_bw_resolved,
        bw_source_override = sprintf("fixed_bandwidth_sensitivity_%s", st_bw_resolved)
      )
      build_gtwr_bandwidth_sensitivity_row_from_payload(
        payload = payload,
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        st_bw = st_bw_resolved,
        baseline_st_bw = baseline_st_bw,
        baseline_latest = baseline_latest
      )
    },
    error = function(e) {
      vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "time_id", outcome, focal_var, selected_controls))
      d_fit <- panel_xy |>
        dplyr::select(dplyr::all_of(intersect(vars, names(panel_xy)))) |>
        tidyr::drop_na()
      n_obs_fit <- nrow(d_fit)
      n_units <- dplyr::n_distinct(d_fit$adm_cd)
      period_meta <- gtwr_period_meta(d_fit)
      st_bw_resolved <- clamp_gtwr_st_bw(st_bw, n_obs_fit, unique(c(focal_var, selected_controls)))
      build_gtwr_bandwidth_sensitivity_deferred_row(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        st_bw = st_bw_resolved,
        baseline_st_bw = baseline_st_bw,
        lamda = cfg$gtwr_lamda,
        ksi = cfg$gtwr_ksi,
        n_obs_fit = n_obs_fit,
        n_units = n_units,
        sample_min_yq = period_meta$earliest_yq,
        sample_max_yq = period_meta$latest_yq,
        bw_source = "not_estimated",
        bw_obs_n = NA_integer_,
        status = "not_estimated",
        message = sprintf("quarterly_gtwr_bandwidth_sensitivity_deferred: unexpected runtime error (%s)", e$message)
      )
    }
  )
}

run_gtwr_bandwidth_sensitivity_cache_job <- function(job) {
  options(gtwr_suppress_spec_log = TRUE)
  payload <- run_gtwr_bandwidth_sensitivity_spec_safe(
    panel_xy = panel_xy,
    outcome = job$outcome,
    focal_var = job$focal_var,
    control_candidates = job$control_candidates,
    selected_controls = job$selected_controls,
    control_set = job$control_set,
    st_bw = job$st_bw,
    baseline_st_bw = job$baseline_st_bw,
    baseline_latest = job$baseline_latest
  )
  write_gtwr_bandwidth_sensitivity_cache(job$cache_path, job$signature, payload)
  payload
}

run_gtwr_bandwidth_sensitivity_pending_jobs <- function(jobs, workers) {
  if (length(jobs) == 0L) return(list())
  if (workers > 1L && !identical(.Platform$OS.type, "windows")) {
    return(parallel::mclapply(
      jobs,
      run_gtwr_bandwidth_sensitivity_cache_job,
      mc.cores = workers,
      mc.preschedule = FALSE
    ))
  }
  lapply(jobs, run_gtwr_bandwidth_sensitivity_cache_job)
}
