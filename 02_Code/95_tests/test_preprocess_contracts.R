#==============================================================================
# Script    : test_preprocess_contracts.R
# Purpose   : Regression tests for the preprocessing helpers that define
#             published panel values, and for the published panel itself. The
#             suite previously covered only the modelling utilities, so the
#             quarterly publication rules, the pooled-z contract, the lag
#             calendar, and the join integrity of panel_main had no test at all.
#             A silent join failure in the living-population layer survived every
#             QC file for that reason; the structural-zero checks below are the
#             regression guard for it.
# Type      : qc
# Inputs    : 01_preprocess/02_build_seoul_quarter_base.R (helpers, parsed not run),
#             01_preprocess/06_build_analysis_panel.R (helpers, parsed not run),
#             80_optional/preprocess/01_build_living_population_inflow.R,
#             optionally 01_Data/03_Processed_Data/** for the published checks
#==============================================================================

#==============================================================================
# 0. Load Helpers Without Running the Pipeline
#==============================================================================

# The preprocessing helpers live inside the pipeline scripts rather than in
# 99_utils, and utils_transform.R records a deliberate decision to keep
# `pooled_z()` there: the copy in 06 and the inline algebra in 07 apply the
# reference mask to different row scopes on purpose, so promoting one into the
# shared surface would be a design change, not a cleanup. Sourcing the scripts
# would execute the whole pipeline, so this pulls out only the top-level
# `name <- function(...)` assignments and evaluates those. The tests then run
# against the shipped definitions rather than a copy that can drift.
source_function_defs <- function(path, env = new.env(parent = globalenv()), also = character(0)) {
  exprs <- parse(path)
  for (e in exprs) {
    if (!is.call(e) || length(e) < 3L) next
    if (!identical(as.character(e[[1L]]), "<-")) next
    nm <- tryCatch(as.character(e[[2L]]), error = function(...) character(0))
    if (length(nm) != 1L) next
    rhs_is_fn <- is.call(e[[3L]]) && identical(as.character(e[[3L]][[1L]]), "function")
    if (rhs_is_fn || nm %in% also) {
      tryCatch(eval(e, envir = env), error = function(...) invisible(NULL))
    }
  }
  env
}

qbase_env <- source_function_defs(here::here("02_Code", "01_preprocess", "02_build_seoul_quarter_base.R"))
panel_env <- source_function_defs(here::here("02_Code", "01_preprocess", "06_build_analysis_panel.R"))
inflow_env <- source_function_defs(
  here::here("02_Code", "80_optional", "preprocess", "01_build_living_population_inflow.R"),
  also = "living_pop_adm_cd_map"
)

quarter_stability_score   <- qbase_env$quarter_stability_score
rolling_quarter_stability <- qbase_env$rolling_quarter_stability
calc_interval_entropy     <- qbase_env$calc_interval_entropy
pooled_z                  <- panel_env$pooled_z
remap_living_pop_adm_cd   <- inflow_env$remap_living_pop_adm_cd


#==============================================================================
# 1. Quarterly Stability: -log1p(CV) Over a Trailing 4-Quarter Window
#==============================================================================

test_context("quarter_stability_score(): bounded above, unbounded below")

if (is.function(quarter_stability_score)) {
  # A perfectly flat quarter has no dispersion, so the score is exactly zero.
  # This is the ceiling of the measure, and it is why research_procedure section
  # 2.9 records the sub-indices as left-skewed: the component cannot reward
  # stability beyond zero but can punish instability without limit.
  expect_equal_num(quarter_stability_score(c(100, 100, 100, 100)), 0,
                   "constant series scores exactly 0 (the upper bound)")

  x <- c(80, 100, 120, 100)
  expect_equal_num(quarter_stability_score(x), -log1p(stats::sd(x) / mean(x)),
                   "score equals -log1p(coefficient of variation)")

  expect_true(quarter_stability_score(c(10, 200, 10, 200)) <
                quarter_stability_score(c(90, 110, 90, 110)),
              "a more volatile series scores strictly lower")

  # The window is all-or-nothing by design. A partially observed window would
  # otherwise publish a stability value computed from a different number of
  # quarters than the contract states.
  expect_true(!is.finite(quarter_stability_score(c(100, 100, 100))),
              "a 3-quarter window is NA, not a rescaled 3-quarter statistic")
  expect_true(!is.finite(quarter_stability_score(c(100, NA, 100, 100))),
              "a missing quarter inside the window yields NA")
  expect_true(!is.finite(quarter_stability_score(c(0, 0, 0, 0))),
              "a zero-mean window yields NA rather than dividing by zero")
} else {
  test_skip("quarter_stability_score contracts", "helper not found in 02_build_seoul_quarter_base.R")
}

