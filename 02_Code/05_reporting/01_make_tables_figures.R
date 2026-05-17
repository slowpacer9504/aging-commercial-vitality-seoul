#==============================================================================
# Script    : 01_make_tables_figures.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Produce annual descriptive tables and time-series figures after
#             the main annual modeling steps have finished.
# Author    : Codex
# Created   : 2026-02-28
# Type      : reporting
# Inputs    : panel_main.parquet
# Outputs   : descriptive_statistics.csv, data_coverage.csv,
#             mean_ln_sales_trend.png
# DependsOn : 02_Code/03_models/01_run_twfe_main.R,
#             02_Code/03_models/02_run_spdm_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
load_project_packages()

if (!file.exists(cfg$paths$panel_main)) stop("[ERROR] panel_main missing", call. = FALSE)
panel <- arrow::read_parquet(cfg$paths$panel_main) |> tibble::as_tibble()

unlink_if_exists <- function(path) {
  if (is.character(path) && length(path) == 1L && file.exists(path)) {
    unlink(path)
  }
  invisible(NULL)
}

clear_stale_appendix_outputs <- function() {
  unlink_if_exists(cfg$paths$spatial_family_main_table)
  unlink_if_exists(cfg$paths$gwr_delta_summary_table)
  unlink_if_exists(cfg$paths$gwr_delta_rankings_table)

  gtwr_control_set <- cfg$gtwr_control_set_token(cfg$gtwr_control_set)
  unlink_if_exists(cfg$get_gtwr_latest_summary_table_path(gtwr_control_set))
  unlink_if_exists(cfg$get_gtwr_latest_rankings_table_path(gtwr_control_set))
  unlink_if_exists(cfg$get_gtwr_delta_summary_table_path(gtwr_control_set))
  unlink_if_exists(cfg$get_gtwr_delta_rankings_table_path(gtwr_control_set))
  unlink_if_exists(cfg$get_gtwr_age_band_delta_summary_table_path(gtwr_control_set))
  unlink_if_exists(cfg$get_gtwr_age_band_delta_rankings_table_path(gtwr_control_set))
  unlink_if_exists(cfg$get_gtwr_sector_share_delta_summary_table_path(gtwr_control_set))
  unlink_if_exists(cfg$get_gtwr_sector_share_delta_rankings_table_path(gtwr_control_set))
  invisible(NULL)
}

ensure_cols <- function(df, cols, fill = NA) {
  for (col in setdiff(cols, names(df))) {
    df[[col]] <- fill
  }
  df
}

safe_numeric_quantile <- function(x, prob) {
  if (length(x) == 0L) return(NA_real_)
  as.numeric(stats::quantile(x, probs = prob, na.rm = TRUE, names = FALSE, type = 7))
}

summarise_descriptive_variable <- function(data, variable, label, role, order) {
  x <- suppressWarnings(as.numeric(data[[variable]]))
  finite <- is.finite(x)
  x_obs <- x[finite]

  year_obs <- integer()
  if ("year" %in% names(data)) {
    year_obs <- suppressWarnings(as.integer(data$year[finite]))
    year_obs <- year_obs[is.finite(year_obs)]
  }

  adm_obs <- character()
  if ("adm_cd" %in% names(data)) {
    adm_obs <- as.character(data$adm_cd[finite])
    adm_obs <- adm_obs[!is.na(adm_obs) & nzchar(adm_obs)]
  }

  total_n <- length(x)
  observed_n <- length(x_obs)
  missing_n <- total_n - observed_n

  tibble::tibble(
    variable = variable,
    label = label,
    role = role,
    display_order = order,
    n = observed_n,
    missing_n = missing_n,
    missing_share = if (total_n > 0L) missing_n / total_n else NA_real_,
    mean = if (observed_n > 0L) mean(x_obs) else NA_real_,
    sd = if (observed_n > 1L) stats::sd(x_obs) else NA_real_,
    min = if (observed_n > 0L) min(x_obs) else NA_real_,
    p25 = safe_numeric_quantile(x_obs, 0.25),
    median = safe_numeric_quantile(x_obs, 0.50),
    p75 = safe_numeric_quantile(x_obs, 0.75),
    max = if (observed_n > 0L) max(x_obs) else NA_real_,
    sample_min_year = if (length(year_obs) > 0L) min(year_obs) else NA_integer_,
    sample_max_year = if (length(year_obs) > 0L) max(year_obs) else NA_integer_,
    n_years = dplyr::n_distinct(year_obs),
    n_adm = dplyr::n_distinct(adm_obs)
  )
}

safe_cor_test_p <- function(x, y, method = "pearson") {
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 3L) return(NA_real_)
  x_ok <- x[ok]
  y_ok <- y[ok]
  if (stats::sd(x_ok) <= .Machine$double.eps || stats::sd(y_ok) <= .Machine$double.eps) {
    return(NA_real_)
  }
  out <- tryCatch(
    stats::cor.test(x_ok, y_ok, method = method)$p.value,
    error = function(e) NA_real_
  )
  as.numeric(out)
}

