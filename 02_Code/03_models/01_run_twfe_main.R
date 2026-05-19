#==============================================================================
# Script    : 01_run_twfe_main.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Estimate the main two-way fixed effects baseline models, export
#             summary tables/plots, and test residual spatial dependence.
# Author    : Codex
# Created   : 2026-02-28
# Type      : panel_modeling
# Inputs    : panel_main.parquet, W_queen.rds
# Outputs   : twfe_main_models.csv/html, twfe_main_coefplot.png,
#             twfe_main_coefplot_supplementary.png,
#             twfe_main_controls_used.csv, twfe_main_diagnostics.csv,
#             twfe_main_residual_moran.csv,
#             twfe_main_residual_moran_by_yq.csv,
#             twfe_main_residual_moran_summary.csv
# DependsOn : 02_Code/01_preprocess/07_build_vitality_index.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# 메인 회귀는 별도 slim panel 파일이 아니라 `panel_main`의
# method-specific view만 읽는다. 결과적으로 데이터 정본은 하나이고,
# 모델 단계는 필요한 열만 선별해 사용하는 구조다.
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
source(here::here("02_Code", "R", "utils_model.R"))
load_project_packages()

if (!file.exists(cfg$paths$panel_main)) {
  stop("[ERROR] Required inputs for TWFE missing", call. = FALSE)
}

panel <- read_panel_main_view("twfe")

build_model_name <- function(outcome, exposure, spec) {
  paste(outcome, exposure, spec, sep = "__")
}


#==============================================================================
# 1. Resolve Estimation Inputs
#==============================================================================

# outcome, exposure, control은 문서 계약에서 정한 후보군 중
# 실제 panel에 존재하고 유한값이 충분한 변수만 남긴다.
# 이렇게 해야 스펙 drift나 부분 재실행 후에도 회귀가 안전하게 돈다.
outcome_registry <- resolve_model_outcomes(
  panel,
  requested_outcomes = value_or(cfg$twfe_main_outcomes, c(
    "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal", "vitality_sub_stability", "vitality_index_base"
  )),
  include_robustness = FALSE
)
outcomes <- outcome_registry$outcome
exposure_base <- if (!is.null(cfg$twfe_main_exposure_vars) && length(cfg$twfe_main_exposure_vars) > 0) {
  cfg$twfe_main_exposure_vars
} else {
  c("age60_resident_share")
}
exposures <- intersect(exposure_base, names(panel))
exposures <- exposures[vapply(exposures, function(v) sum(is.finite(panel[[v]])) > 100, logical(1))]

control_candidates <- value_or(cfg$twfe_main_control_cols, c(
  "ln_resident_pop", "ln_land_price_adjusted", "transit_accessibility"
))
# 후보 control을 넓게 제시한 뒤 usable screening을 적용한다.
control_screen <- resolve_outcome_control_screen(
  panel,
  outcomes = outcomes,
  candidates = control_candidates,
  min_finite = 500L,
  fe_aware = TRUE
)
control_contracts <- resolve_outcome_control_contracts(control_screen, outcomes = outcomes)
controls_by_outcome <- stats::setNames(
  lapply(control_contracts, `[[`, "usable_controls"),
  names(control_contracts)
)

if (length(outcomes) == 0 || length(exposures) == 0) stop("[ERROR] No valid outcomes/exposures for TWFE", call. = FALSE)

write_csv_safe(control_screen, cfg$paths$twfe_main_controls_used)


#==============================================================================
# 2. Estimate TWFE and Export Summaries
#==============================================================================

