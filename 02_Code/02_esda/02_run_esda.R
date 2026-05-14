#==============================================================================
# Script    : 02_run_esda.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run the project ESDA pipeline with latest-year descriptive
#             distribution maps, Global Moran's I, Global Bivariate Moran's I,
#             univariate/bivariate LISA, W-sensitivity diagnostics, and
#             annual-sequence EHSA over core aging and vitality variables.
# Author    : Codex
# Created   : 2026-02-28
# Updated   : 2026-04-22
# Type      : esda
# Inputs    : panel_main.parquet, W_*.rds, 2020 commercial boundary
# Outputs   : global_morans_i.csv, global_morans_i_by_w.csv,
#             global_bivariate_morans_i.csv,
#             univariate_lisa_summary.csv, univariate_lisa_local.csv,
#             bivariate_lisa_summary.csv, bivariate_lisa_local.csv,
#             emerging_hotspot_summary.csv, emerging_hotspot_local.csv,
#             distribution_map__*.png, univariate_lisa_map__*.png,
#             bivariate_lisa_map__*.png, emerging_hotspot_map__*.png
# DependsOn : 02_Code/02_esda/01_build_spatial_weights.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_esda_maps.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
load_project_packages(extra = "Kendall")
ensure_dirs(cfg$required_dirs)

value_or <- function(x, default) {
  if (is.null(x)) default else x
}

if (!file.exists(cfg$paths$panel_main) || !file.exists(cfg$paths$w_queen)) {
  stop("[ERROR] Required panel or W file missing for ESDA", call. = FALSE)
}

panel <- read_panel_main_view("esda")
if (!all(c("adm_cd", "year") %in% names(panel))) {
  stop("[ERROR] ESDA panel view must contain adm_cd and year", call. = FALSE)
}
panel <- panel |>
  dplyr::mutate(
    adm_cd = as.character(adm_cd),
    year = suppressWarnings(as.integer(year))
  )

latest_year <- max(panel$year[is.finite(panel$year)], na.rm = TRUE)
if (!is.finite(latest_year)) {
  stop("[ERROR] no valid annual observations found in panel_main for ESDA", call. = FALSE)
}
latest_year <- as.integer(latest_year)

cs <- panel |>
  dplyr::filter(year == latest_year)
if (nrow(cs) == 0) {
  stop(sprintf("[ERROR] no rows found for latest ESDA year: %d", latest_year), call. = FALSE)
}

b2020 <- load_commercial_boundary(cfg$dir_boundary, cfg$target_crs) |>
  dplyr::select(adm_cd, geometry) |>
  dplyr::mutate(adm_cd = as.character(adm_cd))

aging_vars <- intersect(
  unique(as.character(value_or(
    cfg$impact_aging_vars,
    c("age60_resident_share", "age60_floating_share", "age60_sales_share")
  ))),
  names(panel)
)
outcome_vars <- intersect(
  unique(as.character(value_or(
    cfg$esda_main_outcomes,
    c(
      "vitality_sub_economic",
      "vitality_sub_social",
      "vitality_sub_temporal",
      "vitality_sub_stability",
      "vitality_index_base"
    )
  ))),
  names(panel)
)
esda_global_vars <- intersect(
  unique(as.character(value_or(
    cfg$esda_main_global_moran_vars,
    c("age60_resident_share", "age60_floating_share", outcome_vars)
  ))),
  names(panel)
)
univariate_lisa_vars <- intersect(
  unique(as.character(value_or(cfg$esda_main_univariate_lisa_vars, esda_global_vars))),
  names(panel)
)
bivariate_aging_vars <- intersect(
  unique(as.character(value_or(cfg$esda_main_bivariate_aging_vars, aging_vars))),
  names(panel)
)
bivariate_outcomes <- intersect(
  unique(as.character(value_or(cfg$esda_main_bivariate_outcomes, outcome_vars))),
  names(panel)
)
ehsa_vars <- intersect(
  unique(as.character(value_or(
    cfg$esda_main_ehsa_vars,
    c(
      "age60_resident_share",
      "age60_floating_share",
      "vitality_sub_economic",
      "vitality_sub_social",
      "vitality_sub_temporal",
      "vitality_sub_stability",
      "vitality_index_base"
    )
  ))),
  names(panel)
)
w_paths <- c(
  queen = cfg$paths$w_queen,
  rook = cfg$paths$w_rook,
  knn6 = cfg$paths$w_knn6,
  knn8 = cfg$paths$w_knn8
)

distribution_label_lookup <- c(
  age60_floating_share = "60+ floating-population share",
  age60_resident_share = "60+ resident share",
  vitality_index_base = "Commercial vitality index (supplementary composite)",
  vitality_sub_economic = "Economic vitality subindex",
  vitality_sub_social = "Social vitality subindex",
  vitality_sub_temporal = "Temporal vitality subindex",
  vitality_sub_stability = "Stability vitality subindex"
)
distribution_map_vars <- unique(c(
  "age60_floating_share",
  "age60_resident_share",
  cfg$esda_representative_vitality_outcome,
  "vitality_sub_economic",
  "vitality_sub_social",
  "vitality_sub_temporal",
  "vitality_sub_stability"
))

main_distribution_map_specs <- tibble::tibble(
  variable = intersect(distribution_map_vars, names(panel))
) |>
  dplyr::mutate(
    display_label = dplyr::coalesce(unname(distribution_label_lookup[variable]), variable),
    method = "quantile",
    n_classes = 5L,
    center_zero = FALSE,
    palette_type = "sequential"
  )