build_main_variable_correlation_outputs <- function(data,
                                                    registry,
                                                    method = "pearson",
                                                    high_corr_threshold = 0.70) {
  registry <- registry |>
    dplyr::filter(.data$variable %in% names(data)) |>
    dplyr::distinct(.data$variable, .keep_all = TRUE) |>
    dplyr::mutate(display_order = dplyr::row_number())

  if (nrow(registry) == 0L) {
    empty_matrix <- tibble::tibble(variable = character(), label = character(), role = character(), model_scope = character())
    empty_pairs <- tibble::tibble(
      variable_x = character(), label_x = character(), role_x = character(), model_scope_x = character(),
      variable_y = character(), label_y = character(), role_y = character(), model_scope_y = character(),
      n_pair = integer(), pearson_r = numeric(), p_value = numeric(), abs_pearson_r = numeric(),
      high_corr_flag = logical()
    )
    return(list(matrix = empty_matrix, n_matrix = empty_matrix, pairs = empty_pairs))
  }

  num_tbl <- data |>
    dplyr::select(dplyr::all_of(registry$variable)) |>
    dplyr::mutate(dplyr::across(dplyr::everything(), ~ suppressWarnings(as.numeric(.x))))

  cor_mat <- stats::cor(num_tbl, use = "pairwise.complete.obs", method = method)
  cor_mat[!is.finite(cor_mat)] <- NA_real_

  n_mat <- matrix(
    NA_integer_,
    nrow = ncol(num_tbl),
    ncol = ncol(num_tbl),
    dimnames = list(names(num_tbl), names(num_tbl))
  )
  p_mat <- matrix(
    NA_real_,
    nrow = ncol(num_tbl),
    ncol = ncol(num_tbl),
    dimnames = list(names(num_tbl), names(num_tbl))
  )

  for (i in seq_along(registry$variable)) {
    for (j in seq_along(registry$variable)) {
      x <- suppressWarnings(as.numeric(num_tbl[[i]]))
      y <- suppressWarnings(as.numeric(num_tbl[[j]]))
      ok <- is.finite(x) & is.finite(y)
      n_mat[i, j] <- sum(ok)
      if (i != j) {
        p_mat[i, j] <- safe_cor_test_p(x, y, method = method)
      }
    }
  }

  matrix_tbl <- registry |>
    dplyr::select(variable, label, role, model_scope) |>
    dplyr::bind_cols(tibble::as_tibble(cor_mat, .name_repair = "minimal"))

  n_matrix_tbl <- registry |>
    dplyr::select(variable, label, role, model_scope) |>
    dplyr::bind_cols(tibble::as_tibble(n_mat, .name_repair = "minimal"))

  pair_idx <- utils::combn(seq_along(registry$variable), 2L)
  pairs_tbl <- purrr::map_dfr(seq_len(ncol(pair_idx)), function(k) {
    i <- pair_idx[1L, k]
    j <- pair_idx[2L, k]
    tibble::tibble(
      variable_x = registry$variable[[i]],
      label_x = registry$label[[i]],
      role_x = registry$role[[i]],
      model_scope_x = registry$model_scope[[i]],
      variable_y = registry$variable[[j]],
      label_y = registry$label[[j]],
      role_y = registry$role[[j]],
      model_scope_y = registry$model_scope[[j]],
      n_pair = as.integer(n_mat[i, j]),
      pearson_r = as.numeric(cor_mat[i, j]),
      p_value = as.numeric(p_mat[i, j]),
      abs_pearson_r = abs(as.numeric(cor_mat[i, j]))
    )
  }) |>
    dplyr::mutate(high_corr_flag = is.finite(.data$abs_pearson_r) & .data$abs_pearson_r >= high_corr_threshold) |>
    dplyr::arrange(dplyr::desc(.data$abs_pearson_r), .data$variable_x, .data$variable_y)

  list(matrix = matrix_tbl, n_matrix = n_matrix_tbl, pairs = pairs_tbl)
}

adm_name_lookup <- local({
  cache <- NULL
  function() {
    if (!is.null(cache)) return(cache)
    boundary <- load_commercial_boundary(cfg$dir_boundary) |>
      sf::st_drop_geometry()
    name_col <- intersect(c("adstrd_nm", "adm_nm"), names(boundary))
    if (length(name_col) == 0L) {
      cache <<- tibble::tibble(adm_cd = character(), adstrd_nm = character())
    } else {
      cache <<- boundary |>
        dplyr::transmute(
          adm_cd = as.character(adm_cd),
          adstrd_nm = as.character(.data[[name_col[[1]]]])
        ) |>
        dplyr::distinct(adm_cd, .keep_all = TRUE)
    }
    cache
  }
})

