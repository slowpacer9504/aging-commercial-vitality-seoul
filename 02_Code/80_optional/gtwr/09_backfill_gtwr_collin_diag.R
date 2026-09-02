#==============================================================================
# Script    : 09_backfill_gtwr_collin_diag.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Recompute GTWR local collinearity diagnostics for already-estimated
#             specs without refitting GTWR, and quantify what the GWmodel
#             ti.distv() string-comparison defect changed.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-01
# Status    : QUARTERLY_OPTIONAL / manual diagnostic sidecar
# Type      : spatial_panel_diagnostic
# Inputs    : panel_main.parquet, administrative boundary,
#             gtwr_main_models_<control_set>.csv,
#             gtwr_controls_used_<control_set>.csv,
#             gtwr_local_coefficients_<control_set>.csv
# Outputs   : gtwr_collin_diag_backfill_<control_set>.csv
# DependsOn : 03_run_gtwr_main.R, utils_gtwr_main.R
#==============================================================================
#
# Why this script exists
# ---------------------
# The local collinearity diagnostics depend only on the design matrix and the
# spatiotemporal weights, never on the fitted GTWR coefficients. They can
# therefore be recomputed for an existing run in minutes instead of the ~12h a
# full refit costs, which is what makes it possible to report defensible
# collinearity numbers before scheduling a rerun.
#
# It reports every diagnostic twice:
#   - time_basis = "legacy_string_compare" reproduces GWmodel::ti.distv(), which
#     compares times with as.character() and so treats quarter 3 as "future"
#     relative to quarter 25 ("25" < "3"). This is the weighting the existing
#     stored outputs were actually estimated under.
#   - time_basis = "symmetric" uses the |t_i - t_j| distance the corrected
#     pipeline now builds.
# The gap between the two is a direct, refit-free measure of the defect's reach.
#
# Consistency gate
# ----------------
# Under the legacy basis the recomputed uncentered condition number must
# reproduce local_cn_gtwr_latest as stored by the original run. Agreement proves
# the panel and d_fit were reconstructed exactly as that run saw them; the new
# metrics can then be read alongside the stored coefficients. Disagreement means
# the panel changed after the run, and the script stops after writing its output
# so the mismatch can be inspected.
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
source(here::here("02_Code", "99_utils", "utils_model.R"))
source(here::here("02_Code", "99_utils", "utils_spatial.R"))
source(here::here("02_Code", "99_utils", "utils_gtwr_main.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 09_backfill_gtwr_collin_diag", timestamp()))

# The QC script keeps its CSV reader private, so this sidecar carries its own.
# GTWR tables are written by write_csv_safe()/readr, i.e. plain UTF-8.
read_gtwr_table <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(
    readr::read_csv(path, show_col_types = FALSE, progress = FALSE),
    error = function(e) NULL
  )
}

# Relative tolerance for the consistency gate. The recomputation repeats the same
# floating-point operations in the same order, so agreement should be near exact.
BACKFILL_GATE_TOL <- 1e-6

TIME_BASES <- list(
  legacy_string_compare = gtwr_time_dist_vector_legacy,
  symmetric = gtwr_time_dist_vector
)

empty_backfill_tbl <- function() {
  tibble::tibble(
    adm_cd = character(),
    outcome = character(),
    focal_var = character(),
    control_set = character(),
    time_basis = character(),
    st_bw = numeric(),
    local_cn_uncentered_earliest = numeric(),
    local_cn_uncentered_latest = numeric(),
    local_cn_centered_earliest = numeric(),
    local_cn_centered_latest = numeric(),
    local_vif_max_earliest = numeric(),
    local_vif_max_latest = numeric(),
    collinearity_warn_earliest = logical(),
    collinearity_warn_latest = logical(),
    n_pos_latest = integer(),
    n_eff_latest = numeric(),
    n_dongs_latest = integer(),
    n_quarters_latest = integer()
  )
}

#==============================================================================
# 1. Per-Spec Diagnostic Recomputation
#==============================================================================

