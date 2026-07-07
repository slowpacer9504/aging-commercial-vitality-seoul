#==============================================================================
# Script    : 03_build_gtwr_level_artifacts.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Build paper-ready quarterly GTWR level artifacts from existing GTWR
#             local-beta outputs without rerunning GTWR.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-05-04
# Status    : MANUAL_REPORTING / sidecar outside canonical workflow
# Type      : reporting_sidecar
# Inputs    : gtwr_local_beta_panel_<control_set>.csv,
#             gtwr_local_coefficients_<control_set>.csv,
#             gtwr_main_models_<control_set>.csv
# Outputs   : gtwr_level_*.csv/png under 03_Output/05_report
# DependsOn : 02_Code/03_models/03_run_gtwr_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_spatial.R"))
load_project_packages()

ensure_dirs(c(cfg$dir_report, cfg$dir_logs))

append_log(
  cfg$logs$model_run,
  sprintf("\n## [%s] 03_build_gtwr_level_artifacts", timestamp())
)


#==============================================================================
# 1. Input/Output Resolution
#==============================================================================

normalize_token <- function(x, allowed, default) {
  x <- tolower(trimws(as.character(x[[1]])))
  if (!x %in% allowed) default else x
}

control_set_requested <- normalize_token(
  Sys.getenv("GTWR_LEVEL_CONTROL_SET", unset = "auto"),
  allowed = c("auto", "lean", "extended"),
  default = "auto"
)
control_set_priority <- if (control_set_requested %in% c("lean", "extended")) {
  control_set_requested
} else {
  c("extended", "lean")
}
control_set_selected <- NA_character_

is_temp_gcp_results_path <- function(path) {
  grepl("(^|/)99_GCP_Results(/|$)", normalizePath(path, winslash = "/", mustWork = FALSE))
}

candidate_input_table_dirs <- function() {
  explicit_table_dir <- trimws(Sys.getenv("GTWR_LEVEL_TABLE_DIR", unset = ""))
  if (nzchar(explicit_table_dir)) {
    explicit_table_dir <- normalizePath(explicit_table_dir, winslash = "/", mustWork = FALSE)
    if (is_temp_gcp_results_path(explicit_table_dir)) {
      stop("[ERROR] GTWR_LEVEL_TABLE_DIR points to temporary 99_GCP_Results; use canonical 03_Output/01_Tables instead.", call. = FALSE)
    }
    if (!dir.exists(explicit_table_dir)) {
      stop(sprintf("[ERROR] GTWR_LEVEL_TABLE_DIR does not exist: %s", explicit_table_dir), call. = FALSE)
    }
    return(explicit_table_dir)
  }

  root <- trimws(Sys.getenv("GTWR_LEVEL_INPUT_ROOT", unset = cfg$project_root))
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  candidates <- unique(c(
    file.path(root, "03_Output", "01_Tables"),
    root,
    cfg$dir_tables
  ))
  candidates <- candidates[!vapply(candidates, is_temp_gcp_results_path, logical(1))]

  hits <- candidates[dir.exists(candidates)]
  if (length(hits) == 0L) {
    stop("[ERROR] No GTWR input table directory found.", call. = FALSE)
  }
  hits
}

input_table_dirs <- candidate_input_table_dirs()
input_tables_dir <- input_table_dirs[[1L]]

gtwr_input_path <- function(stem, control_set = control_set_selected, table_dir = input_tables_dir) {
  control_set <- cfg$gtwr_control_set_token(control_set)
  file.path(table_dir, sprintf("%s_%s.csv", stem, control_set))
}

has_usable_gtwr_local_beta_panel <- function(path) {
  if (!file.exists(path)) return(FALSE)
  x <- tryCatch(
    readr::read_csv(path, show_col_types = FALSE),
    error = function(e) NULL
  )
  if (is.null(x) || nrow(x) == 0L) return(FALSE)
  required <- c("adm_cd", "yq", "time_id", "outcome", "focal_var", "estimate", "estimate_type", "status")
  if (length(setdiff(required, names(x))) > 0L) return(FALSE)
  any(x$status == "success" & x$estimate_type == "local_beta", na.rm = TRUE)
}

discover_gtwr_sources <- function() {
  out <- list()
  for (control_set_i in control_set_priority) {
    for (dir_i in input_table_dirs) {
      panel_path_i <- gtwr_input_path("gtwr_local_beta_panel", control_set = control_set_i, table_dir = dir_i)
      main_path_i <- gtwr_input_path("gtwr_main_models", control_set = control_set_i, table_dir = dir_i)
      if (file.exists(main_path_i) && has_usable_gtwr_local_beta_panel(panel_path_i)) {
        out[[length(out) + 1L]] <- tibble::tibble(
          control_set = control_set_i,
          table_dir = dir_i,
          panel_path = panel_path_i,
          main_path = main_path_i
        )
        break
      }
    }
  }
  if (length(out) == 0L) return(tibble::tibble())
  dplyr::bind_rows(out) |>
    dplyr::distinct(control_set, .keep_all = TRUE) |>
    dplyr::arrange(match(control_set, control_set_priority))
}

gtwr_sources_tbl <- discover_gtwr_sources()

if (nrow(gtwr_sources_tbl) == 0L) {
  stop(
    sprintf(
      "[ERROR] No quarterly GTWR level source found for control_set=%s under %s.",
      paste(control_set_priority, collapse = " -> "), paste(input_table_dirs, collapse = ";")
    ),
    call. = FALSE
  )
}

tag_selected <- NA_character_
source_paths <- character()

clear_existing_gtwr_level_artifacts <- function(control_sets = gtwr_sources_tbl$control_set) {
  control_sets <- vapply(control_sets, cfg$gtwr_control_set_token, character(1))
  existing <- list.files(
    cfg$dir_report,
    pattern = sprintf("^gtwr_level_.*(%s).*[.](csv|png)$", paste(control_sets, collapse = "|")),
    full.names = TRUE
  )
  if (length(existing) > 0L) unlink(existing)
  invisible(existing)
}

clear_existing_gtwr_level_artifacts(gtwr_sources_tbl$control_set)

report_csv_path <- function(stem) {
  file.path(cfg$dir_report, sprintf("%s_%s.csv", stem, tag_selected))
}

report_png_path <- function(stem) {
  file.path(cfg$dir_report, sprintf("%s_%s.png", stem, tag_selected))
}