build_gtwr_rankings <- function(local_tbl, group_cols = character()) {
  local_tbl <- ensure_cols(
    local_tbl,
    c(group_cols, "adm_cd", "outcome", "focal_var", "estimate", "estimate_type", "earliest_year", "latest_year", "window_scope", "control_set", "status", "message", "collinearity_warn_flag", "collinearity_warn_stage")
  )
  local_tbl$adm_cd <- as.character(local_tbl$adm_cd)
  local_tbl <- local_tbl |>
    dplyr::left_join(adm_name_lookup(), by = "adm_cd")

  success_tbl <- local_tbl |>
    dplyr::filter(status == "success", is.finite(estimate))

  out_cols <- c(group_cols, "outcome", "focal_var", "rank_group", "rank_order", "adm_cd", "adstrd_nm", "estimate", "estimate_type", "earliest_year", "latest_year", "window_scope", "control_set", "collinearity_warn_flag", "collinearity_warn_stage")
  local_tbl <- ensure_cols(local_tbl, out_cols)
  if (nrow(success_tbl) == 0L) {
    return(tibble::as_tibble(local_tbl[0, out_cols, drop = FALSE]))
  }

  rank_keys <- c(group_cols, "outcome", "focal_var")
  neg_tbl <- success_tbl |>
    dplyr::group_by(dplyr::across(dplyr::all_of(rank_keys))) |>
    dplyr::slice_min(order_by = estimate, n = 5L, with_ties = FALSE) |>
    dplyr::arrange(dplyr::across(dplyr::all_of(rank_keys)), estimate) |>
    dplyr::mutate(rank_group = "most_negative") |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(rank_keys, "rank_group")))) |>
    dplyr::mutate(rank_order = dplyr::row_number()) |>
    dplyr::ungroup()

  pos_tbl <- success_tbl |>
    dplyr::group_by(dplyr::across(dplyr::all_of(rank_keys))) |>
    dplyr::slice_max(order_by = estimate, n = 5L, with_ties = FALSE) |>
    dplyr::arrange(dplyr::across(dplyr::all_of(rank_keys)), dplyr::desc(estimate)) |>
    dplyr::mutate(rank_group = "most_positive") |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(rank_keys, "rank_group")))) |>
    dplyr::mutate(rank_order = dplyr::row_number()) |>
    dplyr::ungroup()

  dplyr::bind_rows(neg_tbl, pos_tbl) |>
    dplyr::select(dplyr::all_of(out_cols))
}

build_gtwr_latest_local <- function(local_tbl) {
  ensure_cols(
    local_tbl,
    c("adm_cd", "outcome", "focal_var", "estimate", "estimate_type", "latest_estimate", "earliest_year", "latest_year", "window_scope", "control_set", "status", "message", "collinearity_warn_latest", "collinearity_warn_flag", "collinearity_warn_stage")
  ) |>
    dplyr::mutate(
      estimate = dplyr::coalesce(
        suppressWarnings(as.numeric(.data$latest_estimate)),
        dplyr::if_else(.data$estimate_type == "latest", suppressWarnings(as.numeric(.data$estimate)), NA_real_)
	      ),
	      estimate_type = "latest",
	      status = dplyr::case_when(
	        .data$status == "success" & !is.finite(.data$estimate) ~ "missing_latest_estimate",
	        TRUE ~ .data$status
	      ),
	      message = dplyr::case_when(
	        .data$status == "missing_latest_estimate" ~ "actual_gtwr_estimated_but_latest_year_coefficient_missing",
	        TRUE ~ .data$message
	      ),
	      collinearity_warn_flag = dplyr::coalesce(.data$collinearity_warn_latest, FALSE),
      collinearity_warn_stage = dplyr::case_when(
        .data$collinearity_warn_flag ~ "latest",
        TRUE ~ NA_character_
      )
    )
}

build_gtwr_latest_summary <- function(latest_local_tbl, gtwr_summary_tbl) {
  out_cols <- c("outcome", "focal_var", "target_year", "estimate_type", "earliest_year", "latest_year", "window_scope", "n_locations", "n_valid", "mean_beta", "sd_beta", "p25_beta", "p50_beta", "p75_beta", "share_positive", "latest_missing_n", "latest_coverage_share", "collinearity_warn_n", "collinearity_warn_share", "max_local_cn_gtwr", "control_set", "fit_scope", "status", "message")
  template <- gtwr_summary_tbl |>
    ensure_cols(c("outcome", "focal_var", "target_year", "earliest_year", "latest_year", "window_scope", "n_locations", "latest_missing_n", "latest_coverage_share", "collinearity_warn_n", "collinearity_warn_share", "max_local_cn_gtwr", "control_set", "fit_scope", "status", "message")) |>
    dplyr::select(outcome, focal_var, target_year, earliest_year, latest_year, window_scope, n_locations, latest_missing_n, latest_coverage_share, collinearity_warn_n, collinearity_warn_share, max_local_cn_gtwr, control_set, fit_scope, status, message)

  success_latest <- latest_local_tbl |>
    ensure_cols(c("outcome", "focal_var", "estimate", "status")) |>
    dplyr::filter(.data$status == "success", is.finite(.data$estimate)) |>
    dplyr::group_by(outcome, focal_var) |>
    dplyr::summarise(
      n_valid = dplyr::n(),
      mean_beta = mean(.data$estimate, na.rm = TRUE),
      sd_beta = stats::sd(.data$estimate, na.rm = TRUE),
      p25_beta = as.numeric(stats::quantile(.data$estimate, 0.25, names = FALSE, na.rm = TRUE)),
      p50_beta = as.numeric(stats::quantile(.data$estimate, 0.50, names = FALSE, na.rm = TRUE)),
      p75_beta = as.numeric(stats::quantile(.data$estimate, 0.75, names = FALSE, na.rm = TRUE)),
      share_positive = mean(.data$estimate > 0, na.rm = TRUE),
      .groups = "drop"
    )

  if (nrow(success_latest) == 0L) {
    summary_estimate_types <- gtwr_summary_tbl |>
      ensure_cols("estimate_type") |>
      dplyr::pull(estimate_type) |>
      stats::na.omit() |>
      unique()
    if (length(summary_estimate_types) > 0L && all(summary_estimate_types == "latest")) {
      return(
        gtwr_summary_tbl |>
          ensure_cols(out_cols) |>
          dplyr::mutate(estimate_type = "latest") |>
          dplyr::select(dplyr::all_of(out_cols))
      )
    }
  }

  template |>
    dplyr::left_join(success_latest, by = c("outcome", "focal_var")) |>
    dplyr::mutate(estimate_type = "latest", .before = target_year) |>
    ensure_cols(out_cols) |>
    dplyr::select(dplyr::all_of(out_cols))
}