# Rebuild the exact complete-case sample run_actual_gtwr_spec() fits on.
build_backfill_d_fit <- function(panel_xy, outcome, rhs_vars) {
  vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", "time_id", "x", "y", outcome, rhs_vars))
  panel_xy |>
    dplyr::select(dplyr::all_of(vars)) |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(c(outcome, rhs_vars, "x", "y")), ~ suppressWarnings(as.numeric(.x)))
    ) |>
    tidyr::drop_na() |>
    dplyr::arrange(.data$time_id, .data$adm_cd)
}

# Diagnostics plus a description of which observations actually carried weight.
# The neighbourhood summary is what shows the defect: under the legacy basis a
# focal quarter silently loses part of its own history.
diagnose_targets <- function(d_fit, mm, loc, tv, target_idx, st_bw, time_dist_fn) {
  if (length(target_idx) == 0L) {
    return(list(diag = empty_gtwr_collin_diag(0L), nbhd = NULL))
  }

  # Computed once per spec so every target column is normalized identically, and
  # so the max over the location matrix is not recomputed for each target.
  scales <- gtwr_st_scales(loc, tv)

  results <- lapply(target_idx, function(i) {
    dv <- gtwr_st_dist_column(
      loc = loc,
      time_ids = tv,
      focus = i,
      lamda = cfg$gtwr_lamda,
      ksi = cfg$gtwr_ksi,
      time_dist_fn = time_dist_fn,
      scales = scales
    )
    w <- tryCatch(
      GWmodel::gw.weight(
        vdist = dv,
        bw = st_bw,
        kernel = cfg$gtwr_kernel,
        adaptive = isTRUE(cfg$gtwr_adaptive)
      ),
      error = function(e) rep(NA_real_, length(dv))
    )
    pos <- is.finite(w) & w > 0
    list(
      diag = weighted_design_collin_diag(mm, w),
      n_pos = sum(pos),
      n_eff = if (any(pos)) sum(w[pos])^2 / sum(w[pos]^2) else NA_real_,
      n_dongs = dplyr::n_distinct(d_fit$adm_cd[pos]),
      n_quarters = dplyr::n_distinct(tv[pos])
    )
  })

  list(
    diag = data.frame(
      cn_uncentered = vapply(results, function(z) z$diag$cn_uncentered, numeric(1)),
      cn_centered = vapply(results, function(z) z$diag$cn_centered, numeric(1)),
      vif_max = vapply(results, function(z) z$diag$vif_max, numeric(1))
    ),
    nbhd = data.frame(
      n_pos = vapply(results, function(z) as.integer(z$n_pos), integer(1)),
      n_eff = vapply(results, function(z) z$n_eff, numeric(1)),
      n_dongs = vapply(results, function(z) as.integer(z$n_dongs), integer(1)),
      n_quarters = vapply(results, function(z) as.integer(z$n_quarters), integer(1))
    )
  )
}

