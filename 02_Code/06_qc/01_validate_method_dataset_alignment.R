#==============================================================================
# Script    : 01_validate_method_dataset_alignment.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Validate the active quarterly panel/method contract and ignore
#             deferred appendix assets when judging run success.
# Author    : Codex
# Created   : 2026-04-18
# Type      : qc
# Inputs    : active preprocess/model outputs up to robustness
# Outputs   : method_dataset_contract_check.csv
# DependsOn : 02_build_seoul_quarter_base.R, 03_build_auxiliary_covariates.R,
#             06_build_analysis_panel.R, 07_build_vitality_index.R,
#             01_build_spatial_weights.R, 02_run_esda.R, 01_run_twfe_main.R,
#             02_run_spdm_main.R, 01_run_spdm_w_robustness.R,
#             02_run_robustness.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
load_project_packages()

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 01_validate_method_dataset_alignment", timestamp()))


#==============================================================================
# 1. Helpers
#==============================================================================

add_row <- function(check_id, method, pass, detail) {
  tibble::tibble(
    check_id = check_id,
    method = method,
    status = if (isTRUE(pass)) "PASS" else "FAIL",
    detail = as.character(detail)
  )
}

describe_presence <- function(paths) {
  paste(sprintf("%s=%s", basename(paths), file.exists(paths)), collapse = ", ")
}

safe_read_csv <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(readr::read_csv(path, show_col_types = FALSE), error = function(e) e)
}

safe_read_view <- function(view_name) {
  tryCatch(read_panel_main_view(view_name), error = function(e) e)
}

describe_optional_absence <- function(path) {
  sprintf("not_run_appendix: %s missing", basename(path))
}

scan_forbidden_patterns <- function(df, patterns) {
  if (nrow(df) == 0L || length(patterns) == 0L) return(character())
  char_cols <- names(df)[vapply(df, function(x) is.character(x) || is.factor(x), logical(1))]
  if (length(char_cols) == 0L) return(character())
  hits <- character()
  for (pat in patterns) {
    matched <- vapply(
      df[char_cols],
      function(col) any(stringr::str_detect(as.character(stats::na.omit(col)), pat)),
      logical(1)
    )
    if (any(matched)) hits <- c(hits, pat)
  }
  unique(hits)
}

check_optional_csv_schema <- function(check_id,
                                      method,
                                      path,
                                      required_cols,
                                      forbidden_cols = c("sample_min_year", "sample_max_year", "target_year", "earliest_year", "latest_year", "recent_year_n"),
                                      forbidden_value_patterns = c("_l[0-9]+\\b", "_f[0-9]+\\b", "_yoy\\b"),
                                      extra_pass = function(df) TRUE,
                                      extra_detail = function(df) "schema ok") {
  if (!isTRUE(optional_required_test_enabled)) {
    return(add_row(check_id, method, TRUE, sprintf("excluded_from_required_quarterly_test_plan: %s", basename(path))))
  }

  tbl <- safe_read_csv(path)
  if (is.null(tbl)) {
    return(add_row(check_id, method, TRUE, describe_optional_absence(path)))
  }
  if (inherits(tbl, "error")) {
    return(add_row(check_id, method, FALSE, tbl$message))
  }

  missing_cols <- setdiff(required_cols, names(tbl))
  leaked_cols <- intersect(forbidden_cols, names(tbl))
  leaked_patterns <- scan_forbidden_patterns(tbl, forbidden_value_patterns)
  extra_ok <- isTRUE(extra_pass(tbl))
  detail <- sprintf(
    "path=%s; missing=%s; leaked_cols=%s; leaked_patterns=%s; %s",
    basename(path),
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (length(leaked_cols) == 0L) "none" else paste(leaked_cols, collapse = ", "),
    if (length(leaked_patterns) == 0L) "none" else paste(leaked_patterns, collapse = ", "),
    extra_detail(tbl)
  )
  add_row(
    check_id,
    method,
    length(missing_cols) == 0L && length(leaked_cols) == 0L && length(leaked_patterns) == 0L && extra_ok,
    detail
  )
}

expected_main_outcomes <- sort(unique(c(cfg$primary_outcomes, cfg$vitality_supplementary_outcomes)))
expected_channel_outcomes <- sort(unique(cfg$spdm_channel_outcomes))
w_robustness_expected <- sort(unique(c(cfg$default_w, cfg$alt_w)))
expected_robustness_axes <- sort(c("outcome_definition", "sample_window", "w_moran"))
optional_required_test_enabled <- FALSE
rows <- list()