build_gtwr_delta_local <- function(local_tbl) {
  ensure_cols(
    local_tbl,
    c("adm_cd", "outcome", "focal_var", "earliest_estimate", "latest_estimate", "earliest_year", "latest_year", "window_scope", "control_set", "status", "message", "collinearity_warn_earliest", "collinearity_warn_latest", "collinearity_warn_flag", "collinearity_warn_stage")
  ) |>
    dplyr::mutate(
      estimate = suppressWarnings(as.numeric(.data$latest_estimate)) - suppressWarnings(as.numeric(.data$earliest_estimate)),
      estimate_type = "latest_minus_earliest",
      collinearity_warn_flag = dplyr::coalesce(.data$collinearity_warn_earliest, FALSE) | dplyr::coalesce(.data$collinearity_warn_latest, FALSE),
      collinearity_warn_stage = dplyr::case_when(
        dplyr::coalesce(.data$collinearity_warn_earliest, FALSE) & dplyr::coalesce(.data$collinearity_warn_latest, FALSE) ~ "earliest_and_latest",
        dplyr::coalesce(.data$collinearity_warn_earliest, FALSE) ~ "earliest",
        dplyr::coalesce(.data$collinearity_warn_latest, FALSE) ~ "latest",
        TRUE ~ NA_character_
      )
    )
}

build_gtwr_delta_summary <- function(delta_local_tbl, gtwr_summary_tbl, group_cols = character()) {
  keys <- c(group_cols, "outcome", "focal_var")
  out_cols <- c(
    group_cols,
    "outcome", "focal_var", "target_year", "estimate_type", "earliest_year", "latest_year",
    "window_scope", "n_locations", "n_valid", "mean_beta", "sd_beta", "p25_beta",
    "p50_beta", "p75_beta", "share_positive", "control_set", "fit_scope", "status", "message"
  )

  template <- gtwr_summary_tbl |>
    ensure_cols(c(group_cols, "outcome", "focal_var", "target_year", "earliest_year", "latest_year", "window_scope", "n_locations", "control_set", "fit_scope", "status", "message")) |>
    dplyr::select(dplyr::all_of(c(group_cols, "outcome", "focal_var", "target_year", "earliest_year", "latest_year", "window_scope", "n_locations", "control_set", "fit_scope", "status", "message")))

  success_delta <- delta_local_tbl |>
    ensure_cols(c(group_cols, "outcome", "focal_var", "estimate", "status")) |>
    dplyr::filter(.data$status == "success", is.finite(.data$estimate)) |>
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) |>
    dplyr::summarise(
      n_valid = dplyr::n(),
      mean_beta = mean(.data$estimate, na.rm = TRUE),
      sd_beta = stats::sd(.data$estimate, na.rm = TRUE),
      p25_beta = as.numeric(stats::quantile(.data$estimate, 0.25, names = FALSE, na.rm = TRUE)),
      p50_beta = as.numeric(stats::quantile(.data$estimate, 0.50, names = FALSE, na.rm = TRUE)),
      p75_beta = as.numeric(stats::quantile(.data$estimate, 0.75, names = FALSE, na.rm = TRUE)),
      share_positive = mean(.data$estimate > 0, na.rm = TRUE),
      .groups = "drop"
    )

  template |>
    dplyr::left_join(success_delta, by = keys) |>
    dplyr::mutate(estimate_type = "latest_minus_earliest", .before = target_year) |>
    ensure_cols(out_cols) |>
    dplyr::select(dplyr::all_of(out_cols))
}

build_gwr_delta_rankings <- function(local_tbl) {
  local_tbl <- ensure_cols(
    local_tbl,
    c("gwr_family", "adm_cd", "outcome", "focal_var", "estimate", "estimate_type", "early_start_year", "early_end_year", "late_start_year", "late_end_year", "window_scope", "window_n_year", "status", "message")
  )
  local_tbl$adm_cd <- as.character(local_tbl$adm_cd)
  local_tbl <- local_tbl |>
    dplyr::left_join(adm_name_lookup(), by = "adm_cd")

  success_tbl <- local_tbl |>
    dplyr::filter(status == "success", is.finite(estimate))

  out_cols <- c("gwr_family", "outcome", "focal_var", "rank_group", "rank_order", "adm_cd", "adstrd_nm", "estimate", "estimate_type", "early_start_year", "early_end_year", "late_start_year", "late_end_year", "window_scope", "window_n_year", "status", "message")
  local_tbl <- ensure_cols(local_tbl, out_cols)
  if (nrow(success_tbl) == 0L) {
    return(tibble::as_tibble(local_tbl[0, out_cols, drop = FALSE]))
  }

  rank_keys <- c("gwr_family", "outcome", "focal_var")
  neg_tbl <- success_tbl |>
    dplyr::group_by(dplyr::across(dplyr::all_of(rank_keys))) |>
    dplyr::slice_min(order_by = estimate, n = 5L, with_ties = FALSE) |>
    dplyr::arrange(dplyr::across(dplyr::all_of(rank_keys)), estimate) |>
    dplyr::mutate(rank_group = "most_negative") |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(rank_keys, "rank_group")))) |>
    dplyr::mutate(rank_order = dplyr::row_number()) |>
    dplyr::ungroup()

  pos_tbl <- success_tbl |>
    dplyr::group_by(dplyr::across(dplyr::all_of(rank_keys))) |>
    dplyr::slice_max(order_by = estimate, n = 5L, with_ties = FALSE) |>
    dplyr::arrange(dplyr::across(dplyr::all_of(rank_keys)), dplyr::desc(estimate)) |>
    dplyr::mutate(rank_group = "most_positive") |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(rank_keys, "rank_group")))) |>
    dplyr::mutate(rank_order = dplyr::row_number()) |>
    dplyr::ungroup()

  dplyr::bind_rows(neg_tbl, pos_tbl) |>
    dplyr::select(dplyr::all_of(out_cols))
}