append_log(
  cfg$logs$model_run,
  paste0(
    "- GTWR quarterly level artifact sources resolved: ",
    paste(gtwr_sources_tbl$control_set, collapse = "; ")
  )
)


#==============================================================================
# 2. Helpers
#==============================================================================

save_plot_safe <- function(plot_obj, path, width, height, dpi = 320) {
  fs::dir_create(fs::path_dir(path))
  tmp <- tempfile(
    pattern = ".gtwr_level_plot_",
    tmpdir = fs::path_dir(path),
    fileext = paste0(".", tools::file_ext(path))
  )
  on.exit({
    if (file.exists(tmp)) unlink(tmp)
  }, add = TRUE)

  ggplot2::ggsave(
    filename = tmp,
    plot = plot_obj,
    width = width,
    height = height,
    dpi = dpi,
    bg = "white"
  )

  ok <- file.rename(tmp, path)
  if (!isTRUE(ok)) {
    stop(sprintf("[ERROR] Failed to promote plot artifact %s -> %s", tmp, path), call. = FALSE)
  }
  invisible(path)
}

save_triptych_plot_safe <- function(plot_left,
                                    plot_middle,
                                    plot_right,
                                    path,
                                    width,
                                    height,
                                    dpi = 320,
                                    widths = c(1, 1, 1.08)) {
  fs::dir_create(fs::path_dir(path))
  tmp <- tempfile(
    pattern = ".gtwr_level_triptych_",
    tmpdir = fs::path_dir(path),
    fileext = paste0(".", tools::file_ext(path))
  )
  on.exit({
    if (file.exists(tmp)) unlink(tmp)
  }, add = TRUE)

  device_open <- FALSE
  grDevices::png(
    filename = tmp,
    width = width,
    height = height,
    units = "in",
    res = dpi,
    bg = "white"
  )
  device_open <- TRUE
  on.exit({
    if (isTRUE(device_open) && grDevices::dev.cur() > 1L) {
      try(grDevices::dev.off(), silent = TRUE)
    }
  }, add = TRUE)

  grid::grid.newpage()
  grid::pushViewport(
    grid::viewport(
      layout = grid::grid.layout(
        nrow = 1,
        ncol = 3,
        widths = grid::unit(widths, "null")
      )
    )
  )

  print(plot_left, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  print(plot_middle, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  print(plot_right, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 3))
  grid::popViewport()

  grDevices::dev.off()
  device_open <- FALSE

  ok <- file.rename(tmp, path)
  if (!isTRUE(ok)) {
    stop(sprintf("[ERROR] Failed to promote triptych artifact %s -> %s", tmp, path), call. = FALSE)
  }
  invisible(path)
}

save_triptych_panel_plot_safe <- function(panel_rows,
                                          path,
                                          width,
                                          row_height,
                                          dpi = 320,
                                          widths = c(0.6, 1, 1, 1, 0.2),
                                          header_height = 0.24) {
  fs::dir_create(fs::path_dir(path))
  tmp <- tempfile(
    pattern = ".gtwr_level_triptych_panel_",
    tmpdir = fs::path_dir(path),
    fileext = paste0(".", tools::file_ext(path))
  )
  on.exit({
    if (file.exists(tmp)) unlink(tmp)
  }, add = TRUE)

  n_rows <- length(panel_rows)
  if (n_rows == 0L) {
    stop("[ERROR] Cannot save empty GTWR triptych panel.", call. = FALSE)
  }

  device_open <- FALSE
  grDevices::png(
    filename = tmp,
    width = width,
    height = header_height + row_height * n_rows,
    units = "in",
    res = dpi,
    bg = "white"
  )
  device_open <- TRUE
  on.exit({
    if (isTRUE(device_open) && grDevices::dev.cur() > 1L) {
      try(grDevices::dev.off(), silent = TRUE)
    }
  }, add = TRUE)

  shared_legend <- cowplot::get_legend(panel_rows[[1]]$delta)

  grid::grid.newpage()
  grid::pushViewport(
    grid::viewport(
      layout = grid::grid.layout(
        nrow = n_rows + 1L,
        ncol = 5L,
        heights = grid::unit(c(header_height, rep(row_height, n_rows)), "in"),
        widths = grid::unit(widths, "null")
      )
    )
  )

  header_gp <- grid::gpar(fontsize = 12, fontface = "bold", col = "#1f2937")
  subheader_gp <- grid::gpar(fontsize = 9, col = "#374151")
  row_gp <- grid::gpar(fontsize = 11, fontface = "bold", col = "#1f2937")

  draw_header <- function(col, title, subtitle) {
    grid::grid.text(
      title,
      x = grid::unit(0.5, "npc"),
      y = grid::unit(0.64, "npc"),
      gp = header_gp,
      vp = grid::viewport(layout.pos.row = 1L, layout.pos.col = col)
    )
    grid::grid.text(
      subtitle,
      x = grid::unit(0.5, "npc"),
      y = grid::unit(0.23, "npc"),
      gp = subheader_gp,
      vp = grid::viewport(layout.pos.row = 1L, layout.pos.col = col)
    )
  }

  draw_header(2L, "Early: 2019", "local beta of age60_resident_share")
  draw_header(3L, "Latest: 2025", "shared level scale")
  draw_header(4L, "Delta: 2025 - 2019", "separate delta scale")

  for (i in seq_along(panel_rows)) {
    row_i <- i + 1L
    row_spec <- panel_rows[[i]]
    grid::grid.text(
      row_spec$row_label,
      x = grid::unit(0.02, "npc"),
      y = grid::unit(0.5, "npc"),
      just = c("left", "center"),
      gp = row_gp,
      vp = grid::viewport(layout.pos.row = row_i, layout.pos.col = 1L)
    )
    print(row_spec$early + ggplot2::theme(legend.position = "none"), vp = grid::viewport(layout.pos.row = row_i, layout.pos.col = 2L))
    print(row_spec$latest + ggplot2::theme(legend.position = "none"), vp = grid::viewport(layout.pos.row = row_i, layout.pos.col = 3L))
    print(row_spec$delta + ggplot2::theme(legend.position = "none"), vp = grid::viewport(layout.pos.row = row_i, layout.pos.col = 4L))
  }

  grid::pushViewport(grid::viewport(layout.pos.row = 2L:(n_rows + 1L), layout.pos.col = 5L))
  grid::grid.draw(shared_legend)
  grid::popViewport()

  grid::popViewport()

  grDevices::dev.off()
  device_open <- FALSE

  ok <- file.rename(tmp, path)
  if (!isTRUE(ok)) {
    stop(sprintf("[ERROR] Failed to promote triptych panel artifact %s -> %s", tmp, path), call. = FALSE)
  }
  invisible(path)
}

artifact_rows <- list()

register_artifact <- function(artifact_name,
                              artifact_path,
                              artifact_type,
                              note = NA_character_) {
  artifact_rows[[length(artifact_rows) + 1L]] <<- tibble::tibble(
    artifact_name = artifact_name,
    artifact_path = artifact_path,
    artifact_type = artifact_type,
    status = "created",
    control_set = control_set_selected,
    input_tables_dir = input_tables_dir,
    source_paths = paste(source_paths, collapse = ";"),
    note = note
  )
}

make_outcome_label <- function(x) {
  dplyr::case_when(
    x == "vitality_sub_economic" ~ "Economic Vitality",
    x == "vitality_sub_social" ~ "Social Vitality",
    x == "vitality_sub_temporal" ~ "Temporal Vitality",
    x == "vitality_sub_stability" ~ "Stability",
    x == "vitality_index_base" ~ "Composite Vitality Index",
    TRUE ~ x
  )
}

ordered_outcome_labels <- function() {
  c(
    "Economic Vitality",
    "Social Vitality",
    "Temporal Vitality",
    "Stability",
    "Composite Vitality Index"
  )
}

order_outcome_labels <- function(x) {
  factor(x, levels = ordered_outcome_labels())
}

make_outcome_label_sentence <- function(x) {
  dplyr::case_when(
    x == "vitality_sub_economic" ~ "Economic vitality",
    x == "vitality_sub_social" ~ "Social vitality",
    x == "vitality_sub_temporal" ~ "Temporal vitality",
    x == "vitality_sub_stability" ~ "Structural stability",
    x == "vitality_index_base" ~ "Composite vitality index",
    TRUE ~ x
  )
}

classify_sign <- function(x, tol = 1e-8) {
  dplyr::case_when(
    !is.finite(x) ~ NA_character_,
    x > tol ~ "positive",
    x < -tol ~ "negative",
    TRUE ~ "zero"
  )
}

safe_quantile_value <- function(x, prob) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) return(NA_real_)
  as.numeric(stats::quantile(x, probs = prob, na.rm = TRUE, names = FALSE))
}