#==============================================================================
# 2. Shared Data Contract
#==============================================================================

shared_paths <- cfg$active_output_contract$shared_data
rows[[length(rows) + 1L]] <- add_row(
  "A01",
  "shared_data",
  all(file.exists(shared_paths)),
  describe_presence(shared_paths)
)

panel_twfe <- safe_read_view("twfe")
if (inherits(panel_twfe, "error")) {
  rows[[length(rows) + 1L]] <- add_row("A02", "panel_main", FALSE, panel_twfe$message)
} else {
  panel_twfe <- panel_twfe |>
    dplyr::mutate(adm_cd = as.character(adm_cd))

  required_cols <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "age60_resident_share", expected_main_outcomes))
  missing_cols <- setdiff(required_cols, names(panel_twfe))
  duplicate_n <- panel_twfe |>
    dplyr::count(adm_cd, yq, name = "n") |>
    dplyr::filter(n > 1L) |>
    nrow()
  observed_yq <- sort(unique(stats::na.omit(as.character(panel_twfe$yq))))
  expected_yq <- sort(unique(as.character(cfg$quarter_sequence$yq)))

  rows[[length(rows) + 1L]] <- add_row(
    "A02",
    "panel_main",
    length(missing_cols) == 0L,
    sprintf(
      "missing core cols=%s",
      if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", ")
    )
  )
  rows[[length(rows) + 1L]] <- add_row(
    "A03",
    "panel_main",
    duplicate_n == 0L,
    sprintf("duplicate adm_cd-yq rows=%d", duplicate_n)
  )
  rows[[length(rows) + 1L]] <- add_row(
    "A04",
    "panel_main",
    identical(observed_yq, expected_yq),
    sprintf(
      "observed_yq=%s; expected_yq=%s",
      paste(observed_yq, collapse = ", "),
      paste(expected_yq, collapse = ", ")
    )
  )
  rows[[length(rows) + 1L]] <- add_row(
    "A05",
    "panel_main",
    length(missing_cols) == 0L,
    sprintf(
      "required quarterly time cols present=%s",
      if (length(missing_cols) == 0L) "yes" else paste(missing_cols, collapse = ", ")
    )
  )
}

for (view_name in c("esda", "twfe", "spdm", "gtwr")) {
  view_tbl <- safe_read_view(view_name)
  check_id <- sprintf("A%02d", match(view_name, c("esda", "twfe", "spdm", "gtwr")) + 5L)
  if (inherits(view_tbl, "error")) {
    rows[[length(rows) + 1L]] <- add_row(check_id, paste0("panel_view_", view_name), FALSE, view_tbl$message)
  } else {
    expected_cols <- get_panel_main_view_cols(view_name)
    missing_cols <- setdiff(expected_cols, names(view_tbl))
    rows[[length(rows) + 1L]] <- add_row(
      check_id,
      paste0("panel_view_", view_name),
      length(missing_cols) == 0L,
      sprintf(
        "n_rows=%d, n_cols=%d, missing=%s",
        nrow(view_tbl),
        ncol(view_tbl),
        if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", ")
      )
    )
  }
}


#==============================================================================
# 3. ESDA Contract
#==============================================================================

esda_paths <- cfg$active_output_contract$esda
rows[[length(rows) + 1L]] <- add_row("E01", "esda", all(file.exists(esda_paths)), describe_presence(esda_paths))

global_moran_tbl <- safe_read_csv(cfg$paths$global_morans_i)
global_bivariate_tbl <- safe_read_csv(cfg$paths$global_bivariate_morans_i)
bivariate_lisa_tbl <- safe_read_csv(cfg$paths$bivariate_lisa_summary)
ehsa_tbl <- safe_read_csv(cfg$paths$emerging_hotspot_summary)