#==============================================================================
# 1. Build Descriptive Statistics
#==============================================================================

desc_var_registry <- tibble::tribble(
  ~variable,                         ~label,                                      ~role,
  "age60_resident_share",            "Age 60+ resident share",                    "aging_exposure",
  "age60_floating_share",            "Age 60+ floating population share",         "aging_exposure",
  "age60_sales_share",               "Age 60+ sales amount share",                "aging_exposure",
  "vitality_sub_economic",           "Economic vitality sub-index",               "vitality_outcome",
  "vitality_sub_social",             "Social vitality sub-index",                 "vitality_outcome",
  "vitality_sub_temporal",           "Temporal vitality sub-index",               "vitality_outcome",
  "vitality_sub_stability",          "Structural stability sub-index",            "vitality_outcome",
  "vitality_index_base",             "Composite vitality index",                  "vitality_outcome",
  "vitality_index_entropy",          "Entropy-weighted vitality index",           "robustness_outcome",
  "vitality_index_pca",              "PCA vitality index",                        "robustness_outcome",
  "ln_sales_count",                  "Log annual sales count",                    "economic_component",
  "ln_total_sales",                  "Log annual total sales amount",             "economic_component",
  "ln_sales_per_store",              "Log annual sales per store",                "economic_support",
  "ln_floating_pop",                 "Log annual floating population",            "social_component",
  "ln_external_inflow_pop",          "Log annual external inflow population",      "social_component",
  "sales_time_entropy",              "Sales time-of-day entropy",                 "temporal_component",
  "floating_time_entropy",           "Floating population time-of-day entropy",    "temporal_component",
  "sales_quarter_stability",         "Sales quarterly stability",                 "temporal_component",
  "floating_quarter_stability",      "Floating population quarterly stability",    "temporal_component",
  "diversity_index",                 "Business diversity index",                  "stability_component",
  "operating_months_rel_seoul",      "Operating duration relative to Seoul",       "stability_component",
  "survival_3y",                     "New-enterprise 3-year survival rate",       "stability_component",
  "ln_resident_pop",                 "Log annual resident population",            "model_control",
  "ln_official_land_price",          "Log official land price",                   "model_control",
  "transit_accessibility",           "Transit accessibility",                     "model_control"
) |>
  dplyr::mutate(display_order = dplyr::row_number()) |>
  dplyr::filter(.data$variable %in% names(panel))

if (nrow(desc_var_registry) > 0L) {
  desc <- dplyr::bind_rows(lapply(seq_len(nrow(desc_var_registry)), function(i) {
    summarise_descriptive_variable(
      data = panel,
      variable = desc_var_registry$variable[[i]],
      label = desc_var_registry$label[[i]],
      role = desc_var_registry$role[[i]],
      order = desc_var_registry$display_order[[i]]
    )
  })) |>
    dplyr::arrange(.data$display_order) |>
    dplyr::select(
      variable, label, role, n, missing_n, missing_share,
      mean, sd, min, p25, median, p75, max,
      sample_min_year, sample_max_year, n_years, n_adm
    )

  write_csv_safe(desc, cfg$paths$descriptive_statistics)
}

desc_vars_missing <- setdiff(
  c(cfg$impact_aging_vars, cfg$primary_outcomes, cfg$vitality_supplementary_outcomes, cfg$twfe_main_control_cols),
  names(panel)
)
if (length(desc_vars_missing) > 0L) {
  message("[WARN] descriptive statistics skipped missing active variables: ", paste(desc_vars_missing, collapse = ", "))
}


#==============================================================================
# 2. Build Main-Analysis Variable Correlation Tables
#==============================================================================

main_corr_vars <- unique(c(
  cfg$spdm_main_exposure_vars,
  cfg$spdm_channel_vars,
  cfg$impact_aging_vars,
  cfg$primary_outcomes,
  cfg$vitality_supplementary_outcomes,
  cfg$gtwr_available_control_cols
))