safe_min <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else min(x)
}

safe_max <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else max(x)
}

value_at_period <- function(x, periods, target_period, default = NA_real_) {
  idx <- which(periods == target_period)
  if (length(idx) == 0L) return(default)
  x[[idx[[1L]]]]
}

max_abs_or_one <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) return(1)
  out <- max(abs(x), na.rm = TRUE)
  if (!is.finite(out) || out <= 0) 1 else out
}

make_map_plot <- function(data,
                          estimate_col,
                          max_abs,
                          title,
                          subtitle,
                          fill_label,
                          show_legend = TRUE) {
  ggplot2::ggplot(data) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data[[estimate_col]]), color = NA) +
    ggplot2::scale_fill_gradient2(
      low = "#2166AC", mid = "white", high = "#B2182B",
      midpoint = 0, limits = c(-max_abs, max_abs), na.value = "grey85",
      oob = scales::squish
    ) +
    ggplot2::theme_void() +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      fill = fill_label
    ) +
    ggplot2::theme(
      legend.position = if (isTRUE(show_legend)) "right" else "none",
      plot.title = ggplot2::element_text(face = "bold", size = 11),
      plot.subtitle = ggplot2::element_text(size = 9),
      strip.text = ggplot2::element_text(face = "bold")
    )
}

read_gtwr_csv <- function(path) {
  readr::read_csv(path, show_col_types = FALSE)
}

ensure_cols <- function(df, cols, fill = NA) {
  for (col in setdiff(cols, names(df))) {
    df[[col]] <- fill
  }
  df
}

read_adm_region_lookup <- function() {
  if (file.exists(cfg$paths$adm_region_lookup)) {
    return(
      arrow::read_parquet(cfg$paths$adm_region_lookup) |>
        tibble::as_tibble() |>
        dplyr::mutate(adm_cd = as.character(.data$adm_cd))
    )
  }

  load_commercial_boundary(cfg$dir_boundary, cfg$target_crs) |>
    build_adm_region_lookup(boundary_year = cfg$boundary_year)
}

summarise_region_distribution <- function(data, region_cols) {
  data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(region_cols))) |>
    dplyr::summarise(
      n_adm = dplyr::n_distinct(.data$adm_cd),
      n_valid = sum(is.finite(.data$estimate)),
      mean_estimate = mean(.data$estimate, na.rm = TRUE),
      sd_estimate = stats::sd(.data$estimate, na.rm = TRUE),
      min_estimate = safe_min(.data$estimate),
      p25_estimate = safe_quantile_value(.data$estimate, 0.25),
      p50_estimate = safe_quantile_value(.data$estimate, 0.50),
      p75_estimate = safe_quantile_value(.data$estimate, 0.75),
      max_estimate = safe_max(.data$estimate),
      share_positive = mean(.data$estimate > 0, na.rm = TRUE),
      share_negative = mean(.data$estimate < 0, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      iqr_estimate = .data$p75_estimate - .data$p25_estimate,
      coverage_share = .data$n_valid / .data$n_adm
    )
}

build_region_period_summary <- function(panel_tbl, region_lookup) {
  base_tbl <- panel_tbl |>
    dplyr::left_join(region_lookup, by = "adm_cd") |>
    dplyr::mutate(outcome_label = make_outcome_label(.data$outcome))

  common_cols <- c(
    "outcome", "outcome_label", "outcome_group", "outcome_order",
    "focal_var", "yq", "time_id", "control_set", "fit_scope",
    "window_scope", "recent_period_n", "location_frac", "location_n"
  )

  living_tbl <- base_tbl |>
    dplyr::mutate(
      region_level = "living_area",
      region_name = .data$living_area,
      region_order = .data$living_area_order,
      parent_region = NA_character_
    ) |>
    summarise_region_distribution(c(
      "region_level", "region_name", "region_order", "parent_region",
      common_cols
    ))

  gu_tbl <- base_tbl |>
    dplyr::mutate(
      region_level = "gu",
      region_name = .data$gu_name,
      region_order = .data$gu_order,
      parent_region = .data$living_area
    ) |>
    summarise_region_distribution(c(
      "region_level", "region_name", "region_order", "parent_region",
      common_cols
    ))

  dplyr::bind_rows(living_tbl, gu_tbl) |>
    dplyr::arrange(.data$outcome_order, .data$time_id, .data$region_level, .data$region_order)
}