test_context("rolling_quarter_stability(): trailing window includes the current quarter")

if (is.function(rolling_quarter_stability)) {
  v <- c(80, 100, 120, 100, 100, 100, 100, 100)
  r <- rolling_quarter_stability(v)

  expect_true(all(!is.finite(r[1:3])), "the first three quarters have no complete window")
  expect_equal_num(r[4], quarter_stability_score(v[1:4]),
                   "quarter 4 uses quarters 1-4, ending at the current quarter")
  expect_equal_num(r[8], quarter_stability_score(v[5:8]),
                   "quarter 8 uses quarters 5-8, not a centred or leading window")

  # A leading window would leak future quarters into a variable that enters the
  # models contemporaneously; this pins the direction.
  expect_true(r[5] != r[4], "the window advances with the quarter")
  expect_equal_num(length(rolling_quarter_stability(c(1, 2))), 2,
                   "a series shorter than the window returns NA of the same length")
} else {
  test_skip("rolling_quarter_stability contracts", "helper not found")
}


#==============================================================================
# 2. Time-of-Day Entropy Over Unequal Day-Part Widths
#==============================================================================

test_context("calc_interval_entropy(): density entropy on unequal bin widths")

if (is.function(calc_interval_entropy)) {
  # The SEMAS day parts are 6/5/3/3/4/3 hours, so a flat *count* across the six
  # bands is not a flat distribution over the day. The maximum must be reached
  # when the counts are proportional to the band widths, and the normalisation
  # must put that maximum at exactly 1.
  hours <- c(6, 5, 3, 3, 4, 3)
  expect_equal_num(sum(hours), 24, "day-part widths cover a full day")

  expect_equal_num(calc_interval_entropy(hours, hours), 1,
                   "counts proportional to band width give the maximum of 1", tol = 1e-12)
  expect_true(calc_interval_entropy(rep(1, 6), hours) < 1,
              "equal counts across unequal bands are NOT the maximum")

  concentrated <- c(1000, 1, 1, 1, 1, 1)
  expect_true(calc_interval_entropy(concentrated, hours) <
                calc_interval_entropy(rep(1, 6), hours),
              "a concentrated day scores lower than a spread one")

  expect_true(calc_interval_entropy(c(100, rep(0, 5)), hours) >= 0,
              "a single occupied band stays inside [0, 1]")
  expect_true(!is.finite(calc_interval_entropy(rep(0, 6), hours)),
              "an all-zero day yields NA rather than 0")

  # The unnormalised form is the differential entropy itself, which is what makes
  # the log(24) divisor the right normaliser rather than log(6).
  expect_equal_num(calc_interval_entropy(hours, hours, normalize = FALSE), log(24),
                   "unnormalised maximum equals log(total hours), not log(n bands)", tol = 1e-12)
} else {
  test_skip("calc_interval_entropy contracts", "helper not found")
}


#==============================================================================
# 3. Pooled z Uses the Active-Window Reference, Not the Rows in Hand
#==============================================================================

test_context("pooled_z(): moments come from the reference mask")

if (is.function(pooled_z)) {
  # The panel carries 2018 lag-support rows and a 2019Q1-Q3 warm-up that must not
  # enter the standardisation moments. Standardising over "whatever rows the
  # caller holds" is the specific bug this contract exists to prevent.
  x <- c(100, 200, 1, 2, 3, 4, 5)
  ref <- c(FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE)
  z <- pooled_z(x, reference = ref)

  expect_equal_num(mean(z[ref]), 0, "reference rows have mean 0")
  expect_equal_num(stats::sd(z[ref]), 1, "reference rows have sd 1")
  expect_equal_num(z[1], (100 - mean(x[ref])) / stats::sd(x[ref]),
                   "non-reference rows are scored on the reference moments")
  expect_true(z[1] > 10, "an out-of-reference outlier keeps its extreme score")

  expect_true(all(!is.finite(pooled_z(c(5, 5, 5, 5), reference = rep(TRUE, 4)))),
              "a zero-variance reference yields NA rather than dividing by zero")
} else {
  test_skip("pooled_z contracts", "helper not found in 06_build_analysis_panel.R")
}


#==============================================================================
# 4. Living-Population adm_cd Crosswalk
#==============================================================================

test_context("living-population adm_cd crosswalk")

xw <- cfg$living_pop_adm_cd_crosswalk
expect_true(is.data.frame(xw) && nrow(xw) == 6L,
            "the crosswalk carries the six Gangbuk-gu code-vintage mismatches")