backfill_one_spec <- function(panel_xy, outcome, focal_var, selected_controls, control_set, st_bw) {
  rhs_vars <- unique(c(focal_var, selected_controls))
  d_fit <- build_backfill_d_fit(panel_xy, outcome, rhs_vars)
  if (nrow(d_fit) == 0L) return(empty_backfill_tbl())

  loc <- gtwr_location_dist(d_fit)
  if (is.null(loc)) return(empty_backfill_tbl())
  tv <- suppressWarnings(as.numeric(d_fit$time_id))

  mm <- tryCatch(
    stats::model.matrix(stats::reformulate(rhs_vars), data = d_fit),
    error = function(e) NULL
  )
  if (is.null(mm) || ncol(mm) <= 1L) return(empty_backfill_tbl())

  period_meta <- gtwr_period_meta(d_fit)
  period_id <- period_meta$period_id
  ordered_idx <- function(period_value) {
    idx <- which(period_id == period_value)
    idx[order(d_fit$adm_cd[idx])]
  }
  earliest_idx <- ordered_idx(period_meta$earliest_period_id)
  latest_idx <- ordered_idx(period_meta$latest_period_id)

  purrr::imap_dfr(TIME_BASES, function(time_dist_fn, basis_name) {
    earliest <- diagnose_targets(d_fit, mm, loc, tv, earliest_idx, st_bw, time_dist_fn)
    latest <- diagnose_targets(d_fit, mm, loc, tv, latest_idx, st_bw, time_dist_fn)

    earliest_tbl <- tibble::tibble(
      adm_cd = as.character(d_fit$adm_cd[earliest_idx]),
      local_cn_uncentered_earliest = earliest$diag$cn_uncentered,
      local_cn_centered_earliest = earliest$diag$cn_centered,
      local_vif_max_earliest = earliest$diag$vif_max,
      collinearity_warn_earliest = gtwr_collin_warn_flag(earliest$diag$vif_max)
    )
    latest_tbl <- tibble::tibble(
      adm_cd = as.character(d_fit$adm_cd[latest_idx]),
      local_cn_uncentered_latest = latest$diag$cn_uncentered,
      local_cn_centered_latest = latest$diag$cn_centered,
      local_vif_max_latest = latest$diag$vif_max,
      collinearity_warn_latest = gtwr_collin_warn_flag(latest$diag$vif_max),
      n_pos_latest = if (is.null(latest$nbhd)) integer(0) else latest$nbhd$n_pos,
      n_eff_latest = if (is.null(latest$nbhd)) numeric(0) else latest$nbhd$n_eff,
      n_dongs_latest = if (is.null(latest$nbhd)) integer(0) else latest$nbhd$n_dongs,
      n_quarters_latest = if (is.null(latest$nbhd)) integer(0) else latest$nbhd$n_quarters
    )

    dplyr::full_join(earliest_tbl, latest_tbl, by = "adm_cd") |>
      dplyr::mutate(
        outcome = outcome,
        focal_var = focal_var,
        control_set = control_set,
        time_basis = basis_name,
        st_bw = as.numeric(st_bw)
      ) |>
      dplyr::select(dplyr::all_of(names(empty_backfill_tbl())))
  })
}

#==============================================================================
# 2. Consistency Gate
#==============================================================================

# Compare the legacy-basis recomputation against what the original run stored.
evaluate_gate <- function(backfill_tbl, local_path) {
  stored <- read_gtwr_table(local_path)
  if (!inherits(stored, "data.frame") || !"local_cn_gtwr_latest" %in% names(stored)) {
    return(list(status = "skipped", detail = "stored local coefficients unavailable"))
  }

  cmp <- backfill_tbl |>
    dplyr::filter(.data$time_basis == "legacy_string_compare") |>
    dplyr::select(adm_cd, outcome, focal_var, recomputed = local_cn_uncentered_latest) |>
    dplyr::inner_join(
      stored |>
        dplyr::transmute(
          adm_cd = as.character(.data$adm_cd),
          outcome = as.character(.data$outcome),
          focal_var = as.character(.data$focal_var),
          stored = suppressWarnings(as.numeric(.data$local_cn_gtwr_latest))
        ),
      by = c("adm_cd", "outcome", "focal_var")
    ) |>
    dplyr::filter(is.finite(.data$recomputed), is.finite(.data$stored))

  if (nrow(cmp) == 0L) {
    return(list(status = "skipped", detail = "no overlapping finite values to compare"))
  }

  rel_diff <- abs(cmp$recomputed - cmp$stored) / pmax(abs(cmp$stored), .Machine$double.eps)
  worst <- max(rel_diff)
  list(
    status = if (worst <= BACKFILL_GATE_TOL) "pass" else "fail",
    detail = sprintf(
      "n_compared=%d, max_rel_diff=%.3e, median_rel_diff=%.3e",
      nrow(cmp), worst, stats::median(rel_diff)
    )
  )
}

#==============================================================================
# 3. Execution
#==============================================================================