esda_ok <- !inherits(global_moran_tbl, "error") &&
  !inherits(global_bivariate_tbl, "error") &&
  !inherits(ehsa_tbl, "error") &&
  !is.null(global_moran_tbl) &&
  !is.null(global_bivariate_tbl) &&
  !is.null(ehsa_tbl) &&
  all(c("yq", "w_type") %in% names(global_moran_tbl)) &&
  all(c("yq", "w_type") %in% names(global_bivariate_tbl)) &&
  all(c("start_yq", "end_yq") %in% names(ehsa_tbl)) &&
  nrow(global_moran_tbl) > 0L &&
  nrow(global_bivariate_tbl) > 0L &&
  nrow(ehsa_tbl) > 0L
rows[[length(rows) + 1L]] <- add_row(
  "E02",
  "esda",
  esda_ok,
  sprintf(
    "global_rows=%s, bivariate_rows=%s, ehsa_rows=%s",
    if (inherits(global_moran_tbl, "data.frame")) nrow(global_moran_tbl) else "unreadable",
    if (inherits(global_bivariate_tbl, "data.frame")) nrow(global_bivariate_tbl) else "unreadable",
    if (inherits(ehsa_tbl, "data.frame")) nrow(ehsa_tbl) else "unreadable"
  )
)

map_counts <- c(
  distribution = length(list.files(cfg$dir_maps, pattern = "^distribution_map__.*[.]png$", full.names = TRUE)),
  univariate_lisa = length(list.files(cfg$dir_maps, pattern = "^univariate_lisa_map__.*[.]png$", full.names = TRUE)),
  bivariate_lisa = length(list.files(cfg$dir_maps, pattern = "^bivariate_lisa_map__.*[.]png$", full.names = TRUE)),
  emerging_hotspot = length(list.files(cfg$dir_maps, pattern = "^emerging_hotspot_map__.*[.]png$", full.names = TRUE))
)
expected_bivariate_lisa_maps <- if (
  inherits(bivariate_lisa_tbl, "data.frame") &&
    all(c("var_x", "var_y", "status") %in% names(bivariate_lisa_tbl))
) {
  bivariate_lisa_tbl |>
    dplyr::filter(status == "success") |>
    dplyr::distinct(var_x, var_y) |>
    nrow()
} else {
  1L
}
map_ok <- all(map_counts[c("distribution", "univariate_lisa", "emerging_hotspot")] > 0L) &&
  expected_bivariate_lisa_maps > 0L &&
  map_counts[["bivariate_lisa"]] >= expected_bivariate_lisa_maps
rows[[length(rows) + 1L]] <- add_row(
  "E03",
  "esda",
  map_ok,
  paste(
    c(
      sprintf("%s=%d", names(map_counts), map_counts),
      sprintf("expected_bivariate_lisa_maps=%d", expected_bivariate_lisa_maps)
    ),
    collapse = ", "
  )
)


#==============================================================================
# 4. TWFE Contract
#==============================================================================

twfe_paths <- cfg$active_output_contract$twfe
rows[[length(rows) + 1L]] <- add_row("T01", "twfe", all(file.exists(twfe_paths)), describe_presence(twfe_paths))

twfe_diag_tbl <- safe_read_csv(cfg$paths$twfe_main_diagnostics)
if (inherits(twfe_diag_tbl, "data.frame")) {
  missing_cols <- setdiff(c("model_name", "outcome", "exposure", "spec", "status"), names(twfe_diag_tbl))
  success_outcomes <- twfe_diag_tbl |>
    dplyr::filter(spec == "m2", exposure == "age60_resident_share", status == "success") |>
    dplyr::pull(outcome) |>
    unique() |>
    sort()
  pass <- length(missing_cols) == 0L && identical(success_outcomes, expected_main_outcomes)
  detail <- sprintf(
    "missing cols=%s; successful m2 outcomes=%s",
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (length(success_outcomes) == 0L) "none" else paste(success_outcomes, collapse = ", ")
  )
} else {
  pass <- FALSE
  detail <- if (inherits(twfe_diag_tbl, "error")) twfe_diag_tbl$message else "unavailable"
}
rows[[length(rows) + 1L]] <- add_row("T02", "twfe", pass, detail)