# 메인 TWFE는 기준선 역할만 맡으므로 m1~m2까지만 적합한다.
# 상호작용(m3, m4)은 02_run_twfe_interaction_models.R에서 별도로 다룬다.
available_specs <- c("m1", "m2")
spec_registry <- tidyr::crossing(
  outcome = outcomes,
  exposure = exposures,
  spec = available_specs
) |>
  dplyr::left_join(outcome_registry, by = "outcome") |>
  dplyr::arrange(outcome_order, exposure, spec) |>
  dplyr::mutate(
    model_name = build_model_name(outcome, exposure, spec),
    interaction_var = dplyr::case_when(
      TRUE ~ NA_character_
    ),
    requested_controls = purrr::map_chr(
      seq_len(dplyr::n()),
      ~ if (spec[[.x]] == "m1") NA_character_ else collapse_chr(controls_by_outcome[[outcome[[.x]]]])
    )
  )

mods <- list()
for (y in outcomes) {
  for (x in exposures) {
    # 동일 조합에 대해 사양만 바꾸는 m1~m2 구조라,
    # 결과 이름도 `outcome__exposure__m#` 패턴으로 고정한다.
    key <- paste(y, x, sep = "__")

    m1 <- run_twfe(panel, y, x, controls = NULL)
    m2 <- run_twfe(panel, y, x, controls = controls_by_outcome[[y]])
    if (!is.null(m1)) mods[[paste0(key, "__m1")]] <- m1
    if (!is.null(m2)) mods[[paste0(key, "__m2")]] <- m2

  }
}

if (length(mods) == 0) stop("[ERROR] No estimable TWFE models", call. = FALSE)

modelsummary::modelsummary(mods, output = cfg$paths$twfe_main_models_html, stars = TRUE, fmt = 3)
twfe_tidy <- tidy_models(mods) |>
  annotate_outcomes(include_robustness = FALSE) |>
  dplyr::arrange(outcome_order, exposure, model_name, term)
write_csv_safe(twfe_tidy, cfg$paths$twfe_main_models)

model_diag_success <- summarize_model_diagnostics(mods)
model_diag <- spec_registry |>
  dplyr::left_join(model_diag_success, by = "model_name", suffix = c("_expected", "")) |>
  dplyr::transmute(
    model_name,
    outcome = dplyr::coalesce(outcome, outcome_expected),
    outcome_group,
    outcome_order,
    exposure = dplyr::coalesce(exposure, exposure_expected),
    spec,
    status = dplyr::coalesce(status, "failed"),
    nobs,
    initial_nobs,
    requested_controls = dplyr::coalesce(requested_controls, requested_controls_expected),
    retained_controls,
    dropped_collinear_controls,
    dropped_collinear_terms,
    interaction_var = dplyr::coalesce(interaction_var, interaction_var_expected)
  )
write_csv_safe(model_diag, cfg$paths$twfe_main_diagnostics)


#==============================================================================
# 3. Plot Main Exposure Coefficients
#==============================================================================

# 그림은 핵심 age60 노출변수의 계수만 남겨,
# 결과 방향성과 신뢰구간을 빠르게 비교하는 요약 시각화다.
exposure_pattern <- paste0("^(", paste(exposure_base, collapse = "|"), ")$")
plot_twfe_coef <- function(plot_df, out_path) {
  if (nrow(plot_df) == 0) {
    if (file.exists(out_path)) unlink(out_path)
    return(invisible(NULL))
  }

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = estimate, y = model_name)) +
    ggplot2::geom_point() +
    ggplot2::geom_errorbar(
      ggplot2::aes(xmin = estimate - 1.96 * std.error, xmax = estimate + 1.96 * std.error),
      width = 0,
      orientation = "y"
    ) +
    ggplot2::theme_minimal()
  ggplot2::ggsave(out_path, p, width = 11, height = 8)
}

plot_td <- twfe_tidy |>
  dplyr::filter(
    grepl(exposure_pattern, term),
    grepl("__m2$", model_name)
  )
plot_twfe_coef(
  plot_td |>
    dplyr::filter(outcome_group == "primary"),
  cfg$paths$twfe_main_coefplot
)
plot_twfe_coef(
  plot_td |>
    dplyr::filter(outcome_group == "supplementary_vitality"),
  cfg$paths$twfe_main_coefplot_supplementary
)