expect_true(!any(duplicated(xw$source_adm_cd)) && !any(duplicated(xw$adm_cd)),
            "the crosswalk is one-to-one in both directions")
expect_true(all(nchar(xw$source_adm_cd) == 10L) && all(nchar(xw$adm_cd) == 10L),
            "both sides are zero-padded 10-digit adm_cd")
expect_true(length(intersect(xw$source_adm_cd, xw$adm_cd)) == 0L,
            "no code maps to itself, which would mean the mismatch was misread")
expect_true(all(substr(xw$source_adm_cd, 1, 7) == substr(xw$adm_cd, 1, 7)),
            "every remap stays inside the same autonomous district")
expect_true(all(xw$verification %in% c("population_match", "order_convention")),
            "each row records how its mapping was established")

if (is.function(remap_living_pop_adm_cd)) {
  expect_equal_num(sum(remap_living_pop_adm_cd(xw$source_adm_cd) == xw$adm_cd), 6,
                   "every source code is remapped to its canonical adm_cd")
  untouched <- c("0011110515", "0011305534", "0011530510")
  expect_true(identical(remap_living_pop_adm_cd(untouched), untouched),
              "codes outside the crosswalk pass through unchanged")
  expect_true(identical(remap_living_pop_adm_cd(character(0)), character(0)),
              "an empty vector is handled without error")
} else {
  test_skip("remap_living_pop_adm_cd contracts", "helper not found")
}

expect_true(identical(as.character(cfg$living_pop_known_absent_adm_cd), "0011530800"),
            "Hangdong is declared absent from the source rather than remapped")


#==============================================================================
# 5. Published Panel Integrity (skips when the panel is absent)
#==============================================================================

test_context("panel_main: published structure and join integrity")

