#==============================================================================
# Script    : utils_transform.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide reusable transformation helpers for panel-safe log and
#             winsorization.
# Author    : Codex
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
  # count/amount 계열은 이론적으로 음수가 아니므로, 로그 변환 전
  # 안전하게 0 이하를 막는다.
  # numeric이 아니면 그대로 반환하는 이유는, 호출부에서 `across()`로
  # 여러 열을 한 번에 넘겨도 문자형 식별자가 깨지지 않게 하기 위해서다.
  if (!is.numeric(x)) return(x)
  log1p(pmax(x, 0))
}

winsorize_vec <- function(x, probs = c(0.01, 0.99)) {
  # 극단치의 영향을 줄이기 위한 보조 helper다.
  # 분위수 계산은 `na.rm = TRUE`로 수행하되, 원래 결측은 유지한다.
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
