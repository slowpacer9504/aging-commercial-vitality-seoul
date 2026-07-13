#==============================================================================
# Script    : 02_build_presentation_artifacts.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build slide-ready presentation tables and figures from quarterly
#             canonical outputs plus any available optional sidecars.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-04-01
# Status    : MANUAL_REPORTING / sidecar outside canonical workflow
# Type      : reporting_sidecar
# Inputs    : canonical ESDA/TWFE/SPDM outputs, optional SPDM-channel outputs,
#             optional GTWR outputs
# Outputs   : presentation_*.csv, presentation_*.png, presentation_manifest.csv
# DependsOn : 02_Code/02_esda/02_run_esda.R,
#             02_Code/03_models/01_run_twfe_main.R,
#             02_Code/03_models/02_run_spdm_main.R,
#             02_Code/80_optional/spdm/07_run_spdm_channel_path.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
load_project_packages()

ensure_dirs(c(cfg$dir_report, cfg$dir_logs))

append_log(
  cfg$logs$model_run,
  sprintf(
    "%s [REPORT] 02_build_presentation_artifacts.R start: building slide-ready artifacts in 03_Output/05_report",
    timestamp()
  )
)


#==============================================================================
# 1. Helpers
#==============================================================================

table_path <- function(filename) file.path(cfg$dir_tables, filename)
map_path <- function(filename) file.path(cfg$dir_maps, filename)

fmt_num <- function(x, digits = 3L) {
  ifelse(is.na(x), NA_character_, formatC(round(x, digits), digits = digits, format = "f"))
}

fmt_pct <- function(x, digits = 1L) {
  ifelse(is.na(x), NA_character_, paste0(formatC(100 * x, digits = digits, format = "f"), "%"))
}

fmt_p <- function(x) {
  dplyr::case_when(
    is.na(x) ~ NA_character_,
    x < 0.001 ~ "<0.001",
    TRUE ~ formatC(x, digits = 3, format = "f")
  )
}

sig_stars <- function(p) {
  dplyr::case_when(
    is.na(p) ~ "",
    p < 0.001 ~ "***",
    p < 0.01 ~ "**",
    p < 0.05 ~ "*",
    p < 0.1 ~ "+",
    TRUE ~ ""
  )
}

fmt_effect <- function(x, p = NA_real_, digits = 3L) {
  paste0(fmt_num(x, digits), sig_stars(p))
}

fmt_ci <- function(low, high, digits = 3L) {
  dplyr::case_when(
    is.na(low) | is.na(high) ~ NA_character_,
    TRUE ~ paste0("[", fmt_num(low, digits), ", ", fmt_num(high, digits), "]")
  )
}

label_inference_method <- function(x) {
  dplyr::case_when(
    x == "adm_cd_wild_residual" ~ "adm_cd wild residual bootstrap",
    x == "delta_independent_approx" ~ "Delta-method fallback",
    TRUE ~ x
  )
}

