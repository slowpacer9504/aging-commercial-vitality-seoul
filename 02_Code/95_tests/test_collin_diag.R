#==============================================================================
# Script    : test_collin_diag.R
# Purpose   : Regression tests for weighted_design_collin_diag(), which produces
#             the three local collinearity measures reported with GTWR results:
#             local_vif_max (the operative criterion, threshold 10),
#             local_cn_centered, and the uncentered local_cn_gtwr.
# Type      : qc
# Inputs    : utils_gtwr_main.R
#==============================================================================

test_context("weighted_design_collin_diag(): variance inflation factors")

set.seed(20260904L)
n <- 400L

# --- 1. Orthogonal predictors have no variance inflation ---------------------
X_orth <- cbind(`(Intercept)` = 1, a = rep(c(-1, 1), each = n / 2),
                b = rep(c(-1, 1, 1, -1), times = n / 4))
expect_equal_num(sum(X_orth[, "a"] * X_orth[, "b"]), 0, "fixture columns are orthogonal")

d <- weighted_design_collin_diag(X_orth, weights = rep(1, n))
expect_equal_num(d$vif_max, 1, "orthogonal predictors give VIF = 1", tol = 1e-8)
expect_true(d$vif_max < cfg$gtwr_local_vif_warn_threshold,
            "orthogonal design is below the warning threshold")

# --- 2. VIF matches the closed form 1/(1 - r^2) ------------------------------
# Two predictors with a known weighted correlation must reproduce the textbook
# value exactly; this is what makes local_vif_max interpretable against the
# conventional cut-off of 10.
for (r in c(0.5, 0.9, 0.99)) {
  z1 <- stats::rnorm(n)
  z2 <- stats::rnorm(n)
  x1 <- z1
  x2 <- r * z1 + sqrt(1 - r^2) * z2
  X <- cbind(`(Intercept)` = 1, x1 = x1, x2 = x2)
  dd <- weighted_design_collin_diag(X, weights = rep(1, n))
  emp_r <- stats::cov.wt(cbind(x1, x2), wt = rep(1 / n, n), cor = TRUE)$cor[1, 2]
  expect_equal_num(dd$vif_max, 1 / (1 - emp_r^2),
                   sprintf("VIF equals 1/(1-r^2) at r ~ %.2f", r), tol = 1e-6)
}

# --- 3. Exact collinearity is reported, not silently swallowed ---------------
X_dep <- cbind(`(Intercept)` = 1, u = stats::rnorm(n))
X_dep <- cbind(X_dep, v = X_dep[, "u"] * 2)
d_dep <- weighted_design_collin_diag(X_dep, weights = rep(1, n))
expect_true(is.infinite(d_dep$vif_max) || d_dep$vif_max > 1e6,
            "perfectly collinear predictors give an infinite or huge VIF")

# --- 4. A single predictor has no collinearity to measure --------------------
d_one <- weighted_design_collin_diag(cbind(`(Intercept)` = 1, q = stats::rnorm(n)), rep(1, n))
expect_true(is.na(d_one$vif_max), "a single predictor yields NA vif_max")
expect_true(is.finite(d_one$cn_uncentered), "the uncentered condition number is still computed")


test_context("weighted_design_collin_diag(): centred vs uncentred condition number")

# The design documents state that on this panel the uncentered measure runs an
# order of magnitude above the centered one because the local intercept is nearly
# dependent with large-mean log controls. Reproduce that structure directly: two
# well-conditioned predictors whose means are large, as ln_resident_pop (~9.9) and
# ln_land_price_adjusted (~15.0) are.
x1 <- 9.9 + stats::rnorm(n, sd = 0.13)
x2 <- 15.0 + stats::rnorm(n, sd = 0.15)
X_big_mean <- cbind(`(Intercept)` = 1, x1 = x1, x2 = x2)
d_big <- weighted_design_collin_diag(X_big_mean, weights = rep(1, n))

expect_true(d_big$vif_max < 2,
            "large-mean but uncorrelated controls have low VIF")
expect_true(d_big$cn_centered < 10,
            "the centered condition number stays small")
expect_true(d_big$cn_uncentered > 10 * d_big$cn_centered,
            "the uncentered condition number is an order of magnitude larger")

# The measures condition on different things, which is why the project reports a
# threshold only for VIF.
expect_true(d_big$cn_uncentered > d_big$cn_centered,
            "uncentered >= centered for an intercept-bearing design")


test_context("weighted_design_collin_diag(): weight handling")

w <- stats::runif(n, 0, 1)
w[seq_len(50)] <- 0  # zero-weight rows, as a compact-support bisquare kernel produces

X <- cbind(`(Intercept)` = 1, p = stats::rnorm(n), q = stats::rnorm(n))

d_zero_kept <- weighted_design_collin_diag(X, weights = w)
d_dropped <- weighted_design_collin_diag(X[w > 0, , drop = FALSE], weights = w[w > 0])

# Dropping zero-weight rows is claimed to be exact for every kernel. If that ever
# stops holding, the bisquare fast path silently changes the reported diagnostics.
expect_equal_num(d_zero_kept$vif_max, d_dropped$vif_max,
                 "dropping zero-weight rows leaves vif_max unchanged", tol = 1e-9)
expect_equal_num(d_zero_kept$cn_centered, d_dropped$cn_centered,
                 "dropping zero-weight rows leaves cn_centered unchanged", tol = 1e-9)
expect_equal_num(d_zero_kept$cn_uncentered, d_dropped$cn_uncentered,
                 "dropping zero-weight rows leaves cn_uncentered unchanged", tol = 1e-9)

# Unequal weights must actually matter, otherwise the local diagnostics would be
# global ones in disguise.
w_tilt <- c(rep(1, n / 2), rep(0.01, n / 2))
d_flat <- weighted_design_collin_diag(X, weights = rep(1, n))
d_tilt <- weighted_design_collin_diag(X, weights = w_tilt)
expect_true(abs(d_flat$vif_max - d_tilt$vif_max) > 1e-6,
            "weights change the diagnostic (it is genuinely local)")


test_context("weighted_design_collin_diag(): degenerate inputs return NA, not errors")

na_out <- function(x) all(vapply(x, is.na, logical(1)))

expect_true(na_out(weighted_design_collin_diag(NULL, numeric(0))),
            "NULL design returns all-NA")
expect_true(na_out(weighted_design_collin_diag(matrix(numeric(0), 0, 0), numeric(0))),
            "empty design returns all-NA")
expect_true(na_out(weighted_design_collin_diag(X, weights = rep(1, 3))),
            "mismatched weight length returns all-NA")
expect_true(na_out(weighted_design_collin_diag(X, weights = rep(0, n))),
            "all-zero weights return all-NA")