twfe_moran_tbl <- safe_read_csv(cfg$paths$twfe_main_residual_moran_summary)
if (inherits(twfe_moran_tbl, "data.frame")) {
  missing_cols <- setdiff(
    c("outcome", "exposure", "status", "sample_min_yq", "sample_max_yq", "n_yq_tested", "latest_yq"),
    names(twfe_moran_tbl)
  )
  success_outcomes <- twfe_moran_tbl |>
    dplyr::filter(exposure == "age60_resident_share", status == "success") |>
    dplyr::pull(outcome) |>
    unique() |>
    sort()
  pass <- length(missing_cols) == 0L && identical(success_outcomes, expected_main_outcomes)
  detail <- sprintf(
    "missing cols=%s; successful Moran outcomes=%s",
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (length(success_outcomes) == 0L) "none" else paste(success_outcomes, collapse = ", ")
  )
} else {
  pass <- FALSE
  detail <- if (inherits(twfe_moran_tbl, "error")) twfe_moran_tbl$message else "unavailable"
}
rows[[length(rows) + 1L]] <- add_row("T03", "twfe", pass, detail)


#==============================================================================
# 5. SPDM Contract
#==============================================================================

spdm_paths <- cfg$active_output_contract$spdm
rows[[length(rows) + 1L]] <- add_row("S01", "spdm_main", all(file.exists(spdm_paths)), describe_presence(spdm_paths))

spdm_diag_tbl <- safe_read_csv(cfg$paths$spdm_main_diagnostics)
if (inherits(spdm_diag_tbl, "data.frame")) {
  missing_cols <- setdiff(
    c("spec_id", "outcome", "exposure", "model_family", "w_type", "status", "n_units", "n_periods", "n_obs", "selected_controls", "impacts_status"),
    names(spdm_diag_tbl)
  )
  success_outcomes <- spdm_diag_tbl |>
    dplyr::filter(
      model_family == "sdm",
      w_type == "queen",
      status == "success",
      impacts_status == "success",
      exposure == "age60_resident_share"
    ) |>
    dplyr::pull(outcome) |>
    unique() |>
    sort()
  pass <- length(missing_cols) == 0L && identical(success_outcomes, expected_main_outcomes)
  detail <- sprintf(
    "missing cols=%s; successful queen outcomes=%s",
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (length(success_outcomes) == 0L) "none" else paste(success_outcomes, collapse = ", ")
  )
} else {
  pass <- FALSE
  detail <- if (inherits(spdm_diag_tbl, "error")) spdm_diag_tbl$message else "unavailable"
}
rows[[length(rows) + 1L]] <- add_row("S02", "spdm_main", pass, detail)

spdm_impacts_tbl <- safe_read_csv(cfg$paths$spdm_impacts)
if (inherits(spdm_impacts_tbl, "data.frame")) {
  missing_cols <- setdiff(
    c("outcome", "focal_var", "status", "model_family", "w_type", "direct", "indirect", "total", "sample_min_yq", "sample_max_yq"),
    names(spdm_impacts_tbl)
  )
  success_outcomes <- spdm_impacts_tbl |>
    dplyr::filter(
      model_family == "sdm",
      w_type == "queen",
      status == "success",
      focal_var == "age60_resident_share"
    ) |>
    dplyr::pull(outcome) |>
    unique() |>
    sort()
  pass <- length(missing_cols) == 0L && identical(success_outcomes, expected_main_outcomes)
  detail <- sprintf(
    "missing cols=%s; successful impact outcomes=%s",
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (length(success_outcomes) == 0L) "none" else paste(success_outcomes, collapse = ", ")
  )
} else {
  pass <- FALSE
  detail <- if (inherits(spdm_impacts_tbl, "error")) spdm_impacts_tbl$message else "unavailable"
}
rows[[length(rows) + 1L]] <- add_row("S03", "spdm_main", pass, detail)


#==============================================================================
# 5A. SPDM Canonical Channel Path Contract
#==============================================================================

spdm_channel_paths <- c(
  cfg$paths$spdm_channel_models,
  cfg$paths$spdm_channel_impacts,
  cfg$paths$spdm_channel_controls_used,
  cfg$paths$spdm_channel_path_effects,
  cfg$paths$spdm_channel_bootstrap_draws,
  cfg$paths$spdm_channel_diagnostics
)
rows[[length(rows) + 1L]] <- add_row(
  "C01",
  "spdm_channel_path",
  all(file.exists(spdm_channel_paths)),
  describe_presence(spdm_channel_paths)
)