#==============================================================================
# 4. Residual Spatial Dependence Check
#==============================================================================

# TWFE 자체는 공간모형이 아니므로, 추정 뒤 잔차에 공간자기상관이
# 남는지 lightweight diagnostic을 한 번 더 본다.
# 여기서 강한 잔차 Moran이 남으면 SPDM 결과 해석 중요도가 커진다.
m2_registry <- spec_registry |>
  dplyr::filter(spec == "m2")

residual_moran_nsim <- as.integer(value_or(cfg$twfe_residual_moran_nsim, value_or(cfg$esda_global_moran_nsim, 999L)))
if (!is.finite(residual_moran_nsim) || residual_moran_nsim < 1L) {
  stop("[ERROR] residual Moran permutation nsim must be a positive integer", call. = FALSE)
}
residual_moran_seed <- as.integer(value_or(cfg$twfe_residual_moran_seed, value_or(cfg$esda_seed, 20260317L)))
residual_moran_p_value_method <- "permutation_two_sided_abs"

# Residual Moran uses permutation inference for a more robust post-estimation
# spatial diagnostic. Seeds are derived from the spec/yq label so reruns are
# reproducible while each outcome-quarter test receives an independent stream.
deterministic_seed_from_label <- function(label, base_seed = residual_moran_seed) {
  ints <- utf8ToInt(enc2utf8(paste(label, collapse = "|")))
  mod <- 2147483647
  seed <- as.double(base_seed %% mod)

  if (length(ints) > 0L) {
    for (value in ints) {
      seed <- (seed * 131 + as.double(value)) %% mod
    }
  }

  seed <- floor(seed)
  if (!is.finite(seed) || seed <= 0) seed <- 1
  as.integer(seed)
}

with_deterministic_seed <- function(label, expr, base_seed = residual_moran_seed) {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)

  on.exit(
    {
      if (had_seed) {
        assign(".Random.seed", old_seed, envir = .GlobalEnv)
      } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    },
    add = TRUE
  )

  set.seed(deterministic_seed_from_label(label, base_seed = base_seed))
  eval.parent(substitute(expr))
}

build_failed_moran_row <- function(model_name, outcome, exposure, yq = NA_character_, message) {
  tibble::tibble(
    model_name = model_name,
    outcome = outcome,
    exposure = exposure,
    yq = as.character(yq),
    n_units = NA_integer_,
    n_missing = NA_integer_,
    missing_policy = NA_character_,
    moran_i = NA_real_,
    expectation = NA_real_,
    p_value = NA_real_,
    p_value_method = residual_moran_p_value_method,
    p_value_analytic = NA_real_,
    nsim = residual_moran_nsim,
    seed = NA_integer_,
    status = "failed",
    message = as.character(message)
  )
}

apply_fixest_obs_selection <- function(data, model_obj) {
  # `fixest::feols(data.save = TRUE)` keeps the complete-case input in
  # `model_obj$data`, but fixed-effect singleton removal can drop additional
  # rows. Residual diagnostics must use the final estimation sample.
  selection <- model_obj$obs_selection
  if (is.null(selection) || length(selection) == 0L) return(data)

  out <- data
  for (idx in selection) {
    idx <- suppressWarnings(as.integer(idx))
    idx <- idx[is.finite(idx) & idx != 0L]
    if (length(idx) == 0L) next
    out <- out[idx, , drop = FALSE]
  }
  out
}