label_outcome <- function(x) {
  dplyr::case_when(
    x == "vitality_sub_economic" ~ "Economic Vitality",
    x == "vitality_sub_social" ~ "Social Vitality",
    x == "vitality_sub_temporal" ~ "Temporal Vitality",
    x == "vitality_sub_stability" ~ "Stability",
    x == "vitality_index_base" ~ "Composite Vitality Index",
    x == "vitality_index_entropy" ~ "Entropy Vitality Index",
    x == "vitality_index_pca" ~ "PCA Vitality Index",
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

label_variable <- function(x) {
  dplyr::case_when(
    x == "lag4_age60_resident_share" ~ "Lag-4 Age 60+ Resident Share",
    x == "age60_resident_share" ~ "Age 60+ Resident Share",
    x == "vitality_index_base" ~ "Composite Vitality Index",
    x == "ln_total_sales" ~ "Log Total Sales",
    TRUE ~ x
  )
}

label_w <- function(x) {
  dplyr::case_when(
    x == "queen" ~ "Queen",
    x == "rook" ~ "Rook",
    x == "knn6" ~ "kNN (6)",
    x == "knn8" ~ "kNN (8)",
    TRUE ~ x
  )
}

remove_if_exists <- function(path) {
  if (file.exists(path)) unlink(path)
  invisible(path)
}

copy_file_safe <- function(from, to) {
  fs::dir_create(fs::path_dir(to))
  tmp <- tempfile(
    pattern = ".presentation_copy_",
    tmpdir = fs::path_dir(to),
    fileext = paste0(".", tools::file_ext(to))
  )
  on.exit({
    if (file.exists(tmp)) unlink(tmp)
  }, add = TRUE)
  ok <- file.copy(from, tmp, overwrite = TRUE)
  if (!isTRUE(ok)) stop(sprintf("[ERROR] Failed to copy %s -> %s", from, tmp), call. = FALSE)
  ok <- file.rename(tmp, to)
  if (!isTRUE(ok)) stop(sprintf("[ERROR] Failed to promote copied artifact %s -> %s", tmp, to), call. = FALSE)
  invisible(to)
}

save_plot_safe <- function(plot_obj, path, width, height, dpi = 320) {
  fs::dir_create(fs::path_dir(path))
  tmp <- tempfile(
    pattern = ".presentation_plot_",
    tmpdir = fs::path_dir(path),
    fileext = paste0(".", tools::file_ext(path))
  )
  on.exit({
    if (file.exists(tmp)) unlink(tmp)
  }, add = TRUE)
  ggplot2::ggsave(filename = tmp, plot = plot_obj, width = width, height = height, dpi = dpi, bg = "white")
  ok <- file.rename(tmp, path)
  if (!isTRUE(ok)) stop(sprintf("[ERROR] Failed to promote plot artifact %s -> %s", tmp, path), call. = FALSE)
  invisible(path)
}

ensure_cols <- function(df, cols, fill = NA) {
  for (col in setdiff(cols, names(df))) {
    df[[col]] <- fill
  }
  df
}

artifact_rows <- list()

register_artifact <- function(
    artifact_name,
    artifact_path,
    artifact_type,
    status,
    source_paths = character(),
    source_mode = NA_character_,
    note = NA_character_) {
  artifact_rows[[length(artifact_rows) + 1L]] <<- tibble::tibble(
    artifact_name = artifact_name,
    artifact_path = artifact_path,
    artifact_type = artifact_type,
    status = status,
    source_mode = source_mode,
    source_paths = paste(source_paths, collapse = ";"),
    note = note
  )
}

mark_missing_artifact <- function(
    artifact_name,
    artifact_path,
    artifact_type,
    source_paths,
    note,
    source_mode = NA_character_) {
  remove_if_exists(artifact_path)
  register_artifact(
    artifact_name = artifact_name,
    artifact_path = artifact_path,
    artifact_type = artifact_type,
    status = "missing_source",
    source_paths = source_paths,
    source_mode = source_mode,
    note = note
  )
}

mark_deferred_artifact <- function(
    artifact_name,
    artifact_path,
    artifact_type,
    source_paths,
    note,
    source_mode = NA_character_) {
  remove_if_exists(artifact_path)
  register_artifact(
    artifact_name = artifact_name,
    artifact_path = artifact_path,
    artifact_type = artifact_type,
    status = "not_run_appendix",
    source_paths = source_paths,
    source_mode = source_mode,
    note = note
  )
}

mark_not_run_appendix_artifact <- function(
    artifact_name,
    artifact_path,
    artifact_type,
    source_paths,
    note,
    source_mode = NA_character_) {
  remove_if_exists(artifact_path)
  register_artifact(
    artifact_name = artifact_name,
    artifact_path = artifact_path,
    artifact_type = artifact_type,
    status = "not_run_appendix",
    source_paths = source_paths,
    source_mode = source_mode,
    note = note
  )
}

make_spdm_channel_path_diagram <- function(diagram_tbl) {
  a_row <- diagram_tbl |>
    dplyr::filter(is.finite(a_total)) |>
    dplyr::slice_head(n = 1L)
  a_label <- if (nrow(a_row) > 0L) {
    paste0("a path\nX -> M\n", fmt_effect(a_row$a_total[[1]], a_row$a_p[[1]]))
  } else {
    "a path\nX -> M"
  }

  indirect_tbl <- diagram_tbl |>
    dplyr::mutate(
      outcome_label_short = dplyr::case_when(
        outcome == "vitality_sub_economic" ~ "Economic",
        outcome == "vitality_sub_temporal" ~ "Temporal",
        outcome == "vitality_sub_stability" ~ "Stability",
        outcome == "vitality_index_base" ~ "Composite",
        TRUE ~ label_outcome(outcome)
      ),
      indirect_label = paste0(outcome_label_short, ": ", fmt_effect(indirect_total, indirect_p))
    ) |>
    dplyr::arrange(outcome_order)

  indirect_label <- paste(indirect_tbl$indirect_label, collapse = "\n")
  sample_label <- diagram_tbl |>
    dplyr::filter(is.finite(n_units), is.finite(n_periods)) |>
    dplyr::slice_head(n = 1L)
  sample_text <- if (nrow(sample_label) > 0L) {
    sprintf(
      "Quarterly Queen SPDM, %d dongs x %d periods (%s-%s)",
      as.integer(sample_label$n_units[[1]]),
      as.integer(sample_label$n_periods[[1]]),
      as.character(sample_label$sample_min_yq[[1]]),
      as.character(sample_label$sample_max_yq[[1]])
    )
  } else {
    "Quarterly Queen SPDM"
  }

  node_tbl <- tibble::tribble(
    ~node, ~x, ~y, ~label, ~fill, ~color,
    "X", 0.12, 0.55, "X\nAge 60+\nResident Share", "#EAF1FF", "#1F5FFF",
    "M", 0.50, 0.78, "M\nAge 60+\nFloating Share", "#E9F7F1", "#009E73",
    "Y", 0.88, 0.55, "Y\nCommercial\nVitality Outcomes", "#FFF2E8", "#D55E00"
  )

  ggplot2::ggplot() +
    ggplot2::annotate(
      "rect",
      xmin = 0.02, xmax = 0.98, ymin = 0.06, ymax = 0.95,
      fill = "#FAFCFF", color = "#D9E3F0", linewidth = 0.7
    ) +
    ggplot2::geom_curve(
      ggplot2::aes(x = 0.24, y = 0.62, xend = 0.40, yend = 0.75),
      curvature = 0.08, arrow = grid::arrow(length = grid::unit(0.18, "inches")),
      linewidth = 1.1, color = "#009E73"
    ) +
    ggplot2::geom_curve(
      ggplot2::aes(x = 0.60, y = 0.75, xend = 0.76, yend = 0.62),
      curvature = -0.08, arrow = grid::arrow(length = grid::unit(0.18, "inches")),
      linewidth = 1.1, color = "#009E73"
    ) +
    ggplot2::geom_segment(
      ggplot2::aes(x = 0.24, y = 0.50, xend = 0.75, yend = 0.50),
      arrow = grid::arrow(length = grid::unit(0.18, "inches")),
      linewidth = 0.95, color = "#D55E00"
    ) +
    ggplot2::geom_curve(
      ggplot2::aes(x = 0.24, y = 0.42, xend = 0.75, yend = 0.42),
      curvature = -0.18, arrow = grid::arrow(length = grid::unit(0.16, "inches")),
      linewidth = 0.75, linetype = "22", color = "#5B6C8F"
    ) +
    ggplot2::geom_label(
      data = node_tbl,
      ggplot2::aes(x = x, y = y, label = label, fill = fill, color = color),
      size = 4.1,
      fontface = "bold",
      linewidth = 0.8,
      label.r = grid::unit(0.16, "lines"),
      label.padding = grid::unit(0.55, "lines"),
      lineheight = 0.92,
      show.legend = FALSE
    ) +
    ggplot2::scale_fill_identity() +
    ggplot2::scale_color_identity() +
    ggplot2::annotate(
      "label",
      x = 0.32, y = 0.83, label = a_label,
      fill = "white", color = "#137A5B", linewidth = 0.35, size = 3.4,
      lineheight = 0.95
    ) +
    ggplot2::annotate(
      "label",
      x = 0.68, y = 0.83, label = "b path\nM -> Y\noutcome-specific",
      fill = "white", color = "#137A5B", linewidth = 0.35, size = 3.4,
      lineheight = 0.95
    ) +
    ggplot2::annotate(
      "label",
      x = 0.50, y = 0.57, label = "c-prime direct path\nX -> Y | M",
      fill = "white", color = "#B04A00", linewidth = 0.35, size = 3.2,
      lineheight = 0.95
    ) +
    ggplot2::annotate(
      "label",
      x = 0.50, y = 0.31,
      label = paste0("a*b mediated channel\n", indirect_label),
      fill = "#F8FFFC", color = "#007A5A", linewidth = 0.35, size = 3.15,
      lineheight = 0.96
    ) +
    ggplot2::annotate(
      "text",
      x = 0.50, y = 0.18,
      label = "Dashed c path: X -> Y total effect without mediator",
      color = "#5B6C8F", size = 3.1
    ) +
    ggplot2::annotate(
      "text",
      x = 0.50, y = 0.10,
      label = sample_text,
      color = "#65758A", size = 3.0
    ) +
    ggplot2::labs(
      title = "SPDM Mediation-Oriented Channel Path",
      subtitle = "Resident aging affects commercial vitality directly and through floating-age composition"
    ) +
    ggplot2::coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), clip = "off") +
    ggplot2::theme_void(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 14, color = "#1B2638"),
      plot.subtitle = ggplot2::element_text(size = 10.5, color = "#5F6F84", margin = ggplot2::margin(b = 7)),
      plot.margin = ggplot2::margin(12, 12, 12, 12)
    )
}

resolve_gtwr_presentation_source <- function() {
  control_set <- cfg$gtwr_control_set_token(cfg$gtwr_control_set)
  latest_path <- cfg$get_gtwr_latest_summary_table_path(control_set)
  delta_path <- cfg$get_gtwr_delta_summary_table_path(control_set)
  main_path <- cfg$get_gtwr_main_models_path(control_set)
  usable_paths <- c(latest_path, main_path, delta_path)[file.exists(c(latest_path, main_path, delta_path))]
  if (length(usable_paths) > 0L) {
    return(list(
      control_set = control_set,
      source_control_set = cfg$gtwr_main_output_tag(control_set),
      latest_path = latest_path,
      delta_path = delta_path,
      main_path = main_path,
      source_paths = usable_paths
    ))
  }
  list(
    control_set = control_set,
    source_control_set = NA_character_,
    latest_path = NA_character_,
    delta_path = NA_character_,
    main_path = NA_character_,
    source_paths = character()
  )
}

read_gtwr_presentation_summary <- function(resolution) {
  if (!is.na(resolution$latest_path) && file.exists(resolution$latest_path)) {
    latest_tbl <- readr::read_csv(resolution$latest_path, show_col_types = FALSE)
    if (!"gtwr_family" %in% names(latest_tbl)) {
      latest_tbl$gtwr_family <- "resident"
    }
    return(
      latest_tbl |>
        dplyr::filter(gtwr_family == "resident") |>
        dplyr::mutate(source_table = basename(resolution$latest_path))
    )
  }
  if (!is.na(resolution$main_path) && file.exists(resolution$main_path)) {
    return(
      readr::read_csv(resolution$main_path, show_col_types = FALSE) |>
        dplyr::mutate(gtwr_family = "resident", source_table = basename(resolution$main_path))
    )
  }
  if (!is.na(resolution$delta_path) && file.exists(resolution$delta_path)) {
    delta_tbl <- readr::read_csv(resolution$delta_path, show_col_types = FALSE)
    if (!"gtwr_family" %in% names(delta_tbl)) {
      delta_tbl$gtwr_family <- "resident"
    }
    return(
      delta_tbl |>
        dplyr::filter(gtwr_family == "resident") |>
        dplyr::mutate(source_table = basename(resolution$delta_path))
    )
  }
  tibble::tibble()
}