main_corr_registry <- tibble::tibble(variable = main_corr_vars) |>
  dplyr::filter(.data$variable %in% names(panel)) |>
  dplyr::left_join(
    desc_var_registry |>
      dplyr::select(variable, label),
    by = "variable"
  ) |>
  dplyr::mutate(
    label = dplyr::coalesce(.data$label, .data$variable),
    role = dplyr::case_when(
      .data$variable %in% cfg$spdm_main_exposure_vars ~ "main_exposure",
      .data$variable %in% cfg$spdm_channel_vars ~ "channel_mediator",
      .data$variable %in% setdiff(cfg$impact_aging_vars, c(cfg$spdm_main_exposure_vars, cfg$spdm_channel_vars)) ~ "supporting_exposure",
      .data$variable %in% cfg$primary_outcomes ~ "outcome_primary",
      .data$variable %in% cfg$vitality_supplementary_outcomes ~ "outcome_composite",
      .data$variable %in% cfg$gtwr_lean_control_cols ~ "control_main_gtwr_lean_extended",
      .data$variable %in% cfg$gtwr_extended_control_cols ~ "control_main_gtwr_extended",
      TRUE ~ "model_variable"
    ),
    model_scope = dplyr::case_when(
      .data$variable %in% cfg$spdm_main_exposure_vars ~ "TWFE/SPDM/GTWR focal exposure",
      .data$variable %in% cfg$spdm_channel_vars ~ "SPDM channel mediator",
      .data$variable %in% setdiff(cfg$impact_aging_vars, c(cfg$spdm_main_exposure_vars, cfg$spdm_channel_vars)) ~ "supporting aging exposure",
      .data$variable %in% c(cfg$primary_outcomes, cfg$vitality_supplementary_outcomes) ~ "TWFE/SPDM/GTWR outcome",
      .data$variable %in% cfg$gtwr_lean_control_cols ~ "TWFE/SPDM control; GTWR lean and extended control",
      .data$variable %in% cfg$gtwr_extended_control_cols ~ "TWFE/SPDM control; GTWR extended control",
      TRUE ~ "main analysis variable"
    )
  )

missing_corr_vars <- setdiff(main_corr_vars, names(panel))
if (length(missing_corr_vars) > 0L) {
  message("[WARN] correlation table skipped missing active variables: ", paste(missing_corr_vars, collapse = ", "))
}

if (nrow(main_corr_registry) > 0L) {
  corr_outputs <- build_main_variable_correlation_outputs(
    data = panel,
    registry = main_corr_registry,
    method = "pearson",
    high_corr_threshold = 0.70
  )

  write_csv_safe(corr_outputs$matrix, cfg$paths$main_variable_correlation_matrix)
  write_csv_safe(corr_outputs$pairs, cfg$paths$main_variable_correlation_pairs)
  write_csv_safe(corr_outputs$n_matrix, cfg$paths$main_variable_correlation_n_matrix)
}


#==============================================================================
# 3. Summarize Annual Coverage
#==============================================================================

cov_tbl <- panel |>
  dplyr::count(year, name = "n_rows") |>
  dplyr::arrange(year)
write_csv_safe(cov_tbl, cfg$paths$data_coverage)


#==============================================================================
# 4. Export Annual Time-Series Figure
#==============================================================================

if ("ln_total_sales" %in% names(panel)) {
  ts <- panel |>
    dplyr::group_by(year) |>
    dplyr::summarise(mean_sales = mean(ln_total_sales, na.rm = TRUE), .groups = "drop")

  p <- ggplot2::ggplot(ts, ggplot2::aes(x = year, y = mean_sales)) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::scale_x_continuous(breaks = sort(unique(ts$year))) +
    ggplot2::theme_minimal()
  ggplot2::ggsave(cfg$paths$mean_ln_sales_trend, p, width = 9, height = 4)
}


#==============================================================================
# 4. Build Optional Appendix Tables
#==============================================================================

clear_stale_appendix_outputs()

spatial_family_status_msg <- "spatial family appendix table not run: manual annual appendix source missing"
gwr_delta_tables_status_msg <- "gwr delta tables not run: manual annual appendix source missing"
gtwr_tables_status_msg <- "gtwr delta ranking tables not run: manual annual appendix source missing"
gtwr_age_band_tables_status_msg <- "gtwr age-band delta tables not run: manual annual appendix source missing"
gtwr_sector_share_tables_status_msg <- "gtwr sector-share delta tables not run: manual annual appendix source missing"
gwr_delta_summary_cols <- c(
  "gwr_family", "outcome", "focal_var", "estimate_type", "early_start_year",
  "early_end_year", "late_start_year", "late_end_year", "window_scope",
  "window_n_year", "n_locations", "n_valid", "mean_beta", "sd_beta",
  "p25_beta", "p50_beta", "p75_beta", "share_positive", "status", "message"
)
gwr_delta_local_cols <- c(
  "gwr_family", "adm_cd", "outcome", "focal_var", "coef_early", "coef_late",
  "estimate", "estimate_type", "early_start_year", "early_end_year",
  "late_start_year", "late_end_year", "window_scope", "window_n_year",
  "bandwidth", "kernel", "adaptive", "method", "status", "message"
)

read_gwr_delta_summary_source <- function(path) {
  if (!file.exists(path)) return(tibble::tibble())
  readr::read_csv(path, show_col_types = FALSE) |>
    ensure_cols(gwr_delta_summary_cols) |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(c("early_start_year", "early_end_year", "late_start_year", "late_end_year", "window_n_year", "n_locations", "n_valid")),
        ~ suppressWarnings(as.integer(.x))
      ),
      dplyr::across(
        dplyr::all_of(c("mean_beta", "sd_beta", "p25_beta", "p50_beta", "p75_beta", "share_positive")),
        ~ suppressWarnings(as.numeric(.x))
      )
    ) |>
    dplyr::select(dplyr::all_of(gwr_delta_summary_cols))
}