run_residual_moran_by_yq <- function(model_name, model_obj, lw) {
  meta <- value_or(model_obj$twfe_meta, list())
  outcome <- value_or(meta$outcome, NA_character_)
  exposure <- value_or(meta$exposure, NA_character_)

  tryCatch({
    used_data <- apply_fixest_obs_selection(model_obj$data, model_obj)
    if (is.null(used_data) || nrow(used_data) == 0) stop("model data unavailable")
    if (!all(c("adm_cd", "yq") %in% names(used_data))) stop("model data missing adm_cd/yq")

    resid_vec <- as.numeric(stats::residuals(model_obj))
    if (length(resid_vec) != nrow(used_data)) stop("residual length mismatch")
    used_data$resid_model <- resid_vec

    used_data <- used_data |>
      dplyr::mutate(
        adm_cd = as.character(adm_cd),
        yq = as.character(yq)
      )

    yq_vals <- sort(unique(used_data$yq))
    yq_vals <- yq_vals[!is.na(yq_vals) & nzchar(yq_vals)]
    purrr::map_dfr(yq_vals, function(yq_val) {
      tryCatch({
        cs <- used_data |>
          dplyr::filter(yq == yq_val)

        aligned <- align_numeric_vector_to_listw(cs, lw, value_col = "resid_model", id_col = "adm_cd", min_units = 30L)
        seed_label <- sprintf(
          "twfe_residual_moran|%s|%s|%s|%s|nsim=%d",
          model_name, outcome, exposure, yq_val, residual_moran_nsim
        )
        seed_value <- deterministic_seed_from_label(seed_label)
        mt_analytic <- spdep::moran.test(aligned$values, aligned$lw, alternative = "two.sided", zero.policy = TRUE)
        mt_perm <- with_deterministic_seed(
          seed_label,
          spdep::moran.mc(aligned$values, aligned$lw, nsim = residual_moran_nsim, zero.policy = TRUE)
        )

        obs <- suppressWarnings(as.numeric(mt_perm$statistic[[1]]))
        sim_vals <- suppressWarnings(as.numeric(mt_perm$res))
        if (length(sim_vals) > residual_moran_nsim) {
          sim_vals <- sim_vals[seq_len(residual_moran_nsim)]
        }
        sim_vals <- sim_vals[is.finite(sim_vals)]
        p_value_perm <- if (is.finite(obs) && length(sim_vals) > 0L) {
          (sum(abs(sim_vals) >= abs(obs)) + 1) / (length(sim_vals) + 1)
        } else {
          NA_real_
        }

        tibble::tibble(
          model_name = model_name,
          outcome = outcome,
          exposure = exposure,
          yq = yq_val,
          n_units = aligned$n_complete,
          n_missing = aligned$n_missing,
          missing_policy = aligned$missing_policy,
          moran_i = obs,
          expectation = if (length(sim_vals) > 0L) mean(sim_vals, na.rm = TRUE) else NA_real_,
          p_value = p_value_perm,
          p_value_method = residual_moran_p_value_method,
          p_value_analytic = mt_analytic$p.value,
          nsim = residual_moran_nsim,
          seed = seed_value,
          status = "success",
          message = NA_character_
        )
      }, error = function(e) {
        build_failed_moran_row(model_name, outcome, exposure, yq = yq_val, message = e$message)
      })
    })
  }, error = function(e) {
    build_failed_moran_row(model_name, outcome, exposure, message = e$message)
  })
}

if (file.exists(cfg$paths$w_queen)) {
  lw <- readRDS(cfg$paths$w_queen)
  moran_by_yq <- purrr::pmap_dfr(m2_registry, function(outcome, exposure, spec, outcome_group, outcome_order, model_name, interaction_var, requested_controls) {
    model_obj <- mods[[model_name]]
    if (is.null(model_obj)) {
      return(build_failed_moran_row(model_name, outcome, exposure, message = "model_not_estimable"))
    }
    run_residual_moran_by_yq(model_name, model_obj, lw)
  })
} else {
  moran_by_yq <- purrr::pmap_dfr(m2_registry, function(outcome, exposure, spec, outcome_group, outcome_order, model_name, interaction_var, requested_controls) {
    build_failed_moran_row(model_name, outcome, exposure, message = "w_queen_missing")
  })
}
moran_by_yq <- moran_by_yq |>
  annotate_outcomes(include_robustness = FALSE) |>
  dplyr::arrange(outcome_order, exposure, model_name, yq)
