#!/usr/bin/env Rscript

#==============================================================================
# Script    : 03_run_exploratory_diagnostics.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Exploratory checks the spatial ESDA does not cover: the shape of
#             the exposure-outcome relationship that every model assumes to be
#             linear, and the quarterly trajectory of each outcome across a
#             window that contains COVID.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-04
# Type      : esda
# Inputs    : panel_main.parquet
# Outputs   : exposure_response_bins.csv, exposure_linearity_tests.csv,
#             outcome_quarterly_trend.csv, outcome_quarterly_trend.png
# DependsOn : 00_setup/config.R, 00_setup/packages.R, 99_utils/utils_io.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

options(scipen = 999)

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
load_project_packages()
source(here::here("02_Code", "99_utils", "utils_io.R"))

ensure_dirs(cfg$required_dirs)
append_log(cfg$logs$model_run, sprintf("\n## [%s] 03_run_exploratory_diagnostics", timestamp()))

OUTCOMES <- c("vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal",
              "vitality_sub_stability", "vitality_index_base")
EXPOSURE <- "lag4_age60_resident_share"

N_BINS <- suppressWarnings(as.integer(Sys.getenv("EDA_EXPOSURE_BINS", unset = "20")))
if (!is.finite(N_BINS) || N_BINS < 5L) N_BINS <- 20L

panel <- read_panel_main_view("twfe")
panel <- panel |> dplyr::mutate(adm_cd = as.character(.data$adm_cd))
have <- intersect(OUTCOMES, names(panel))
if (length(have) == 0L || !EXPOSURE %in% names(panel)) {
  stop("[ERROR] exposure or outcomes missing from the analysis panel", call. = FALSE)
}


#==============================================================================
# 1. Two-Way Within Transform
#==============================================================================

# The models identify from within-dong, within-quarter deviations, so the shape
# of the relationship has to be inspected on that variation. A binned plot of the
# raw levels would mostly trace the cross-sectional gradient between districts,
# which the fixed effects remove before estimation.
vars <- c(EXPOSURE, have)
within <- panel |>
  dplyr::filter(stats::complete.cases(dplyr::pick(dplyr::all_of(vars)))) |>
  dplyr::group_by(.data$adm_cd) |>
  dplyr::mutate(dplyr::across(dplyr::all_of(vars), ~ .x - mean(.x, na.rm = TRUE))) |>
  dplyr::ungroup() |>
  dplyr::group_by(.data$yq) |>
  dplyr::mutate(dplyr::across(dplyr::all_of(vars), ~ .x - mean(.x, na.rm = TRUE))) |>
  dplyr::ungroup()


#==============================================================================
# 2. Binned Exposure-Response
#==============================================================================

# Equal-count bins rather than equal-width, so every point carries comparable
# weight and the tails do not produce bins of two observations.
brks <- stats::quantile(within[[EXPOSURE]], probs = seq(0, 1, length.out = N_BINS + 1L),
                        na.rm = TRUE, type = 7)
brks <- unique(brks)
within$exposure_bin <- cut(within[[EXPOSURE]], breaks = brks, include.lowest = TRUE, labels = FALSE)

bins <- purrr::map_dfr(have, function(oc) {
  within |>
    dplyr::filter(is.finite(.data$exposure_bin)) |>
    dplyr::group_by(bin = .data$exposure_bin) |>
    dplyr::summarise(
      outcome = oc,
      n = dplyr::n(),
      exposure_mean_within = mean(.data[[EXPOSURE]], na.rm = TRUE),
      outcome_mean_within = mean(.data[[oc]], na.rm = TRUE),
      outcome_se_within = stats::sd(.data[[oc]], na.rm = TRUE) / sqrt(dplyr::n()),
      .groups = "drop"
    ) |>
    dplyr::relocate("outcome", .before = "bin")
})

write_csv_safe(bins, cfg$paths$exposure_response_bins)


