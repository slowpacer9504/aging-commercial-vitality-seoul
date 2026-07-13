#==============================================================================
# Script    : utils_transform.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide reusable transformation helpers for panel-safe log and
#             winsorization.
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

winsorize_vec <- function(x, probs = c(0.01, 0.99)) {
  # Trim extreme numeric values while preserving original missing values.
  if (!is.numeric(x)) return(x)
  qs <- stats::quantile(x, probs = probs, na.rm = TRUE, type = 7)
  pmin(pmax(x, qs[[1]]), qs[[2]])
}

zscore_vec <- function(x) {
  if (!is.numeric(x)) return(x)
  mu <- mean(x, na.rm = TRUE)
  sig <- stats::sd(x, na.rm = TRUE)
  if (!is.finite(mu) || !is.finite(sig) || sig <= .Machine$double.eps) {
    return(rep(NA_real_, length(x)))
  }
  (x - mu) / sig
}
