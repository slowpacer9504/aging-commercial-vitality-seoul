#==============================================================================
# Script    : test_gtwr_local_inference.R
# Purpose   : Pin the extraction of GTWR local standard errors and t-values.
#             GWmodel::gtwr() returns `<var>_SE` and `<var>_TV` for every
#             estimation point; the project read only the coefficient, which left
#             the local surface with no way to separate a varying relationship
#             from the sampling noise of many small local fits. These tests fix
#             the contract so that a silent return to coefficient-only output is
#             caught rather than shipped.
# Type      : qc
# Inputs    : utils_gtwr_main.R
#==============================================================================

test_context("extract_gtwr_local_inference(): reads the SDF inference columns")

FOC <- "aging"
sdf <- data.frame(
  Intercept = c(1, 2, 3, 4),
  aging = c(-2, 0.5, -1, 3),
  aging_SE = c(0.5, 2, 0.25, 1),
  aging_TV = c(-4, 0.25, -4, 3)
)

got <- extract_gtwr_local_inference(sdf, FOC, edf = 1000)
expect_equal_num(got$se, sdf$aging_SE, "the standard error column is read verbatim")
expect_equal_num(got$t, sdf$aging_TV, "the t-value column is read verbatim")
expect_true(identical(got$source, "gwmodel_sdf"), "a usable edf selects the t reference")

# Two-sided p-value on the reported effective residual degrees of freedom.
expect_equal_num(
  got$p,
  2 * stats::pt(-abs(sdf$aging_TV), df = 1000),
  "p-values are two-sided on the effective residual degrees of freedom"
)

# The p-value must be monotone in |t|: the largest |t| carries the smallest p.
expect_true(
  which.min(got$p) %in% which(abs(got$t) == max(abs(got$t))),
  "the largest |t| yields the smallest p-value"
)


test_context("extract_gtwr_local_inference(): degenerate and missing inputs")

# GWmodel reports no usable edf: fall back to a normal reference and say so,
# rather than silently emitting NA p-values for an otherwise complete fit.
norm_ref <- extract_gtwr_local_inference(sdf, FOC, edf = NA_real_)
expect_equal_num(
  norm_ref$p,
  2 * stats::pnorm(-abs(sdf$aging_TV)),
  "a missing edf falls back to the normal reference"
)
expect_true(
  identical(norm_ref$source, "gwmodel_sdf_normal_reference"),
  "the normal fallback is recorded in the inference source"
)

# With thousands of residual degrees of freedom the two references agree, so the
# fallback is not a material change to any published number.
big_df <- extract_gtwr_local_inference(sdf, FOC, edf = 5000)
expect_true(
  max(abs(big_df$p - norm_ref$p)) < 1e-3,
  "t and normal references agree to 1e-3 at realistic residual degrees of freedom"
)

# A future GWmodel that stops returning the columns must degrade to NA with a
# named reason, never to a silent zero or a recycled coefficient.
absent <- extract_gtwr_local_inference(sdf[, c("Intercept", "aging")], FOC, edf = 1000)
expect_true(all(is.na(absent$se)), "absent SE columns yield NA rather than a substitute")
expect_true(all(is.na(absent$t)), "absent TV columns yield NA rather than a substitute")
expect_true(
  identical(absent$source, "absent_from_sdf"),
  "the absent case is named in the inference source"
)
expect_equal_num(length(absent$se), nrow(sdf), "the NA vector keeps one entry per estimation point")

empty <- extract_gtwr_local_inference(sdf[0, ], FOC, edf = 1000)
expect_equal_num(length(empty$se), 0, "an empty SDF yields empty vectors")


test_context("local significance: BH-FDR is applied across the reported dongs")

# The reported surface is one local test per dong at a single quarter, so the
# adjustment is over that family. BH can never make a p smaller, and must not
# promote anything the raw threshold rejected.
set.seed(11)
p_raw <- c(runif(400, 0, 1), c(1e-6, 1e-5, 1e-4))
p_bh <- stats::p.adjust(p_raw, method = "BH")
expect_true(all(p_bh >= p_raw - 1e-12), "BH adjustment never decreases a p-value")
expect_true(
  sum(p_bh < 0.05, na.rm = TRUE) <= sum(p_raw < 0.05, na.rm = TRUE),
  "the FDR-significant set is contained in the nominally significant set"
)

# Pure noise: the nominal rule rejects about 5% of 425 dongs, BH should keep
# almost none. This is the reason the summary counts the adjusted flag.
set.seed(12)
noise <- stats::runif(425)
expect_true(
  sum(stats::p.adjust(noise, method = "BH") < 0.05) == 0,
  "under pure noise the FDR-significant count is zero"
)


test_context("output schemas carry the inference columns")

for (col in c("estimate_se", "estimate_t", "estimate_p", "estimate_inference_source")) {
  expect_true(col %in% names(empty_gtwr_local_beta_panel_tbl()),
              sprintf("beta panel schema declares %s", col))
}
for (col in c("latest_estimate_se", "latest_estimate_t", "latest_estimate_p",
              "latest_estimate_p_fdr", "latest_significant_fdr")) {
  expect_true(col %in% names(empty_gtwr_local_tbl()),
              sprintf("local coefficient schema declares %s", col))
}
for (col in c("median_local_se", "n_significant_fdr", "share_significant_fdr",
              "share_positive_among_significant", "local_inference_status")) {
  expect_true(col %in% names(empty_gtwr_main_tbl()),
              sprintf("main summary schema declares %s", col))
}