read_gwr_delta_local_source <- function(path) {
  if (!file.exists(path)) return(tibble::tibble())
  readr::read_csv(path, show_col_types = FALSE) |>
    ensure_cols(gwr_delta_local_cols) |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(c("early_start_year", "early_end_year", "late_start_year", "late_end_year", "window_n_year")),
        ~ suppressWarnings(as.integer(.x))
      ),
      dplyr::across(
        dplyr::all_of(c("coef_early", "coef_late", "estimate", "bandwidth")),
        ~ suppressWarnings(as.numeric(.x))
      )
    ) |>
    dplyr::select(dplyr::all_of(gwr_delta_local_cols))
}

if (file.exists(cfg$paths$spdm_family_comparison)) {
  family_tbl <- readr::read_csv(cfg$paths$spdm_family_comparison, show_col_types = FALSE) |>
    ensure_cols(c(
      "outcome", "family", "w_type", "status", "impacts_status",
      "n_units", "n_periods", "sample_min_year", "sample_max_year",
      "selected_controls", "focal_term", "focal_estimate", "focal_se", "focal_p",
      "lag_param_name", "lag_param_estimate", "lag_param_p",
      "error_param_name", "error_param_estimate", "error_param_p",
      "spatial_param_estimate", "spatial_param_p", "logLik", "AIC", "BIC",
      "direct", "direct_p", "indirect", "indirect_p", "total", "total_p",
      "message"
    ))
  spatial_family_tbl <- family_tbl |>
    dplyr::transmute(
      outcome,
      family,
      w_type,
      status,
      impacts_status,
      n_units,
      n_periods,
      sample_min_year,
      sample_max_year,
      selected_controls,
      focal_term,
      focal_estimate,
      focal_se,
      focal_p,
      lag_param_name,
      lag_param_estimate,
      lag_param_p,
      error_param_name,
      error_param_estimate,
      error_param_p,
      spatial_param_estimate,
      spatial_param_p,
      logLik,
      AIC,
      BIC,
      direct,
      direct_p,
      indirect,
      indirect_p,
      total,
      total_p,
      message
    ) |>
    dplyr::arrange(
      match(outcome, cfg$twfe_main_outcomes),
      match(family, c("twfe_common", "slx", "sar", "sdm", "sem", "sdem", "sarar_sac", "gns")),
      w_type
    )
  write_csv_safe(spatial_family_tbl, cfg$paths$spatial_family_main_table)
  spatial_family_status_msg <- sprintf("spatial family appendix table created: rows=%d", nrow(spatial_family_tbl))
}

if (file.exists(cfg$paths$gwr_delta_main_models)) {
  gwr_delta_summary_tbl <- dplyr::bind_rows(
    read_gwr_delta_summary_source(cfg$paths$gwr_delta_main_models),
    read_gwr_delta_summary_source(cfg$paths$gwr_delta_floating_models)
  ) |>
    dplyr::select(dplyr::all_of(gwr_delta_summary_cols))
  write_csv_safe(gwr_delta_summary_tbl, cfg$paths$gwr_delta_summary_table)

  gwr_delta_local_tbl <- dplyr::bind_rows(
    read_gwr_delta_local_source(cfg$paths$gwr_delta_local_coefficients),
    read_gwr_delta_local_source(cfg$paths$gwr_delta_floating_local_coefficients)
  )
  write_csv_safe(build_gwr_delta_rankings(gwr_delta_local_tbl), cfg$paths$gwr_delta_rankings_table)
  gwr_delta_tables_status_msg <- sprintf("gwr delta appendix tables created: summary_rows=%d, ranking_rows=%d", nrow(gwr_delta_summary_tbl), nrow(build_gwr_delta_rankings(gwr_delta_local_tbl)))
}

gtwr_control_set_report <- cfg$gtwr_control_set_token(cfg$gtwr_control_set)
gtwr_main_path <- cfg$get_gtwr_main_models_path(gtwr_control_set_report)
gtwr_local_path <- cfg$get_gtwr_local_coefficients_path(gtwr_control_set_report)
if (file.exists(gtwr_main_path)) {
  gtwr_summary_tbl <- readr::read_csv(gtwr_main_path, show_col_types = FALSE)
  gtwr_local_tbl <- if (file.exists(gtwr_local_path)) {
    readr::read_csv(gtwr_local_path, show_col_types = FALSE)
  } else {
    tibble::tibble()
  }
  gtwr_latest_local_tbl <- build_gtwr_latest_local(gtwr_local_tbl)
  gtwr_latest_tbl <- build_gtwr_latest_summary(gtwr_latest_local_tbl, gtwr_summary_tbl)
  write_csv_safe(gtwr_latest_tbl, cfg$get_gtwr_latest_summary_table_path(gtwr_control_set_report))

  gtwr_latest_rankings_tbl <- build_gtwr_rankings(gtwr_latest_local_tbl)
  write_csv_safe(gtwr_latest_rankings_tbl, cfg$get_gtwr_latest_rankings_table_path(gtwr_control_set_report))

  gtwr_delta_local_tbl <- build_gtwr_delta_local(gtwr_local_tbl)
  gtwr_delta_tbl <- build_gtwr_delta_summary(gtwr_delta_local_tbl, gtwr_summary_tbl)
  gtwr_delta_rankings_tbl <- build_gtwr_rankings(gtwr_delta_local_tbl)
  write_csv_safe(gtwr_delta_tbl, cfg$get_gtwr_delta_summary_table_path(gtwr_control_set_report))
  write_csv_safe(gtwr_delta_rankings_tbl, cfg$get_gtwr_delta_rankings_table_path(gtwr_control_set_report))

  if (all(c("latest_year", "status") %in% names(gtwr_summary_tbl))) {
    latest_years <- sort(unique(stats::na.omit(as.integer(gtwr_summary_tbl$latest_year))))
    gtwr_tables_status_msg <- sprintf(
      "gtwr annual appendix tables created: control_set=%s, latest_summary_rows=%d, latest_ranking_rows=%d, delta_summary_rows=%d, delta_ranking_rows=%d, statuses=%s, latest_year=%s",
      gtwr_control_set_report,
      nrow(gtwr_latest_tbl),
      nrow(gtwr_latest_rankings_tbl),
      nrow(gtwr_delta_tbl),
      nrow(gtwr_delta_rankings_tbl),
      paste(unique(gtwr_summary_tbl$status), collapse = "|"),
      if (length(latest_years) == 0L) "none" else paste(latest_years, collapse = "|")
    )
  }
}