spdm_channel_diag_tbl <- safe_read_csv(cfg$paths$spdm_channel_diagnostics)
if (inherits(spdm_channel_diag_tbl, "data.frame")) {
  missing_cols <- setdiff(
    c("outcome", "equation", "path", "exposure", "mediator", "status", "impacts_status", "sample_min_yq", "sample_max_yq"),
    names(spdm_channel_diag_tbl)
  )
  success_outcomes <- spdm_channel_diag_tbl |>
    dplyr::filter(
      equation == "outcome",
      status == "success",
      impacts_status == "success",
      exposure == "age60_resident_share",
      mediator == "age60_floating_share"
    ) |>
    dplyr::pull(outcome) |>
    unique() |>
    sort()
  pass <- length(missing_cols) == 0L && identical(success_outcomes, expected_channel_outcomes)
  detail <- sprintf(
    "missing cols=%s; successful channel outcomes=%s",
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (length(success_outcomes) == 0L) "none" else paste(success_outcomes, collapse = ", ")
  )
} else {
  pass <- FALSE
  detail <- if (inherits(spdm_channel_diag_tbl, "error")) spdm_channel_diag_tbl$message else "unavailable"
}
rows[[length(rows) + 1L]] <- add_row("C02", "spdm_channel_path", pass, detail)

spdm_channel_path_tbl <- safe_read_csv(cfg$paths$spdm_channel_path_effects)
if (inherits(spdm_channel_path_tbl, "data.frame")) {
  missing_cols <- setdiff(
    c(
      "outcome", "effect_scale",
      "c_total_estimate", "c_prime_estimate", "direct_attenuation",
      "indirect_effect", "indirect_p", "status", "inference_method",
      "bootstrap_valid_draws", "bootstrap_R", "bootstrap_method"
    ),
    names(spdm_channel_path_tbl)
  )
  success_total_outcomes <- spdm_channel_path_tbl |>
    dplyr::filter(effect_scale == "total", status == "success") |>
    dplyr::pull(outcome) |>
    unique() |>
    sort()
  pass <- length(missing_cols) == 0L && identical(success_total_outcomes, expected_channel_outcomes)
  detail <- sprintf(
    "missing cols=%s; successful total indirect outcomes=%s",
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (length(success_total_outcomes) == 0L) "none" else paste(success_total_outcomes, collapse = ", ")
  )
} else {
  pass <- FALSE
  detail <- if (inherits(spdm_channel_path_tbl, "error")) spdm_channel_path_tbl$message else "unavailable"
}
rows[[length(rows) + 1L]] <- add_row("C03", "spdm_channel_path", pass, detail)


#==============================================================================
# 6. SPDM W-Robustness Contract
#==============================================================================

spdm_w_paths <- cfg$active_output_contract$spdm_w_robustness
rows[[length(rows) + 1L]] <- add_row(
  "W01",
  "spdm_w_robustness",
  all(file.exists(spdm_w_paths)),
  describe_presence(spdm_w_paths)
)

spdm_w_diag_tbl <- safe_read_csv(cfg$paths$spdm_w_robustness_diagnostics)
if (inherits(spdm_w_diag_tbl, "data.frame")) {
  missing_cols <- setdiff(
    c("outcome", "exposure", "model_family", "w_type", "status", "impacts_status"),
    names(spdm_w_diag_tbl)
  )
  success_grid <- spdm_w_diag_tbl |>
    dplyr::filter(
      model_family == "sdm",
      status == "success",
      impacts_status == "success",
      exposure == "age60_resident_share"
    ) |>
    dplyr::distinct(outcome, w_type)
  expected_grid <- tidyr::crossing(outcome = expected_main_outcomes, w_type = w_robustness_expected)
  unmatched_grid <- dplyr::anti_join(expected_grid, success_grid, by = c("outcome", "w_type"))
  pass <- length(missing_cols) == 0L && nrow(unmatched_grid) == 0L
  detail <- sprintf(
    "missing cols=%s; missing outcome-w pairs=%s",
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (nrow(unmatched_grid) == 0L) "none" else paste(sprintf("%s@%s", unmatched_grid$outcome, unmatched_grid$w_type), collapse = ", ")
  )
} else {
  pass <- FALSE
  detail <- if (inherits(spdm_w_diag_tbl, "error")) spdm_w_diag_tbl$message else "unavailable"
}
rows[[length(rows) + 1L]] <- add_row("W02", "spdm_w_robustness", pass, detail)


#==============================================================================
# 7. Robustness Contract
#==============================================================================