lisa_map_pairs <- tidyr::crossing(
  var_x = bivariate_aging_vars,
  var_y = bivariate_outcomes
)

lisa_levels <- c("High-High", "High-Low", "Low-High", "Low-Low", "Not Significant", "Missing")
lisa_palette <- c(
  "High-High" = "#9d0208",
  "High-Low" = "#f48c06",
  "Low-High" = "#577590",
  "Low-Low" = "#023e8a",
  "Not Significant" = "#d9d9d9",
  "Missing" = "#f5f5f5"
)
ehsa_palette <- c(
  "new hotspot" = "#d73027",
  "consecutive hotspot" = "#f46d43",
  "intensifying hotspot" = "#fdae61",
  "persistent hotspot" = "#f46d43",
  "diminishing hotspot" = "#fee08b",
  "sporadic hotspot" = "#fdd49e",
  "oscillating hotspot" = "#f16913",
  "oscilating hotspot" = "#f16913",
  "historical hotspot" = "#fcae91",
  "new coldspot" = "#4575b4",
  "consecutive coldspot" = "#74add1",
  "intensifying coldspot" = "#abd9e9",
  "persistent coldspot" = "#3288bd",
  "diminishing coldspot" = "#d0e1f2",
  "sporadic coldspot" = "#92c5de",
  "oscillating coldspot" = "#2166ac",
  "oscilating coldspot" = "#2166ac",
  "historical coldspot" = "#c6dbef",
  "no pattern detected" = "#d9d9d9",
  "not evaluated" = "#f0f0f0"
)


#==============================================================================
# 1. Shared Helpers
#==============================================================================

sanitize_stub <- function(x) {
  out <- stringr::str_replace_all(x, "[^A-Za-z0-9]+", "_")
  stringr::str_replace_all(out, "^_+|_+$", "")
}

clear_map_family <- function(pattern) {
  stale_maps <- list.files(cfg$dir_maps, pattern = pattern, full.names = TRUE)
  if (length(stale_maps) > 0L) {
    fs::file_delete(stale_maps)
  }
  invisible(stale_maps)
}

deterministic_seed_from_label <- function(label, base_seed = cfg$esda_seed) {
  ints <- utf8ToInt(enc2utf8(paste(label, collapse = "|")))
  mod <- 2147483647
  seed <- as.double(base_seed %% mod)

  if (length(ints) > 0L) {
    for (value in ints) {
      seed <- (seed * 131 + as.double(value)) %% mod
    }
  }

  seed <- floor(seed)
  if (!is.finite(seed) || seed <= 0) seed <- 1
  as.integer(seed)
}

with_deterministic_seed <- function(label, expr, base_seed = cfg$esda_seed) {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)

  on.exit(
    {
      if (had_seed) {
        assign(".Random.seed", old_seed, envir = .GlobalEnv)
      } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    },
    add = TRUE
  )

  set.seed(deterministic_seed_from_label(label, base_seed = base_seed))
  eval.parent(substitute(expr))
}

standardize_or_zero <- function(x) {
  if (length(x) == 0L) return(numeric())
  x <- as.numeric(x)
  if (!any(is.finite(x))) return(rep(0, length(x)))
  mu <- mean(x, na.rm = TRUE)
  s <- stats::sd(x, na.rm = TRUE)
  if (!is.finite(s) || s == 0) return(rep(0, length(x)))
  (x - mu) / s
}

get_w_ids <- function(lw) {
  get_listw_region_ids(lw)
}

compute_global_moran_table <- function(cs, lw, w_type, vars, year_value, nsim = cfg$esda_global_moran_nsim) {
  purrr::map_dfr(vars, function(v) {
    aligned <- tryCatch(
      align_numeric_vector_to_listw(cs, lw, value_col = v, id_col = "adm_cd", min_units = 30L),
      error = function(e) e
    )

    if (inherits(aligned, "error")) {
      return(tibble::tibble(
        year = as.integer(year_value),
        w_type = w_type,
        variable = v,
        n_units = NA_integer_,
        n_missing = NA_integer_,
        missing_policy = NA_character_,
        moran_i = NA_real_,
        expectation = NA_real_,
        p_value = NA_real_,
        nsim = as.integer(nsim),
        inference = cfg$esda_global_moran_p_value,
        status = "failed",
        message = aligned$message
      ))
    }

    seed_label <- sprintf(
      "global_moran|%d|%s|%s|nsim=%d",
      as.integer(year_value), w_type, v, as.integer(nsim)
    )
    mt <- tryCatch(
      with_deterministic_seed(
        seed_label,
        spdep::moran.mc(aligned$values, aligned$lw, nsim = nsim, zero.policy = TRUE)
      ),
      error = function(e) e
    )

    if (inherits(mt, "error")) {
      return(tibble::tibble(
        year = as.integer(year_value),
        w_type = w_type,
        variable = v,
        n_units = aligned$n_complete,
        n_missing = aligned$n_missing,
        missing_policy = aligned$missing_policy,
        moran_i = NA_real_,
        expectation = NA_real_,
        p_value = NA_real_,
        nsim = as.integer(nsim),
        inference = cfg$esda_global_moran_p_value,
        status = "failed",
        message = mt$message
      ))
    }

    obs <- suppressWarnings(as.numeric(mt$statistic[[1]]))
    sim_vals <- suppressWarnings(as.numeric(mt$res))
    if (length(sim_vals) > as.integer(nsim)) {
      sim_vals <- sim_vals[seq_len(as.integer(nsim))]
    }
    sim_vals <- sim_vals[is.finite(sim_vals)]
    p_value <- if (is.finite(obs) && length(sim_vals) > 0L) {
      (sum(abs(sim_vals) >= abs(obs)) + 1) / (length(sim_vals) + 1)
    } else {
      NA_real_
    }

    tibble::tibble(
      year = as.integer(year_value),
      w_type = w_type,
      variable = v,
      n_units = aligned$n_complete,
      n_missing = aligned$n_missing,
      missing_policy = aligned$missing_policy,
      moran_i = obs,
      expectation = if (length(sim_vals) > 0L) mean(sim_vals, na.rm = TRUE) else NA_real_,
      p_value = p_value,
      nsim = as.integer(nsim),
      inference = cfg$esda_global_moran_p_value,
      status = "success",
      message = NA_character_
    )
  })
}