{
  control_set <- normalize_control_set_main(cfg$gtwr_control_set)
  summary_path <- cfg$get_gtwr_main_models_path(control_set)
  controls_path <- cfg$get_gtwr_controls_used_path(control_set)
  local_path <- cfg$get_gtwr_local_coefficients_path(control_set)
  out_path <- file.path(
    cfg$dir_tables,
    sprintf("gtwr_collin_diag_backfill_%s.csv", cfg$gtwr_main_output_tag(control_set))
  )

  missing_inputs <- c(summary_path, controls_path)[!file.exists(c(summary_path, controls_path))]
  if (length(missing_inputs) > 0L) {
    stop(
      sprintf(
        "[ERROR] Backfill requires existing GTWR outputs; missing: %s",
        paste(basename(missing_inputs), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  summary_tbl <- read_gtwr_table(summary_path)
  controls_tbl <- read_gtwr_table(controls_path)
  if (!inherits(summary_tbl, "data.frame") || !inherits(controls_tbl, "data.frame")) {
    stop("[ERROR] Could not read the existing GTWR summary/controls tables.", call. = FALSE)
  }

  # The bandwidth and control set are taken from the original run, never
  # reselected, so the recomputed weights match the run being described.
  spec_tbl <- summary_tbl |>
    dplyr::filter(.data$status == "success") |>
    dplyr::transmute(
      outcome = as.character(.data$outcome),
      focal_var = as.character(.data$focal_var),
      st_bw = suppressWarnings(as.numeric(.data$st_bw))
    ) |>
    dplyr::inner_join(
      controls_tbl |>
        dplyr::transmute(
          outcome = as.character(.data$outcome),
          focal_var = as.character(.data$focal_var),
          selected_controls = as.character(.data$selected_controls)
        ),
      by = c("outcome", "focal_var")
    ) |>
    dplyr::filter(is.finite(.data$st_bw))

  if (nrow(spec_tbl) == 0L) {
    write_csv_safe(empty_backfill_tbl(), out_path)
    append_log(cfg$logs$model_run, "- GTWR collinearity backfill skipped: no successful specs found")
  } else {
    panel_xy <- read_panel_main_view("gtwr") |>
      dplyr::mutate(adm_cd = as.character(adm_cd)) |>
      prepare_gtwr_points()

    backfill_tbl <- purrr::pmap_dfr(
      list(spec_tbl$outcome, spec_tbl$focal_var, spec_tbl$selected_controls, spec_tbl$st_bw),
      function(outcome, focal_var, selected_controls, st_bw) {
        controls <- trimws(strsplit(selected_controls, ";", fixed = TRUE)[[1]])
        controls <- controls[nzchar(controls) & !is.na(controls) & controls != "NA"]
        append_log(
          cfg$logs$model_run,
          sprintf("- backfilling collinearity diagnostics: outcome=%s, focal=%s, st_bw=%s", outcome, focal_var, st_bw)
        )
        backfill_one_spec(
          panel_xy = panel_xy,
          outcome = outcome,
          focal_var = focal_var,
          selected_controls = controls,
          control_set = control_set,
          st_bw = st_bw
        )
      }
    )

    write_csv_safe(backfill_tbl, out_path)

    gate <- evaluate_gate(backfill_tbl, local_path)
    append_log(
      cfg$logs$model_run,
      sprintf("- GTWR collinearity backfill consistency gate: %s (%s)", gate$status, gate$detail)
    )
    message(sprintf("[GATE] %s -- %s", toupper(gate$status), gate$detail))

    # Written before the gate is enforced so a mismatch can still be inspected.
    if (identical(gate$status, "fail")) {
      stop(
        sprintf(
          paste0(
            "[ERROR] Consistency gate failed (%s). The reconstructed sample does not reproduce the stored ",
            "local_cn_gtwr_latest, so panel_main.parquet has changed since the GTWR run that produced %s. ",
            "The backfilled diagnostics cannot be paired with the stored coefficients; a GTWR rerun is required. ",
            "Output was still written to %s for inspection."
          ),
          gate$detail, basename(local_path), basename(out_path)
        ),
        call. = FALSE
      )
    }
  }
}
