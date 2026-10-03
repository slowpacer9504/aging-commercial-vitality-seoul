#==============================================================================
# Script    : test_gtwr_sensitivity_baseline.R
# Purpose   : Regression tests for the baseline contract gate the bandwidth and
#             lamda sensitivity sidecars run before scoring anything. Those
#             sidecars reuse the published main GTWR surface as their baseline
#             row instead of refitting it, so a main run estimated at other
#             parameters would be republished under the contracted ones and every
#             agreement column would silently describe the wrong comparison. The
#             case that motivated the gate is real: the published bundle was fitted
#             at st_bw 90 with a raw-unit lamda while the contract read 60 / 0.5.
# Type      : qc
# Inputs    : utils_gtwr_main.R
#==============================================================================

# cfg is an environment, so assigning into it here would mutate the contract for
# every later test file. The fixtures therefore read the live contract and
# perturb copies of it, which also keeps the tests correct when the suite runs
# under GTWR_* overrides.
contract_st_bw <- suppressWarnings(as.integer(cfg$gtwr_st_bw))
contract_lamda <- suppressWarnings(as.numeric(cfg$gtwr_lamda))
contract_convention <- as.character(cfg$gtwr_lamda_convention)
contract_kernel <- as.character(cfg$gtwr_kernel)
contract_ksi <- suppressWarnings(as.numeric(cfg$gtwr_ksi))
other_kernel <- setdiff(c("bisquare", "gaussian"), contract_kernel)[[1]]

write_fixture <- function(tbl) {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(tbl, path, row.names = FALSE)
  path
}

frozen_fixture <- function(...) {
  overrides <- list(...)
  base <- data.frame(
    outcome = c("vitality_index_base", "vitality_sub_economic"),
    st_bw = contract_st_bw,
    kernel = contract_kernel,
    adaptive = TRUE,
    lamda = contract_lamda,
    lamda_convention = contract_convention,
    ksi = contract_ksi,
    status = "success",
    stringsAsFactors = FALSE
  )
  for (nm in names(overrides)) base[[nm]] <- overrides[[nm]]
  write_fixture(base)
}

summary_fixture <- function(st_bw = contract_st_bw, status = "success") {
  data.frame(
    outcome = c("vitality_index_base", "vitality_sub_economic"),
    st_bw = st_bw,
    status = status,
    stringsAsFactors = FALSE
  )
}

gate_passes <- function(summary_tbl, frozen_path) {
  isTRUE(assert_gtwr_sensitivity_baseline_contract(
    summary_tbl,
    control_set = "lean",
    context = "test",
    frozen_spec_path = frozen_path
  ))
}

gate_stops <- function(summary_tbl, frozen_path) {
  result <- tryCatch(
    assert_gtwr_sensitivity_baseline_contract(
      summary_tbl,
      control_set = "lean",
      context = "test",
      frozen_spec_path = frozen_path
    ),
    error = function(e) e
  )
  # A gate that stops for an unrelated reason is no gate, so the refusal has to
  # name the mismatch rather than merely be an error.
  inherits(result, "error") && grepl("cannot baseline on the published", conditionMessage(result), fixed = TRUE)
}


test_context("assert_gtwr_sensitivity_baseline_contract(): the contracted baseline passes")

expect_true(
  gate_passes(summary_fixture(), frozen_fixture()),
  "a main run at the contracted bandwidth, lamda, convention, kernel and angle passes"
)


test_context("assert_gtwr_sensitivity_baseline_contract(): a baseline off contract stops")

off_bw <- contract_st_bw + 30L
off_lamda <- if (isTRUE(all.equal(contract_lamda, 0.05))) 0.5 else 0.05
expect_true(
  gate_stops(summary_fixture(st_bw = off_bw), frozen_fixture(st_bw = off_bw)),
  sprintf("a main run at st_bw %d is refused against a contract of %d", off_bw, contract_st_bw)
)
expect_true(
  gate_stops(summary_fixture(), frozen_fixture(lamda = off_lamda)),
  sprintf("a main run at lamda %s is refused against a contract of %s", off_lamda, contract_lamda)
)

# A frozen spec written before 2026-09-02 carries no convention stamp, so its
# lamda is raw-unit and not comparable with a dimensionless contract even when
# the two numbers happen to match.
unstamped <- utils::read.csv(frozen_fixture(), stringsAsFactors = FALSE)
unstamped$lamda_convention <- NULL
expect_true(
  gate_stops(summary_fixture(), write_fixture(unstamped)),
  "an unstamped frozen spec is refused even at the contracted lamda value"
)
expect_true(
  gate_stops(summary_fixture(), frozen_fixture(lamda_convention = "raw_unit")),
  "a frozen spec stamped with another convention is refused"
)

expect_true(
  gate_stops(summary_fixture(), frozen_fixture(kernel = other_kernel)),
  sprintf("a baseline fitted with the %s kernel is refused", other_kernel)
)
expect_true(
  gate_stops(summary_fixture(), frozen_fixture(ksi = contract_ksi + pi / 2)),
  "a baseline fitted at another angle parameter is refused"
)
expect_true(
  gate_stops(summary_fixture(), file.path(tempdir(), "absent_frozen_spec.csv")),
  "a missing frozen spec is refused rather than assumed to match"
)


test_context("assert_gtwr_sensitivity_baseline_contract(): only estimated rows describe the baseline")

# A deferred row carries the configured fallback rather than an estimated value,
# so it must neither excuse an off-contract fit nor condemn an on-contract one.
expect_true(
  gate_stops(
    rbind(
      summary_fixture(st_bw = off_bw),
      summary_fixture(st_bw = contract_st_bw, status = "not_estimated")
    ),
    frozen_fixture(st_bw = off_bw)
  ),
  "a deferred row at the contracted bandwidth does not rescue an off-contract fit"
)
expect_true(
  gate_passes(
    rbind(
      summary_fixture(),
      summary_fixture(st_bw = 480L, status = "not_estimated")
    ),
    frozen_fixture()
  ),
  "a deferred row off contract does not fail a baseline whose fits are on contract"
)