gtwr_age_band_summary_path <- cfg$get_gtwr_age_band_models_path(gtwr_control_set_report)
gtwr_age_band_local_path <- cfg$get_gtwr_age_band_local_path(gtwr_control_set_report)
if (file.exists(gtwr_age_band_summary_path)) {
  gtwr_age_band_source_tbl <- readr::read_csv(gtwr_age_band_summary_path, show_col_types = FALSE)
  gtwr_age_band_local_tbl <- if (file.exists(gtwr_age_band_local_path)) {
    readr::read_csv(gtwr_age_band_local_path, show_col_types = FALSE)
  } else {
    tibble::tibble()
  }
  gtwr_age_band_delta_local_tbl <- build_gtwr_delta_local(gtwr_age_band_local_tbl)
  gtwr_age_band_tbl <- build_gtwr_delta_summary(
    gtwr_age_band_delta_local_tbl,
    gtwr_age_band_source_tbl,
    group_cols = c("domain", "age_band", "same_domain_total_control")
  )
  write_csv_safe(gtwr_age_band_tbl, cfg$get_gtwr_age_band_delta_summary_table_path(gtwr_control_set_report))

  age_band_rankings_tbl <- build_gtwr_rankings(
    gtwr_age_band_delta_local_tbl,
    group_cols = c("domain", "age_band", "same_domain_total_control")
  )
  write_csv_safe(age_band_rankings_tbl, cfg$get_gtwr_age_band_delta_rankings_table_path(gtwr_control_set_report))
  gtwr_age_band_tables_status_msg <- sprintf("gtwr age-band appendix tables created: summary_rows=%d, ranking_rows=%d", nrow(gtwr_age_band_tbl), nrow(age_band_rankings_tbl))
}

gtwr_sector_share_summary_path <- cfg$get_gtwr_sector_share_models_path(gtwr_control_set_report)
gtwr_sector_share_local_path <- cfg$get_gtwr_sector_share_local_path(gtwr_control_set_report)
if (file.exists(gtwr_sector_share_summary_path)) {
  gtwr_sector_share_source_tbl <- readr::read_csv(gtwr_sector_share_summary_path, show_col_types = FALSE)
  gtwr_sector_share_local_tbl <- if (file.exists(gtwr_sector_share_local_path)) {
    readr::read_csv(gtwr_sector_share_local_path, show_col_types = FALSE)
  } else {
    tibble::tibble()
  }
  gtwr_sector_share_delta_local_tbl <- build_gtwr_delta_local(gtwr_sector_share_local_tbl)
  gtwr_sector_share_tbl <- build_gtwr_delta_summary(
    gtwr_sector_share_delta_local_tbl,
    gtwr_sector_share_source_tbl,
    group_cols = c("exposure_family", "same_domain_total_control")
  )
  write_csv_safe(gtwr_sector_share_tbl, cfg$get_gtwr_sector_share_delta_summary_table_path(gtwr_control_set_report))

  sector_rankings_tbl <- build_gtwr_rankings(
    gtwr_sector_share_delta_local_tbl,
    group_cols = c("exposure_family", "same_domain_total_control")
  )
  write_csv_safe(sector_rankings_tbl, cfg$get_gtwr_sector_share_delta_rankings_table_path(gtwr_control_set_report))
  gtwr_sector_share_tables_status_msg <- sprintf("gtwr sector-share appendix tables created: summary_rows=%d, ranking_rows=%d", nrow(gtwr_sector_share_tbl), nrow(sector_rankings_tbl))
}

append_log(cfg$logs$model_run, sprintf("\n## [%s] 01_make_tables_figures", timestamp()))
append_log(cfg$logs$model_run, paste0("- ", spatial_family_status_msg))
append_log(cfg$logs$model_run, paste0("- ", gwr_delta_tables_status_msg))
append_log(cfg$logs$model_run, paste0("- ", gtwr_tables_status_msg))
append_log(cfg$logs$model_run, paste0("- ", gtwr_age_band_tables_status_msg))
append_log(cfg$logs$model_run, paste0("- ", gtwr_sector_share_tables_status_msg))
append_log(cfg$logs$model_run, "- Annual summary tables/figures generated")