empty_bivariate_summary <- function(year_value, var_x, var_y, message, status = "failed") {
  tibble::tibble(
    year = as.integer(year_value),
    w_type = "queen",
    var_x = var_x,
    var_y = var_y,
    n_units = NA_integer_,
    n_significant = NA_integer_,
    share_significant = NA_real_,
    n_high_high = NA_integer_,
    n_high_low = NA_integer_,
    n_low_high = NA_integer_,
    n_low_low = NA_integer_,
    n_not_significant = NA_integer_,
    status = status,
    message = message
  )
}

empty_global_bivariate_summary <- function(year_value, var_x, var_y, message, status = "failed") {
  tibble::tibble(
    year = as.integer(year_value),
    w_type = "queen",
    var_x = var_x,
    var_y = var_y,
    n_units = NA_integer_,
    n_missing = NA_integer_,
    missing_policy = NA_character_,
    moran_bv = NA_real_,
    expectation = NA_real_,
    p_value = NA_real_,
    nsim = NA_integer_,
    status = status,
    message = message
  )
}

empty_univariate_summary <- function(year_value, variable, message, status = "failed") {
  tibble::tibble(
    year = as.integer(year_value),
    w_type = "queen",
    variable = variable,
    n_units = NA_integer_,
    n_significant = NA_integer_,
    share_significant = NA_real_,
    n_high_high = NA_integer_,
    n_high_low = NA_integer_,
    n_low_high = NA_integer_,
    n_low_low = NA_integer_,
    n_not_significant = NA_integer_,
    status = status,
    message = message
  )
}

compute_univariate_lisa_var <- function(cs, lw, variable, year_value, nsim = 499L, alpha = 0.05) {
  d <- cs |>
    dplyr::transmute(
      adm_cd = as.character(adm_cd),
      x = suppressWarnings(as.numeric(.data[[variable]]))
    ) |>
    dplyr::filter(is.finite(x))

  w_ids <- get_w_ids(lw)
  keep_ids <- intersect(w_ids, d$adm_cd)
  if (length(keep_ids) < 30L) {
    return(list(
      summary = empty_univariate_summary(year_value, variable, "insufficient overlap after complete-case filter", "skipped"),
      local = tibble::tibble()
    ))
  }

  lw_sub <- tryCatch(
    spdep::subset.listw(lw, subset = w_ids %in% keep_ids, zero.policy = TRUE),
    error = function(e) e
  )
  if (inherits(lw_sub, "error")) {
    return(list(
      summary = empty_univariate_summary(year_value, variable, lw_sub$message),
      local = tibble::tibble()
    ))
  }

  d <- d |>
    dplyr::filter(adm_cd %in% keep_ids) |>
    dplyr::slice(match(keep_ids, adm_cd))

  seed_label <- sprintf(
    "univariate_lisa|%d|%s|queen|nsim=%d|alpha=%s",
    as.integer(year_value), variable, as.integer(nsim), alpha
  )
  local_raw <- tryCatch(
    with_deterministic_seed(
      seed_label,
      sfdep::local_moran(d$x, lw_sub$neighbours, lw_sub$weights, nsim = nsim)
    ),
    error = function(e) e
  )
  if (inherits(local_raw, "error")) {
    return(list(
      summary = empty_univariate_summary(year_value, variable, local_raw$message),
      local = tibble::tibble()
    ))
  }

  x_z <- standardize_or_zero(d$x)
  lag_x <- tryCatch(
    spdep::lag.listw(lw_sub, d$x, zero.policy = TRUE),
    error = function(e) rep(NA_real_, nrow(d))
  )
  lag_x_z <- tryCatch(
    spdep::lag.listw(lw_sub, x_z, zero.policy = TRUE),
    error = function(e) rep(NA_real_, nrow(d))
  )
  pvals <- as.numeric(local_raw$p_ii_sim)
  significant <- is.finite(pvals) & pvals <= alpha

  cluster <- dplyr::case_when(
    significant & x_z >= 0 & lag_x_z >= 0 ~ "High-High",
    significant & x_z >= 0 & lag_x_z < 0 ~ "High-Low",
    significant & x_z < 0 & lag_x_z >= 0 ~ "Low-High",
    significant & x_z < 0 & lag_x_z < 0 ~ "Low-Low",
    TRUE ~ "Not Significant"
  )

  local <- tibble::tibble(
    year = as.integer(year_value),
    w_type = "queen",
    variable = variable,
    adm_cd = d$adm_cd,
    x_value = d$x,
    lag_x = lag_x,
    x_z = x_z,
    lag_x_z = lag_x_z,
    local_i = as.numeric(local_raw$ii),
    local_z = as.numeric(local_raw$z_ii),
    p_value = pvals,
    cluster = cluster,
    significant = significant
  )

  summary <- tibble::tibble(
    year = as.integer(year_value),
    w_type = "queen",
    variable = variable,
    n_units = nrow(local),
    n_significant = sum(local$significant, na.rm = TRUE),
    share_significant = mean(local$significant, na.rm = TRUE),
    n_high_high = sum(local$cluster == "High-High", na.rm = TRUE),
    n_high_low = sum(local$cluster == "High-Low", na.rm = TRUE),
    n_low_high = sum(local$cluster == "Low-High", na.rm = TRUE),
    n_low_low = sum(local$cluster == "Low-Low", na.rm = TRUE),
    n_not_significant = sum(local$cluster == "Not Significant", na.rm = TRUE),
    status = "success",
    message = NA_character_
  )

  list(summary = summary, local = local)
}

