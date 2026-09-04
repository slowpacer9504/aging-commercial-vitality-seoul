#==============================================================================
# Script    : test_gtwr_st_distance.R
# Purpose   : Regression tests for the project-built GTWR spatiotemporal distance.
#             The suite exists because GWmodel::ti.distv() compares observation
#             times with as.character(), so for integer period ids "25" >= "3" is
#             FALSE and genuinely past quarters were assigned a 1e50 "future"
#             sentinel. build_gtwr_st_dmat() replaces that with the symmetric
#             |t_i - t_j| of Huang et al. (2010); these tests pin that behaviour.
# Type      : qc
# Inputs    : utils_gtwr_main.R
#==============================================================================

test_context("gtwr_st_scales(): distances are normalised by their own span")

loc_fixture <- list(dmat = matrix(c(0, 300, 1200, 300, 0, 900, 1200, 900, 0), 3, 3))

s <- gtwr_st_scales(loc_fixture, time_ids = c(1, 5, 25))
expect_equal_num(s$s, 1200, "spatial scale is the maximum observed distance")
expect_equal_num(s$t, 24, "temporal scale is the observed span (max - min)")

# A degenerate input must not divide by zero.
s0 <- gtwr_st_scales(list(dmat = matrix(0, 2, 2)), time_ids = c(7, 7))
expect_equal_num(s0$s, 1, "zero spatial spread falls back to scale 1")
expect_equal_num(s0$t, 1, "zero temporal spread falls back to scale 1")


test_context("gtwr_st_combine(): Huang et al. (2010) combination")

scales <- list(s = 1000, t = 10)

# With ksi = 0 the interaction term enters at full weight and the expression
# collapses to a perfect square:
#   lam*ds + (1-lam)*dt + 2*sqrt(lam*(1-lam)*ds*dt) = (sqrt(lam*ds) + sqrt((1-lam)*dt))^2
ds <- c(0, 250, 500, 1000)
dt <- c(0, 2, 5, 10)
for (lam in c(0.1, 0.5, 0.9)) {
  got <- gtwr_st_combine(ds, dt, lamda = lam, ksi = 0, scales = scales)
  want <- (sqrt(lam * (ds / scales$s)) + sqrt((1 - lam) * (dt / scales$t)))^2
  expect_equal_num(got, want, sprintf("ksi=0 collapses to a perfect square at lamda=%.1f", lam))
}

# Boundary values of the dimensionless lamda.
expect_equal_num(
  gtwr_st_combine(ds, dt, lamda = 1, ksi = 0, scales = scales),
  ds / scales$s,
  "lamda=1 is purely spatial on the normalised scale"
)
expect_equal_num(
  gtwr_st_combine(ds, dt, lamda = 0, ksi = 0, scales = scales),
  dt / scales$t,
  "lamda=0 is purely temporal on the normalised scale"
)

expect_equal_num(
  gtwr_st_combine(0, 0, lamda = 0.5, ksi = 0, scales = scales), 0,
  "zero space and zero time gives zero distance"
)
expect_true(
  all(gtwr_st_combine(ds, dt, lamda = 0.5, ksi = 0, scales = scales) >= 0),
  "combined distance is non-negative"
)

# The normalisation is what makes lamda dimensionless: doubling the spatial units
# while doubling the scale must leave the combined distance unchanged.
expect_equal_num(
  gtwr_st_combine(ds, dt, 0.5, 0, list(s = 1000, t = 10)),
  gtwr_st_combine(ds * 2, dt, 0.5, 0, list(s = 2000, t = 10)),
  "combined distance is invariant to the spatial unit"
)


test_context("build_gtwr_st_dmat(): symmetric time distance (ti.distv regression)")

# Two dongs, thirteen quarters each, with integer period ids that span the
# one-digit / two-digit boundary where the legacy string comparison failed.
d_fit <- data.frame(
  adm_cd = rep(c("A", "B"), each = 13L),
  x = rep(c(0, 3000), each = 13L),
  y = rep(c(0, 4000), each = 13L),
  time_id = rep(c(1:9, 10L, 25L, 3L, 7L), times = 2L),
  stringsAsFactors = FALSE
)

dm <- build_gtwr_st_dmat(d_fit, lamda = 0.5, ksi = 0)

expect_true(is.matrix(dm) && all(dim(dm) == nrow(d_fit)),
            "returns a square matrix matching the fit sample")
expect_true(all(is.finite(dm)), "every entry is finite")
expect_true(max(dm) < 1e6,
            "no 1e50 sentinel survives (the ti.distv defect would blow this up)")
expect_equal_num(diag(dm), rep(0, nrow(d_fit)),
                 "distance from an observation to itself is zero")
expect_true(max(abs(dm - t(dm))) < 1e-9, "matrix is symmetric")

# The specific case the string comparison got wrong: "25" >= "3" is FALSE, so a
# focal observation at quarter 25 treated quarter 3 as being in the future.
i25 <- which(d_fit$time_id == 25L & d_fit$adm_cd == "A")[[1]]
i3 <- which(d_fit$time_id == 3L & d_fit$adm_cd == "A")[[1]]
i7 <- which(d_fit$time_id == 7L & d_fit$adm_cd == "A")[[1]]

expect_equal_num(dm[i25, i3], dm[i3, i25],
                 "d(t=25, t=3) equals d(t=3, t=25)")
expect_true(is.finite(dm[i25, i3]) && dm[i25, i3] < 1e6,
            "quarter 3 is a finite distance from quarter 25, not a future sentinel")
expect_true(dm[i25, i3] > dm[i25, i7],
            "a larger time gap gives a larger distance (25-3 exceeds 25-7)")

# Same location, so the spatial term is zero and the value is purely temporal.
expect_equal_num(
  dm[i25, i3],
  gtwr_st_combine(0, abs(25 - 3), 0.5, 0, gtwr_st_scales(list(dmat = as.matrix(stats::dist(cbind(c(0, 3000), c(0, 4000))))), d_fit$time_id)),
  "same-dong distance matches the temporal term alone"
)

# Monotonicity in the time gap for a fixed location.
idxA <- which(d_fit$adm_cd == "A")
focal <- which(d_fit$time_id == 1L & d_fit$adm_cd == "A")[[1]]
gaps <- abs(d_fit$time_id[idxA] - 1L)
vals <- dm[focal, idxA]
expect_true(all(diff(vals[order(gaps)]) >= -1e-9),
            "distance is non-decreasing in the time gap at a fixed location")


test_context("require_gtwr_st_dmat(): refuses to let GWmodel rebuild the matrix")

expect_true(
  inherits(tryCatch(require_gtwr_st_dmat(NULL, 26L, "unit test"), error = function(e) e), "error"),
  "a NULL distance matrix is rejected"
)
expect_true(
  inherits(tryCatch(require_gtwr_st_dmat(matrix(0, 3, 3), 26L, "unit test"), error = function(e) e), "error"),
  "a wrongly sized distance matrix is rejected"
)
expect_true(
  !inherits(tryCatch(require_gtwr_st_dmat(dm, nrow(d_fit), "unit test"), error = function(e) e), "error"),
  "a correctly sized distance matrix is accepted"
)