first_matching_value <- function(x, pattern) {
  hit <- unique(stats::na.omit(x[stringr::str_detect(x, pattern)]))
  if (length(hit) == 0L) return(NA_character_)
  as.character(hit[[1]])
}


#==============================================================================
# 2. ESDA Presentation Artifacts
#==============================================================================

global_moran_source <- table_path("global_morans_i.csv")
global_bv_source <- table_path("global_bivariate_morans_i.csv")
bv_lisa_source <- table_path("bivariate_lisa_summary.csv")
bv_lisa_map_source <- map_path("bivariate_lisa_map__age60_resident_share__vitality_index_base.png")

if (file.exists(global_moran_source)) {
  global_moran_tbl <- readr::read_csv(global_moran_source, show_col_types = FALSE)
  latest_yq <- max(as.character(global_moran_tbl$yq), na.rm = TRUE)

  presentation_esda_global <- global_moran_tbl |>
    dplyr::filter(
      yq == latest_yq,
      w_type == "queen",
      variable %in% c("age60_resident_share", "vitality_index_base", "ln_total_sales")
    ) |>
    dplyr::transmute(
      Variable = label_variable(variable),
      `Moran's I` = fmt_num(moran_i),
      `p-value` = fmt_p(p_value),
      Quarter = yq,
      `Spatial Weights` = label_w(w_type),
      `Number of Dongs` = n_units
    )

  write_csv_safe(presentation_esda_global, cfg$paths$presentation_esda_global_moran)
  register_artifact(
    artifact_name = "presentation_esda_global_moran",
    artifact_path = cfg$paths$presentation_esda_global_moran,
    artifact_type = "csv",
    status = "created",
    source_paths = global_moran_source,
    note = "latest-quarter queen-only Global Moran summary for four presentation variables"
  )
} else {
  mark_missing_artifact(
    artifact_name = "presentation_esda_global_moran",
    artifact_path = cfg$paths$presentation_esda_global_moran,
    artifact_type = "csv",
    source_paths = global_moran_source,
    note = "global_morans_i.csv not found"
  )
}

if (file.exists(global_bv_source) && file.exists(bv_lisa_source)) {
  global_bv_tbl <- readr::read_csv(global_bv_source, show_col_types = FALSE)
  bv_lisa_tbl <- readr::read_csv(bv_lisa_source, show_col_types = FALSE)
  latest_yq_bv <- max(as.character(global_bv_tbl$yq), na.rm = TRUE)

  presentation_esda_bv <- global_bv_tbl |>
    dplyr::filter(
      yq == latest_yq_bv,
      w_type == "queen",
      var_x == "age60_resident_share",
      var_y == "vitality_index_base"
    ) |>
    dplyr::left_join(
      bv_lisa_tbl |>
        dplyr::filter(
          yq == latest_yq_bv,
          w_type == "queen",
          var_x == "age60_resident_share",
          var_y == "vitality_index_base"
        ),
      by = c("yq", "w_type", "var_x", "var_y", "n_units", "status", "message")
    ) |>
    dplyr::transmute(
      `Aging Variable` = label_variable(var_x),
      `Vitality Variable` = label_variable(var_y),
      `Global Bivariate Moran's I` = fmt_num(moran_bv),
      `p-value` = fmt_p(p_value),
      `Share Significant` = fmt_pct(share_significant),
      HH = n_high_high,
      HL = n_high_low,
      LH = n_low_high,
      LL = n_low_low,
      Quarter = yq,
      `Spatial Weights` = label_w(w_type),
      `Number of Dongs` = n_units
    )

  write_csv_safe(presentation_esda_bv, cfg$paths$presentation_esda_bivariate_summary)
  register_artifact(
    artifact_name = "presentation_esda_bivariate_summary",
    artifact_path = cfg$paths$presentation_esda_bivariate_summary,
    artifact_type = "csv",
    status = "created",
    source_paths = c(global_bv_source, bv_lisa_source),
    note = "resident aging x vitality index bivariate Moran/LISA summary"
  )
} else {
  mark_missing_artifact(
    artifact_name = "presentation_esda_bivariate_summary",
    artifact_path = cfg$paths$presentation_esda_bivariate_summary,
    artifact_type = "csv",
    source_paths = c(global_bv_source, bv_lisa_source),
    note = "global_bivariate_morans_i.csv or bivariate_lisa_summary.csv not found"
  )
}

if (file.exists(bv_lisa_map_source)) {
  copy_file_safe(bv_lisa_map_source, cfg$paths$presentation_esda_bivariate_lisa)
  register_artifact(
    artifact_name = "presentation_esda_bivariate_lisa",
    artifact_path = cfg$paths$presentation_esda_bivariate_lisa,
    artifact_type = "png",
    status = "created",
    source_paths = bv_lisa_map_source,
    note = "copied representative bivariate LISA map"
  )
} else {
  mark_missing_artifact(
    artifact_name = "presentation_esda_bivariate_lisa",
    artifact_path = cfg$paths$presentation_esda_bivariate_lisa,
    artifact_type = "png",
    source_paths = bv_lisa_map_source,
    note = "representative bivariate LISA map not found"
  )
}


#==============================================================================
# 3. TWFE Presentation Artifacts
#==============================================================================

twfe_main_source <- cfg$paths$twfe_main_models
twfe_residual_source <- cfg$paths$twfe_main_residual_moran_summary
twfe_presentation_exposures <- unique(as.character(value_or(
  cfg$twfe_main_exposure_vars,
  "lag4_age60_resident_share"
)))