compute_bivariate_lisa_pair <- function(cs, lw, var_x, var_y, year_value, nsim = 499L, alpha = 0.05) {
  d <- cs |>
    dplyr::transmute(
      adm_cd = as.character(adm_cd),
      x = suppressWarnings(as.numeric(.data[[var_x]])),
      y = suppressWarnings(as.numeric(.data[[var_y]]))
    ) |>
    dplyr::filter(is.finite(x), is.finite(y))

  w_ids <- get_w_ids(lw)
  keep_ids <- intersect(w_ids, d$adm_cd)
  if (length(keep_ids) < 30L) {
    return(list(
      summary = empty_bivariate_summary(year_value, var_x, var_y, "insufficient overlap after complete-case filter", "skipped"),
      local = tibble::tibble()
    ))
  }

  lw_sub <- tryCatch(
    spdep::subset.listw(lw, subset = w_ids %in% keep_ids, zero.policy = TRUE),
    error = function(e) e
  )
  if (inherits(lw_sub, "error")) {
    return(list(
      summary = empty_bivariate_summary(year_value, var_x, var_y, lw_sub$message),
      local = tibble::tibble()
    ))
  }

  d <- d |>
    dplyr::filter(adm_cd %in% keep_ids) |>
    dplyr::slice(match(keep_ids, adm_cd))

  seed_label <- sprintf(
    "bivariate_lisa|%d|%s|%s|queen|nsim=%d|alpha=%s",
    as.integer(year_value), var_x, var_y, as.integer(nsim), alpha
  )
  local_raw <- tryCatch(
    with_deterministic_seed(
      seed_label,
      sfdep::local_moran_bv(d$x, d$y, lw_sub$neighbours, lw_sub$weights, nsim = nsim)
    ),
    error = function(e) e
  )
  if (inherits(local_raw, "error")) {
    return(list(
      summary = empty_bivariate_summary(year_value, var_x, var_y, local_raw$message),
      local = tibble::tibble()
    ))
  }

  x_z <- standardize_or_zero(d$x)
  y_z <- standardize_or_zero(d$y)
  lag_y <- tryCatch(
    spdep::lag.listw(lw_sub, d$y, zero.policy = TRUE),
    error = function(e) rep(NA_real_, nrow(d))
  )
  lag_y_z <- tryCatch(
    spdep::lag.listw(lw_sub, y_z, zero.policy = TRUE),
    error = function(e) rep(NA_real_, nrow(d))
  )
  pvals <- as.numeric(local_raw$p_sim)
  significant <- is.finite(pvals) & pvals <= alpha

  cluster <- dplyr::case_when(
    significant & x_z >= 0 & lag_y_z >= 0 ~ "High-High",
    significant & x_z >= 0 & lag_y_z < 0 ~ "High-Low",
    significant & x_z < 0 & lag_y_z >= 0 ~ "Low-High",
    significant & x_z < 0 & lag_y_z < 0 ~ "Low-Low",
    TRUE ~ "Not Significant"
  )

  local <- tibble::tibble(
    year = as.integer(year_value),
    w_type = "queen",
    var_x = var_x,
    var_y = var_y,
    adm_cd = d$adm_cd,
    x_value = d$x,
    y_value = d$y,
    lag_y = lag_y,
    x_z = x_z,
    lag_y_z = lag_y_z,
    local_bv = as.numeric(local_raw$Ib),
    p_value = pvals,
    cluster = cluster,
    significant = significant
  )

  summary <- tibble::tibble(
    year = as.integer(year_value),
    w_type = "queen",
    var_x = var_x,
    var_y = var_y,
    n_units = nrow(local),
    n_significant = sum(local$significant, na.rm = TRUE),
    share_significant = mean(local$significant, na.rm = TRUE),
    n_high_high = sum(local$cluster == "High-High", na.rm = TRUE),
    n_high_low = sum(local$cluster == "High-Low", na.rm = TRUE),
    n_low_high = sum(local$cluster == "Low-High", na.rm = TRUE),
    n_low_low = sum(local$cluster == "Low-Low", na.rm = TRUE),
    n_not_significant = sum(local$cluster == "Not Significant", na.rm = TRUE),
    status = "success",
    message = NA_character_
  )

  list(summary = summary, local = local)
}