panel_path <- cfg$paths$panel_main
if (!file.exists(panel_path)) {
  test_skip("panel_main checks", "panel_main.parquet not built")
} else {
  pm <- arrow::read_parquet(panel_path)

  expect_equal_num(nrow(pm), 425 * 28, "panel is the full 425 dong x 28 quarter grid")
  expect_equal_num(sum(duplicated(pm[, c("adm_cd", "yq")])), 0, "adm_cd x yq is unique")
  expect_true(all(c("year", "quarter", "yq", "quarter_index") %in% names(pm)),
              "the four canonical time keys survive into the active panel")

  # --- Structural zeros ------------------------------------------------------
  # A dong held at exactly zero in every quarter is a failed join, not a low
  # value. Counts that are legitimately zero across a whole dong (subway
  # stations, malls) are deliberately outside this scope.
  zero_scope <- intersect(
    c("resident_pop", "age60_resident_pop", "floating_pop", "age60_floating_pop",
      "external_inflow_pop", "total_sales", "sales_count", "total_store_count",
      "spend_total", "official_land_price", "land_price_adjusted",
      "workplace_worker_pop", "adm_area_km2", "bus_stop_count_aux"),
    names(pm)
  )
  offenders <- character(0)
  for (v in zero_scope) {
    by_dong <- tapply(pm[[v]], pm$adm_cd, function(z) {
      fin <- is.finite(z)
      sum(fin) > 0L && all(z[fin] == 0)
    })
    hit <- names(by_dong)[vapply(by_dong, isTRUE, logical(1))]
    if (length(hit) > 0L) offenders <- c(offenders, sprintf("%s:%s", v, hit))
  }
  # The offenders are carried in the label because that is the whole diagnostic
  # value of this check: knowing which dong-variable pairs failed is what points
  # at the responsible join. `expect_true()` reports only "condition was not
  # TRUE", so the list would otherwise be lost.
  expect_true(length(offenders) == 0L,
              sprintf("no variable is zero in every observed quarter for any dong%s",
                      if (length(offenders) > 0L) {
                        paste0(" [offenders: ", paste(offenders, collapse = ", "), "]")
                      } else ""))

  # --- Lag calendar ----------------------------------------------------------
  # The lags are built by a calendar join against the lag-support layers, not by
  # a positional shift, so they must agree with a within-panel shift wherever
  # both are defined. A mismatch means a dong's history was silently misaligned.
  ord <- pm[order(pm$adm_cd, pm$quarter_index), ]
  lag_pairs <- list(
    c("age60_resident_share", "lag4_age60_resident_share", "4"),
    c("ln_resident_pop", "lag4_ln_resident_pop", "4"),
    c("ln_land_price_adjusted", "lag4_ln_land_price_adjusted", "4"),
    c("ln_workplace_worker_pop", "lag4_ln_workplace_worker_pop", "4"),
    c("age60_floating_share", "lag2_age60_floating_share", "2")
  )
  for (p in lag_pairs) {
    src <- p[[1]]; tgt <- p[[2]]; k <- as.integer(p[[3]])
    if (!all(c(src, tgt) %in% names(ord))) {
      test_skip(sprintf("%s matches a %d-quarter shift", tgt, k), "column absent")
      next
    }
    shifted <- unlist(lapply(split(ord[[src]], ord$adm_cd), function(z) c(rep(NA_real_, k), utils::head(z, -k))))
    keep <- ord$quarter_index > k
    d <- abs(shifted[keep] - ord[[tgt]][keep])
    expect_true(all(!is.finite(d) | d <= 1e-9),
                sprintf("%s equals the within-panel %d-quarter shift", tgt, k))
  }

  # The active window must be fully supplied by the 2018 lag-support layer.
  act <- pm[pm$quarter_index >= 4, ]
  for (v in intersect(c("lag4_age60_resident_share", "lag4_ln_resident_pop",
                        "lag4_ln_land_price_adjusted", "lag4_transit_accessibility",
                        "lag4_ln_workplace_worker_pop"), names(act))) {
    expect_equal_num(sum(!is.finite(act[[v]])), 0,
                     sprintf("%s is complete over the active window", v))
  }

  # --- Vitality composition --------------------------------------------------
  # The sub-indices are means of pooled z-scores over the active window. If the
  # standardisation reference or the component list drifts, these break.
  zz <- function(z) (z - mean(z, na.rm = TRUE)) / stats::sd(z, na.rm = TRUE)
  if (all(c("vitality_sub_economic", "ln_sales_count", "ln_total_sales") %in% names(act))) {
    rebuilt <- rowMeans(cbind(zz(act$ln_sales_count), zz(act$ln_total_sales)))
    d <- abs(rebuilt - act$vitality_sub_economic)
    expect_true(all(!is.finite(d) | d <= 1e-9),
                "vitality_sub_economic is the mean of its two pooled-z components")
  }
  if (all(c("vitality_sub_social", "ln_floating_pop", "ln_external_inflow_pop") %in% names(act))) {
    rebuilt <- rowMeans(cbind(zz(act$ln_floating_pop), zz(act$ln_external_inflow_pop)))
    d <- abs(rebuilt - act$vitality_sub_social)
    expect_true(all(!is.finite(d) | d <= 1e-9),
                "vitality_sub_social is the mean of its two pooled-z components")
  }
  for (v in intersect(c("vitality_sub_economic", "vitality_sub_social",
                        "vitality_sub_temporal", "vitality_sub_stability"), names(act))) {
    expect_true(abs(mean(act[[v]], na.rm = TRUE)) < 0.01,
                sprintf("%s is centred on the active window, not the full panel", v))
  }
  for (v in intersect(c("vitality_sub_economic", "vitality_sub_social",
                        "vitality_sub_temporal", "vitality_sub_stability",
                        "vitality_index_base"), names(pm))) {
    warm <- pm[pm$quarter_index <= 3, v, drop = TRUE]
    expect_equal_num(sum(is.finite(warm)), 0,
                     sprintf("%s stays NA through the 2019Q1-Q3 warm-up", v))
  }
}

test_context("living_population_external_inflow: no fabricated zeros")

inflow_path <- cfg$paths$living_population_external_inflow
if (!file.exists(inflow_path)) {
  test_skip("inflow layer checks", "living_population_external_inflow.parquet not built")
} else {
  li <- arrow::read_parquet(inflow_path)
  by_dong <- tapply(li$external_inflow_pop, li$adm_cd, function(z) {
    fin <- is.finite(z)
    sum(fin) > 0L && all(z[fin] == 0)
  })
  hit <- names(by_dong)[vapply(by_dong, isTRUE, logical(1))]
  expect_true(length(hit) == 0L,
              sprintf("no dong is zero in every quarter (the 2026-09 code-vintage join failure)%s",
                      if (length(hit) > 0L) {
                        paste0(" [offenders: ", paste(hit, collapse = ", "), "]")
                      } else ""))

  missing_dongs <- unique(li$adm_cd[!is.finite(li$external_inflow_pop)])
  expect_true(all(missing_dongs %in% as.character(cfg$living_pop_known_absent_adm_cd)),
              "every missing dong is on the declared known-absent list")

  for (cd in cfg$living_pop_adm_cd_crosswalk$adm_cd) {
    vals <- li$external_inflow_pop[li$adm_cd == cd]
    expect_true(any(is.finite(vals) & vals > 0),
                sprintf("remapped dong %s carries positive inflow", cd))
  }
}
