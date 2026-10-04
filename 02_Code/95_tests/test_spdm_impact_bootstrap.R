#==============================================================================
# Script    : test_spdm_impact_bootstrap.R
# Purpose   : Pin the dong-level bootstrap that carries the main SPDM inference.
#             The weights must be constant within a dong, a failed or thin
#             bootstrap must empty the primary columns rather than fall back to
#             the model-based values, and on a panel whose errors are serially
#             dependent within a dong the bootstrap must report the larger
#             standard error that the model-based one misses.
# Type      : qc
# Inputs    : utils_spdm.R
#==============================================================================

test_context("spdm_unit_rademacher_weights(): one weight per dong")

units <- sprintf("u%02d", 1:12)
rows <- rep(units, each = 7)
wts <- spdm_unit_rademacher_weights(units, rows, seed = 101)
expect_true(all(wts %in% c(-1, 1)), "every weight is -1 or +1")
expect_true(all(tapply(wts, rows, function(v) length(unique(v))) == 1L),
            "the weight is constant across the rows of a dong")
expect_equal_num(spdm_unit_rademacher_weights(units, rows, seed = 101), wts,
                 "the same seed reproduces the same weights")
expect_true(
  inherits(tryCatch(spdm_unit_rademacher_weights(units, c(rows, "zz"), seed = 1),
                    error = function(e) e), "error"),
  "a row outside the unit set is an error"
)


test_context("spdm_bootstrap_status(): disabled, failed, thin, and usable")

expect_true(identical(spdm_bootstrap_status(NULL)$state, "disabled"),
            "NULL means the bootstrap was not run")
expect_true(identical(spdm_bootstrap_status(simpleError("boom"))$state, "failed"),
            "an error condition is a failed bootstrap")
thin <- list(R = 100L, n_valid = 89L, errors = "spml did not converge")
expect_true(identical(spdm_bootstrap_status(thin)$state, "failed"),
            "fewer than 90% valid draws is a failed bootstrap")
expect_true(grepl("spml did not converge", spdm_bootstrap_status(thin)$message),
            "the first draw error is reported")
expect_true(identical(spdm_bootstrap_status(list(R = 100L, n_valid = 90L, errors = character()))$state, "ok"),
            "90% valid draws is usable")


test_context("apply_spdm_bootstrap_to_impacts(): the bootstrap takes the primary columns")

imp_row <- spdm_empty_impacts_tbl() |>
  dplyr::add_row(
    spec_id = "S01", outcome = "y", exposure = "x", focal_var = "x",
    direct = -1, direct_se = 0.1, direct_z = -10, direct_p = 1e-23,
    direct_ci_low = -1.2, direct_ci_high = -0.8,
    indirect = -0.5, indirect_se = 0.2, indirect_z = -2.5, indirect_p = 0.012,
    indirect_ci_low = -0.9, indirect_ci_high = -0.1,
    total = -1.5, total_se = 0.2, total_z = -7.5, total_p = 6e-14,
    total_ci_low = -1.9, total_ci_high = -1.1,
    status = "success", impact_se_method = "simulation_from_model_based_ml_vcov",
    message = "fit ok"
  )

set.seed(5)
draw_mat <- cbind(
  direct = stats::rnorm(200, -1, 0.5),
  indirect = stats::rnorm(200, -0.5, 0.8),
  total = stats::rnorm(200, -1.5, 0.9),
  lambda = stats::rnorm(200, 0.1, 0.05),
  x = stats::rnorm(200, -1, 0.5),
  w_x = stats::rnorm(200, 0.3, 0.6)
)
boot_ok <- list(
  draws = draw_mat, R = 200L, n_valid = 200L, seed = 7L, errors = character(),
  roundtrip_max_deviation = 0, max_design_residual_cor = 0
)

out <- apply_spdm_bootstrap_to_impacts(imp_row, boot_ok)
sd_direct <- stats::sd(draw_mat[, "direct"])
expect_equal_num(out$direct_se, sd_direct, "direct_se is the bootstrap standard deviation")
expect_equal_num(out$direct_p, 2 * stats::pnorm(-abs(-1 / sd_direct)),
                 "direct_p is the normal reading of the bootstrap standard error")
expect_equal_num(out$total_ci_low, stats::quantile(draw_mat[, "total"], 0.025, names = FALSE),
                 "the interval is the bootstrap percentile interval")
expect_equal_num(out$direct, -1, "the point estimate is untouched")
expect_equal_num(out$direct_se_model, 0.1, "the model-based SE moves to direct_se_model")
expect_equal_num(out$indirect_p_model, 0.012, "the model-based p moves to indirect_p_model")
expect_true(identical(out$impact_se_method, "adm_cd_wild_reduced_form_bootstrap"),
            "the row names its inference")
expect_true(identical(out$boot_valid_draws, 200L), "the valid draw count is carried")

out_fail <- apply_spdm_bootstrap_to_impacts(imp_row, simpleError("refit failed"))
expect_true(all(is.na(c(out_fail$direct_se, out_fail$direct_p, out_fail$total_ci_high))),
            "a failed bootstrap empties the primary inference columns")
expect_equal_num(out_fail$direct_se_model, 0.1,
                 "the model-based value survives only in direct_se_model")
expect_true(identical(out_fail$impact_se_method, "adm_cd_wild_reduced_form_bootstrap_failed"),
            "the row says the bootstrap failed")
expect_true(grepl("refit failed", out_fail$message), "the failure reason reaches the message")

