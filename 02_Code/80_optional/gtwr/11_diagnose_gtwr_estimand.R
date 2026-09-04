#!/usr/bin/env Rscript

#==============================================================================
# Script    : 11_diagnose_gtwr_estimand.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Establish what the GTWR local surface is an estimate *of*, and what
#             the spatiotemporal kernel actually averages over, without refitting
#             the model.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-04
# Status    : QUARTERLY_OPTIONAL / manual GTWR diagnostic outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, administrative boundary,
#             gtwr_main_models_<control_set>.csv,
#             gtwr_local_beta_panel_<control_set>.csv
# Outputs   : gtwr_estimand_comparison_<control_set>.csv,
#             gtwr_kernel_geometry_<control_set>.csv,
#             gtwr_temporal_edge_<control_set>.csv
# DependsOn : 00_setup/config.R, 00_setup/packages.R, 99_utils/utils_gtwr_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# Three questions the GTWR outputs cannot answer about themselves, none of which
# requires a refit:
#
#   1. GTWR is fitted on raw levels with no fixed effects, while TWFE and SPDM are
#      within estimators. If the levels and within relationships differ on this
#      panel, then the local surface is not a decomposition of the global effect,
#      and the two cannot be narrated as the same quantity varying by place.
#   2. With ksi = 0 the Huang et al. (2010) distance collapses to
#      (sqrt(lamda*ds) + sqrt((1-lamda)*dt))^2, which penalises a neighbour that
#      is distant in both dimensions far more than one distant in either alone.
#      Whether the kernel then averages over genuinely spatiotemporal neighbours
#      is a measurable property of the window, not a matter of interpretation.
#   3. Every reported coefficient comes from the last quarter, where the temporal
#      half of the kernel has no future side. How much support is lost there, and
#      whether the resulting estimates are typical of the other quarters, decides
#      how the reporting surface should be described.
#
# All three are answered from distances and the already-published beta panel.
options(scipen = 999)

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
source(here::here("02_Code", "99_utils", "utils_model.R"))
source(here::here("02_Code", "99_utils", "utils_spatial.R"))
source(here::here("02_Code", "99_utils", "utils_gtwr_main.R"))
load_project_packages()

ensure_dirs(cfg$required_dirs)
append_log(cfg$logs$model_run, sprintf("\n## [%s] 11_diagnose_gtwr_estimand", timestamp()))

control_set <- normalize_control_set_main(cfg$gtwr_control_set)
FOCAL <- as.character(value_or(cfg$gtwr_main_exposure_vars, "lag4_age60_resident_share")[[1L]])
CONTROLS <- gtwr_main_control_candidate_cols()
OUTCOMES <- cfg$gtwr_main_outcomes

# Probe sizes. The diagnostic reads a sample of focal points rather than all
# 10,593, because the window composition is a distributional property and a few
# hundred draws pin it to more precision than the question needs.
N_GEOM <- suppressWarnings(as.integer(Sys.getenv("GTWR_DIAG_GEOM_POINTS", unset = "300")))
if (!is.finite(N_GEOM) || N_GEOM < 50L) N_GEOM <- 300L
N_EDGE <- suppressWarnings(as.integer(Sys.getenv("GTWR_DIAG_EDGE_POINTS", unset = "60")))
if (!is.finite(N_EDGE) || N_EDGE < 20L) N_EDGE <- 60L

panel <- prepare_gtwr_points(
  read_panel_main_view("gtwr") |> dplyr::mutate(adm_cd = as.character(.data$adm_cd))
)


#==============================================================================
# 1. What Is the Local Surface an Estimate Of?
#==============================================================================

# The same specification under three estimators on the same complete-case sample:
# a levels OLS with no fixed effects, which is what GTWR generalises; the two-way
# within estimator, which is what TWFE and SPDM report; and the mean of the
# published local coefficients. Whichever of the first two the GTWR mean tracks is
# the estimand its local variation decomposes.
published <- if (file.exists(cfg$get_gtwr_main_models_path(control_set))) {
  readr::read_csv(cfg$get_gtwr_main_models_path(control_set), show_col_types = FALSE)
} else {
  NULL
}

