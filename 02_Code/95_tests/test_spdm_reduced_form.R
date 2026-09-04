#==============================================================================
# Script    : test_spdm_reduced_form.R
# Purpose   : Pin the reduced-form resampler used by the channel-path bootstrap.
#             The previous scheme built y* as `fitted + residual * weight` on an
#             splm object whose `fitted.values` slot is not a fitted value of the
#             outcome in any scale, and splm defines no `fitted` method, so the
#             substitution was silent. These tests fix both the algebra and the
#             round-trip guard that makes such a substitution impossible to ship.
# Type      : qc
# Inputs    : utils_spdm.R
#==============================================================================

test_context("spdm_within_transform(): two-way demeaning")

set.seed(4)
unit <- rep(letters[1:5], each = 6)
period <- rep(1:6, times = 5)
v <- stats::rnorm(30, mean = 3)

vd <- spdm_within_transform(v, unit, period)
expect_true(abs(mean(vd)) < 1e-12, "the transformed vector has mean zero")
expect_true(max(abs(tapply(vd, unit, mean))) < 1e-12, "every unit mean is zero")
expect_true(max(abs(tapply(vd, period, mean))) < 1e-12, "every period mean is zero")

# Idempotence. The estimator demeans again on refit, so a resampled outcome
# already on the within scale must survive a second pass unchanged.
expect_equal_num(spdm_within_transform(vd, unit, period), vd,
                 "the within transform is idempotent")

# Adding any unit-level or period-level shift changes nothing.
shift <- as.numeric(factor(unit)) * 10 + period * 3
expect_equal_num(spdm_within_transform(v + shift, unit, period), vd,
                 "unit and period shifts are absorbed")


test_context("spdm_apply_w_by_period() and the spatial multiplier")

# Row-standardised W on a 3-unit ring, repeated over 4 periods.
W <- matrix(c(0, 0.5, 0.5, 0.5, 0, 0.5, 0.5, 0.5, 0), 3, 3, byrow = TRUE)
per <- rep(1:4, each = 3)
x <- c(1, 2, 3, 10, 20, 30, 0, 0, 1, -1, 1, -1)

wx <- spdm_apply_w_by_period(x, per, W)
expect_equal_num(wx[1:3], as.numeric(W %*% x[1:3]), "period 1 is multiplied by W alone")
expect_equal_num(wx[10:12], as.numeric(W %*% x[10:12]), "period 4 is multiplied by W alone")
expect_true(max(abs(wx[1:3] - W %*% c(1, 2, 3))) < 1e-12, "no leakage across periods")

# (I - rho W)^-1 must invert (I - rho W) exactly, period by period.
for (rho in c(-0.4, 0, 0.25, 0.6)) {
  back <- spdm_solve_multiplier_by_period(x - rho * spdm_apply_w_by_period(x, per, W), per, W, rho)
  expect_equal_num(back, x, sprintf("the multiplier inverts (I - rho W) at rho = %.2f", rho))
}


test_context("reduced-form algebra: a resample must reproduce its own data")

# A small SDM built by hand, so the target is known rather than snapshotted.
#   y = rho W y + Z gamma + e
n_u <- 3; n_t <- 5
per2 <- rep(seq_len(n_t), each = n_u)
unit2 <- rep(letters[1:n_u], times = n_t)
set.seed(9)
z <- stats::rnorm(n_u * n_t)
gamma <- 1.7
rho <- 0.35
e <- stats::rnorm(n_u * n_t, sd = 0.4)
y <- spdm_solve_multiplier_by_period(z * gamma + e, per2, W, rho)

# The residual recovered from the structural form must be the one generating y.
e_hat <- (y - rho * spdm_apply_w_by_period(y, per2, W)) - z * gamma
expect_equal_num(e_hat, e, "the structural residual is recovered exactly")

# Unit weights must return the original outcome: this is the round-trip the
# resampler asserts before it will produce a standard error.
y_back <- spdm_solve_multiplier_by_period(z * gamma + e_hat * rep(1, length(e_hat)), per2, W, rho)
expect_equal_num(y_back, y, "unit weights reproduce the outcome exactly")