compute_global_bivariate_moran_pair <- function(cs, lw, var_x, var_y, year_value, nsim = 499L) {
  d <- cs |>
    dplyr::transmute(
      adm_cd = as.character(adm_cd),
      x = suppressWarnings(as.numeric(.data[[var_x]])),
      y = suppressWarnings(as.numeric(.data[[var_y]]))
    ) |>
    dplyr::filter(is.finite(x), is.finite(y))

  w_ids <- get_w_ids(lw)
  keep_ids <- intersect(w_ids, d$adm_cd)
  n_missing <- length(unique(cs$adm_cd)) - length(keep_ids)

  if (length(keep_ids) < 30L) {
    return(
      empty_global_bivariate_summary(
        year_value, var_x, var_y, "insufficient overlap after complete-case filter", "skipped"
      ) |>
        dplyr::mutate(
          n_units = length(keep_ids),
          n_missing = n_missing,
          missing_policy = "complete_case_pair"
        )
    )
  }

  lw_sub <- tryCatch(
    spdep::subset.listw(lw, subset = w_ids %in% keep_ids, zero.policy = TRUE),
    error = function(e) e
  )
  if (inherits(lw_sub, "error")) {
    return(
      empty_global_bivariate_summary(year_value, var_x, var_y, lw_sub$message) |>
        dplyr::mutate(
          n_units = length(keep_ids),
          n_missing = n_missing,
          missing_policy = "complete_case_pair"
        )
    )
  }

  d <- d |>
    dplyr::filter(adm_cd %in% keep_ids) |>
    dplyr::slice(match(keep_ids, adm_cd))

  seed_label <- sprintf(
    "global_bivariate_moran|%d|%s|%s|queen|nsim=%d",
    as.integer(year_value), var_x, var_y, as.integer(nsim)
  )
  stat_raw <- tryCatch(
    with_deterministic_seed(
      seed_label,
      spdep::moran_bv(d$x, d$y, lw_sub, nsim = nsim, scale = TRUE)
    ),
    error = function(e) e
  )
  if (inherits(stat_raw, "error")) {
    return(
      empty_global_bivariate_summary(year_value, var_x, var_y, stat_raw$message) |>
        dplyr::mutate(
          n_units = nrow(d),
          n_missing = n_missing,
          missing_policy = "complete_case_pair",
          nsim = as.integer(nsim)
        )
    )
  }

  sim_vals <- suppressWarnings(as.numeric(stat_raw$t[, 1]))
  sim_vals <- sim_vals[is.finite(sim_vals)]
  obs <- suppressWarnings(as.numeric(stat_raw$t0[[1]]))
  p_value <- if (is.finite(obs) && length(sim_vals) > 0L) {
    (sum(abs(sim_vals) >= abs(obs)) + 1) / (length(sim_vals) + 1)
  } else {
    NA_real_
  }

  tibble::tibble(
    year = as.integer(year_value),
    w_type = "queen",
    var_x = var_x,
    var_y = var_y,
    n_units = nrow(d),
    n_missing = n_missing,
    missing_policy = "complete_case_pair",
    moran_bv = obs,
    expectation = if (length(sim_vals) > 0L) mean(sim_vals, na.rm = TRUE) else NA_real_,
    p_value = p_value,
    nsim = as.integer(nsim),
    status = "success",
    message = NA_character_
  )
}

save_univariate_lisa_map <- function(local_tbl, boundary, variable, year_value) {
  stub <- sanitize_stub(variable)
  out_path <- file.path(cfg$dir_maps, sprintf("univariate_lisa_map__%s.png", stub))

  plot_df <- boundary |>
    dplyr::left_join(
      local_tbl |>
        dplyr::select(adm_cd, cluster),
      by = "adm_cd"
    ) |>
    dplyr::mutate(cluster = dplyr::if_else(is.na(cluster), "Missing", cluster))

  plot_df$cluster <- factor(plot_df$cluster, levels = lisa_levels)

  p <- ggplot2::ggplot(plot_df) +
    ggplot2::geom_sf(ggplot2::aes(fill = cluster), color = "white", linewidth = 0.05) +
    ggplot2::scale_fill_manual(values = lisa_palette, drop = FALSE) +
    ggplot2::labs(
      title = sprintf("Univariate LISA: %s", variable),
      subtitle = sprintf("Latest year cross-section: %d", as.integer(year_value)),
      fill = NULL
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12),
      plot.subtitle = ggplot2::element_text(size = 10),
      legend.position = "bottom"
    )

  ggplot2::ggsave(out_path, p, width = 8, height = 7, dpi = 300)
  invisible(out_path)
}

save_bivariate_lisa_map <- function(local_tbl, boundary, var_x, var_y, year_value) {
  stub_x <- sanitize_stub(var_x)
  stub_y <- sanitize_stub(var_y)
  out_path <- file.path(cfg$dir_maps, sprintf("bivariate_lisa_map__%s__%s.png", stub_x, stub_y))

  plot_df <- boundary |>
    dplyr::left_join(
      local_tbl |>
        dplyr::select(adm_cd, cluster),
      by = "adm_cd"
    ) |>
    dplyr::mutate(cluster = dplyr::if_else(is.na(cluster), "Missing", cluster))

  plot_df$cluster <- factor(plot_df$cluster, levels = lisa_levels)

  p <- ggplot2::ggplot(plot_df) +
    ggplot2::geom_sf(ggplot2::aes(fill = cluster), color = "white", linewidth = 0.05) +
    ggplot2::scale_fill_manual(values = lisa_palette, drop = FALSE) +
    ggplot2::labs(
      title = sprintf("Bivariate LISA: %s vs W(%s)", var_x, var_y),
      subtitle = sprintf("Latest year cross-section: %d", as.integer(year_value)),
      fill = NULL
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12),
      plot.subtitle = ggplot2::element_text(size = 10),
      legend.position = "bottom"
    )

  ggplot2::ggsave(out_path, p, width = 8, height = 7, dpi = 300)
  invisible(out_path)
}

