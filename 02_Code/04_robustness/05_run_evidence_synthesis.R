#!/usr/bin/env Rscript

#==============================================================================
# Script    : 05_run_evidence_synthesis.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Cross-tabulate every diagnostic the project runs against every
#             reported outcome, so that what survives all of them at once is a
#             computed result rather than a recollection of separate audits.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-04
# Type      : robustness
# Inputs    : twfe_main_models.csv, twfe_main_diagnostics.csv, spdm_impacts.csv,
#             influence_robustness_summary.csv, identification_placebo_lead.csv,
#             identification_trend_spec.csv,
#             identification_exposure_persistence.csv,
#             exposure_linearity_tests.csv
# Outputs   : evidence_synthesis_gates.csv, evidence_synthesis.csv,
#             evidence_synthesis_matrix.png
# DependsOn : 00_setup/config.R, 00_setup/packages.R, 99_utils/utils_io.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# Each diagnostic in this project was added separately and reads, on its own,
# like a survivable result: two or three of the five outcomes come through every
# time. The outcomes that come through are not the same ones each time, so the
# per-audit counts overstate what is jointly defensible. A paper has to defend a
# single result against every diagnostic simultaneously, which makes the relevant
# quantity the intersection, not the per-audit pass rate. This script computes
# that intersection from the tables the diagnostics already wrote.
#
# It estimates nothing. Every cell traces to a named column of a named upstream
# table, recorded in `evidence_synthesis_gates.csv`, so a disputed verdict can be
# checked against its source rather than against this script's judgement.
options(scipen = 999)

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
load_project_packages()
source(here::here("02_Code", "99_utils", "utils_io.R"))

ensure_dirs(cfg$required_dirs)
append_log(cfg$logs$model_run, sprintf("\n## [%s] 05_run_evidence_synthesis", timestamp()))

OUTCOMES <- c("vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal",
              "vitality_sub_stability", "vitality_index_base")
EXPOSURE <- "lag4_age60_resident_share"
ALPHA <- 0.05

# Influence tolerance. A coefficient that moves by more than this share of itself
# when a small set of dongs is dropped is not reportable as a magnitude, even when
# it never crosses a significance threshold. 50 is a stated convention, not an
# inferential rule, and it is exposed so a reader can re-run the synthesis under a
# different one; the underlying `pct_change` values are carried in the output so
# the choice can be inspected instead of trusted.
PCT_TOL <- suppressWarnings(as.numeric(Sys.getenv("SYNTHESIS_INFLUENCE_PCT_TOL", unset = "50")))
if (!is.finite(PCT_TOL) || PCT_TOL <= 0) PCT_TOL <- 50


#==============================================================================
# 1. Input
#==============================================================================

