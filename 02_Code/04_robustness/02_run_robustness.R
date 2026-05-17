#==============================================================================
# Script    : 02_run_robustness.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run annual outcome-definition, sample-window, and W-Moran
#             sensitivity checks around the main TWFE specification.
# Author    : Codex
# Created   : 2026-02-28
# Type      : robustness
# Inputs    : panel_main.parquet, W_queen.rds, W_rook.rds, W_knn6.rds, W_knn8.rds
# Outputs   : robustness_summary.csv, robustness_compare.png
# DependsOn : 02_Code/03_models/01_run_twfe_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
source(here::here("02_Code", "R", "utils_model.R"))
load_project_packages()

if (!file.exists(cfg$paths$panel_main)) stop("[ERROR] panel_main missing", call. = FALSE)
panel <- read_panel_main_view("twfe") |>
  dplyr::mutate(adm_cd = as.character(adm_cd)) |>
  dplyr::arrange(adm_cd, year)

label_outcome <- function(x) {
  dplyr::case_when(
    x == "vitality_sub_economic" ~ "Economic Vitality",
    x == "vitality_sub_social" ~ "Social Vitality",
    x == "vitality_sub_temporal" ~ "Temporal Vitality",
    x == "vitality_sub_stability" ~ "Stability",
    x == "vitality_index_base" ~ "Composite Vitality Index",
    TRUE ~ x
  )
}

presentation_outcome_levels <- function(reverse = FALSE) {
  levels <- c(
    "Economic Vitality",
    "Social Vitality",
    "Temporal Vitality",
    "Stability",
    "Composite Vitality Index"
  )
  if (isTRUE(reverse)) rev(levels) else levels
}

main_outcomes <- resolve_model_outcomes(
  panel,
  requested_outcomes = cfg$twfe_main_outcomes,
  include_robustness = FALSE
)$outcome

robustness_outcomes <- resolve_model_outcomes(
  panel,
  requested_outcomes = cfg$robustness_outcomes,
  include_robustness = TRUE
)$outcome

outcome_definition_outcomes <- intersect(
  c(cfg$vitality_supplementary_outcomes, cfg$vitality_robustness_outcomes),
  names(panel)
)