robustness_paths <- cfg$active_output_contract$robustness
rows[[length(rows) + 1L]] <- add_row(
  "R01",
  "robustness",
  all(file.exists(robustness_paths)),
  describe_presence(robustness_paths)
)

robustness_tbl <- safe_read_csv(cfg$paths$robustness_summary)
if (inherits(robustness_tbl, "data.frame")) {
  missing_cols <- setdiff(c("outcome", "spec_axis", "spec", "term", "status"), names(robustness_tbl))
  observed_axes <- robustness_tbl |>
    dplyr::pull(spec_axis) |>
    unique() |>
    sort()
  pass <- length(missing_cols) == 0L && identical(observed_axes, expected_robustness_axes)
  detail <- sprintf(
    "missing cols=%s; observed axes=%s",
    if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
    if (length(observed_axes) == 0L) "none" else paste(observed_axes, collapse = ", ")
  )
} else {
  pass <- FALSE
  detail <- if (inherits(robustness_tbl, "error")) robustness_tbl$message else "unavailable"
}
rows[[length(rows) + 1L]] <- add_row("R02", "robustness", pass, detail)


#==============================================================================
# 8. Optional GTWR Sidecar Contract
#==============================================================================

gtwr_control_set <- cfg$gtwr_control_set_token(cfg$gtwr_control_set)

gtwr_raw_paths <- c(
  cfg$get_gtwr_main_models_path(gtwr_control_set),
  cfg$get_gtwr_local_beta_panel_path(gtwr_control_set),
  cfg$get_gtwr_local_coefficients_path(gtwr_control_set),
  cfg$get_gtwr_controls_used_path(gtwr_control_set)
)

if (!isTRUE(optional_required_test_enabled)) {
  rows[[length(rows) + 1L]] <- add_row(
    "G01",
    "gtwr_optional",
    TRUE,
    sprintf("excluded_from_required_quarterly_test_plan: %s", describe_presence(gtwr_raw_paths))
  )
} else if (!isTRUE(cfg$run_gtwr_main_sidecar)) {
  rows[[length(rows) + 1L]] <- add_row(
    "G01",
    "gtwr_optional",
    TRUE,
    sprintf("RUN_GTWR_MAIN_SIDECAR=FALSE; optional raw outputs ignored (%s)", describe_presence(gtwr_raw_paths))
  )
} else {
  rows[[length(rows) + 1L]] <- add_row(
    "G01",
    "gtwr_optional",
    all(file.exists(gtwr_raw_paths)),
    sprintf("control_set=%s; %s", gtwr_control_set, describe_presence(gtwr_raw_paths))
  )

  gtwr_main_tbl <- safe_read_csv(cfg$get_gtwr_main_models_path(gtwr_control_set))
  if (inherits(gtwr_main_tbl, "data.frame")) {
    missing_cols <- setdiff(
      c("outcome", "focal_var", "status", "control_set", "fit_scope", "target_yq", "latest_yq"),
      names(gtwr_main_tbl)
    )
    expected_outcomes <- sort(unique(cfg$gtwr_main_outcomes))
    gtwr_focus_tbl <- gtwr_main_tbl |>
      dplyr::filter(focal_var == "age60_resident_share", control_set == .env$gtwr_control_set)
    observed_outcomes <- gtwr_focus_tbl |>
      dplyr::pull(outcome) |>
      unique() |>
      sort()
    valid_status <- all(gtwr_focus_tbl$status %in% c("success", "not_estimated"))
    quarterly_deferred_ok <- all(
      gtwr_focus_tbl$status == "success" |
        stringr::str_detect(gtwr_focus_tbl$fit_scope, "quarterly_deferred")
    )
    pass <- length(missing_cols) == 0L &&
      identical(observed_outcomes, expected_outcomes) &&
      valid_status &&
      quarterly_deferred_ok
    detail <- sprintf(
      "missing cols=%s; outcomes=%s; statuses=%s; fit_scopes=%s",
      if (length(missing_cols) == 0L) "none" else paste(missing_cols, collapse = ", "),
      if (length(observed_outcomes) == 0L) "none" else paste(observed_outcomes, collapse = ", "),
      if (nrow(gtwr_focus_tbl) == 0L) "none" else paste(unique(gtwr_focus_tbl$status), collapse = "|"),
      if (nrow(gtwr_focus_tbl) == 0L) "none" else paste(unique(gtwr_focus_tbl$fit_scope), collapse = "|")
    )
  } else {
    pass <- FALSE
    detail <- if (inherits(gtwr_main_tbl, "error")) gtwr_main_tbl$message else "unavailable"
  }
  rows[[length(rows) + 1L]] <- add_row("G02", "gtwr_optional", pass, detail)
}