if (file.exists(twfe_main_source) && file.exists(twfe_residual_source)) {
  twfe_main_tbl <- readr::read_csv(twfe_main_source, show_col_types = FALSE)
  twfe_resid_tbl <- readr::read_csv(twfe_residual_source, show_col_types = FALSE)

  presentation_twfe_tbl <- twfe_main_tbl |>
    dplyr::filter(grepl("__m2$", model_name), term == exposure, exposure %in% twfe_presentation_exposures) |>
    dplyr::select(outcome, outcome_order, estimate, p.value, nobs) |>
    dplyr::distinct() |>
    dplyr::left_join(
      twfe_resid_tbl |>
        dplyr::select(outcome, sample_min_yq, sample_max_yq, mean_moran_i, share_p_lt_0_05, latest_yq, latest_moran_i, latest_p),
      by = "outcome"
    ) |>
    dplyr::arrange(outcome_order) |>
    dplyr::transmute(
      Outcome = label_outcome(outcome),
      `TWFE Coefficient (M2)` = fmt_num(estimate),
      `TWFE p-value` = fmt_p(p.value),
      `Mean Residual Moran's I` = fmt_num(mean_moran_i),
      `Share of Quarters with p<0.05` = fmt_pct(share_p_lt_0_05),
      `Latest Quarter` = latest_yq,
      `Latest Quarter Moran's I` = fmt_num(latest_moran_i),
      `Latest Quarter p-value` = fmt_p(latest_p),
      `Sample Window` = paste(sample_min_yq, sample_max_yq, sep = " ~ "),
      `Number of Observations` = nobs
    )

  write_csv_safe(presentation_twfe_tbl, cfg$paths$presentation_twfe_space_dependence)
  register_artifact(
    artifact_name = "presentation_twfe_space_dependence",
    artifact_path = cfg$paths$presentation_twfe_space_dependence,
    artifact_type = "csv",
    status = "created",
    source_paths = c(twfe_main_source, twfe_residual_source),
    note = "quarterly M2 focal coefficients joined with residual Moran summary"
  )

  twfe_plot_tbl <- twfe_main_tbl |>
    dplyr::filter(grepl("__m2$", model_name), term == exposure, exposure %in% twfe_presentation_exposures) |>
    dplyr::select(outcome, estimate, std.error) |>
    dplyr::distinct() |>
    dplyr::mutate(
      outcome_label = factor(label_outcome(outcome), levels = presentation_outcome_levels(reverse = TRUE))
    ) |>
    dplyr::arrange(outcome_label)

  twfe_plot <- ggplot2::ggplot(twfe_plot_tbl, ggplot2::aes(x = estimate, y = outcome_label)) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "grey55") +
    ggplot2::geom_errorbar(
      ggplot2::aes(xmin = estimate - 1.96 * std.error, xmax = estimate + 1.96 * std.error),
      width = 0.14,
      orientation = "y",
      color = "#607D8B"
    ) +
    ggplot2::geom_point(size = 2.8, color = "#1D3557") +
    ggplot2::labs(
      title = "TWFE Main Results (M2)",
      subtitle = "Age 60+ resident share across vitality outcomes",
      x = "Estimated Coefficient",
      y = NULL
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank())

  save_plot_safe(twfe_plot, cfg$paths$presentation_twfe_coefplot, width = 8.8, height = 5.4)
  register_artifact(
    artifact_name = "presentation_twfe_coefplot",
    artifact_path = cfg$paths$presentation_twfe_coefplot,
    artifact_type = "png",
    status = "created",
    source_paths = c(twfe_main_source, twfe_residual_source),
    note = "presentation-specific quarterly TWFE coefficient plot"
  )
} else {
  mark_missing_artifact(
    artifact_name = "presentation_twfe_space_dependence",
    artifact_path = cfg$paths$presentation_twfe_space_dependence,
    artifact_type = "csv",
    source_paths = c(twfe_main_source, twfe_residual_source),
    note = "twfe main or residual Moran summary source missing"
  )
  mark_missing_artifact(
    artifact_name = "presentation_twfe_coefplot",
    artifact_path = cfg$paths$presentation_twfe_coefplot,
    artifact_type = "png",
    source_paths = c(twfe_main_source, twfe_residual_source),
    note = "twfe main or residual Moran summary source missing"
  )
}


#==============================================================================
# 4. SPDM Presentation Artifacts
#==============================================================================

spdm_main_source <- cfg$paths$spdm_impacts
spdm_w_source <- cfg$paths$spdm_w_robustness_impacts
spdm_channel_models_source <- cfg$paths$spdm_channel_models
spdm_channel_impacts_source <- cfg$paths$spdm_channel_impacts
spdm_channel_path_effects_source <- cfg$paths$spdm_channel_path_effects
spdm_channel_bootstrap_source <- cfg$paths$spdm_channel_bootstrap_draws
spdm_channel_diagnostics_source <- cfg$paths$spdm_channel_diagnostics

if (file.exists(spdm_main_source)) {
  spdm_main_tbl <- readr::read_csv(spdm_main_source, show_col_types = FALSE) |>
    dplyr::filter(status == "success") |>
    dplyr::arrange(outcome_order)

  presentation_spdm_main_tbl <- spdm_main_tbl |>
    dplyr::transmute(
      Outcome = label_outcome(outcome),
      `Direct Effect` = fmt_num(direct),
      `Direct Effect p-value` = fmt_p(direct_p),
      `Indirect Effect` = fmt_num(indirect),
      `Indirect Effect p-value` = fmt_p(indirect_p),
      `Total Effect` = fmt_num(total),
      `Total Effect p-value` = fmt_p(total_p),
      `Number of Dongs` = n_units,
      `Number of Periods` = n_periods,
      `Sample Window` = paste(sample_min_yq, sample_max_yq, sep = " ~ "),
      `Spatial Weights` = label_w(w_type)
    )
  write_csv_safe(presentation_spdm_main_tbl, cfg$paths$presentation_spdm_main)
  register_artifact(
    artifact_name = "presentation_spdm_main",
    artifact_path = cfg$paths$presentation_spdm_main,
    artifact_type = "csv",
    status = "created",
    source_paths = spdm_main_source,
    note = "full vitality outcome grid with direct-indirect-total impacts"
  )

  spdm_main_plot_tbl <- spdm_main_tbl |>
    dplyr::transmute(
      outcome_label = label_outcome(outcome),
      direct = direct,
      direct_ci_low = direct_ci_low,
      direct_ci_high = direct_ci_high,
      indirect = indirect,
      indirect_ci_low = indirect_ci_low,
      indirect_ci_high = indirect_ci_high,
      total = total,
      total_ci_low = total_ci_low,
      total_ci_high = total_ci_high
    ) |>
    tidyr::pivot_longer(cols = c(direct, indirect, total), names_to = "effect_type", values_to = "estimate") |>
    dplyr::mutate(
      ci_low = dplyr::case_when(
        effect_type == "direct" ~ direct_ci_low,
        effect_type == "indirect" ~ indirect_ci_low,
        TRUE ~ total_ci_low
      ),
      ci_high = dplyr::case_when(
        effect_type == "direct" ~ direct_ci_high,
        effect_type == "indirect" ~ indirect_ci_high,
        TRUE ~ total_ci_high
      ),
      effect_label = dplyr::case_when(
        effect_type == "direct" ~ "Direct Effect",
        effect_type == "indirect" ~ "Indirect Effect",
        TRUE ~ "Total Effect"
      ),
      outcome_label = factor(outcome_label, levels = presentation_outcome_levels())
    )

  spdm_main_plot <- ggplot2::ggplot(
    spdm_main_plot_tbl,
    ggplot2::aes(x = outcome_label, y = estimate, color = effect_label)
  ) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "grey55") +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = ci_low, ymax = ci_high),
      width = 0.12,
      position = ggplot2::position_dodge(width = 0.5)
    ) +
    ggplot2::geom_point(size = 2.8, position = ggplot2::position_dodge(width = 0.5)) +
    ggplot2::scale_color_manual(
      values = c("Direct Effect" = "#264653", "Indirect Effect" = "#2A9D8F", "Total Effect" = "#E76F51")
    ) +
    ggplot2::labs(
      title = "Main SPDM Results",
      subtitle = "Quarterly direct, indirect, and total effects",
      x = NULL,
      y = "Estimated Effect",
      color = NULL
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "top", panel.grid.minor = ggplot2::element_blank())

  save_plot_safe(spdm_main_plot, cfg$paths$presentation_spdm_main_plot, width = 9.4, height = 5.6)
  register_artifact(
    artifact_name = "presentation_spdm_main_plot",
    artifact_path = cfg$paths$presentation_spdm_main_plot,
    artifact_type = "png",
    status = "created",
    source_paths = spdm_main_source,
    note = "presentation-specific quarterly SPDM main plot"
  )
} else {
  mark_missing_artifact(
    artifact_name = "presentation_spdm_main",
    artifact_path = cfg$paths$presentation_spdm_main,
    artifact_type = "csv",
    source_paths = spdm_main_source,
    note = "spdm_impacts.csv not found"
  )
  mark_missing_artifact(
    artifact_name = "presentation_spdm_main_plot",
    artifact_path = cfg$paths$presentation_spdm_main_plot,
    artifact_type = "png",
    source_paths = spdm_main_source,
    note = "spdm_impacts.csv not found"
  )
}