empty_ehsa_summary <- function(var, message, status = "failed") {
  tibble::tibble(
    var = var,
    start_year = NA_integer_,
    end_year = NA_integer_,
    n_periods = NA_integer_,
    n_total_locations = NA_integer_,
    n_used_locations = NA_integer_,
    n_excluded_locations = NA_integer_,
    classification = NA_character_,
    n_locations = NA_integer_,
    share_locations = NA_real_,
    status = status,
    message = message
  )
}

normalize_ehsa_classification <- function(x) {
  dplyr::recode(
    as.character(x),
    "oscilating hotspot" = "oscillating hotspot",
    "oscilating coldspot" = "oscillating coldspot",
    .default = as.character(x)
  )
}

resolve_ehsa_suffix <- function(panel_df, var, min_locations = 30L) {
  d <- panel_df |>
    dplyr::select(adm_cd, year, dplyr::all_of(var)) |>
    dplyr::mutate(
      adm_cd = as.character(adm_cd),
      year = suppressWarnings(as.integer(year))
    )

  total_n <- dplyr::n_distinct(d$adm_cd)
  coverage <- d |>
    dplyr::filter(is.finite(year)) |>
    dplyr::distinct(year) |>
    dplyr::arrange(year)

  if (nrow(coverage) == 0L) return(NULL)

  for (start_idx in seq_len(nrow(coverage))) {
    keep_years <- coverage$year[start_idx:nrow(coverage)]
    n_periods <- length(keep_years)

    complete_ids <- d |>
      dplyr::filter(year %in% keep_years, is.finite(.data[[var]])) |>
      dplyr::count(adm_cd, name = "n_valid") |>
      dplyr::filter(n_valid == n_periods) |>
      dplyr::pull(adm_cd)

    if (length(complete_ids) < min_locations) next

    out <- d |>
      dplyr::filter(adm_cd %in% complete_ids, year %in% keep_years, is.finite(.data[[var]])) |>
      dplyr::mutate(time_id = match(year, keep_years))

    expected_n <- length(complete_ids) * n_periods
    if (nrow(out) != expected_n) next

    return(list(
      data = out,
      ids = as.character(complete_ids),
      start_year = as.integer(keep_years[[1]]),
      end_year = as.integer(keep_years[[length(keep_years)]]),
      n_periods = as.integer(n_periods),
      n_total_locations = as.integer(total_n),
      n_used_locations = as.integer(length(complete_ids)),
      n_excluded_locations = as.integer(total_n - length(complete_ids))
    ))
  }

  NULL
}

compute_ehsa_for_var <- function(
  panel_df,
  boundary,
  lw_queen,
  var,
  nsim = 199L,
  threshold = 0.01,
  k = 1L,
  min_locations = 30L,
  min_periods = cfg$esda_ehsa_min_years
) {
  suffix <- resolve_ehsa_suffix(panel_df, var, min_locations = min_locations)
  if (is.null(suffix)) {
    return(list(
      summary = empty_ehsa_summary(var, "no complete annual suffix panel available", "skipped"),
      local = tibble::tibble()
    ))
  }
  if (suffix$n_periods < min_periods) {
    return(list(
      summary = empty_ehsa_summary(var, sprintf("insufficient annual periods for EHSA: %d", suffix$n_periods), "skipped"),
      local = tibble::tibble()
    ))
  }

  w_ids <- get_w_ids(lw_queen)
  keep_ids <- intersect(w_ids, suffix$ids)
  if (length(keep_ids) < min_locations) {
    return(list(
      summary = empty_ehsa_summary(var, sprintf("insufficient complete-case overlap with W: %d", length(keep_ids)), "skipped"),
      local = tibble::tibble()
    ))
  }

  lw_subset <- tryCatch(
    spdep::subset.listw(lw_queen, subset = w_ids %in% keep_ids, zero.policy = TRUE),
    error = function(e) e
  )
  if (inherits(lw_subset, "error")) {
    return(list(
      summary = empty_ehsa_summary(var, lw_subset$message),
      local = tibble::tibble()
    ))
  }

  sub_w_ids <- get_w_ids(lw_subset)
  nb_queen_self <- sfdep::include_self(lw_subset$neighbours)
  wt_queen_self <- sfdep::st_weights(nb_queen_self)
  b_geo <- boundary |>
    dplyr::filter(adm_cd %in% sub_w_ids) |>
    dplyr::slice(match(sub_w_ids, adm_cd))
  b_geo$nb_queen <- nb_queen_self
  b_geo$wt_queen <- wt_queen_self

  stc_data <- suffix$data |>
    dplyr::filter(adm_cd %in% sub_w_ids)

  expected_n <- length(sub_w_ids) * suffix$n_periods
  if (nrow(stc_data) != expected_n) {
    return(list(
      summary = empty_ehsa_summary(var, "complete-case annual suffix panel is not balanced after W subset"),
      local = tibble::tibble()
    ))
  }

  stc <- tryCatch(
    sfdep::spacetime(
      stc_data |>
        dplyr::select(adm_cd, time_id, dplyr::all_of(var)),
      b_geo,
      .loc_col = "adm_cd",
      .time_col = "time_id"
    ),
    error = function(e) e
  )
  if (inherits(stc, "error")) {
    return(list(
      summary = empty_ehsa_summary(var, stc$message),
      local = tibble::tibble()
    ))
  }

  ehsa <- tryCatch(
    with_deterministic_seed(
      sprintf(
        "ehsa|%s|%d|%d|periods=%d|nsim=%d|threshold=%s|k=%d",
        var, suffix$start_year, suffix$end_year, suffix$n_periods, as.integer(nsim), threshold, as.integer(k)
      ),
      sfdep::emerging_hotspot_analysis(
        stc,
        .var = var,
        k = k,
        nb_col = "nb_queen",
        wt_col = "wt_queen",
        nsim = nsim,
        threshold = threshold
      )
    ),
    error = function(e) e
  )
  if (inherits(ehsa, "error")) {
    return(list(
      summary = empty_ehsa_summary(var, ehsa$message),
      local = tibble::tibble()
    ))
  }

  local <- ehsa |>
    dplyr::rename(adm_cd = location) |>
    dplyr::mutate(
      classification = normalize_ehsa_classification(classification),
      var = var,
      start_year = suffix$start_year,
      end_year = suffix$end_year,
      n_periods = suffix$n_periods,
      threshold = threshold,
      w_type = "queen_include_self",
      n_total_locations = suffix$n_total_locations,
      n_used_locations = as.integer(length(sub_w_ids)),
      n_excluded_locations = as.integer(suffix$n_total_locations - length(sub_w_ids)),
      .before = 1
    )

  summary_message <- if (suffix$n_total_locations > length(sub_w_ids)) {
    sprintf("complete-case location subset: %d of %d locations", length(sub_w_ids), suffix$n_total_locations)
  } else {
    NA_character_
  }

  summary <- local |>
    dplyr::count(
      var, start_year, end_year, n_periods,
      n_total_locations, n_used_locations, n_excluded_locations,
      classification,
      name = "n_locations"
    ) |>
    dplyr::group_by(var) |>
    dplyr::mutate(share_locations = n_locations / sum(n_locations)) |>
    dplyr::ungroup() |>
    dplyr::mutate(status = "success", message = summary_message)

  list(summary = summary, local = local)
}