#==============================================================================
# 3. Linearity Tests
#==============================================================================

# Two complementary checks against the linear specification the models use.
# Quadratic: add a squared exposure term and test it, which detects curvature but
# only of that one shape.
# Lack of fit: add the bin dummies on top of the linear term, which detects any
# departure the bins can resolve without assuming its form.
lin_tests <- purrr::map_dfr(have, function(oc) {
  d <- within |> dplyr::filter(is.finite(.data[[oc]]), is.finite(.data[[EXPOSURE]]))
  x <- d[[EXPOSURE]]; y <- d[[oc]]

  m_lin <- stats::lm(y ~ x)
  m_quad <- stats::lm(y ~ x + I(x^2))
  a_quad <- stats::anova(m_lin, m_quad)

  quad_p <- a_quad[["Pr(>F)"]][2]
  quad_coef <- unname(stats::coef(m_quad)[["I(x^2)"]])

  # The F-tests above assume independent errors. This panel does not have them:
  # the within-dong residual AR(1) reported by the TWFE diagnostics runs between
  # 0.61 and 0.81, so an OLS F-test on 10,000-odd rows treats far more
  # information as independent than the panel contains, and over-rejects. Every
  # inferential statement elsewhere in this project clusters on `adm_cd`, so the
  # same test is repeated under that contract and reported beside the OLS result
  # rather than replacing it. The two disagree on this panel, and the clustered
  # column is the one to read.
  dd <- d
  dd$.y <- y
  dd$.x <- x
  dd$.x2 <- x^2
  quad_p_cl <- tryCatch({
    mq <- fixest::feols(.y ~ .x + .x2, data = dd, cluster = ~adm_cd, notes = FALSE)
    unname(fixest::coeftable(mq)[".x2", "Pr(>|t|)"])
  }, error = function(e) NA_real_)

  # Lack-of-fit test. The comparison must be nested, so the bin dummies are added
  # *to* the linear term rather than substituted for it: `y ~ x` against
  # `y ~ x + factor(bin)` asks whether the binned means depart from the fitted
  # line. Comparing `y ~ x` with `y ~ factor(bin)` directly is not a valid F test,
  # because a coarsening of x does not span the linear term.
  bin_p <- NA_real_; bin_df <- NA_integer_; bin_p_cl <- NA_real_
  if (any(is.finite(d$exposure_bin)) && dplyr::n_distinct(d$exposure_bin) > 2L) {
    bin_f <- factor(d$exposure_bin)
    m_bin <- stats::lm(y ~ x + bin_f)
    a_bin <- tryCatch(stats::anova(m_lin, m_bin), error = function(e) NULL)
    if (!is.null(a_bin) && nrow(a_bin) >= 2L) {
      bin_p <- a_bin[["Pr(>F)"]][2]
      bin_df <- a_bin[["Df"]][2]
    }
    # Same lack-of-fit hypothesis, tested as a joint Wald on the bin dummies with
    # dong-clustered standard errors.
    dd$.bin <- bin_f
    bin_p_cl <- tryCatch({
      mb <- fixest::feols(.y ~ .x + .bin, data = dd, cluster = ~adm_cd, notes = FALSE)
      unname(fixest::wald(mb, ".bin", print = FALSE)$p)
    }, error = function(e) NA_real_)
  }

  tibble::tibble(
    outcome = oc, n = nrow(d), n_bins = dplyr::n_distinct(d$exposure_bin),
    n_clusters = dplyr::n_distinct(d$adm_cd),
    linear_slope = unname(stats::coef(m_lin)[["x"]]),
    quadratic_coef = quad_coef,
    quadratic_p_ols = quad_p,
    quadratic_p_clustered = quad_p_cl,
    # NA rather than FALSE when the clustered fit failed. `is.finite(NA) && ...`
    # is FALSE, which would read as "linearity is not rejected" -- the permissive
    # conclusion -- from a test that never ran. These columns are the primary
    # ones now, so they must fail loudly rather than quietly agreeable.
    quadratic_rejects_linearity = if (is.finite(quad_p_cl)) quad_p_cl < 0.05 else NA,
    quadratic_rejects_linearity_ols = is.finite(quad_p) && quad_p < 0.05,
    lack_of_fit_df = bin_df,
    lack_of_fit_p_ols = bin_p,
    lack_of_fit_p_clustered = bin_p_cl,
    lack_of_fit_rejects_linearity = if (is.finite(bin_p_cl)) bin_p_cl < 0.05 else NA,
    lack_of_fit_rejects_linearity_ols = is.finite(bin_p) && bin_p < 0.05,
    inference = "primary: dong-clustered; *_ols columns assume independent errors and over-reject on this panel",
    note = "two-way within transform; equal-count exposure bins; lack-of-fit is y~x vs y~x+factor(bin)"
  )
})