#==============================================================================
# 9. Manual Appendix Contract (Excluded From Required Quarterly Test Plan)
#==============================================================================

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X01",
  "appendix_twfe_channel",
  cfg$paths$twfe_channel_models,
  required_cols = c("equation_type", "main_exposure", "channel_vars", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X02",
  "appendix_twfe_interaction",
  cfg$paths$twfe_interaction_diagnostics,
  required_cols = c("sample_min_yq", "sample_max_yq", "n_covid_obs", "n_non_covid_obs", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X03",
  "appendix_twfe_age_mix",
  cfg$paths$twfe_age_mix_experiment_diagnostics,
  required_cols = c("model_family", "domain", "same_domain_total_control", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X05",
  "appendix_spdm_interaction",
  cfg$paths$spdm_interaction_diagnostics,
  required_cols = c("sample_min_yq", "sample_max_yq", "n_pre_covid_obs", "n_post_covid_obs", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X06",
  "appendix_spdm_age_mix",
  cfg$paths$spdm_age_mix_experiment_diagnostics,
  required_cols = c("model_family_spdm", "age_mix_family", "domain", "sample_min_yq", "sample_max_yq", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X07",
  "appendix_spdm_sector_share",
  cfg$paths$spdm_sector_share_experiment_diagnostics,
  required_cols = c("exposure_family", "exposure_var", "finite_n__age60_resident_share", "finite_n__age60_floating_share", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X08",
  "appendix_spdm_selection",
  cfg$paths$spdm_selection_family_comparison,
  required_cols = c("family", "sample_min_yq", "sample_max_yq", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X09",
  "appendix_spdm_family_comparison",
  cfg$paths$spdm_family_comparison,
  required_cols = c("family", "status", "impacts_status", "sample_min_yq", "sample_max_yq", "focal_estimate"),
  extra_detail = function(df) sprintf("rows=%d; families=%s", nrow(df), paste(sort(unique(df$family)), collapse = ";"))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X09B",
  "appendix_spdm_family_models",
  cfg$paths$spdm_family_models,
  required_cols = c("model_family", "sample_min_yq", "sample_max_yq", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X10",
  "appendix_gtwr_floating",
  cfg$get_gtwr_floating_models_path(gtwr_control_set),
  required_cols = c("target_yq", "latest_yq", "control_set", "fit_scope", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X11",
  "appendix_gtwr_age_band",
  cfg$get_gtwr_age_band_models_path(gtwr_control_set),
  required_cols = c("domain", "age_band", "same_domain_total_control", "target_yq", "latest_yq", "control_set", "fit_scope", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X12",
  "appendix_gtwr_sector_share",
  cfg$get_gtwr_sector_share_models_path(gtwr_control_set),
  required_cols = c("exposure_family", "same_domain_total_control", "target_yq", "latest_yq", "control_set", "fit_scope", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X13",
  "appendix_gwr_delta",
  cfg$paths$gwr_delta_main_models,
  required_cols = c("early_start_year", "early_end_year", "late_start_year", "late_end_year", "window_n_year", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)

rows[[length(rows) + 1L]] <- check_optional_csv_schema(
  "X14",
  "appendix_gtwr_experiment",
  cfg$get_gtwr_experiment_main_models_path(gtwr_control_set),
  required_cols = c("target_yq", "latest_yq", "control_set", "fit_scope", "status"),
  extra_detail = function(df) sprintf("rows=%d", nrow(df))
)


#==============================================================================
# 10. Write QC Table
#==============================================================================

qc_tbl <- dplyr::bind_rows(rows) |>
  dplyr::arrange(check_id)

write_csv_safe(qc_tbl, cfg$paths$method_dataset_contract_check)

append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Quarterly contract QC complete: pass=%d, fail=%d",
    sum(qc_tbl$status == "PASS", na.rm = TRUE),
    sum(qc_tbl$status == "FAIL", na.rm = TRUE)
  )
)