build_region_snapshot_summary <- function(snapshot_pairs, region_lookup) {
  snapshot_long <- dplyr::bind_rows(
    snapshot_pairs |>
      dplyr::transmute(
        adm_cd, outcome, outcome_label, outcome_group, outcome_order, focal_var,
        estimate_scope = "earliest_level",
        reference_period = as.character(earliest_yq),
        estimate = earliest_estimate,
        control_set, fit_scope, window_scope
      ),
    snapshot_pairs |>
      dplyr::transmute(
        adm_cd, outcome, outcome_label, outcome_group, outcome_order, focal_var,
        estimate_scope = "latest_level",
        reference_period = as.character(latest_yq),
        estimate = latest_estimate,
        control_set, fit_scope, window_scope
      ),
    snapshot_pairs |>
      dplyr::transmute(
        adm_cd, outcome, outcome_label, outcome_group, outcome_order, focal_var,
        estimate_scope = "delta_latest_minus_earliest",
        reference_period = paste(earliest_yq, latest_yq, sep = " -> "),
        estimate = delta_estimate,
        control_set, fit_scope, window_scope
      )
  ) |>
    dplyr::left_join(region_lookup, by = "adm_cd")

  common_cols <- c(
    "outcome", "outcome_label", "outcome_group", "outcome_order",
    "focal_var", "estimate_scope", "reference_period",
    "control_set", "fit_scope", "window_scope"
  )

  living_tbl <- snapshot_long |>
    dplyr::mutate(
      region_level = "living_area",
      region_name = .data$living_area,
      region_order = .data$living_area_order,
      parent_region = NA_character_
    ) |>
    summarise_region_distribution(c(
      "region_level", "region_name", "region_order", "parent_region",
      common_cols
    ))

  gu_tbl <- snapshot_long |>
    dplyr::mutate(
      region_level = "gu",
      region_name = .data$gu_name,
      region_order = .data$gu_order,
      parent_region = .data$living_area
    ) |>
    summarise_region_distribution(c(
      "region_level", "region_name", "region_order", "parent_region",
      common_cols
    ))

  dplyr::bind_rows(living_tbl, gu_tbl) |>
    dplyr::arrange(.data$outcome_order, .data$estimate_scope, .data$region_level, .data$region_order)
}