save_ehsa_map <- function(local_tbl, boundary, var) {
  stub <- sanitize_stub(var)
  out_path <- file.path(cfg$dir_maps, sprintf("emerging_hotspot_map__%s.png", stub))

  plot_df <- boundary |>
    dplyr::left_join(
      local_tbl |>
        dplyr::select(adm_cd, classification),
      by = "adm_cd"
    ) |>
    dplyr::mutate(classification = dplyr::if_else(is.na(classification), "not evaluated", classification))

  classes <- unique(plot_df$classification)
  palette_use <- ehsa_palette[names(ehsa_palette) %in% classes]
  missing_classes <- setdiff(classes, names(palette_use))
  if (length(missing_classes) > 0L) {
    palette_use <- c(palette_use, stats::setNames(rep("#bdbdbd", length(missing_classes)), missing_classes))
  }

  plot_df$classification <- factor(plot_df$classification, levels = names(palette_use))

  p <- ggplot2::ggplot(plot_df) +
    ggplot2::geom_sf(ggplot2::aes(fill = classification), color = "white", linewidth = 0.05) +
    ggplot2::scale_fill_manual(values = palette_use, drop = FALSE) +
    ggplot2::labs(
      title = sprintf("Emerging Hot Spot: %s", var),
      subtitle = sprintf(
        "Complete-case annual sequence: %d to %d (%d of %d locations)",
        local_tbl$start_year[[1]],
        local_tbl$end_year[[1]],
        local_tbl$n_used_locations[[1]],
        local_tbl$n_total_locations[[1]]
      ),
      fill = NULL
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12),
      plot.subtitle = ggplot2::element_text(size = 10),
      legend.position = "bottom"
    )

  ggplot2::ggsave(out_path, p, width = 8, height = 7, dpi = 300)
  invisible(out_path)
}


#==============================================================================
# 2. Descriptive Distribution Maps
#==============================================================================

if (nrow(main_distribution_map_specs) > 0L) {
  clear_map_family("^distribution_map__.*\\.png$")
  purrr::pwalk(
    list(
      main_distribution_map_specs$variable,
      main_distribution_map_specs$display_label,
      main_distribution_map_specs$method,
      main_distribution_map_specs$n_classes,
      main_distribution_map_specs$center_zero,
      main_distribution_map_specs$palette_type
    ),
    function(variable, display_label, method, n_classes, center_zero, palette_type) {
      out_path <- file.path(cfg$dir_maps, sprintf("distribution_map__%s.png", sanitize_stub(variable)))
      save_distribution_map(
        boundary = b2020,
        value_df = cs,
        value_col = variable,
        out_path = out_path,
        title = sprintf("Distribution Map: %s", display_label),
        subtitle = sprintf("Latest year cross-section: %d | quintile classes", latest_year),
        method = method,
        n_classes = n_classes,
        center_zero = center_zero,
        palette_type = palette_type
      )
    }
  )
}


#==============================================================================
# 3. Global Moran's I and W Sensitivity
#==============================================================================