write_csv_safe(moran_by_yq, cfg$paths$twfe_main_residual_moran_by_yq)

moran_tbl <- moran_by_yq |>
  dplyr::filter(status == "success") |>
  dplyr::group_by(model_name, outcome, exposure, outcome_group, outcome_order) |>
  dplyr::slice_max(order_by = yq, n = 1, with_ties = FALSE) |>
  dplyr::ungroup()

failed_only_models <- m2_registry |>
  dplyr::select(model_name, outcome, exposure) |>
  dplyr::anti_join(
    moran_tbl |>
      dplyr::select(model_name),
    by = "model_name"
  ) |>
  dplyr::mutate(
    yq = NA_character_,
    n_units = NA_integer_,
    n_missing = NA_integer_,
    missing_policy = NA_character_,
    moran_i = NA_real_,
    expectation = NA_real_,
    p_value = NA_real_,
    p_value_method = residual_moran_p_value_method,
    p_value_analytic = NA_real_,
    nsim = residual_moran_nsim,
    seed = NA_integer_,
    status = "failed",
    message = "no_successful_moran_by_yq"
  ) |>
  annotate_outcomes(include_robustness = FALSE)

moran_tbl <- dplyr::bind_rows(moran_tbl, failed_only_models) |>
  dplyr::arrange(outcome_order, exposure, model_name)
write_csv_safe(moran_tbl, cfg$paths$twfe_main_residual_moran)

moran_summary_stats <- moran_by_yq |>
  dplyr::filter(status == "success") |>
  dplyr::group_by(outcome, exposure) |>
  dplyr::summarise(
    sample_min_yq = min(yq, na.rm = TRUE),
    sample_max_yq = max(yq, na.rm = TRUE),
    n_yq_tested = dplyr::n(),
    mean_moran_i = mean(moran_i, na.rm = TRUE),
    median_moran_i = stats::median(moran_i, na.rm = TRUE),
    share_p_lt_0_05 = mean(p_value < 0.05, na.rm = TRUE),
    share_p_lt_0_10 = mean(p_value < 0.10, na.rm = TRUE),
    p_value_method = dplyr::first(p_value_method),
    nsim = dplyr::first(nsim),
    .groups = "drop"
  )

moran_latest_stats <- moran_tbl |>
  dplyr::transmute(
    outcome,
    exposure,
    latest_yq = yq,
    latest_moran_i = moran_i,
    latest_p = p_value,
    latest_p_analytic = p_value_analytic
  )

moran_summary <- m2_registry |>
  dplyr::distinct(outcome, exposure) |>
  dplyr::left_join(moran_summary_stats, by = c("outcome", "exposure")) |>
  dplyr::left_join(moran_latest_stats, by = c("outcome", "exposure")) |>
  dplyr::mutate(
    status = dplyr::if_else(!is.na(n_yq_tested) & n_yq_tested > 0L, "success", "failed"),
    n_yq_tested = dplyr::coalesce(as.integer(n_yq_tested), 0L),
    message = dplyr::if_else(status == "success", NA_character_, "no_successful_moran_by_yq")
  ) |>
  annotate_outcomes(include_robustness = FALSE) |>
  dplyr::select(
    outcome,
    exposure,
    outcome_group,
    outcome_order,
    status,
    sample_min_yq,
    sample_max_yq,
    n_yq_tested,
    mean_moran_i,
    median_moran_i,
    share_p_lt_0_05,
    share_p_lt_0_10,
    p_value_method,
    nsim,
    latest_yq,
    latest_moran_i,
    latest_p,
    latest_p_analytic,
    message
  ) |>
  dplyr::arrange(outcome_order, exposure)
write_csv_safe(moran_summary, cfg$paths$twfe_main_residual_moran_summary)

append_log(cfg$logs$model_run, sprintf("\n## [%s] 01_run_twfe_main", timestamp()))
append_log(cfg$logs$model_run, sprintf("- TWFE models: %d/%d", length(mods), nrow(spec_registry)))