build_distribution_summary <- function(snapshot_pairs) {
  earliest_tbl <- snapshot_pairs |>
    dplyr::transmute(
      outcome, outcome_group, outcome_order, focal_var,
      estimate_scope = "earliest_level",
      reference_period = as.character(earliest_yq),
      estimate = earliest_estimate
    )

  latest_tbl <- snapshot_pairs |>
    dplyr::transmute(
      outcome, outcome_group, outcome_order, focal_var,
      estimate_scope = "latest_level",
      reference_period = as.character(latest_yq),
      estimate = latest_estimate
    )

  delta_tbl <- snapshot_pairs |>
    dplyr::transmute(
      outcome, outcome_group, outcome_order, focal_var,
      estimate_scope = "delta_latest_minus_earliest",
      reference_period = paste(earliest_yq, latest_yq, sep = " -> "),
      estimate = delta_estimate
    )

  dplyr::bind_rows(earliest_tbl, latest_tbl, delta_tbl) |>
    dplyr::group_by(
      outcome, outcome_group, outcome_order, focal_var,
      estimate_scope, reference_period
    ) |>
    dplyr::summarise(
      n_valid = sum(is.finite(estimate)),
      mean_estimate = mean(estimate, na.rm = TRUE),
      sd_estimate = stats::sd(estimate, na.rm = TRUE),
      min_estimate = safe_min(estimate),
      p25_estimate = safe_quantile_value(estimate, 0.25),
      p50_estimate = safe_quantile_value(estimate, 0.50),
      p75_estimate = safe_quantile_value(estimate, 0.75),
      max_estimate = safe_max(estimate),
      share_positive = mean(estimate > 0, na.rm = TRUE),
      share_negative = mean(estimate < 0, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      iqr_estimate = p75_estimate - p25_estimate,
      outcome_label = make_outcome_label(outcome)
    ) |>
    dplyr::arrange(outcome_order, estimate_scope)
}

build_mean_trajectories <- function(panel_tbl) {
  panel_tbl |>
    dplyr::group_by(
      outcome, outcome_group, outcome_order, focal_var,
      yq, time_id, control_set, fit_scope, window_scope,
      recent_period_n, location_frac, location_n
    ) |>
    dplyr::summarise(
      n_units = sum(is.finite(estimate)),
      mean_estimate = mean(estimate, na.rm = TRUE),
      sd_estimate = stats::sd(estimate, na.rm = TRUE),
      min_estimate = safe_min(estimate),
      p25_estimate = safe_quantile_value(estimate, 0.25),
      p50_estimate = safe_quantile_value(estimate, 0.50),
      p75_estimate = safe_quantile_value(estimate, 0.75),
      max_estimate = safe_max(estimate),
      share_positive = mean(estimate > 0, na.rm = TRUE),
      share_negative = mean(estimate < 0, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(outcome_label = make_outcome_label(outcome)) |>
    dplyr::arrange(outcome_order, time_id)
}

build_sign_transition_summary <- function(snapshot_pairs) {
  local_tbl <- snapshot_pairs |>
    dplyr::mutate(
      earliest_sign = classify_sign(earliest_estimate),
      latest_sign = classify_sign(latest_estimate),
      transition = paste(earliest_sign, latest_sign, sep = "_to_"),
      transition_family = dplyr::case_when(
        earliest_sign == "negative" & latest_sign == "negative" ~ "stay_negative",
        earliest_sign == "positive" & latest_sign == "positive" ~ "stay_positive",
        earliest_sign == "negative" & latest_sign == "positive" ~ "negative_to_positive",
        earliest_sign == "positive" & latest_sign == "negative" ~ "positive_to_negative",
        TRUE ~ "zero_or_missing_involved"
      )
    )

  totals_tbl <- local_tbl |>
    dplyr::group_by(outcome, focal_var) |>
    dplyr::summarise(total_units = dplyr::n(), .groups = "drop")

  summary_tbl <- local_tbl |>
    dplyr::group_by(
      outcome, outcome_group, outcome_order, focal_var,
      transition_family, transition
    ) |>
    dplyr::summarise(n_units = dplyr::n(), .groups = "drop") |>
    dplyr::left_join(totals_tbl, by = c("outcome", "focal_var")) |>
    dplyr::mutate(
      share_units = n_units / total_units,
      outcome_label = make_outcome_label(outcome)
    ) |>
    dplyr::arrange(outcome_order, transition_family, transition)

  list(local = local_tbl, summary = summary_tbl)
}

build_delta_rankings <- function(snapshot_pairs, n_keep = 10L) {
  rank_one_side <- function(tbl, rank_group, order_desc = FALSE) {
    if (nrow(tbl) == 0L) return(tbl[0, , drop = FALSE])
    out <- if (isTRUE(order_desc)) {
      tbl |> dplyr::arrange(dplyr::desc(delta_estimate), adm_cd)
    } else {
      tbl |> dplyr::arrange(delta_estimate, adm_cd)
    }
    out |>
      dplyr::slice_head(n = min(n_keep, nrow(out))) |>
      dplyr::mutate(rank_group = rank_group, rank_order = dplyr::row_number())
  }

  snapshot_pairs |>
    dplyr::filter(is.finite(delta_estimate)) |>
    dplyr::group_by(outcome, focal_var) |>
    dplyr::group_modify(~ {
      dplyr::bind_rows(
        rank_one_side(.x, "most_negative_delta", order_desc = FALSE),
        rank_one_side(.x, "most_positive_delta", order_desc = TRUE)
      )
    }) |>
    dplyr::ungroup() |>
    dplyr::mutate(outcome_label = make_outcome_label(outcome)) |>
    dplyr::arrange(outcome_order, rank_group, rank_order)
}

pick_representative_units <- function(snapshot_pairs) {
  role_spec <- list(
    latest_most_positive = function(tbl) tbl |>
      dplyr::filter(is.finite(latest_estimate)) |>
      dplyr::arrange(dplyr::desc(latest_estimate), adm_cd),
    latest_most_negative = function(tbl) tbl |>
      dplyr::filter(is.finite(latest_estimate)) |>
      dplyr::arrange(latest_estimate, adm_cd),
    delta_most_positive = function(tbl) tbl |>
      dplyr::filter(is.finite(delta_estimate)) |>
      dplyr::arrange(dplyr::desc(delta_estimate), adm_cd),
    delta_most_negative = function(tbl) tbl |>
      dplyr::filter(is.finite(delta_estimate)) |>
      dplyr::arrange(delta_estimate, adm_cd),
    latest_near_zero = function(tbl) tbl |>
      dplyr::filter(is.finite(latest_estimate)) |>
      dplyr::arrange(abs(latest_estimate), adm_cd)
  )

  snapshot_pairs |>
    dplyr::group_by(outcome, focal_var, outcome_group, outcome_order) |>
    dplyr::group_modify(~ {
      used_ids <- character()
      picked <- vector("list", length(role_spec))
      idx <- 0L
      for (role_nm in names(role_spec)) {
        idx <- idx + 1L
        candidate <- role_spec[[role_nm]](.x) |>
          dplyr::filter(!adm_cd %in% used_ids) |>
          dplyr::slice_head(n = 1L) |>
          dplyr::mutate(representative_role = role_nm)
        if (nrow(candidate) == 0L) {
          candidate <- role_spec[[role_nm]](.x) |>
            dplyr::slice_head(n = 1L) |>
            dplyr::mutate(representative_role = role_nm)
        }
        if (nrow(candidate) > 0L) {
          used_ids <- unique(c(used_ids, candidate$adm_cd))
          picked[[idx]] <- candidate
        } else {
          picked[[idx]] <- .x[0, , drop = FALSE]
        }
      }
      dplyr::bind_rows(picked)
    }) |>
    dplyr::ungroup() |>
    dplyr::mutate(outcome_label = make_outcome_label(outcome)) |>
    dplyr::arrange(outcome_order, representative_role)
}


#==============================================================================
# 3. Build Artifacts by Available GTWR Source
#==============================================================================

build_gtwr_level_artifacts_for_source <- function(source_row) {
  control_set_selected <<- as.character(source_row$control_set[[1]])
  input_tables_dir <<- as.character(source_row$table_dir[[1]])
  tag_selected <<- control_set_selected
  source_paths <<- c(
    gtwr_input_path("gtwr_local_beta_panel"),
    gtwr_input_path("gtwr_local_coefficients"),
    gtwr_input_path("gtwr_main_models")
  )
  source_paths <<- source_paths[file.exists(source_paths)]
  artifact_rows <<- list()

  append_log(
    cfg$logs$model_run,
    paste0(
      "- GTWR quarterly level artifact build start: control_set=", control_set_selected,
      ", input_tables_dir=", input_tables_dir
    )
  )

panel_path <- gtwr_input_path("gtwr_local_beta_panel")
main_path <- gtwr_input_path("gtwr_main_models")
local_path <- gtwr_input_path("gtwr_local_coefficients")

panel_tbl <- read_gtwr_csv(panel_path)
main_tbl <- read_gtwr_csv(main_path)
local_tbl <- if (file.exists(local_path)) read_gtwr_csv(local_path) else tibble::tibble()

required_panel_cols <- c("adm_cd", "year", "yq", "time_id", "outcome", "focal_var", "estimate", "estimate_type", "status")
missing_panel_cols <- setdiff(required_panel_cols, names(panel_tbl))
if (length(missing_panel_cols) > 0L) {
  stop(
    sprintf("[ERROR] GTWR local beta panel is not quarterly/current. Missing columns: %s", paste(missing_panel_cols, collapse = ", ")),
    call. = FALSE
  )
}

panel_tbl <- panel_tbl |>
  ensure_cols(c("control_set", "fit_scope", "window_scope", "recent_period_n", "location_frac", "location_n")) |>
  dplyr::mutate(
    adm_cd = as.character(adm_cd),
    year = as.integer(year),
    yq = as.character(yq),
    time_id = as.integer(time_id),
    estimate = suppressWarnings(as.numeric(estimate)),
    recent_period_n = suppressWarnings(as.integer(recent_period_n)),
    location_frac = suppressWarnings(as.numeric(location_frac)),
    location_n = suppressWarnings(as.integer(location_n))
  ) |>
  dplyr::filter(status == "success", estimate_type == "local_beta")

if (nrow(panel_tbl) == 0L) {
  stop("[ERROR] GTWR local beta panel has no successful quarterly local_beta rows.", call. = FALSE)
}

observed_yq <- panel_tbl |>
  dplyr::distinct(yq, time_id) |>
  dplyr::arrange(time_id) |>
  dplyr::pull(yq) |>
  as.character()
expected_yq <- as.character(cfg$analysis_quarter_sequence$yq)
if (!identical(observed_yq, expected_yq)) {
  stop(
    sprintf(
      "[ERROR] Quarterly GTWR local beta panel has stale or incomplete yq values: observed=%s, expected=%s.",
      paste(observed_yq, collapse = ","),
      paste(expected_yq, collapse = ",")
    ),
    call. = FALSE
  )
}
expected_time_ids <- seq_along(expected_yq)
quarter_axis_tick_idx <- which(
  grepl("Q4$", expected_yq) | seq_along(expected_yq) %in% c(1L, length(expected_yq))
)
quarter_axis_tick_idx <- sort(unique(quarter_axis_tick_idx))
quarter_axis_breaks <- expected_time_ids[quarter_axis_tick_idx]
quarter_axis_labels <- expected_yq[quarter_axis_tick_idx]

main_meta <- main_tbl |>
  ensure_cols(c(
    "outcome_group", "outcome_order", "target_yq", "earliest_yq", "latest_yq",
    "st_bw", "collinearity_warn_n", "collinearity_warn_share", "max_local_cn_gtwr",
    "latest_coverage_share", "status"
  )) |>
  dplyr::mutate(
    outcome = as.character(outcome),
    focal_var = as.character(focal_var),
    outcome_group = dplyr::coalesce(as.character(outcome_group), as.character(outcome)),
    outcome_order = suppressWarnings(as.integer(.data$outcome_order))
  ) |>
  dplyr::select(
    dplyr::any_of(c(
      "outcome", "focal_var", "outcome_group", "outcome_order",
      "target_yq", "earliest_yq", "latest_yq", "st_bw",
      "collinearity_warn_n", "collinearity_warn_share", "max_local_cn_gtwr",
      "latest_coverage_share", "status"
    ))
  ) |>
  dplyr::distinct(outcome, focal_var, .keep_all = TRUE)

panel_tbl <- panel_tbl |>
  dplyr::left_join(
    main_meta |>
      dplyr::select(outcome, focal_var, outcome_group, outcome_order),
    by = c("outcome", "focal_var")
  ) |>
  dplyr::mutate(
    outcome_group = dplyr::coalesce(outcome_group, outcome),
    outcome_order = dplyr::coalesce(outcome_order, dplyr::dense_rank(outcome))
  )

boundary_tbl <- load_commercial_boundary(cfg$dir_boundary, cfg$target_crs) |>
  dplyr::mutate(adm_cd = as.character(adm_cd)) |>
  dplyr::select(adm_cd, dplyr::any_of(c("adstrd_nm", "adm_nm")), geometry) |>
  dplyr::distinct(adm_cd, .keep_all = TRUE)

if (!"adstrd_nm" %in% names(boundary_tbl)) {
  if ("adm_nm" %in% names(boundary_tbl)) {
    boundary_tbl <- boundary_tbl |> dplyr::rename(adstrd_nm = adm_nm)
  } else {
    boundary_tbl$adstrd_nm <- NA_character_
  }
}

region_lookup_tbl <- read_adm_region_lookup()

earliest_target_yq <- expected_yq[[1L]]
latest_target_yq <- expected_yq[[length(expected_yq)]]

snapshot_pairs <- panel_tbl |>
  dplyr::group_by(outcome, focal_var, adm_cd) |>
  dplyr::arrange(time_id, .by_group = TRUE) |>
  dplyr::summarise(
    earliest_yq = earliest_target_yq,
    latest_yq = latest_target_yq,
    earliest_time_id = value_at_period(time_id, yq, earliest_target_yq, NA_integer_),
    latest_time_id = value_at_period(time_id, yq, latest_target_yq, NA_integer_),
    earliest_estimate = value_at_period(estimate, yq, earliest_target_yq, NA_real_),
    latest_estimate = value_at_period(estimate, yq, latest_target_yq, NA_real_),
    delta_estimate = latest_estimate - earliest_estimate,
    control_set = dplyr::first(control_set),
    fit_scope = dplyr::first(fit_scope),
    window_scope = dplyr::first(window_scope),
    recent_period_n = dplyr::first(recent_period_n),
    location_frac = dplyr::first(location_frac),
    location_n = dplyr::first(location_n),
    outcome_group = dplyr::first(outcome_group),
    outcome_order = dplyr::first(outcome_order),
    .groups = "drop"
  ) |>
  dplyr::left_join(sf::st_drop_geometry(boundary_tbl), by = "adm_cd") |>
  dplyr::mutate(outcome_label = make_outcome_label(outcome)) |>
  dplyr::arrange(outcome_order, adm_cd)

if (nrow(local_tbl) > 0L) {
  local_cn_cols <- intersect(
    c("local_cn_gtwr_earliest", "local_cn_gtwr_latest", "collinearity_warn_earliest", "collinearity_warn_latest"),
    names(local_tbl)
  )
  if (length(local_cn_cols) > 0L) {
    snapshot_pairs <- snapshot_pairs |>
      dplyr::left_join(
        local_tbl |>
          dplyr::mutate(adm_cd = as.character(adm_cd)) |>
          dplyr::select(adm_cd, outcome, focal_var, dplyr::all_of(local_cn_cols)),
        by = c("adm_cd", "outcome", "focal_var")
      )
  }
}


#==============================================================================
# 4. Tables
#==============================================================================

distribution_summary_tbl <- build_distribution_summary(snapshot_pairs)
mean_trajectories_tbl <- build_mean_trajectories(panel_tbl)
region_period_summary_tbl <- build_region_period_summary(panel_tbl, region_lookup_tbl)
region_snapshot_summary_tbl <- build_region_snapshot_summary(snapshot_pairs, region_lookup_tbl)
sign_transition_bundle <- build_sign_transition_summary(snapshot_pairs)
sign_transition_local_tbl <- sign_transition_bundle$local |>
  dplyr::mutate(outcome_label = make_outcome_label(outcome)) |>
  dplyr::arrange(outcome_order, transition_family, adm_cd)
sign_transition_summary_tbl <- sign_transition_bundle$summary
delta_rankings_tbl <- build_delta_rankings(snapshot_pairs)
representative_units_tbl <- pick_representative_units(snapshot_pairs)

trajectory_tbl <- panel_tbl |>
  dplyr::inner_join(
    representative_units_tbl |>
      dplyr::select(
        outcome, focal_var, adm_cd, adstrd_nm, representative_role,
        earliest_yq, latest_yq, delta_estimate, latest_estimate
      ),
    by = c("outcome", "focal_var", "adm_cd")
  ) |>
  dplyr::mutate(
    outcome_label = make_outcome_label(outcome),
    representative_label = paste0(representative_role, ": ", adstrd_nm, " (", adm_cd, ")")
  ) |>
  dplyr::arrange(outcome_order, representative_role, time_id)

snapshot_pairs_path <- report_csv_path("gtwr_level_snapshot_pairs")
distribution_summary_path <- report_csv_path("gtwr_level_distribution_summary")
mean_trajectories_path <- report_csv_path("gtwr_level_mean_trajectories")
region_period_summary_path <- report_csv_path("gtwr_level_region_period_summary")
region_snapshot_summary_path <- report_csv_path("gtwr_level_region_snapshot_summary")
sign_transition_summary_path <- report_csv_path("gtwr_level_sign_transition_summary")
sign_transition_local_path <- report_csv_path("gtwr_level_sign_transition_local")
delta_rankings_path <- report_csv_path("gtwr_level_delta_rankings")
representative_units_path <- report_csv_path("gtwr_level_representative_units")
trajectory_path <- report_csv_path("gtwr_level_representative_trajectories")
manifest_path <- report_csv_path("gtwr_level_artifact_manifest")

write_csv_safe(snapshot_pairs, snapshot_pairs_path)
register_artifact("gtwr_level_snapshot_pairs", snapshot_pairs_path, "csv", "earliest/latest/delta quarterly local coefficients by adm_cd and outcome")

write_csv_safe(distribution_summary_tbl, distribution_summary_path)
register_artifact("gtwr_level_distribution_summary", distribution_summary_path, "csv", "distribution summary for quarterly earliest/latest level snapshots and delta")

write_csv_safe(mean_trajectories_tbl, mean_trajectories_path)
register_artifact("gtwr_level_mean_trajectories", mean_trajectories_path, "csv", "quarterly mean local beta trajectories across all administrative districts")

write_csv_safe(region_period_summary_tbl, region_period_summary_path)
register_artifact("gtwr_level_region_period_summary", region_period_summary_path, "csv", "quarterly local beta summaries by Seoul living area and gu")

write_csv_safe(region_snapshot_summary_tbl, region_snapshot_summary_path)
register_artifact("gtwr_level_region_snapshot_summary", region_snapshot_summary_path, "csv", "earliest/latest/delta local beta summaries by Seoul living area and gu")

write_csv_safe(sign_transition_summary_tbl, sign_transition_summary_path)
register_artifact("gtwr_level_sign_transition_summary", sign_transition_summary_path, "csv", "sign-transition counts and shares between earliest and latest quarterly GTWR snapshots")

write_csv_safe(sign_transition_local_tbl, sign_transition_local_path)
register_artifact("gtwr_level_sign_transition_local", sign_transition_local_path, "csv", "local sign-transition classifications by adm_cd and outcome")

write_csv_safe(delta_rankings_tbl, delta_rankings_path)
register_artifact("gtwr_level_delta_rankings", delta_rankings_path, "csv", "top positive and negative latest-minus-earliest delta rankings by outcome")

write_csv_safe(representative_units_tbl, representative_units_path)
register_artifact("gtwr_level_representative_units", representative_units_path, "csv", "selected representative districts for quarterly GTWR trajectory plots")

write_csv_safe(trajectory_tbl, trajectory_path)
register_artifact("gtwr_level_representative_trajectories", trajectory_path, "csv", "quarterly local beta trajectories for representative districts")


#==============================================================================
# 5. Trajectory Plots
#==============================================================================

mean_trajectory_plot_path <- report_png_path("gtwr_level_mean_trajectories")
trajectory_plot_path <- report_png_path("gtwr_level_representative_trajectories")

mean_trajectory_plot <- mean_trajectories_tbl |>
  dplyr::mutate(outcome_label = order_outcome_labels(outcome_label)) |>
  ggplot2::ggplot(ggplot2::aes(x = time_id, y = mean_estimate, group = 1)) +
  ggplot2::geom_hline(yintercept = 0, color = "grey70", linewidth = 0.25) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = p25_estimate, ymax = p75_estimate),
    fill = "#9ECAE1",
    alpha = 0.45
  ) +
  ggplot2::geom_line(color = "#08519C", linewidth = 0.7) +
  ggplot2::geom_point(color = "#08519C", size = 1.5) +
  ggplot2::facet_wrap(~ outcome_label, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(
    breaks = quarter_axis_breaks,
    labels = quarter_axis_labels,
    expand = ggplot2::expansion(mult = c(0.01, 0.02))
  ) +
  ggplot2::labs(
    title = sprintf("GTWR Mean Local Beta Trajectories (%s)", tag_selected),
    subtitle = "Quarterly mean across administrative districts; ribbon shows p25 to p75",
    x = "Quarter",
    y = "Mean local beta"
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(size = 8),
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold")
  )

save_plot_safe(mean_trajectory_plot, mean_trajectory_plot_path, width = 10.5, height = 7.5)
register_artifact("gtwr_level_mean_trajectories_plot", mean_trajectory_plot_path, "png", "faceted quarterly mean local beta trajectories")

trajectory_plot <- trajectory_tbl |>
  dplyr::mutate(
    outcome_label = order_outcome_labels(outcome_label),
    representative_label = factor(representative_label, levels = unique(representative_label))
  ) |>
  ggplot2::ggplot(ggplot2::aes(x = time_id, y = estimate, color = representative_role, group = representative_label)) +
  ggplot2::geom_hline(yintercept = 0, color = "grey70", linewidth = 0.25) +
  ggplot2::geom_line(linewidth = 0.6) +
  ggplot2::geom_point(size = 1.4) +
  ggplot2::facet_wrap(~ outcome_label, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(
    breaks = quarter_axis_breaks,
    labels = quarter_axis_labels,
    expand = ggplot2::expansion(mult = c(0.01, 0.02))
  ) +
  ggplot2::scale_color_brewer(palette = "Dark2") +
  ggplot2::labs(
    title = sprintf("GTWR Representative Local Beta Trajectories (%s)", tag_selected),
    subtitle = "Representative districts selected from latest level and latest-minus-earliest extremes",
    x = "Quarter",
    y = "Local beta",
    color = "Representative role"
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(size = 8),
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold")
  )

save_plot_safe(trajectory_plot, trajectory_plot_path, width = 11.5, height = 8)
register_artifact("gtwr_level_representative_trajectories_plot", trajectory_plot_path, "png", "faceted quarterly representative local beta trajectories")


#==============================================================================
# 6. Maps
#==============================================================================

outcome_registry <- snapshot_pairs |>
  dplyr::distinct(outcome, outcome_label, focal_var, outcome_order, earliest_yq, latest_yq) |>
  dplyr::arrange(outcome_order)

triptych_panel_rows <- list()

for (i in seq_len(nrow(outcome_registry))) {
  outcome_i <- outcome_registry$outcome[[i]]
  outcome_label_i <- outcome_registry$outcome_label[[i]]
  focal_i <- outcome_registry$focal_var[[i]]
  earliest_yq_i <- outcome_registry$earliest_yq[[i]]
  latest_yq_i <- outcome_registry$latest_yq[[i]]

  snapshot_i <- snapshot_pairs |>
    dplyr::filter(outcome == outcome_i, focal_var == focal_i)

  map_tbl_i <- boundary_tbl |>
    dplyr::left_join(
      snapshot_i |> dplyr::select(-dplyr::any_of("adstrd_nm")),
      by = "adm_cd"
    )

  max_abs_level_i <- 10
  max_abs_delta_i <- 10

  triptych_map_path_i <- file.path(
    cfg$dir_report,
    sprintf(
      "gtwr_level_early_latest_delta_triptych__%s__%s__%s__%s__%s.png",
      tag_selected, outcome_i, focal_i, earliest_yq_i, latest_yq_i
    )
  )

  early_triptych_plot_i <- make_map_plot(
    data = map_tbl_i,
    estimate_col = "earliest_estimate",
    max_abs = max_abs_level_i,
    title = sprintf("Early: %s", earliest_yq_i),
    subtitle = sprintf("%s | %s", outcome_label_i, focal_i),
    fill_label = "beta\n(level)",
    show_legend = FALSE
  )

  latest_triptych_plot_i <- make_map_plot(
    data = map_tbl_i,
    estimate_col = "latest_estimate",
    max_abs = max_abs_level_i,
    title = sprintf("Latest: %s", latest_yq_i),
    subtitle = "shared level scale",
    fill_label = "beta",
    show_legend = FALSE
  )

  delta_triptych_plot_i <- make_map_plot(
    data = map_tbl_i,
    estimate_col = "delta_estimate",
    max_abs = max_abs_delta_i,
    title = "Delta: latest - earliest",
    subtitle = sprintf("%s | separate delta scale", tag_selected),
    fill_label = "beta"
  )

  save_triptych_plot_safe(
    plot_left = early_triptych_plot_i,
    plot_middle = latest_triptych_plot_i,
    plot_right = delta_triptych_plot_i,
    path = triptych_map_path_i,
    width = 17.8,
    height = 6.6
  )
  register_artifact(
    artifact_name = sprintf("gtwr_level_early_latest_delta_triptych__%s", outcome_i),
    artifact_path = triptych_map_path_i,
    artifact_type = "png",
    note = sprintf("early/latest/delta quarterly GTWR triptych for %s", outcome_i)
  )

  clean_early_plot_i <- make_map_plot(
    data = map_tbl_i,
    estimate_col = "earliest_estimate",
    max_abs = max_abs_level_i,
    title = NULL,
    subtitle = NULL,
    fill_label = "beta\n(level)",
    show_legend = FALSE
  )

  clean_latest_plot_i <- make_map_plot(
    data = map_tbl_i,
    estimate_col = "latest_estimate",
    max_abs = max_abs_level_i,
    title = NULL,
    subtitle = NULL,
    fill_label = "beta",
    show_legend = FALSE
  )

  clean_delta_plot_i <- make_map_plot(
    data = map_tbl_i,
    estimate_col = "delta_estimate",
    max_abs = max_abs_delta_i,
    title = NULL,
    subtitle = NULL,
    fill_label = "beta"
  )

  triptych_panel_rows[[length(triptych_panel_rows) + 1L]] <- list(
    row_label = sprintf("(%s) %s", letters[[i]], make_outcome_label_sentence(outcome_i)),
    early = clean_early_plot_i,
    latest = clean_latest_plot_i,
    delta = clean_delta_plot_i
  )
}

triptych_panel_clean_path <- report_png_path("gtwr_level_early_latest_delta_triptych_panel_clean")
save_triptych_panel_plot_safe(
  panel_rows = triptych_panel_rows,
  path = triptych_panel_clean_path,
  width = 14.5,
  row_height = 2.35,
  header_height = 0.55
)
register_artifact(
  artifact_name = "gtwr_level_early_latest_delta_triptych_panel_clean",
  artifact_path = triptych_panel_clean_path,
  artifact_type = "png",
  note = "paper-ready clean panel of early/latest/delta quarterly GTWR triptychs with shared column headers"
)


#==============================================================================
# 7. Manifest
#==============================================================================

manifest_tbl <- dplyr::bind_rows(artifact_rows) |>
  dplyr::mutate(
    expected_yq = paste(expected_yq, collapse = "|"),
    observed_yq = paste(observed_yq, collapse = "|"),
    observed_earliest_yq = expected_yq[[1L]],
    observed_latest_yq = expected_yq[[length(expected_yq)]]
  )

write_csv_safe(manifest_tbl, manifest_path)

append_log(
  cfg$logs$model_run,
    paste0(
      "- GTWR quarterly level artifacts created: control_set=", control_set_selected,
      ", tables=", sum(manifest_tbl$artifact_type == "csv"),
      ", plots=", sum(manifest_tbl$artifact_type == "png"),
      ", manifest=", basename(manifest_path)
    )
)

  manifest_tbl
}

all_manifest_tbl <- dplyr::bind_rows(lapply(seq_len(nrow(gtwr_sources_tbl)), function(i) {
  build_gtwr_level_artifacts_for_source(gtwr_sources_tbl[i, , drop = FALSE])
}))

append_log(
  cfg$logs$model_run,
  paste0(
    "- GTWR quarterly level artifact build complete: sources=",
    paste(unique(all_manifest_tbl$control_set), collapse = ";"),
    ", artifacts=", nrow(all_manifest_tbl)
  )
)