global_by_w <- purrr::imap_dfr(w_paths, function(w_path, w_type) {
  if (!file.exists(w_path)) {
    return(tibble::tibble(
      year = latest_year,
      w_type = w_type,
      variable = esda_global_vars,
      n_units = NA_integer_,
      n_missing = NA_integer_,
      missing_policy = NA_character_,
      moran_i = NA_real_,
      expectation = NA_real_,
      p_value = NA_real_,
      nsim = as.integer(cfg$esda_global_moran_nsim),
      inference = cfg$esda_global_moran_p_value,
      status = "missing_w",
      message = "spatial weight file not found"
    ))
  }

  lw <- readRDS(w_path)
  compute_global_moran_table(cs, lw, w_type, esda_global_vars, latest_year)
})

write_csv_safe(global_by_w, cfg$paths$global_morans_i_by_w)
write_csv_safe(
  global_by_w |>
    dplyr::filter(w_type == "queen"),
  cfg$paths$global_morans_i
)

lw_queen <- readRDS(cfg$paths$w_queen)


#==============================================================================
# 4. Global Bivariate Moran's I
#==============================================================================

bv_pairs <- tidyr::crossing(var_x = bivariate_aging_vars, var_y = bivariate_outcomes)
global_bv_summary <- purrr::pmap_dfr(
  list(bv_pairs$var_x, bv_pairs$var_y),
  function(var_x, var_y) compute_global_bivariate_moran_pair(cs, lw_queen, var_x, var_y, latest_year)
)

write_csv_safe(global_bv_summary, cfg$paths$global_bivariate_morans_i)


#==============================================================================
# 5. Univariate LISA
#==============================================================================

uv_results <- purrr::map(
  univariate_lisa_vars,
  ~ compute_univariate_lisa_var(cs, lw_queen, .x, latest_year)
)

uv_summary <- dplyr::bind_rows(purrr::map(uv_results, "summary"))
uv_local <- dplyr::bind_rows(purrr::map(uv_results, "local"))

write_csv_safe(uv_summary, cfg$paths$univariate_lisa_summary)
write_csv_safe(uv_local, cfg$paths$univariate_lisa_local)

if (length(univariate_lisa_vars) > 0L && nrow(uv_local) > 0L) {
  clear_map_family("^univariate_lisa_map__.*\\.png$")
  purrr::walk(
    univariate_lisa_vars,
    function(map_var) {
      local_var <- uv_local |>
        dplyr::filter(variable == !!map_var)
      if (nrow(local_var) == 0L) return(invisible(NULL))
      save_univariate_lisa_map(local_var, b2020, map_var, latest_year)
    }
  )
}


#==============================================================================
# 6. Bivariate LISA
#==============================================================================

bv_results <- purrr::pmap(
  list(bv_pairs$var_x, bv_pairs$var_y),
  function(var_x, var_y) compute_bivariate_lisa_pair(cs, lw_queen, var_x, var_y, latest_year)
)

bv_summary <- dplyr::bind_rows(purrr::map(bv_results, "summary"))
bv_local <- dplyr::bind_rows(purrr::map(bv_results, "local"))

write_csv_safe(bv_summary, cfg$paths$bivariate_lisa_summary)
write_csv_safe(bv_local, cfg$paths$bivariate_lisa_local)

if (nrow(lisa_map_pairs) > 0L && nrow(bv_local) > 0L) {
  clear_map_family("^bivariate_lisa_map__.*\\.png$")
  purrr::pwalk(
    list(lisa_map_pairs$var_x, lisa_map_pairs$var_y),
    function(map_x, map_y) {
      local_pair <- bv_local |>
        dplyr::filter(var_x == !!map_x, var_y == !!map_y)
      if (nrow(local_pair) == 0L) return(invisible(NULL))
      save_bivariate_lisa_map(local_pair, b2020, map_x, map_y, latest_year)
    }
  )
}


#==============================================================================
# 7. Emerging Hot Spot Analysis
#==============================================================================

ehsa_results <- purrr::map(
  ehsa_vars,
  ~ compute_ehsa_for_var(panel, b2020, lw_queen, .x)
)

ehsa_summary <- dplyr::bind_rows(purrr::map(ehsa_results, "summary"))
ehsa_local <- dplyr::bind_rows(purrr::map(ehsa_results, "local"))

write_csv_safe(ehsa_summary, cfg$paths$emerging_hotspot_summary)
write_csv_safe(ehsa_local, cfg$paths$emerging_hotspot_local)

if (nrow(ehsa_local) > 0L) {
  clear_map_family("^emerging_hotspot_map__.*\\.png$")
  purrr::walk(
    unique(ehsa_local$var),
    function(ehsa_var) {
      local_var <- ehsa_local |>
        dplyr::filter(var == !!ehsa_var)
      if (nrow(local_var) == 0L) return(invisible(NULL))
      save_ehsa_map(local_var, b2020, ehsa_var)
    }
  )
}


#==============================================================================
# 8. Logs
#==============================================================================

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 02_run_esda", timestamp()))
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- ESDA completed at latest year %d with seed=%d: descriptive maps=%d, global vars=%d, global-W rows=%d, global bivariate pairs=%d, univariate vars=%d, univariate maps=%d, bivariate pairs=%d, bivariate maps=%d, ehsa vars=%d, ehsa_min_years=%d",
    latest_year,
    cfg$esda_seed,
    nrow(main_distribution_map_specs),
    length(esda_global_vars),
    nrow(global_by_w),
    nrow(global_bv_summary),
    length(univariate_lisa_vars),
    length(univariate_lisa_vars),
    nrow(bv_summary),
    nrow(lisa_map_pairs),
    length(ehsa_vars),
    as.integer(cfg$esda_ehsa_min_years)
  )
)