estimand <- purrr::map_dfr(intersect(OUTCOMES, names(panel)), function(oc) {
  vars <- c(oc, FOCAL, CONTROLS, "x", "y", "time_id")
  d <- panel |>
    dplyr::select(dplyr::all_of(unique(c("adm_cd", "yq", vars)))) |>
    tidyr::drop_na()
  if (nrow(d) == 0L) return(NULL)

  rhs <- paste(CONTROLS, collapse = " + ")
  levels_fit <- stats::lm(stats::reformulate(c(FOCAL, CONTROLS), response = oc), data = d)
  within_fit <- fixest::feols(
    stats::as.formula(sprintf("%s ~ %s + %s | adm_cd + yq", oc, FOCAL, rhs)),
    data = d, cluster = ~adm_cd, notes = FALSE
  )
  b_lv <- unname(stats::coef(levels_fit)[[FOCAL]])
  b_wi <- unname(stats::coef(within_fit)[[FOCAL]])

  pub <- if (is.null(published)) NULL else published[published$outcome == oc & published$focal_var == FOCAL, ]
  b_gt <- if (is.null(pub) || nrow(pub) == 0L) NA_real_ else suppressWarnings(as.numeric(pub$mean_beta[[1L]]))
  sd_gt <- if (is.null(pub) || nrow(pub) == 0L) NA_real_ else suppressWarnings(as.numeric(pub$sd_beta[[1L]]))
  bw_pub <- if (is.null(pub) || nrow(pub) == 0L) NA_real_ else suppressWarnings(as.numeric(pub$st_bw[[1L]]))

  tibble::tibble(
    outcome = oc,
    focal_var = FOCAL,
    control_set = control_set,
    n_obs = nrow(d),
    levels_ols_beta = b_lv,
    levels_ols_p = unname(summary(levels_fit)$coefficients[FOCAL, 4]),
    within_twfe_beta = b_wi,
    within_twfe_p = unname(fixest::pvalue(within_fit)[[FOCAL]]),
    gtwr_published_mean_beta = b_gt,
    gtwr_published_sd_beta = sd_gt,
    gtwr_published_st_bw = bw_pub,
    sign_matches_levels = is.finite(b_gt) && sign(b_gt) == sign(b_lv),
    sign_matches_within = is.finite(b_gt) && sign(b_gt) == sign(b_wi),
    levels_within_sign_differ = sign(b_lv) != sign(b_wi),
    note = "GTWR is fitted on levels with no fixed effects; TWFE and SPDM are within estimators"
  )
})

write_csv_safe(estimand, cfg$get_gtwr_estimand_comparison_path(control_set))


#==============================================================================
# 2. What Does the Kernel Average Over?
#==============================================================================

# One representative specification is enough: the window is a property of the
# distance matrix and the bandwidth, not of the outcome.
geom_vars <- c(OUTCOMES[[1L]], FOCAL, CONTROLS, "x", "y", "time_id")
d_geom <- panel |>
  dplyr::select(dplyr::all_of(unique(c("adm_cd", "yq", geom_vars)))) |>
  tidyr::drop_na()

loc <- gtwr_location_dist(d_geom)
tv <- as.numeric(d_geom$time_id)
scales <- gtwr_st_scales(loc, tv)

set.seed(cfg$analysis_seed)
focal_idx <- sort(sample(seq_len(nrow(d_geom)), min(N_GEOM, nrow(d_geom))))