# Read-only over published tables. A missing table yields NA gates rather than an
# error, because a partial synthesis that says which gates it could not evaluate
# is more useful than no synthesis at all; `sources_missing` in the wide output
# names anything absent.
read_if_present <- function(path) {
  if (!file.exists(path)) return(NULL)
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

src <- list(
  twfe = cfg$paths$twfe_main_models,
  spdm = cfg$paths$spdm_impacts,
  influence = cfg$paths$influence_robustness_summary,
  placebo = cfg$paths$identification_placebo,
  trend = cfg$paths$identification_trend_spec,
  persistence = cfg$paths$identification_exposure_persistence,
  linearity = cfg$paths$exposure_linearity_tests
)
dat <- lapply(src, read_if_present)
missing_src <- names(src)[vapply(dat, is.null, logical(1))]

# Provenance. A synthesis over stale inputs is worse than none, so the modification
# time of every source is carried into the log and the wide output.
src_mtime <- vapply(src, function(p) {
  if (file.exists(p)) format(file.info(p)$mtime, "%Y-%m-%d %H:%M:%S") else NA_character_
}, character(1))

# TWFE m1 (exposure only) and m2 (with the control contract) are separated by the
# model_name suffix; the exposure row is the one the gates read.
twfe_exposure <- NULL
if (!is.null(dat$twfe)) {
  twfe_exposure <- dat$twfe |>
    dplyr::filter(.data$term == EXPOSURE, .data$exposure == EXPOSURE) |>
    dplyr::mutate(spec = sub("^.*__", "", .data$model_name))
}

pick <- function(tbl, oc, col, where = NULL) {
  if (is.null(tbl) || !col %in% names(tbl)) return(NA)
  rows <- tbl[tbl$outcome == oc, , drop = FALSE]
  if (!is.null(where)) rows <- rows[where(rows), , drop = FALSE]
  if (nrow(rows) != 1L) return(NA)
  rows[[col]][[1L]]
}


#==============================================================================
# 2. Gate Definitions
#==============================================================================

# Gates are grouped by the audit that produced them and tagged with the role they
# play in the claim rule of section 4. The tags are the judgement in this script,
# and they are written to the output so that a reader who weighs the evidence
# differently can re-tier the same matrix without re-deriving it.
#
#   prerequisite : nothing is reportable if this fails
#   stability    : decides whether a magnitude may be stated
#   identification: decides whether a directional or causal reading is available
#   supporting   : qualifies the reading; does not by itself void a claim
GATE_META <- tibble::tribble(
  ~gate,                     ~audit,            ~role,             ~source, ~pass_rule,
  "baseline_significant",    "specification",   "prerequisite",    "twfe",      "TWFE m2 p < .05, clustered by dong",
  "control_set_consistency", "specification",   "supporting",      "twfe",      "m1 and m2 agree on sign and on the 5% verdict",
  "model_family_agreement",  "specification",   "supporting",      "spdm",      "TWFE m2 and SPDM direct agree on sign and on the 5% verdict",
  "influence_stable",        "influence",       "stability",       "influence", "no sign flip, no lost significance, and |pct_change| <= tol in all variants",
  "placebo_lead_null",       "identification",  "identification",  "placebo",   "the 4-quarter lead is not significant at 5%",
  "lag_beats_lead",          "identification",  "identification",  "placebo",   "the lag stays significant at 5% with the lead entered alongside",
  "dong_trend_survival",     "identification",  "identification",  "trend",     "significant at 5% with dong-specific linear trends",
  "linearity_not_rejected",  "linearity",       "supporting",      "linearity", "neither the quadratic term nor the lack-of-fit test rejects",
  "se_twoway_significant",   "standard_errors", "supporting",      "twfe",      "TWFE m2 p < .05 when clustered on dong and quarter"
)

as_gate <- function(x) if (is.na(x)) NA else isTRUE(x)

eval_gates <- function(oc) {
  m1 <- if (is.null(twfe_exposure)) NULL else twfe_exposure[twfe_exposure$outcome == oc & twfe_exposure$spec == "m1", ]
  m2 <- if (is.null(twfe_exposure)) NULL else twfe_exposure[twfe_exposure$outcome == oc & twfe_exposure$spec == "m2", ]
  one <- function(x, col) if (is.null(x) || nrow(x) != 1L || !col %in% names(x)) NA_real_ else x[[col]][[1L]]

  b2 <- one(m2, "estimate"); p2 <- one(m2, "p.value")
  b1 <- one(m1, "estimate"); p1 <- one(m1, "p.value")
  p2tw <- one(m2, "p.value_twoway")

  sd_direct <- pick(dat$spdm, oc, "direct")
  sd_p <- pick(dat$spdm, oc, "direct_p")

  inf <- if (is.null(dat$influence)) NULL else dat$influence[dat$influence$outcome == oc, , drop = FALSE]
  inf_flip <- if (is.null(inf) || nrow(inf) == 0L) NA else any(inf$sign_flip, na.rm = TRUE)
  inf_lose <- if (is.null(inf) || nrow(inf) == 0L) NA else any(inf$loses_5pct_significance, na.rm = TRUE)
  inf_pct <- if (is.null(inf) || nrow(inf) == 0L) NA_real_ else max(abs(inf$pct_change), na.rm = TRUE)

  lead_p <- pick(dat$placebo, oc, "lead_p")
  hr_lag_p <- pick(dat$placebo, oc, "horserace_lag_p")
  trend_p <- pick(dat$trend, oc, "trend_p")
  quad_p <- pick(dat$linearity, oc, "quadratic_p")
  lof_p <- pick(dat$linearity, oc, "lack_of_fit_p")

  sig <- function(p) if (is.na(p)) NA else p < ALPHA

  tibble::tibble(
    outcome = oc,
    gate = GATE_META$gate,
    passed = c(
      as_gate(sig(p2)),
      as_gate(if (anyNA(c(b1, b2, p1, p2))) NA else sign(b1) == sign(b2) && (p1 < ALPHA) == (p2 < ALPHA)),
      as_gate(if (anyNA(c(b2, p2, sd_direct, sd_p))) NA else sign(b2) == sign(sd_direct) && (p2 < ALPHA) == (sd_p < ALPHA)),
      as_gate(if (anyNA(c(inf_flip, inf_lose, inf_pct))) NA else !inf_flip && !inf_lose && inf_pct <= PCT_TOL),
      as_gate(if (is.na(lead_p)) NA else lead_p >= ALPHA),
      as_gate(sig(hr_lag_p)),
      as_gate(sig(trend_p)),
      as_gate(if (anyNA(c(quad_p, lof_p))) NA else quad_p >= ALPHA && lof_p >= ALPHA),
      as_gate(sig(p2tw))
    ),
    statistic = c(
      sprintf("beta = %.3f, p = %.4f", b2, p2),
      sprintf("m1 beta = %.3f (p = %.4f); m2 beta = %.3f (p = %.4f)", b1, p1, b2, p2),
      sprintf("TWFE beta = %.3f (p = %.4f); SPDM direct = %.3f (p = %.4g)", b2, p2, sd_direct, sd_p),
      sprintf("sign_flip = %s, loses_5pct = %s, max |pct_change| = %.1f (tol %.0f)",
              inf_flip, inf_lose, inf_pct, PCT_TOL),
      sprintf("lead p = %.4f", lead_p),
      sprintf("horse-race lag p = %.4f", hr_lag_p),
      sprintf("trend-spec p = %.4f", trend_p),
      sprintf("quadratic p = %.4f, lack-of-fit p = %.4g", quad_p, lof_p),
      sprintf("two-way clustered p = %.4f", p2tw)
    )
  )
}

gates <- purrr::map_dfr(intersect(OUTCOMES, unique(c(twfe_exposure$outcome, dat$influence$outcome))), eval_gates)
if (nrow(gates) == 0L) stop("[ERROR] no outcome could be evaluated; upstream diagnostic tables are missing", call. = FALSE)

gates <- gates |>
  dplyr::left_join(GATE_META, by = "gate") |>
  dplyr::mutate(
    outcome = factor(.data$outcome, levels = OUTCOMES),
    gate = factor(.data$gate, levels = GATE_META$gate)
  ) |>
  dplyr::arrange(.data$outcome, .data$gate) |>
  dplyr::relocate("audit", "role", .after = "gate")

write_csv_safe(gates, cfg$paths$evidence_synthesis_gates)


#==============================================================================
# 3. Design-Level Versus Outcome-Level Failure
#==============================================================================

# A gate that no outcome passes is not discriminating between outcomes: it is
# reporting a property of the design. Separating the two matters for how the
# limitation is written up, because a design-level failure cannot be answered by
# choosing a different outcome.
gate_scope <- gates |>
  dplyr::group_by(.data$gate, .data$audit, .data$role) |>
  dplyr::summarise(
    n_eval = sum(!is.na(.data$passed)),
    n_pass = sum(.data$passed, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    scope = dplyr::case_when(
      .data$n_eval == 0L ~ "not_evaluated",
      .data$n_pass == 0L ~ "design_level_failure",
      .data$n_pass == .data$n_eval ~ "passed_by_all",
      TRUE ~ "outcome_level"
    )
  )


#==============================================================================
# 4. Claim Tier
#==============================================================================

# The tier names a *kind* of claim, not a quality ranking, because the failures
# are not commensurable: an estimate that moves under dong exclusion and an
# estimate that is inseparable from a trend fail in different ways and license
# different sentences. `n_gates_passed` is reported beside the tier so a reader
# who weighs the gates differently is not obliged to accept this rule.
#
#   not_supported           : the baseline itself is not significant
#   descriptive_only        : significant, but the magnitude is not stable
#   conditional_association : stable magnitude, not separable from trend or ordering
#   robust_association      : stable and separable, but the functional form or a
#                             supporting check fails
#   causal_directional      : every gate passes
tier_of <- function(g) {
  got <- function(nm) {
    v <- g$passed[g$gate == nm]
    if (length(v) != 1L) NA else v
  }
  ident <- c(got("placebo_lead_null"), got("lag_beats_lead"), got("dong_trend_survival"))
  supp <- c(got("control_set_consistency"), got("model_family_agreement"),
            got("linearity_not_rejected"), got("se_twoway_significant"))

  if (isTRUE(is.na(got("baseline_significant")))) return("incomplete")
  if (!isTRUE(got("baseline_significant"))) return("not_supported")
  if (!isTRUE(got("influence_stable"))) return("descriptive_only")
  if (!all(vapply(ident, isTRUE, logical(1)))) return("conditional_association")
  if (!all(vapply(supp, isTRUE, logical(1)))) return("robust_association")
  "causal_directional"
}

wide <- gates |>
  dplyr::select("outcome", "gate", "passed") |>
  tidyr::pivot_wider(names_from = "gate", values_from = "passed") |>
  dplyr::arrange(.data$outcome)

summary_tbl <- purrr::map_dfr(levels(gates$outcome)[levels(gates$outcome) %in% as.character(wide$outcome)], function(oc) {
  g <- gates[gates$outcome == oc, ]
  failed <- as.character(g$gate[!is.na(g$passed) & !g$passed])
  tibble::tibble(
    outcome = oc,
    n_gates_passed = sum(g$passed, na.rm = TRUE),
    n_gates_evaluated = sum(!is.na(g$passed)),
    n_gates_total = nrow(GATE_META),
    claim_tier = tier_of(g),
    failed_gates = if (length(failed) == 0L) NA_character_ else paste(failed, collapse = ";"),
    failed_decisive_gates = {
      d <- intersect(failed, GATE_META$gate[GATE_META$role %in% c("prerequisite", "stability", "identification")])
      if (length(d) == 0L) NA_character_ else paste(d, collapse = ";")
    }
  )
})

summary_tbl <- summary_tbl |>
  dplyr::left_join(dplyr::mutate(wide, outcome = as.character(.data$outcome)), by = "outcome") |>
  dplyr::mutate(
    influence_pct_tol = PCT_TOL,
    alpha = ALPHA,
    sources_missing = if (length(missing_src) == 0L) NA_character_ else paste(missing_src, collapse = ";"),
    source_mtimes = paste(sprintf("%s=%s", names(src_mtime), src_mtime), collapse = ";")
  )

write_csv_safe(summary_tbl, cfg$paths$evidence_synthesis)


#==============================================================================
# 5. Gate Matrix Figure
#==============================================================================

plot_dat <- gates |>
  dplyr::mutate(
    status = dplyr::case_when(
      is.na(.data$passed) ~ "not evaluated",
      .data$passed ~ "passes",
      TRUE ~ "fails"
    ),
    # Outcomes read top to bottom in the contract order, which reversing the
    # factor achieves under ggplot's bottom-up discrete axis.
    outcome = factor(.data$outcome, levels = rev(levels(.data$outcome)))
  )

n_tier <- summary_tbl |> dplyr::count(.data$claim_tier)
matrix_plot <- ggplot2::ggplot(plot_dat, ggplot2::aes(x = .data$gate, y = .data$outcome, fill = .data$status)) +
  ggplot2::geom_tile(colour = "white", linewidth = 0.9) +
  ggplot2::scale_fill_manual(values = c(passes = "#2c7fb8", fails = "#d94801",
                                        `not evaluated` = "#cccccc")) +
  ggplot2::facet_grid(cols = ggplot2::vars(.data$audit), scales = "free_x", space = "free_x") +
  ggplot2::labs(
    title = "Diagnostic gates by outcome",
    subtitle = sprintf("Each cell is one diagnostic applied to one outcome. Claim tiers: %s.",
                       paste(sprintf("%s = %d", n_tier$claim_tier, n_tier$n), collapse = ", ")),
    x = NULL, y = NULL, fill = NULL
  ) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 6.5),
    panel.grid = ggplot2::element_blank(),
    legend.position = "bottom",
    strip.text = ggplot2::element_text(size = 7, face = "bold")
  )

ggplot2::ggsave(cfg$paths$evidence_synthesis_matrix, matrix_plot, width = 11, height = 4.2, dpi = 200)


#==============================================================================
# 6. Log
#==============================================================================

design_fail <- gate_scope$gate[gate_scope$scope == "design_level_failure"]
tier_line <- paste(sprintf("%s=%s", summary_tbl$outcome, summary_tbl$claim_tier), collapse = "; ")

append_log(cfg$logs$data_qc, sprintf(
  "- Evidence synthesis: %d outcomes x %d gates; no outcome passes all gates (max %d). Tiers: %s. Design-level failures (no outcome passes): %s",
  nrow(summary_tbl), nrow(GATE_META), max(summary_tbl$n_gates_passed), tier_line,
  if (length(design_fail) == 0L) "none" else paste(design_fail, collapse = ", ")))

if (length(missing_src) > 0L) {
  warning(sprintf("[SYNTHESIS] missing source tables, gates left NA: %s",
                  paste(missing_src, collapse = ", ")), call. = FALSE, immediate. = TRUE)
}

message(sprintf("[DONE] evidence synthesis: best outcome passes %d of %d gates; tiers: %s",
                max(summary_tbl$n_gates_passed), nrow(GATE_META), tier_line))