# A sign flip must move the outcome, and must move it through the multiplier:
# holding W y fixed would give a different vector.
w_flip <- rep(c(1, -1, 1), times = n_t)
y_star <- spdm_solve_multiplier_by_period(z * gamma + e_hat * w_flip, per2, W, rho)
naive <- (y - e_hat) + e_hat * w_flip   # the discarded scheme: W y pinned at the original y
expect_true(max(abs(y_star - y)) > 1e-8, "a sign flip actually perturbs the outcome")
expect_true(
  max(abs(y_star - naive)) > 1e-8,
  "the reduced form differs from pinning W y at its original value"
)

# At rho = 0 there is no feedback, so the two schemes must agree. This is the
# check that the difference above is the multiplier and not an algebra slip.
y0 <- spdm_solve_multiplier_by_period(z * gamma + e, per2, W, 0)
e0 <- (y0 - 0 * spdm_apply_w_by_period(y0, per2, W)) - z * gamma
expect_equal_num(
  spdm_solve_multiplier_by_period(z * gamma + e0 * w_flip, per2, W, 0),
  (y0 - e0) + e0 * w_flip,
  "at rho = 0 the reduced form and the naive scheme coincide"
)


test_context("the round-trip guard rejects a non-fitted vector")

# The failure that shipped: a vector that is not a fitted value passes silently
# through `fitted + residual`. Reconstructing from it cannot return the outcome,
# which is exactly what the guard tests.
bogus_fitted <- stats::rnorm(length(y))
bogus_resid <- y - bogus_fitted
expect_true(
  max(abs((bogus_fitted + bogus_resid) - y)) < 1e-12,
  "any vector plus its complement trivially reproduces y, so that alone is no check"
)
# The real check is whether the model's own coefficients regenerate the outcome.
wrong_gamma <- gamma * 1.5
y_wrong <- spdm_solve_multiplier_by_period(z * wrong_gamma + e_hat, per2, W, rho)
expect_true(
  max(abs(y_wrong - y)) > 1e-6 * stats::sd(y),
  "a wrong coefficient fails the reduced-form round trip"
)


test_context("build_spdm_reduced_form_resampler(): the closure itself")

# A minimal stand-in for a fitted splm object. stats::coef() reads $coefficients,
# which is all the resampler needs beyond the data and the weights.
make_fake_fit <- function(coefs) structure(list(coefficients = coefs), class = "fake_splm")

n_u <- 3; n_t <- 5
Wr <- matrix(c(0, 0.5, 0.5, 0.5, 0, 0.5, 0.5, 0.5, 0), 3, 3, byrow = TRUE)
lw_fixture <- spdep::mat2listw(Wr, style = "W")
attr(lw_fixture$neighbours, "region.id") <- letters[1:n_u]

set.seed(21)
per3 <- rep(seq_len(n_t), each = n_u)
unit3 <- rep(letters[1:n_u], times = n_t)
zx <- stats::rnorm(n_u * n_t)
zc <- stats::rnorm(n_u * n_t)
rho3 <- 0.3
g <- c(x = 1.4, ctrl = -0.8)
ee <- stats::rnorm(n_u * n_t, sd = 0.5)

# Generate on the within scale so the resampler's own transform is a no-op there.
zx_d <- spdm_within_transform(zx, unit3, per3)
zc_d <- spdm_within_transform(zc, unit3, per3)
ee_d <- spdm_within_transform(ee, unit3, per3)

# A maximum-likelihood fit leaves the structural residual orthogonal to the
# design, so the fixture has to as well: drawing an independent error and calling
# it a fitted residual would fail the orthogonality guard purely on the sample
# correlation of a fifteen-row toy panel. Residualising makes the fixture a
# faithful stand-in for a converged fit rather than a lucky draw.
ee_d <- stats::residuals(stats::lm(ee_d ~ zx_d + zc_d))
y_d <- spdm_solve_multiplier_by_period(zx_d * g[["x"]] + zc_d * g[["ctrl"]] + ee_d, per3, Wr, rho3)