# A grid across the angle parameter, not just the contracted value and one
# contrast. This is the project's only working sensitivity on `ksi`: the appendix
# that section 7X was believed to provide it through never estimates - every row
# it writes is `not_estimated` - so nothing varied the angle until this table.
# The sweep is geometric rather than estimate-based, which is what makes it cheap
# enough to run without a refit: it reports what the kernel averages over at each
# angle, and the consequence for the coefficients follows from that.
ksi_grid <- suppressWarnings(as.numeric(trimws(strsplit(
  Sys.getenv("GTWR_DIAG_KSI_GRID", unset = "0,0.7854,1.5708,2.3562,3.1416"), ","
)[[1]])))
ksi_grid <- ksi_grid[is.finite(ksi_grid)]
if (length(ksi_grid) == 0L) ksi_grid <- c(0, pi / 2)
ksi_grid <- sort(unique(c(as.numeric(cfg$gtwr_ksi), ksi_grid)))
bw_grid <- unique(c(as.numeric(cfg$gtwr_st_bw), 90))
bw_grid <- bw_grid[is.finite(bw_grid) & bw_grid >= 10]

geometry <- purrr::map_dfr(ksi_grid, function(ksi) {
  cols <- lapply(focal_idx, function(i) {
    gtwr_st_dist_column(loc, tv, i, lamda = cfg$gtwr_lamda, ksi = ksi, scales = scales)
  })
  purrr::map_dfr(bw_grid, function(bw) {
    k_bw <- as.integer(bw)
    stat <- purrr::map_dfr(seq_along(focal_idx), function(j) {
      i <- focal_idx[[j]]
      k <- order(cols[[j]])[seq_len(min(k_bw, length(cols[[j]])))]
      same_t <- tv[k] == tv[i]
      same_s <- d_geom$adm_cd[k] == d_geom$adm_cd[i]
      tibble::tibble(
        pure_spatial = mean(same_t & !same_s),
        pure_temporal = mean(same_s & !same_t),
        spatiotemporal = mean(!same_t & !same_s),
        n_dongs = dplyr::n_distinct(d_geom$adm_cd[k]),
        n_quarters = dplyr::n_distinct(tv[k]),
        max_abs_dt = max(abs(tv[k] - tv[i]))
      )
    })
    tibble::tibble(
      control_set = control_set,
      lamda = cfg$gtwr_lamda,
      lamda_convention = as.character(cfg$gtwr_lamda_convention),
      ksi = ksi,
      is_contracted_ksi = isTRUE(all.equal(ksi, as.numeric(cfg$gtwr_ksi))),
      st_bw = bw,
      is_contracted_bw = isTRUE(all.equal(bw, as.numeric(cfg$gtwr_st_bw))),
      n_focal_probed = length(focal_idx),
      share_pure_spatial = mean(stat$pure_spatial),
      share_pure_temporal = mean(stat$pure_temporal),
      share_spatiotemporal = mean(stat$spatiotemporal),
      median_n_dongs = stats::median(stat$n_dongs),
      median_n_quarters = stats::median(stat$n_quarters),
      median_max_abs_dt = stats::median(stat$max_abs_dt),
      note = "shares are of the bandwidth-nearest window; pure_spatial = same quarter, different dong"
    )
  })
})

write_csv_safe(geometry, cfg$get_gtwr_kernel_geometry_path(control_set))


#==============================================================================
# 3. The Reporting Surface Sits at the Temporal Edge
#==============================================================================

# Two independent readings of the same concern. The first measures the support
# directly: how many own-dong time points the window reaches at each focal
# quarter, and how they split around it. The second asks the published betas
# whether the reported quarter's local mean is typical of the other quarters.
bw_edge <- as.integer(cfg$gtwr_st_bw)
quarters <- sort(unique(tv))

edge_support <- purrr::map_dfr(quarters, function(tq) {
  ii <- which(tv == tq)
  ii <- ii[seq_len(min(N_EDGE, length(ii)))]
  own_n <- past_n <- future_n <- numeric(length(ii))
  for (j in seq_along(ii)) {
    i <- ii[[j]]
    col <- gtwr_st_dist_column(loc, tv, i, lamda = cfg$gtwr_lamda, ksi = cfg$gtwr_ksi, scales = scales)
    k <- order(col)[seq_len(min(bw_edge, length(col)))]
    own <- k[d_geom$adm_cd[k] == d_geom$adm_cd[i]]
    own_n[[j]] <- length(own)
    past_n[[j]] <- sum(tv[own] < tq)
    future_n[[j]] <- sum(tv[own] > tq)
  }
  tibble::tibble(
    control_set = control_set,
    time_id = tq,
    yq = as.character(d_geom$yq[ii[[1L]]]),
    st_bw = bw_edge,
    n_focal_probed = length(ii),
    mean_own_dong_points = mean(own_n),
    mean_past_points = mean(past_n),
    mean_future_points = mean(future_n),
    one_sided = mean(future_n) == 0 || mean(past_n) == 0
  )
})