if (file.exists(spdm_w_source)) {
  spdm_w_tbl <- readr::read_csv(spdm_w_source, show_col_types = FALSE) |>
    dplyr::filter(status == "success")

  main_outcomes <- c(
    "vitality_sub_economic",
    "vitality_sub_social",
    "vitality_sub_temporal",
    "vitality_sub_stability",
    "vitality_index_base"
  )

  presentation_spdm_w_tbl <- spdm_w_tbl |>
    dplyr::filter(outcome %in% main_outcomes) |>
    dplyr::arrange(match(outcome, main_outcomes), w_type) |>
    dplyr::transmute(
      Outcome = label_outcome(outcome),
      `Spatial Weights` = label_w(w_type),
      `Total Effect` = fmt_num(total),
      `Total Effect p-value` = fmt_p(total_p),
      `Direct Effect` = fmt_num(direct),
      `Indirect Effect` = fmt_num(indirect),
      `Number of Dongs` = n_units,
      `Number of Periods` = n_periods,
      `Sample Window` = paste(sample_min_yq, sample_max_yq, sep = " ~ ")
    )
  write_csv_safe(presentation_spdm_w_tbl, cfg$paths$presentation_spdm_w_robustness)
  register_artifact(
    artifact_name = "presentation_spdm_w_robustness",
    artifact_path = cfg$paths$presentation_spdm_w_robustness,
    artifact_type = "csv",
    status = "created",
    source_paths = spdm_w_source,
    note = "quarterly W-robustness summary for main outcomes"
  )

  presentation_spdm_w_all_tbl <- spdm_w_tbl |>
    dplyr::arrange(outcome_order, w_type) |>
    dplyr::transmute(
      Outcome = label_outcome(outcome),
      `Spatial Weights` = label_w(w_type),
      `Total Effect` = fmt_num(total),
      `Total Effect p-value` = fmt_p(total_p),
      `Direct Effect` = fmt_num(direct),
      `Indirect Effect` = fmt_num(indirect),
      `Number of Dongs` = n_units,
      `Number of Periods` = n_periods,
      `Sample Window` = paste(sample_min_yq, sample_max_yq, sep = " ~ ")
    )
  write_csv_safe(presentation_spdm_w_all_tbl, cfg$paths$presentation_spdm_w_robustness_all_outcomes)
  register_artifact(
    artifact_name = "presentation_spdm_w_robustness_all_outcomes",
    artifact_path = cfg$paths$presentation_spdm_w_robustness_all_outcomes,
    artifact_type = "csv",
    status = "created",
    source_paths = spdm_w_source,
    note = "quarterly W-robustness summary for all available outcomes"
  )

  build_w_plot <- function(df, title_text, path, artifact_name, note_text) {
    plot_tbl <- df |>
      dplyr::mutate(
        outcome_label = factor(label_outcome(outcome), levels = presentation_outcome_levels()),
        w_label = factor(label_w(w_type), levels = c("Queen", "Rook", "kNN (6)", "kNN (8)"))
      )

    plot_obj <- ggplot2::ggplot(plot_tbl, ggplot2::aes(x = outcome_label, y = total, color = w_label, group = w_label)) +
      ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "grey55") +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::geom_point(size = 2.4) +
      ggplot2::labs(
        title = title_text,
        subtitle = "Annual total effects across alternative spatial-weight matrices",
        x = NULL,
        y = "Total Effect",
        color = NULL
      ) +
      ggplot2::theme_minimal(base_size = 11) +
      ggplot2::theme(legend.position = "top", panel.grid.minor = ggplot2::element_blank())

    save_plot_safe(plot_obj, path, width = 9.2, height = 5.6)
    register_artifact(
      artifact_name = artifact_name,
      artifact_path = path,
      artifact_type = "png",
      status = "created",
      source_paths = spdm_w_source,
      note = note_text
    )
  }

  build_w_plot(
    spdm_w_tbl |> dplyr::filter(outcome %in% main_outcomes),
    "SPDM W Robustness",
    cfg$paths$presentation_spdm_w_robustness_plot,
    "presentation_spdm_w_robustness_plot",
    "quarterly W-robustness plot for main outcomes"
  )
  build_w_plot(
    spdm_w_tbl,
    "SPDM W Robustness Across All Outcomes",
    cfg$paths$presentation_spdm_w_robustness_all_outcomes_plot,
    "presentation_spdm_w_robustness_all_outcomes_plot",
    "quarterly W-robustness plot for all available outcomes"
  )
} else {
  for (artifact in list(
    list("presentation_spdm_w_robustness", cfg$paths$presentation_spdm_w_robustness, "csv"),
    list("presentation_spdm_w_robustness_plot", cfg$paths$presentation_spdm_w_robustness_plot, "png"),
    list("presentation_spdm_w_robustness_all_outcomes", cfg$paths$presentation_spdm_w_robustness_all_outcomes, "csv"),
    list("presentation_spdm_w_robustness_all_outcomes_plot", cfg$paths$presentation_spdm_w_robustness_all_outcomes_plot, "png")
  )) {
    mark_missing_artifact(
      artifact_name = artifact[[1]],
      artifact_path = artifact[[2]],
      artifact_type = artifact[[3]],
      source_paths = spdm_w_source,
      note = "spdm_w_robustness_impacts.csv not found"
    )
  }
}


#==============================================================================
# 5. SPDM Channel Path Presentation Artifacts
#==============================================================================

spdm_channel_sources <- c(
  spdm_channel_models_source,
  spdm_channel_impacts_source,
  spdm_channel_path_effects_source,
  spdm_channel_bootstrap_source,
  spdm_channel_diagnostics_source
)

