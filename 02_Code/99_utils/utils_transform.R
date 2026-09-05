#==============================================================================
# Script    : utils_transform.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide reusable transformation helpers for panel-safe log
#             transforms.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-02-28
# Type      : utility
# Inputs    : numeric vectors and panel data frames
# Outputs   : transformed vectors or enriched data frames
# DependsOn : stats
#==============================================================================

#==============================================================================
# 1. Vector Transformations
#==============================================================================

safe_log1p <- function(x) {
  # Negative counts are clipped at zero because the target variables in this
  # project are inherently non-negative and log1p is used for scale control.
  # Non-numeric inputs pass through unchanged so grouped `across()` calls do not
  # corrupt identifier columns.
  if (!is.numeric(x)) return(x)
  log1p(pmax(x, 0))
}

# `winsorize_vec()` and `zscore_vec()` were removed on 2026-09-05. Neither had a
# call site, and each contradicted an active contract rather than merely sitting
# idle.
#
# Winsorising is not a missing feature here, it is a decision: research_procedure
# section 2.9 states that no winsorising, trimming, or robust standardisation is
# applied at any stage, because the extreme values on this panel are real events
# (large-scale residential redevelopment, the COVID collapse of the central
# business district) rather than data errors. The price of that decision is paid
# by reporting 03_run_influence_robustness.R beside the impacts. A helper that
# lets the policy be broken silently does not belong in the shared surface.
#
# The z-score encoded the wrong standardisation contract. The project standardises
# by a pooled z over the *active analysis sample* (2019Q4~2025Q4), so the
# reference rows are part of the definition; `zscore_vec(x)` took no reference
# argument and would have standardised over whatever rows a caller happened to
# hold, silently including the 2019Q1~2019Q3 warm-up.
#
# The contract-correct implementation is `pooled_z(x, reference)`, defined
# locally in 01_preprocess/06_build_analysis_panel.R; 07_build_vitality_index.R
# open-codes similar algebra inline at four places. All five apply the
# `analysis_reference` mask correctly, so the published vitality indices are on
# contract and nothing is wrong today.
#
# Do not "promote" one of them into this file as a mechanical refactor: the two
# are not the same function. `pooled_z()` writes to every finite row using the
# reference moments, which is what 06 needs because its lag-support rows reach
# back to 2018; the inline version in 07 writes only to reference rows, which is
# what 07 needs because the 2019Q1~2019Q3 warm-up must stay NA in the vitality
# columns. `pooled_z()` also guards a near-zero standard deviation and a
# reference smaller than two observations, and the inline version does not.
# Unifying them means designing a shared helper with an explicit assignment
# scope and deciding the guard behaviour for 07, then verifying against a rerun
# — a deliberate change, not a cleanup to fold into an unrelated one.