pdat_fix <- data.frame(
  adm_cd = unit3, time_id = per3,
  yv = y_d, x = zx_d, ctrl = zc_d,
  stringsAsFactors = FALSE
)
fit_fix <- make_fake_fit(c(lambda = rho3, x = g[["x"]], ctrl = g[["ctrl"]]))

rs <- build_spdm_reduced_form_resampler(fit_fix, pdat_fix, "yv", c("x", "ctrl"), lw_fixture, "test")
expect_true(rs$roundtrip_max_deviation < 1e-9, "the resampler round-trips at construction")
expect_equal_num(rs$rho, rho3, "the spatial parameter is read from the fit")

# Unit weights return the outcome; this is the property the guard enforces.
expect_equal_num(rs$resample(rep(1, nrow(pdat_fix))), rs$y_within,
                 "resample() at unit weights returns the observed within outcome")

# A sign flip must differ from pinning W y at the original outcome. This is the
# defect that shipped: `fitted + residual * w` keeps the spatial feedback frozen.
wf <- rep(c(1, -1, 1), times = n_t)
got <- rs$resample(wf)
pinned <- (rs$y_within - rs$e_hat) + rs$e_hat * wf
expect_true(max(abs(got - rs$y_within)) > 1e-8, "a sign flip perturbs the outcome")
expect_true(max(abs(got - pinned)) > 1e-8,
            "the reduced form differs from holding W y at its original value")

# The gap must be exactly the multiplier acting on the perturbation.
delta_e <- rs$e_hat * (wf - 1)
expect_equal_num(got - rs$y_within,
                 spdm_solve_multiplier_by_period(delta_e, rs$period, rs$W, rs$rho),
                 "the resample moves by (I - rho W)^-1 applied to the residual change")

# Overriding a design column has to change the systematic part, which the
# mediation draw depends on: the outcome equation must see the resampled mediator.
ov <- rs$resample(rep(1, nrow(pdat_fix)), override = list(ctrl = zc_d * 2))
expect_true(max(abs(ov - rs$y_within)) > 1e-8, "an override changes the drawn outcome")
expect_equal_num(ov - rs$y_within,
                 spdm_solve_multiplier_by_period(zc_d * g[["ctrl"]], rs$period, rs$W, rs$rho),
                 "the override enters through gamma and the multiplier")

expect_true(
  inherits(tryCatch(rs$resample(rep(1, nrow(pdat_fix)), override = list(absent = zc_d)),
                    error = function(e) e), "error"),
  "overriding a column that is not in the design is an error"
)


test_context("the guard refuses a fit that cannot regenerate its outcome")

# The round trip alone cannot catch a wrong coefficient: e_hat is defined as the
# residual and absorbs whatever gamma leaves behind, so the reconstruction is
# self-consistent by construction. That is why orthogonality is checked as well.
bad_fit <- make_fake_fit(c(lambda = rho3, x = g[["x"]] * 3, ctrl = g[["ctrl"]]))
err <- tryCatch(
  build_spdm_reduced_form_resampler(bad_fit, pdat_fix, "yv", c("x", "ctrl"), lw_fixture, "test-bad"),
  error = function(e) e
)
expect_true(inherits(err, "error"), "coefficients that do not belong to the design are refused")
expect_true(grepl("not orthogonal to the design", err$message),
            "the refusal names the orthogonality check")

# And a correct fit must pass it comfortably rather than sit at the threshold.
expect_true(rs$max_design_residual_cor < 1e-8,
            "a correct fit leaves the residual orthogonal to the design")

missing_rho <- make_fake_fit(c(x = g[["x"]], ctrl = g[["ctrl"]]))
expect_true(
  inherits(tryCatch(build_spdm_reduced_form_resampler(missing_rho, pdat_fix, "yv",
                                                      c("x", "ctrl"), lw_fixture, "test-norho"),
                    error = function(e) e), "error"),
  "a fit without a spatial lag parameter is refused"
)