if (all(file.exists(spdm_channel_sources))) {
  spdm_channel_imp_tbl <- readr::read_csv(spdm_channel_impacts_source, show_col_types = FALSE)
  spdm_channel_path_tbl <- readr::read_csv(spdm_channel_path_effects_source, show_col_types = FALSE)
  spdm_channel_diag_tbl <- readr::read_csv(spdm_channel_diagnostics_source, show_col_types = FALSE)

  outcome_base_tbl <- tibble::tibble(
    outcome = cfg$spdm_channel_outcomes,
    outcome_order = seq_along(cfg$spdm_channel_outcomes)
  )

  channel_total_path_tbl <- spdm_channel_path_tbl |>
    dplyr::filter(effect_scale == "total") |>
    dplyr::transmute(
      outcome,
      c_total = suppressWarnings(as.numeric(c_total_estimate)),
      c_total_p = suppressWarnings(as.numeric(c_total_p)),
      c_total_ci_low = suppressWarnings(as.numeric(c_total_ci_low)),
      c_total_ci_high = suppressWarnings(as.numeric(c_total_ci_high)),
      indirect_total = suppressWarnings(as.numeric(indirect_effect)),
      indirect_total_se = suppressWarnings(as.numeric(indirect_se)),
      indirect_total_p = suppressWarnings(as.numeric(indirect_p)),
      indirect_total_ci_low = suppressWarnings(as.numeric(indirect_ci_low)),
      indirect_total_ci_high = suppressWarnings(as.numeric(indirect_ci_high)),
      delta_indirect_total_se = suppressWarnings(as.numeric(delta_indirect_se)),
      delta_indirect_total_p = suppressWarnings(as.numeric(delta_indirect_p)),
      delta_indirect_total_ci_low = suppressWarnings(as.numeric(delta_indirect_ci_low)),
      delta_indirect_total_ci_high = suppressWarnings(as.numeric(delta_indirect_ci_high)),
      bootstrap_total_se = suppressWarnings(as.numeric(bootstrap_se)),
      bootstrap_total_p = suppressWarnings(as.numeric(bootstrap_p)),
      bootstrap_total_ci_low = suppressWarnings(as.numeric(bootstrap_ci_low)),
      bootstrap_total_ci_high = suppressWarnings(as.numeric(bootstrap_ci_high)),
      bootstrap_valid_draws = suppressWarnings(as.integer(bootstrap_valid_draws)),
      bootstrap_R = suppressWarnings(as.integer(bootstrap_R)),
      bootstrap_method,
      mediated_share_vs_cprime = suppressWarnings(as.numeric(mediated_share_vs_cprime)),
      inference_method,
      channel_status_raw = status,
      channel_note = message,
      n_units, n_periods, sample_min_yq, sample_max_yq
    )

  channel_imp_total_tbl <- spdm_channel_imp_tbl |>
    dplyr::filter(path %in% c("a_x_to_m", "b_m_to_y", "c_prime_x_to_y")) |>
    dplyr::mutate(join_outcome = dplyr::coalesce(target_outcome, outcome)) |>
      dplyr::select(join_outcome, path, total, total_se, total_p, total_ci_low, total_ci_high) |>
    tidyr::pivot_wider(
      names_from = path,
      values_from = c(total, total_se, total_p, total_ci_low, total_ci_high),
      names_glue = "{path}_{.value}"
    ) |>
    dplyr::rename(outcome = join_outcome)

  channel_status_tbl <- spdm_channel_diag_tbl |>
    dplyr::filter(equation == "outcome") |>
    dplyr::transmute(
      outcome,
      `Channel Spec Status` = dplyr::case_when(
        status == "success" & impacts_status == "success" ~ "Estimated",
        status == "failed" ~ "Failed",
        TRUE ~ status
      ),
      `Channel Note` = dplyr::case_when(
        status == "success" & impacts_status == "success" ~ "Estimated successfully",
        TRUE ~ message
      )
    )

  channel_joined_tbl <- outcome_base_tbl |>
    dplyr::left_join(channel_imp_total_tbl, by = "outcome") |>
    dplyr::left_join(channel_total_path_tbl, by = "outcome") |>
    dplyr::left_join(channel_status_tbl, by = "outcome")

  channel_joined_tbl <- ensure_cols(
    channel_joined_tbl,
    c(
      "c_total", "c_total_p",
      "c_total_ci_low", "c_total_ci_high",
      "a_x_to_m_total", "a_x_to_m_total_p",
      "b_m_to_y_total", "b_m_to_y_total_p",
      "c_prime_x_to_y_total", "c_prime_x_to_y_total_p",
      "c_prime_x_to_y_total_ci_low", "c_prime_x_to_y_total_ci_high",
      "indirect_total", "indirect_total_se", "indirect_total_p",
      "indirect_total_ci_low", "indirect_total_ci_high",
      "delta_indirect_total_se", "delta_indirect_total_p",
      "delta_indirect_total_ci_low", "delta_indirect_total_ci_high",
      "bootstrap_total_se", "bootstrap_total_p",
      "bootstrap_total_ci_low", "bootstrap_total_ci_high",
      "bootstrap_valid_draws", "bootstrap_R", "bootstrap_method",
      "mediated_share_vs_cprime", "inference_method",
      "Channel Spec Status", "Channel Note",
      "n_units", "n_periods", "sample_min_yq", "sample_max_yq"
    )
  )

  presentation_spdm_channel_tbl <- channel_joined_tbl |>
    dplyr::arrange(outcome_order) |>
    dplyr::mutate(
      bootstrap_completion = dplyr::if_else(
        is.finite(as.numeric(bootstrap_R)) & as.numeric(bootstrap_R) > 0,
        as.numeric(bootstrap_valid_draws) / as.numeric(bootstrap_R),
        NA_real_
      ),
      inference_detail = dplyr::case_when(
        inference_method == "adm_cd_wild_residual" ~ "Primary SE/CI/p-value use adm_cd wild residual bootstrap",
        inference_method == "delta_independent_approx" & is.finite(as.numeric(bootstrap_R)) & as.numeric(bootstrap_R) > 0 ~
          "Delta fallback used because bootstrap did not provide enough valid draws",
        inference_method == "delta_independent_approx" ~ "Delta fallback used because bootstrap was not run",
        TRUE ~ inference_method
      )
    ) |>
    dplyr::transmute(
      Outcome = label_outcome(outcome),
      `c Total Effect without Mediator` = fmt_num(c_total),
      `c Total Effect p-value` = fmt_p(c_total_p),
      `a Path Total Effect: Resident -> Floating` = fmt_num(a_x_to_m_total),
      `a Path p-value` = fmt_p(a_x_to_m_total_p),
      `b Path Total Effect: Floating -> Vitality` = fmt_num(b_m_to_y_total),
      `b Path p-value` = fmt_p(b_m_to_y_total_p),
      `c-prime Total Effect: Resident -> Vitality` = fmt_num(c_prime_x_to_y_total),
      `c-prime p-value` = fmt_p(c_prime_x_to_y_total_p),
      `Indirect Total Effect a*b` = fmt_num(indirect_total),
      `Indirect Total Effect SE` = fmt_num(indirect_total_se),
      `Indirect Total Effect p-value` = fmt_p(indirect_total_p),
      `Indirect Total Effect 95% CI` = fmt_ci(indirect_total_ci_low, indirect_total_ci_high),
      `Primary Indirect Inference` = label_inference_method(inference_method),
      `Bootstrap Method` = bootstrap_method,
      `Bootstrap Valid Draws` = bootstrap_valid_draws,
      `Bootstrap Requested Draws` = bootstrap_R,
      `Bootstrap Completion Share` = fmt_pct(bootstrap_completion),
      `Bootstrap Indirect p-value` = fmt_p(bootstrap_total_p),
      `Bootstrap Indirect 95% CI` = fmt_ci(bootstrap_total_ci_low, bootstrap_total_ci_high),
      `Delta Fallback Indirect p-value` = fmt_p(delta_indirect_total_p),
      `Delta Fallback Indirect 95% CI` = fmt_ci(delta_indirect_total_ci_low, delta_indirect_total_ci_high),
      `Indirect Share Diagnostic vs c-prime` = fmt_num(mediated_share_vs_cprime),
      `Inference Detail` = inference_detail,
      `Interpretation Scope` = "SPDM mediation-oriented channel inference; standalone social outcome excluded, but composite index retains social vitality",
      `Channel Spec Status` = `Channel Spec Status`,
      `Channel Note` = `Channel Note`,
      `Number of Dongs` = n_units,
      `Number of Periods` = n_periods,
      `Sample Window` = paste(sample_min_yq, sample_max_yq, sep = " ~ ")
    )

  write_csv_safe(presentation_spdm_channel_tbl, cfg$paths$presentation_spdm_channel)
  register_artifact(
    artifact_name = "presentation_spdm_channel",
    artifact_path = cfg$paths$presentation_spdm_channel,
    artifact_type = "csv",
    status = "created",
    source_paths = spdm_channel_sources,
    note = "optional quarterly SPDM channel path summary; standalone social outcome excluded while composite index retains social vitality"
  )

  spdm_channel_path_diagram_tbl <- channel_joined_tbl |>
    dplyr::arrange(outcome_order) |>
    dplyr::transmute(
      Outcome = label_outcome(outcome),
      outcome,
      outcome_order,
      `a Path Total Effect: Resident -> Floating` = a_x_to_m_total,
      `a Path p-value` = a_x_to_m_total_p,
      `b Path Total Effect: Floating -> Vitality` = b_m_to_y_total,
      `b Path p-value` = b_m_to_y_total_p,
      `c Total Effect without Mediator` = c_total,
      `c Total Effect p-value` = c_total_p,
      `c-prime Total Effect: Resident -> Vitality` = c_prime_x_to_y_total,
      `c-prime p-value` = c_prime_x_to_y_total_p,
      `Indirect Total Effect a*b` = indirect_total,
      `Indirect Total Effect p-value` = indirect_total_p,
      `Number of Dongs` = n_units,
      `Number of Periods` = n_periods,
      `Sample Window` = paste(sample_min_yq, sample_max_yq, sep = " ~ ")
    )

  write_csv_safe(spdm_channel_path_diagram_tbl, cfg$paths$presentation_spdm_channel_path_diagram_data)
  register_artifact(
    artifact_name = "presentation_spdm_channel_path_diagram_data",
    artifact_path = cfg$paths$presentation_spdm_channel_path_diagram_data,
    artifact_type = "csv",
    status = "created",
    source_paths = spdm_channel_sources,
    note = "slide-ready X -> M -> Y SPDM channel path diagram data"
  )

  spdm_channel_path_diagram_input <- channel_joined_tbl |>
    dplyr::arrange(outcome_order) |>
    dplyr::transmute(
      outcome,
      outcome_order,
      a_total = suppressWarnings(as.numeric(a_x_to_m_total)),
      a_p = suppressWarnings(as.numeric(a_x_to_m_total_p)),
      indirect_total = suppressWarnings(as.numeric(indirect_total)),
      indirect_p = suppressWarnings(as.numeric(indirect_total_p)),
      n_units = suppressWarnings(as.numeric(n_units)),
      n_periods = suppressWarnings(as.numeric(n_periods)),
      sample_min_yq = as.character(sample_min_yq),
      sample_max_yq = as.character(sample_max_yq)
    )

  spdm_channel_path_diagram <- make_spdm_channel_path_diagram(spdm_channel_path_diagram_input)
  save_plot_safe(
    spdm_channel_path_diagram,
    cfg$paths$presentation_spdm_channel_path_diagram,
    width = 9.4,
    height = 5.8
  )
  register_artifact(
    artifact_name = "presentation_spdm_channel_path_diagram",
    artifact_path = cfg$paths$presentation_spdm_channel_path_diagram,
    artifact_type = "png",
    status = "created",
    source_paths = spdm_channel_sources,
    note = "slide-ready mediation path diagram for resident aging -> floating aging -> vitality"
  )

  spdm_channel_plot_tbl <- channel_joined_tbl |>
    dplyr::transmute(
      outcome_label = factor(label_outcome(outcome), levels = presentation_outcome_levels()),
      c_total = c_total,
      c_total_ci_low = c_total_ci_low,
      c_total_ci_high = c_total_ci_high,
      c_prime_total = c_prime_x_to_y_total,
      c_prime_total_ci_low = c_prime_x_to_y_total_ci_low,
      c_prime_total_ci_high = c_prime_x_to_y_total_ci_high,
      indirect_total_ci_low = indirect_total_ci_low,
      indirect_total_ci_high = indirect_total_ci_high,
      indirect_total = indirect_total
    ) |>
    tidyr::pivot_longer(
      cols = c(c_total, c_prime_total, indirect_total),
      names_to = "series",
      values_to = "estimate"
    ) |>
    dplyr::mutate(
      ci_low = dplyr::case_when(
        series == "c_total" ~ c_total_ci_low,
        series == "c_prime_total" ~ c_prime_total_ci_low,
        TRUE ~ indirect_total_ci_low
      ),
      ci_high = dplyr::case_when(
        series == "c_total" ~ c_total_ci_high,
        series == "c_prime_total" ~ c_prime_total_ci_high,
        TRUE ~ indirect_total_ci_high
      ),
      series_label = dplyr::case_when(
        series == "c_total" ~ "c Total Effect without Mediator",
        series == "c_prime_total" ~ "c-prime Total Effect with Mediator",
        TRUE ~ "a*b Indirect Total Effect"
      ),
      series_label = factor(
        series_label,
        levels = c(
          "c Total Effect without Mediator",
          "c-prime Total Effect with Mediator",
          "a*b Indirect Total Effect"
        )
      )
    )

  spdm_channel_plot <- ggplot2::ggplot(
    spdm_channel_plot_tbl,
    ggplot2::aes(x = outcome_label, y = estimate, color = series_label)
  ) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "grey55") +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = ci_low, ymax = ci_high),
      position = ggplot2::position_dodge(width = 0.58),
      width = 0.12,
      na.rm = TRUE
    ) +
    ggplot2::geom_point(
      position = ggplot2::position_dodge(width = 0.58),
      size = 2.6,
      na.rm = TRUE
    ) +
    ggplot2::scale_color_manual(
      values = c(
        "c Total Effect without Mediator" = "#5B6C8F",
        "c-prime Total Effect with Mediator" = "#D55E00",
        "a*b Indirect Total Effect" = "#009E73"
      )
    ) +
    ggplot2::labs(
      title = "SPDM Optional Channel Path",
      subtitle = "Resident aging -> floating aging -> vitality; standalone social outcome excluded, composite retained",
      x = NULL,
      y = "Estimated Total Effect",
      color = NULL,
      caption = "a*b error bars use the primary inference stored by 07_run_spdm_channel_path: bootstrap when valid, delta-method fallback otherwise."
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "top", panel.grid.minor = ggplot2::element_blank())

  save_plot_safe(spdm_channel_plot, cfg$paths$presentation_spdm_channel_plot, width = 9.4, height = 5.8)
  register_artifact(
    artifact_name = "presentation_spdm_channel_plot",
    artifact_path = cfg$paths$presentation_spdm_channel_plot,
    artifact_type = "png",
    status = "created",
    source_paths = spdm_channel_sources,
    note = "optional quarterly SPDM channel path plot using primary 07_run_spdm_channel_path inference intervals"
  )
} else {
  mark_missing_artifact(
    artifact_name = "presentation_spdm_channel",
    artifact_path = cfg$paths$presentation_spdm_channel,
    artifact_type = "csv",
    source_paths = spdm_channel_sources,
    note = "optional SPDM channel path source table missing"
  )
  mark_missing_artifact(
    artifact_name = "presentation_spdm_channel_path_diagram_data",
    artifact_path = cfg$paths$presentation_spdm_channel_path_diagram_data,
    artifact_type = "csv",
    source_paths = spdm_channel_sources,
    note = "optional SPDM channel path source table missing"
  )
  mark_missing_artifact(
    artifact_name = "presentation_spdm_channel_path_diagram",
    artifact_path = cfg$paths$presentation_spdm_channel_path_diagram,
    artifact_type = "png",
    source_paths = spdm_channel_sources,
    note = "optional SPDM channel path source table missing"
  )
  mark_missing_artifact(
    artifact_name = "presentation_spdm_channel_plot",
    artifact_path = cfg$paths$presentation_spdm_channel_plot,
    artifact_type = "png",
    source_paths = spdm_channel_sources,
    note = "optional SPDM channel path source table missing"
  )
}