if (length(robustness_outcomes) == 0L) {
  append_log(cfg$logs$model_run, sprintf("\n## [%s] 02_run_robustness", timestamp()))
  append_log(cfg$logs$model_run, "- Skipped: no robustness outcome")
} else {

  #============================================================================
  # 1. Shared Annual Contract
  #============================================================================

  control_candidates <- c(
    "ln_resident_pop", "ln_official_land_price", "transit_accessibility"
  )

  control_screen <- resolve_outcome_control_screen(
    panel,
    outcomes = robustness_outcomes,
    candidates = control_candidates,
    min_finite = 100L,
    fe_aware = TRUE
  )
  control_contracts <- resolve_outcome_control_contracts(control_screen, outcomes = robustness_outcomes)
  ctrl_by_outcome <- stats::setNames(
    lapply(control_contracts, `[[`, "usable_controls"),
    names(control_contracts)
  )

  extract_model_term <- function(model,
                                 outcome,
                                 spec_axis,
                                 spec,
                                 term,
                                 status = NULL,
                                 message = NA_character_,
                                 fallback_controls = character()) {
    if (is.null(model)) {
      return(tibble::tibble(
        outcome = outcome,
        spec_axis = spec_axis,
        spec = spec,
        term = term,
        estimate = NA_real_,
        std.error = NA_real_,
        statistic = NA_real_,
        p.value = NA_real_,
        nobs = NA_integer_,
        initial_nobs = NA_integer_,
        requested_controls = collapse_chr(fallback_controls),
        retained_controls = collapse_chr(fallback_controls),
        dropped_collinear_controls = NA_character_,
        dropped_collinear_terms = NA_character_,
        interaction_var = NA_character_,
        status = value_or(status, "failed"),
        message = as.character(message)
      ))
    }

    td <- broom::tidy(model) |>
      dplyr::filter(term == !!term)
    if (nrow(td) == 0L) {
      td <- tibble::tibble(
        term = term,
        estimate = NA_real_,
        std.error = NA_real_,
        statistic = NA_real_,
        p.value = NA_real_
      )
    }

    meta <- model_meta_tibble(model)
    td |>
      dplyr::bind_cols(meta[rep(1L, nrow(td)), , drop = FALSE]) |>
      dplyr::mutate(
        outcome = outcome,
        spec_axis = spec_axis,
        spec = spec,
        status = value_or(status, "success"),
        message = as.character(message),
        .before = 1
      )
  }

  run_spec_once <- function(data, outcome, exposure, spec_axis, spec_label) {
    controls_y <- ctrl_by_outcome[[outcome]]
    model <- run_twfe(data, outcome, exposure, controls = controls_y)
    extract_model_term(
      model,
      outcome = outcome,
      spec_axis = spec_axis,
      spec = spec_label,
      term = exposure,
      fallback_controls = controls_y
    )
  }


  #============================================================================
  # 2. Outcome Definition Sensitivity
  #============================================================================

  res_outcome_definition <- if (length(outcome_definition_outcomes) == 0L) {
    tibble::tibble()
  } else {
    purrr::map_dfr(outcome_definition_outcomes, function(outcome) {
      run_spec_once(
        panel,
        outcome = outcome,
        exposure = "age60_resident_share",
        spec_axis = "outcome_definition",
        spec_label = outcome
      )
    })
  }


  #============================================================================
  # 3. W Sensitivity via Latest-Year Moran's I
  #============================================================================

  latest_year <- suppressWarnings(max(panel$year, na.rm = TRUE))
  cs <- panel |>
    dplyr::filter(year == latest_year)
  w_paths <- c(
    queen = cfg$paths$w_queen,
    rook = cfg$paths$w_rook,
    knn6 = cfg$paths$w_knn6,
    knn8 = cfg$paths$w_knn8
  )

  res_w <- purrr::imap_dfr(w_paths, function(w_path, w_name) {
    if (!file.exists(w_path)) return(tibble::tibble())
    lw <- readRDS(w_path)
    purrr::map_dfr(robustness_outcomes, function(outcome) {
      aligned <- tryCatch(
        align_numeric_vector_to_listw(cs, lw, value_col = outcome, id_col = "adm_cd", min_units = 30L),
        error = function(e) NULL
      )
      if (is.null(aligned)) {
        return(tibble::tibble(
          outcome = outcome,
          spec_axis = "w_moran",
          spec = paste0("w_", w_name),
          term = "global_moran",
          estimate = NA_real_,
          std.error = NA_real_,
          statistic = NA_real_,
          p.value = NA_real_,
          n_units = NA_integer_,
          n_missing = NA_integer_,
          missing_policy = NA_character_,
          status = "not_estimated",
          message = "insufficient aligned units for Moran's I"
        ))
      }

      mt <- tryCatch(
        spdep::moran.test(aligned$values, aligned$lw, zero.policy = TRUE),
        error = function(e) e
      )
      if (inherits(mt, "error")) {
        return(tibble::tibble(
          outcome = outcome,
          spec_axis = "w_moran",
          spec = paste0("w_", w_name),
          term = "global_moran",
          estimate = NA_real_,
          std.error = NA_real_,
          statistic = NA_real_,
          p.value = NA_real_,
          n_units = aligned$n_complete,
          n_missing = aligned$n_missing,
          missing_policy = aligned$missing_policy,
          status = "failed",
          message = as.character(mt$message)
        ))
      }

      tibble::tibble(
        outcome = outcome,
        spec_axis = "w_moran",
        spec = paste0("w_", w_name),
        term = "global_moran",
        estimate = as.numeric(mt$estimate[[1]]),
        std.error = NA_real_,
        statistic = as.numeric(mt$statistic[[1]]),
        p.value = mt$p.value,
        n_units = aligned$n_complete,
        n_missing = aligned$n_missing,
        missing_policy = aligned$missing_policy,
        status = "success",
        message = NA_character_
      )
    })
  })


  #============================================================================
  # 4. Sample-Window Sensitivity
  #============================================================================

  windows <- list(
    full = panel,
    pre2025 = panel |> dplyr::filter(year < 2025L)
  )

  res_window <- purrr::imap_dfr(windows, function(data, window_name) {
    purrr::map_dfr(main_outcomes, function(outcome) {
      run_spec_once(
        data,
        outcome = outcome,
        exposure = "age60_resident_share",
        spec_axis = "sample_window",
        spec_label = window_name
      )
    })
  })


  #============================================================================
  # 5. Save Summary and Comparison Plot
  #============================================================================

  res <- dplyr::bind_rows(
    res_outcome_definition,
    res_w,
    res_window
  ) |>
    annotate_outcomes(include_robustness = TRUE) |>
    dplyr::arrange(outcome_order, spec_axis, spec, term) |>
    dplyr::select(
      outcome, outcome_group, outcome_order, spec_axis, spec, term,
      estimate, std.error, statistic, p.value, status, message,
      dplyr::everything()
    )

  write_csv_safe(res, cfg$paths$robustness_summary)

  plot_df <- res |>
    dplyr::filter(
      spec_axis %in% c("outcome_definition", "sample_window"),
      status == "success",
      is.finite(estimate),
      is.finite(std.error)
    ) |>
    dplyr::mutate(
      spec_label = dplyr::case_when(
        spec_axis == "outcome_definition" ~ paste("Outcome:", spec),
        TRUE ~ paste("Window:", spec)
      )
    )

  if (nrow(plot_df) > 0L) {
    plot_df <- plot_df |>
      dplyr::mutate(
        spec_label = factor(spec_label, levels = unique(spec_label)),
        outcome_label = factor(label_outcome(outcome), levels = presentation_outcome_levels(reverse = TRUE))
      )

    p <- ggplot2::ggplot(
      plot_df,
      ggplot2::aes(x = estimate, y = outcome_label, color = spec_label)
    ) +
      ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "grey60") +
      ggplot2::geom_errorbar(
        ggplot2::aes(
          xmin = estimate - 1.96 * std.error,
          xmax = estimate + 1.96 * std.error
        ),
        width = 0.16,
        orientation = "y",
        position = ggplot2::position_dodge(width = 0.5)
      ) +
      ggplot2::geom_point(
        size = 2.6,
        position = ggplot2::position_dodge(width = 0.5)
      ) +
      ggplot2::facet_wrap(~ spec_axis, scales = "free_x") +
      ggplot2::labs(
        title = "Annual TWFE Robustness Checks",
        subtitle = "Outcome-definition and sample-window sensitivity",
        x = "Estimated Coefficient",
        y = NULL,
        color = NULL
      ) +
      ggplot2::theme_minimal(base_size = 11) +
      ggplot2::theme(
        legend.position = "bottom",
        panel.grid.minor = ggplot2::element_blank()
      )

    ggplot2::ggsave(
      filename = cfg$paths$robustness_compare,
      plot = p,
      width = 11.5,
      height = 7.5,
      dpi = 320,
      bg = "white"
    )
  } else if (file.exists(cfg$paths$robustness_compare)) {
    unlink(cfg$paths$robustness_compare)
  }

  append_log(cfg$logs$model_run, sprintf("\n## [%s] 02_run_robustness", timestamp()))
  append_log(
    cfg$logs$model_run,
    sprintf(
      "- Robustness rows: %d (success=%d, skipped=%d, failed=%d)",
      nrow(res),
      sum(res$status == "success", na.rm = TRUE),
      sum(res$status == "not_estimated", na.rm = TRUE),
      sum(!res$status %in% c("success", "not_estimated"), na.rm = TRUE)
    )
  )
}