out_off <- apply_spdm_bootstrap_to_impacts(imp_row, NULL)
expect_equal_num(out_off$direct_se, 0.1, "with the bootstrap off the primary columns stay model-based")
expect_true(identical(out_off$impact_se_method, "simulation_from_model_based_ml_vcov"),
            "and the row says so")


test_context("apply_spdm_bootstrap_to_coefs(): coefficient standard errors from the draws")

coef_tbl <- spdm_empty_coef_tbl() |>
  dplyr::add_row(
    term = c("lambda", "x", "w_x"),
    estimate = c(0.1, -1, 0.3),
    std.error = c(0.015, 0.1, 0.2),
    statistic = c(6.7, -10, 1.5),
    p.value = c(2e-11, 1e-23, 0.13),
    se_method = "model_based_asymptotic_ml_vcov",
    status = "success"
  )
cout <- apply_spdm_bootstrap_to_coefs(coef_tbl, boot_ok)
expect_equal_num(
  cout$std.error,
  c(stats::sd(draw_mat[, "lambda"]), stats::sd(draw_mat[, "x"]), stats::sd(draw_mat[, "w_x"])),
  "each coefficient SE is the standard deviation of its draws"
)
expect_equal_num(cout$std.error_model, c(0.015, 0.1, 0.2), "model-based SEs move to std.error_model")
expect_true(all(cout$se_method == "adm_cd_wild_reduced_form_bootstrap"), "every row names its inference")


test_context("run_spdm_impact_bootstrap(): serially dependent errors on a real spml fit")

# A 40-dong grid over 20 quarters, generated from a true SDM whose errors follow
# an AR(1) with coefficient 0.9 inside each dong and whose exposure is close to a
# dong-specific trend: the two features of the project panel under which the
# model-based standard error is too small. A Monte Carlo of the non-spatial part
# of this design puts the true standard deviation of the slope at about 2.9 times
# the i.i.d. standard error, so the 1.5 threshold below is not near the edge.
nb_grid <- spdep::cell2nb(5, 8, type = "queen")
grid_ids <- sprintf("u%02d", seq_along(nb_grid))
attr(nb_grid, "region.id") <- grid_ids
lw_grid <- spdep::nb2listw(nb_grid, style = "W")
W_grid <- spdep::listw2mat(lw_grid)

set.seed(42)
n_u <- length(grid_ids)
n_t <- 20L
phi <- 0.9
slope <- stats::rnorm(n_u, sd = 0.1)
X <- outer(slope, seq_len(n_t)) + matrix(stats::rnorm(n_u * n_t, sd = 0.05), n_u, n_t)
E <- matrix(0, n_u, n_t)
E[, 1] <- stats::rnorm(n_u, sd = 1 / sqrt(1 - phi^2))
for (tt in 2:n_t) E[, tt] <- phi * E[, tt - 1] + stats::rnorm(n_u)
alpha <- stats::rnorm(n_u)
tau <- stats::rnorm(n_t)
A_inv <- solve(diag(n_u) - 0.3 * W_grid)
Y <- vapply(seq_len(n_t), function(tt) {
  as.numeric(A_inv %*% (1.0 * X[, tt] + 0.5 * as.numeric(W_grid %*% X[, tt]) + alpha + tau[[tt]] + E[, tt]))
}, numeric(n_u))

# Unit-major rows with the factor levels in region.id order, as prepare_spdm_spec()
# builds them, so the alignment guard and splm's internal sort agree.
pdat_grid <- tibble::tibble(
  adm_cd = factor(rep(grid_ids, each = n_t), levels = grid_ids),
  time_id = rep(seq_len(n_t), times = n_u),
  y = as.numeric(t(Y)),
  x = as.numeric(t(X))
)

fit_grid <- tryCatch(
  fit_spdm_model(pdat_grid, "y", "x", character(), lw_grid, model_family = "sdm"),
  error = function(e) e
)
expect_true(!inherits(fit_grid, "error"), "the fixture SDM fits")

if (!inherits(fit_grid, "error")) {
  prep_grid <- list(mod = fit_grid, pdat = pdat_grid, lw_sub = lw_grid, selected_controls = character())

  boot_a <- run_spdm_impact_bootstrap(prep_grid, "y", "x", R = 8L, seed = 3L, cores = 1L, context = "test")
  boot_b <- run_spdm_impact_bootstrap(prep_grid, "y", "x", R = 8L, seed = 3L, cores = 1L, context = "test")
  expect_true(identical(boot_a$n_valid, 8L), "every draw refits")
  expect_equal_num(boot_b$draws, boot_a$draws, "the same seed reproduces the draws exactly")
  expect_true(all(c("direct", "indirect", "total", "lambda", "x", "w_x") %in% colnames(boot_a$draws)),
              "the draws carry the three impacts and every coefficient")
  expect_true(boot_a$roundtrip_max_deviation < 1e-6, "the resampler round trip is carried with the draws")

  boot_big <- run_spdm_impact_bootstrap(prep_grid, "y", "x", R = 99L, seed = 11L, cores = 1L, context = "test")
  model_se_x <- summary(fit_grid)$CoefTable["x", 2]
  boot_se_x <- stats::sd(boot_big$draws[, "x"])
  expect_true(
    boot_se_x > 1.5 * model_se_x,
    sprintf("with AR(1) errors the bootstrap SE exceeds the model-based SE (%.3f against %.3f)",
            boot_se_x, model_se_x)
  )
}