write_csv_safe(lin_tests, cfg$paths$exposure_linearity_tests)


#==============================================================================
# 4. Quarterly Outcome Trends
#==============================================================================

# A 25-quarter window that contains the COVID shock deserves more than one sales
# trend figure. Reported on the untransformed outcomes, because the point is to
# see the common time pattern that the quarter fixed effects later absorb.
trend <- purrr::map_dfr(have, function(oc) {
  panel |>
    dplyr::filter(is.finite(.data[[oc]])) |>
    dplyr::group_by(.data$yq) |>
    dplyr::summarise(
      outcome = oc,
      n = dplyr::n(),
      mean = mean(.data[[oc]], na.rm = TRUE),
      median = stats::median(.data[[oc]], na.rm = TRUE),
      p10 = stats::quantile(.data[[oc]], 0.10, na.rm = TRUE),
      p90 = stats::quantile(.data[[oc]], 0.90, na.rm = TRUE),
      sd = stats::sd(.data[[oc]], na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::relocate("outcome", .before = "yq")
})

# covid_period marks 2020Q1~2022Q2 in the panel contract; carry the flag so the
# table can be read against the shock without re-deriving the window.
if ("covid_period" %in% names(panel)) {
  covid_map <- panel |>
    dplyr::distinct(.data$yq, .data$covid_period) |>
    dplyr::group_by(.data$yq) |>
    dplyr::summarise(covid_period = max(.data$covid_period, na.rm = TRUE), .groups = "drop")
  trend <- trend |> dplyr::left_join(covid_map, by = "yq")
}

write_csv_safe(trend, cfg$paths$outcome_quarterly_trend)

trend_plot <- ggplot2::ggplot(trend, ggplot2::aes(x = .data$yq, y = .data$mean, group = .data$outcome)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$p10, ymax = .data$p90), alpha = 0.15) +
  ggplot2::geom_line(linewidth = 0.6) +
  ggplot2::facet_wrap(~ outcome, scales = "free_y") +
  ggplot2::labs(
    title = "Quarterly outcome trajectories, active analysis window",
    subtitle = "Line: cross-sectional mean. Band: p10-p90 across administrative dongs.",
    x = NULL, y = NULL
  ) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, vjust = 0.5, size = 5))

ggplot2::ggsave(cfg$paths$outcome_quarterly_trend_plot, trend_plot,
                width = 10, height = 6, dpi = 200)


#==============================================================================
# 5. Log
#==============================================================================

n_reject <- sum(lin_tests$quadratic_rejects_linearity | lin_tests$lack_of_fit_rejects_linearity, na.rm = TRUE)
append_log(cfg$logs$data_qc, sprintf(
  "- Exploratory diagnostics: %d outcomes, %d exposure bins; linearity rejected for %d of %d outcomes",
  length(have), N_BINS, n_reject, length(have)))

message(sprintf("[DONE] exploratory diagnostics: linearity rejected for %d of %d outcomes",
                n_reject, length(have)))