#==============================================================================
# 6. GTWR Presentation Artifacts
#==============================================================================

gtwr_resolution <- resolve_gtwr_presentation_source()
gtwr_presentation_focals <- unique(as.character(value_or(
  cfg$gtwr_main_exposure_vars,
  "lag4_age60_resident_share"
)))

if (!is.na(gtwr_resolution$source_control_set)) {
  gtwr_summary_tbl <- read_gtwr_presentation_summary(gtwr_resolution) |>
    ensure_cols(c("recent_period_n", "earliest_yq", "latest_yq", "fit_scope", "message", "status", "source_table")) |>
    dplyr::mutate(
      period_n = suppressWarnings(as.integer(recent_period_n)),
      comparison_window = paste(.data$earliest_yq, .data$latest_yq, sep = " ~ ")
    ) |>
    dplyr::filter(focal_var %in% gtwr_presentation_focals) |>
    dplyr::mutate(outcome_order_presentation = match(outcome, cfg$gtwr_main_outcomes)) |>
    dplyr::arrange(outcome_order_presentation, outcome)

  if (nrow(gtwr_summary_tbl) == 0L) {
    mark_not_run_appendix_artifact(
      artifact_name = "presentation_gtwr_summary",
      artifact_path = cfg$paths$presentation_gtwr_summary,
      artifact_type = "csv",
      source_paths = gtwr_resolution$source_paths,
      source_mode = gtwr_resolution$source_control_set,
      note = "manual appendix not run: resolved GTWR source exists but no resident age60 rows were found"
    )
    mark_not_run_appendix_artifact(
      artifact_name = "presentation_gtwr_summary_plot",
      artifact_path = cfg$paths$presentation_gtwr_summary_plot,
      artifact_type = "png",
      source_paths = gtwr_resolution$source_paths,
      source_mode = gtwr_resolution$source_control_set,
      note = "manual appendix not run: resolved GTWR source exists but no resident age60 rows were found"
    )
  } else if (any(gtwr_summary_tbl$status == "success")) {
      gtwr_success_tbl <- gtwr_summary_tbl |>
        dplyr::filter(status == "success") |>
        ensure_cols(c("global_lm_r2", "global_gw_r2", "max_local_cn_gtwr")) |>
        dplyr::mutate(global_lm_r2 = dplyr::coalesce(.data$global_lm_r2, .data$global_gw_r2))

    presentation_gtwr_tbl <- gtwr_success_tbl |>
      dplyr::transmute(
        Outcome = label_outcome(outcome),
        source_control_set = gtwr_resolution$source_control_set,
        `Mean Beta` = fmt_num(mean_beta),
        `25th Percentile` = fmt_num(p25_beta),
        `Median Beta` = fmt_num(p50_beta),
        `75th Percentile` = fmt_num(p75_beta),
          `Share Positive` = fmt_pct(share_positive),
          `Global LM R2` = fmt_num(global_lm_r2),
          `Max GTWR Local CN` = fmt_num(max_local_cn_gtwr),
        `Comparison Window` = comparison_window,
        window_scope = window_scope,
        fit_scope = fit_scope,
        source_table = source_table
      )
    write_csv_safe(presentation_gtwr_tbl, cfg$paths$presentation_gtwr_summary)
    register_artifact(
      artifact_name = "presentation_gtwr_summary",
      artifact_path = cfg$paths$presentation_gtwr_summary,
      artifact_type = "csv",
      status = "created",
      source_paths = gtwr_resolution$source_paths,
      source_mode = gtwr_resolution$source_control_set,
      note = "GTWR success summary resolved from selected control set"
    )

    gtwr_plot_tbl <- gtwr_success_tbl |>
      dplyr::mutate(outcome_label = label_outcome(outcome))

    gtwr_plot <- ggplot2::ggplot(
      gtwr_plot_tbl,
      ggplot2::aes(x = factor(outcome_label, levels = outcome_label), y = p50_beta)
    ) +
      ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "grey55") +
      ggplot2::geom_linerange(ggplot2::aes(ymin = p25_beta, ymax = p75_beta), linewidth = 4, color = "#B8C7CC") +
      ggplot2::geom_point(size = 3.2, shape = 21, fill = "white", color = "#264653", stroke = 1) +
      ggplot2::geom_point(ggplot2::aes(y = mean_beta), size = 2.4, color = "#D1495B") +
      ggplot2::coord_flip() +
      ggplot2::labs(
        title = "GTWR Local-Coefficient Summary",
        subtitle = sprintf("control set: %s", gtwr_resolution$source_control_set),
        x = NULL,
        y = "Local-Coefficient Summary",
        caption = "Thick segment: 25th to 75th percentile, white point: median, red point: mean"
      ) +
      ggplot2::theme_minimal(base_size = 11) +
      ggplot2::theme(panel.grid.minor = ggplot2::element_blank())

    save_plot_safe(gtwr_plot, cfg$paths$presentation_gtwr_summary_plot, width = 8.2, height = 4.8)
    register_artifact(
      artifact_name = "presentation_gtwr_summary_plot",
      artifact_path = cfg$paths$presentation_gtwr_summary_plot,
      artifact_type = "png",
      status = "created",
      source_paths = gtwr_resolution$source_paths,
      source_mode = gtwr_resolution$source_control_set,
      note = "GTWR local-coefficient summary plot"
    )
  } else {
    presentation_gtwr_tbl <- gtwr_summary_tbl |>
      dplyr::transmute(
        Outcome = label_outcome(outcome),
        source_control_set = gtwr_resolution$source_control_set,
        Status = status,
        `Comparison Window` = comparison_window,
        fit_scope = fit_scope,
        `Number of Periods` = period_n,
        Message = message,
        source_table = source_table
      )
    write_csv_safe(presentation_gtwr_tbl, cfg$paths$presentation_gtwr_summary)
    register_artifact(
      artifact_name = "presentation_gtwr_summary",
      artifact_path = cfg$paths$presentation_gtwr_summary,
      artifact_type = "csv",
      status = "created",
      source_paths = gtwr_resolution$source_paths,
      source_mode = gtwr_resolution$source_control_set,
      note = "manual quarterly appendix summary created from GTWR raw outputs with only not-estimated rows"
    )
    mark_not_run_appendix_artifact(
      artifact_name = "presentation_gtwr_summary_plot",
      artifact_path = cfg$paths$presentation_gtwr_summary_plot,
      artifact_type = "png",
      source_paths = gtwr_resolution$source_paths,
      source_mode = gtwr_resolution$source_control_set,
      note = "manual quarterly appendix not run for plotting: GTWR raw outputs contain no success rows"
    )
  }
} else {
  missing_control_set <- cfg$gtwr_control_set_token(cfg$gtwr_control_set)
  missing_sources <- c(
    cfg$get_gtwr_latest_summary_table_path(missing_control_set),
    cfg$get_gtwr_delta_summary_table_path(missing_control_set),
    cfg$get_gtwr_main_models_path(missing_control_set)
  )
  mark_not_run_appendix_artifact(
    artifact_name = "presentation_gtwr_summary",
    artifact_path = cfg$paths$presentation_gtwr_summary,
    artifact_type = "csv",
    source_paths = missing_sources,
    note = "manual appendix not run: no GTWR source found for selected control set"
  )
  mark_not_run_appendix_artifact(
    artifact_name = "presentation_gtwr_summary_plot",
    artifact_path = cfg$paths$presentation_gtwr_summary_plot,
    artifact_type = "png",
    source_paths = missing_sources,
    note = "manual appendix not run: no GTWR source found for selected control set"
  )
}


#==============================================================================
# 7. Manifest
#==============================================================================

manifest_tbl <- dplyr::bind_rows(artifact_rows) |>
  dplyr::mutate(created_at = timestamp()) |>
  dplyr::arrange(artifact_name)

write_csv_safe(manifest_tbl, cfg$paths$presentation_manifest)

append_log(
  cfg$logs$model_run,
  sprintf(
    "%s [REPORT] 02_build_presentation_artifacts.R end: artifacts=%d, created=%d, not_run_appendix=%d, deferred=%d, missing=%d",
    timestamp(),
    nrow(manifest_tbl),
    sum(manifest_tbl$status == "created", na.rm = TRUE),
    sum(manifest_tbl$status == "not_run_appendix", na.rm = TRUE),
    sum(manifest_tbl$status == "deferred", na.rm = TRUE),
    sum(manifest_tbl$status == "missing_source", na.rm = TRUE)
  )
)