# The published local betas by quarter. The reported surface is the last row.
beta_panel_path <- cfg$get_gtwr_local_beta_panel_path(control_set)
edge_beta <- if (file.exists(beta_panel_path)) {
  bp <- readr::read_csv(beta_panel_path, show_col_types = FALSE) |>
    dplyr::filter(.data$focal_var == FOCAL, is.finite(.data$estimate))
  by_q <- bp |>
    dplyr::group_by(.data$outcome, .data$yq) |>
    dplyr::summarise(mean_beta = mean(.data$estimate), sd_beta = stats::sd(.data$estimate), .groups = "drop") |>
    dplyr::arrange(.data$outcome, .data$yq)
  by_q |>
    dplyr::group_by(.data$outcome) |>
    dplyr::summarise(
      n_quarters = dplyr::n(),
      latest_yq = dplyr::last(.data$yq),
      latest_mean_beta = dplyr::last(.data$mean_beta),
      other_min = min(.data$mean_beta[-dplyr::n()]),
      other_max = max(.data$mean_beta[-dplyr::n()]),
      other_mean = mean(.data$mean_beta[-dplyr::n()]),
      latest_sd_over_other_sd = dplyr::last(.data$sd_beta) / mean(.data$sd_beta[-dplyr::n()]),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      latest_outside_other_range = .data$latest_mean_beta < .data$other_min |
        .data$latest_mean_beta > .data$other_max,
      control_set = control_set,
      focal_var = FOCAL
    )
} else {
  NULL
}

temporal_edge <- list(
  support = edge_support |> dplyr::mutate(measure = "kernel_support"),
  beta = if (is.null(edge_beta)) NULL else edge_beta |> dplyr::mutate(measure = "published_beta_by_quarter")
)
temporal_out <- dplyr::bind_rows(temporal_edge$support, temporal_edge$beta) |>
  dplyr::relocate("measure", .before = 1)

write_csv_safe(temporal_out, cfg$get_gtwr_temporal_edge_path(control_set))


#==============================================================================
# 4. Log
#==============================================================================

n_match_levels <- sum(estimand$sign_matches_levels, na.rm = TRUE)
n_match_within <- sum(estimand$sign_matches_within, na.rm = TRUE)
contracted_geom <- geometry |>
  dplyr::filter(.data$is_contracted_ksi, .data$is_contracted_bw)
share_st <- if (nrow(contracted_geom) > 0L) contracted_geom$share_spatiotemporal[[1L]] else NA_real_
n_outside <- if (is.null(edge_beta)) NA_integer_ else sum(edge_beta$latest_outside_other_range, na.rm = TRUE)

append_log(cfg$logs$data_qc, sprintf(
  paste0("- GTWR estimand diagnostic: published local mean matches the levels sign in %d of %d outcomes and the ",
         "within sign in %d; at the contracted kernel %.1f%% of the window is genuinely spatiotemporal; ",
         "the reported quarter's mean lies outside the other quarters' range for %s outcomes"),
  n_match_levels, nrow(estimand), n_match_within, 100 * share_st,
  if (is.na(n_outside)) "an unmeasured number of" else as.character(n_outside)))

message(sprintf(
  "[DONE] gtwr estimand diagnostic: levels-sign %d/%d, within-sign %d/%d, spatiotemporal share %.1f%%, latest-quarter outlier %s",
  n_match_levels, nrow(estimand), n_match_within, nrow(estimand), 100 * share_st,
  if (is.na(n_outside)) "NA" else sprintf("%d/%d", n_outside, nrow(edge_beta))))
