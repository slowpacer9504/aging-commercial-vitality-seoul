#==============================================================================
# Script    : 03_run_spdm_sector_share_experiment.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Run appendix SPDM models using broad sector-share outcomes and
#             separate resident/floating aging-share exposures.
# Author    : Codex
# Created   : 2026-03-29
# Status    : QUARTERLY_APPENDIX / manual sidecar outside canonical workflow
# Type      : spatial_panel_modeling
# Inputs    : panel_main.parquet, W_queen.rds
# Outputs   : spdm_sector_share_experiment_models.csv,
#             spdm_sector_share_experiment_impacts.csv,
#             spdm_sector_share_experiment_controls_used.csv,
#             spdm_sector_share_experiment_diagnostics.csv,
#             spdm_sector_share_experiment_exposure_relations.csv
# DependsOn : 01_build_spatial_weights.R, 02_run_spdm_main.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_model.R"))
source(here::here("02_Code", "R", "utils_spdm.R"))
load_project_packages()

append_log(cfg$logs$model_run, sprintf("\n## [%s] 03_run_spdm_sector_share_experiment", timestamp()))

path_models <- value_or(cfg$paths$spdm_sector_share_experiment_models, file.path(cfg$dir_tables, "spdm_sector_share_experiment_models.csv"))
path_impacts <- value_or(cfg$paths$spdm_sector_share_experiment_impacts, file.path(cfg$dir_tables, "spdm_sector_share_experiment_impacts.csv"))
path_controls <- value_or(cfg$paths$spdm_sector_share_experiment_controls_used, file.path(cfg$dir_tables, "spdm_sector_share_experiment_controls_used.csv"))
path_diagnostics <- value_or(cfg$paths$spdm_sector_share_experiment_diagnostics, file.path(cfg$dir_tables, "spdm_sector_share_experiment_diagnostics.csv"))
path_relations <- value_or(cfg$paths$spdm_sector_share_experiment_exposure_relations, file.path(cfg$dir_tables, "spdm_sector_share_experiment_exposure_relations.csv"))

{
  if (!file.exists(cfg$paths$panel_main) || !file.exists(cfg$paths$w_queen)) {
    stop("[ERROR] Missing panel or W", call. = FALSE)
  }

  extra_cols <- unique(c(
    value_or(cfg$spdm_sector_share_outcomes, c(
      "sales_share_cs1", "sales_share_cs2", "sales_share_cs3",
      "store_share_cs1", "store_share_cs2", "store_share_cs3"
    )),
    "age60_floating_share"
  ))
  panel <- read_panel_main_view("spdm", extra_cols = extra_cols)
  panel$adm_cd <- as.character(panel$adm_cd)
  panel$year <- suppressWarnings(as.integer(panel$year))
  panel$yq <- as.character(panel$yq)

  outcomes <- intersect(
    value_or(cfg$spdm_sector_share_outcomes, c(
      "sales_share_cs1", "sales_share_cs2", "sales_share_cs3",
      "store_share_cs1", "store_share_cs2", "store_share_cs3"
    )),
    names(panel)
  )
  exposure_defs <- tibble::tibble(
    exposure_family = c("resident_only", "floating_only"),
    exposure_var = c("age60_resident_share", "age60_floating_share"),
    exposure_order = c(1L, 2L)
  ) |>
    dplyr::filter(exposure_var %in% names(panel))

  control_candidates <- spdm_main_control_candidate_cols()
  assert_spdm_main_controls_current(
    tibble::tibble(control = control_candidates, selected = TRUE),
    context = "03_run_spdm_sector_share_experiment",
    control_col = "control",
    selected_col = "selected"
  )
  usable_controls <- select_usable_controls(panel, control_candidates, min_finite = 500L)

  calc_share_qc <- function(data, cols) {
    if (!all(cols %in% names(data))) {
      return(list(mean_abs_dev = NA_real_, max_abs_dev = NA_real_))
    }

    x <- data |>
      dplyr::select(dplyr::all_of(cols)) |>
      dplyr::filter(dplyr::if_all(dplyr::everything(), is.finite))
    if (nrow(x) == 0L) {
      return(list(mean_abs_dev = NA_real_, max_abs_dev = NA_real_))
    }

    sums <- rowSums(as.data.frame(x))
    list(
      mean_abs_dev = mean(abs(sums - 1), na.rm = TRUE),
      max_abs_dev = max(abs(sums - 1), na.rm = TRUE)
    )
  }

  sales_share_qc <- calc_share_qc(panel, c("sales_share_cs1", "sales_share_cs2", "sales_share_cs3"))
  store_share_qc <- calc_share_qc(panel, c("store_share_cs1", "store_share_cs2", "store_share_cs3"))
  exposure_finite_n <- vapply(
    c("age60_resident_share", "age60_floating_share"),
    function(v) {
      if (!v %in% names(panel)) return(0L)
      as.integer(sum(is.finite(panel[[v]]), na.rm = TRUE))
    },
    integer(1)
  )

  build_exposure_relations <- function(data) {
    exposure_vars <- c("age60_resident_share", "age60_floating_share")
    if (!all(exposure_vars %in% names(data))) {
      return(tibble::tibble(
        relation_type = character(),
        metric_label = character(),
        focal_var = character(),
        other_var = character(),
        estimate = numeric(),
        n_obs = integer(),
        message = character()
      ))
    }

    cc <- data |>
      dplyr::select(dplyr::all_of(exposure_vars)) |>
      tidyr::drop_na()
    if (nrow(cc) == 0L) {
      return(tibble::tibble(
        relation_type = character(),
        metric_label = character(),
        focal_var = character(),
        other_var = character(),
        estimate = numeric(),
        n_obs = integer(),
        message = character()
      ))
    }

    corr_pairs <- tibble::tribble(
      ~metric_label, ~focal_var, ~other_var,
      "resident_vs_floating", "age60_resident_share", "age60_floating_share"
    ) |>
      dplyr::rowwise() |>
      dplyr::mutate(
        relation_type = "pairwise_correlation",
        estimate = stats::cor(cc[[focal_var]], cc[[other_var]], use = "complete.obs"),
        n_obs = as.integer(nrow(cc)),
        message = "pearson_complete_case"
      ) |>
      dplyr::ungroup() |>
      dplyr::select(relation_type, metric_label, focal_var, other_var, estimate, n_obs, message)

    vif_rows <- purrr::map_dfr(exposure_vars, function(v) {
      others <- setdiff(exposure_vars, v)
      est <- NA_real_
      msg <- "joint_complete_case"
      if (nrow(cc) < 5L) {
        msg <- "insufficient_complete_case"
      } else {
        fit <- tryCatch(
          stats::lm(stats::as.formula(sprintf("%s ~ %s", v, paste(others, collapse = " + "))), data = cc),
          error = function(e) e
        )
        if (inherits(fit, "error")) {
          msg <- paste("vif_lm_error:", fit$message)
        } else {
          r2 <- summary(fit)$r.squared
          est <- if (is.finite(r2) && r2 < 1) 1 / (1 - r2) else Inf
        }
      }

      tibble::tibble(
        relation_type = "vif",
        metric_label = v,
        focal_var = v,
        other_var = NA_character_,
        estimate = est,
        n_obs = as.integer(nrow(cc)),
        message = msg
      )
    })

    dplyr::bind_rows(corr_pairs, vif_rows)
  }

  exposure_relations <- build_exposure_relations(panel)


  #============================================================================
  # 1. Helpers
  #============================================================================

  build_control_rows <- function(spec_id,
                                 model_name,
                                 outcome,
                                 outcome_family,
                                 exposure_family,
                                 exposure_var,
                                 requested_controls,
                                 usable_controls,
                                 balanced_controls,
                                 selected_controls,
                                 status,
                                 message) {
    if (length(requested_controls) == 0L) {
      return(tibble::tibble(
        spec_id = character(),
        model_name = character(),
        outcome = character(),
        outcome_family = character(),
        exposure_family = character(),
        exposure_var = character(),
        control_var = character(),
        control_order = integer(),
        requested = logical(),
        usable = logical(),
        balanced_candidate = logical(),
        selected = logical(),
        status = character(),
        message = character()
      ))
    }

    tibble::tibble(
      spec_id = spec_id,
      model_name = model_name,
      outcome = outcome,
      outcome_family = outcome_family,
      exposure_family = exposure_family,
      exposure_var = exposure_var,
      control_var = requested_controls,
      control_order = seq_along(requested_controls),
      requested = TRUE,
      usable = requested_controls %in% usable_controls,
      balanced_candidate = requested_controls %in% balanced_controls,
      selected = requested_controls %in% selected_controls,
      status = status,
      message = as.character(message)
    )
  }

  build_diagnostic_row <- function(spec_id,
                                   model_name,
                                   outcome,
                                   outcome_family,
                                   exposure_family,
                                   exposure_var,
                                   status,
                                   message,
                                   n_units = NA_integer_,
                                   n_periods = NA_integer_,
                                   n_obs = NA_integer_) {
    tibble::tibble(
      spec_id = spec_id,
      model_name = model_name,
      outcome = outcome,
      outcome_family = outcome_family,
      exposure_family = exposure_family,
      exposure_var = exposure_var,
      status = status,
      message = as.character(message),
      n_units = as.integer(n_units),
      n_periods = as.integer(n_periods),
      n_obs = as.integer(n_obs),
      sales_share_sum_mean_abs_dev = sales_share_qc$mean_abs_dev,
      sales_share_sum_max_abs_dev = sales_share_qc$max_abs_dev,
      store_share_sum_mean_abs_dev = store_share_qc$mean_abs_dev,
      store_share_sum_max_abs_dev = store_share_qc$max_abs_dev,
      finite_n__age60_resident_share = exposure_finite_n[["age60_resident_share"]],
      finite_n__age60_floating_share = exposure_finite_n[["age60_floating_share"]]
    )
  }

  make_fail <- function(spec_id,
                        model_name,
                        outcome,
                        outcome_family,
                        exposure_family,
                        exposure_var,
                        message,
                        requested_controls = character(),
                        usable_controls = character(),
                        balanced_controls = character(),
                        selected_controls = character()) {
    list(
      coefs = tibble::tibble(
        spec_id = spec_id,
        model_name = model_name,
        outcome = outcome,
        outcome_family = outcome_family,
        exposure_family = exposure_family,
        exposure_var = exposure_var,
        term = NA_character_,
        estimate = NA_real_,
        std.error = NA_real_,
        statistic = NA_real_,
        p.value = NA_real_,
        status = "failed",
        n_units = NA_integer_,
        n_periods = NA_integer_,
        n_obs = NA_integer_,
        message = as.character(message)
      ),
      impacts = tibble::tibble(
        spec_id = spec_id,
        model_name = model_name,
        outcome = outcome,
        outcome_family = outcome_family,
        exposure_family = exposure_family,
        exposure_var = exposure_var,
        focal_var = exposure_var,
        direct = NA_real_,
        indirect = NA_real_,
        total = NA_real_,
        status = "failed",
        message = as.character(message)
      ),
      controls = build_control_rows(
        spec_id = spec_id,
        model_name = model_name,
        outcome = outcome,
        outcome_family = outcome_family,
        exposure_family = exposure_family,
        exposure_var = exposure_var,
        requested_controls = requested_controls,
        usable_controls = usable_controls,
        balanced_controls = balanced_controls,
        selected_controls = selected_controls,
        status = "failed",
        message = message
      ),
      diagnostics = build_diagnostic_row(
        spec_id = spec_id,
        model_name = model_name,
        outcome = outcome,
        outcome_family = outcome_family,
        exposure_family = exposure_family,
        exposure_var = exposure_var,
        status = "failed",
        message = message
      )
    )
  }

  pick_effect_value <- function(df, key) {
    nms <- names(df)
    hit <- nms[tolower(nms) == tolower(key)]
    if (length(hit) == 0L) return(NA_real_)
    suppressWarnings(as.numeric(df[[hit[[1]]]]))
  }

  assess_balanced_dims <- function(d, w_ids) {
    if (nrow(d) == 0) {
      return(list(ok = FALSE, keep_ids = character(), n_units = 0L, n_periods = 0L))
    }

    balanced <- d |>
      dplyr::count(adm_cd, name = "n_t")
    full_t <- max(balanced$n_t)
    adm_balanced <- balanced |>
      dplyr::filter(n_t == full_t) |>
      dplyr::pull(adm_cd)

  keep_ids <- intersect(w_ids, adm_balanced)
  list(
    ok = (length(keep_ids) >= 20L && full_t >= cfg$spdm_min_periods),
    keep_ids = keep_ids,
    n_units = as.integer(length(keep_ids)),
    n_periods = as.integer(full_t)
    )
  }

  choose_controls_for_spec <- function(panel, outcome, exposure, control_pool, w_ids) {
    if (length(control_pool) == 0L) return(character())

    selected <- character()
    for (ctrl in control_pool) {
      trial <- c(selected, ctrl)
      vars <- unique(c("adm_cd", "year", outcome, exposure, trial))
      d_try <- panel |>
        dplyr::select(dplyr::all_of(vars)) |>
        tidyr::drop_na()
      dims <- assess_balanced_dims(d_try, w_ids)
      if (isTRUE(dims$ok)) {
        selected <- trial
      }
    }
    selected
  }

  make_control_ladder <- function(controls) {
    k <- length(controls)
    lapply(seq(k, 0L), function(i) {
      if (i == 0L) character() else controls[seq_len(i)]
    })
  }

  run_one_spec <- function(spec_id,
                           model_name,
                           outcome,
                           outcome_family,
                           exposure_family,
                           exposure_var,
                           panel,
                           lw,
                           w_ids,
                           requested_controls,
                           usable_controls) {
    spec_controls <- choose_controls_for_spec(panel, outcome, exposure_var, usable_controls, w_ids)
    control_ladder <- make_control_ladder(spec_controls)
    mod <- NULL
    mod_err_message <- "no estimable control set"
    used_controls <- character()
    lw_sub <- NULL
    n_units <- NA_integer_
    n_periods <- NA_integer_
    n_obs <- NA_integer_

    for (ctrl_try in control_ladder) {
      vars <- unique(c("adm_cd", "year", "quarter", "yq", "quarter_index", outcome, exposure_var, ctrl_try))
      d_try <- panel |>
        dplyr::select(dplyr::all_of(vars)) |>
        tidyr::drop_na()
      if (nrow(d_try) < 400L) {
        mod_err_message <- "insufficient sample after drop_na"
        next
      }

      dims <- assess_balanced_dims(d_try, w_ids)
      keep_ids <- dims$keep_ids
      if (!isTRUE(dims$ok)) {
        mod_err_message <- "insufficient balanced units for SPDM"
        next
      }

      lw_try <- tryCatch(
        spdep::subset.listw(lw, subset = w_ids %in% keep_ids, zero.policy = TRUE),
        error = function(e) e
      )
      if (inherits(lw_try, "error") || is.null(lw_try)) {
        mod_err_message <- if (inherits(lw_try, "error")) paste("failed to subset listw:", lw_try$message) else "failed to subset listw"
        next
      }

      yq_levels <- d_try |>
        dplyr::distinct(yq, quarter_index) |>
        dplyr::arrange(quarter_index, yq) |>
        dplyr::pull(yq) |>
        as.character()

      pdat_try <- d_try |>
        dplyr::filter(adm_cd %in% keep_ids) |>
        dplyr::mutate(
          adm_cd = factor(adm_cd, levels = keep_ids),
          yq = as.character(yq),
          time_id = as.integer(factor(yq, levels = yq_levels))
        ) |>
        dplyr::arrange(adm_cd, time_id)

      n_units_try <- dplyr::n_distinct(pdat_try$adm_cd)
      n_periods_try <- dplyr::n_distinct(pdat_try$time_id)
      n_obs_try <- nrow(pdat_try)
      if (n_units_try < 20L || n_periods_try < cfg$spdm_min_periods) {
        mod_err_message <- "insufficient aligned panel dimensions"
        next
      }

      rhs <- c(exposure_var, ctrl_try)
      wx_obj <- tryCatch(build_spdm_wx_terms(pdat_try, rhs, lw_try), error = function(e) e)
      if (inherits(wx_obj, "error")) {
        mod_err_message <- paste("W X construction error:", wx_obj$message)
        next
      }
      pdat_model <- wx_obj$data
      fm <- stats::as.formula(sprintf("%s ~ %s", outcome, paste(c(rhs, wx_obj$wx_terms), collapse = " + ")))
      mod_try <- tryCatch(
        splm::spml(
          formula = fm,
          data = pdat_model,
          listw = lw_try,
          model = "within",
          lag = TRUE,
          spatial.error = "none",
          effect = "twoways",
          index = c("adm_cd", "time_id")
        ),
        error = function(e) e
      )
      if (!inherits(mod_try, "error")) {
        attr(mod_try, "spdm_model_family") <- "sdm"
        attr(mod_try, "spdm_rhs_vars") <- rhs
        attr(mod_try, "spdm_wx_terms") <- wx_obj$wx_terms
        attr(mod_try, "spdm_wx_map") <- wx_obj$wx_map
        attr(mod_try, "spdm_true_sdm") <- TRUE
        attr(mod_try, "spdm_implementation") <- "manual_wx_true_sdm"
        mod <- mod_try
        used_controls <- ctrl_try
        lw_sub <- lw_try
        n_units <- as.integer(n_units_try)
        n_periods <- as.integer(n_periods_try)
        n_obs <- as.integer(n_obs_try)
        break
      }
      mod_err_message <- paste("spml error:", mod_try$message)
    }

    if (is.null(mod)) {
      return(make_fail(
        spec_id = spec_id,
        model_name = model_name,
        outcome = outcome,
        outcome_family = outcome_family,
        exposure_family = exposure_family,
        exposure_var = exposure_var,
        message = mod_err_message,
        requested_controls = requested_controls,
        usable_controls = usable_controls,
        balanced_controls = spec_controls,
        selected_controls = used_controls
      ))
    }

    sm <- summary(mod)
    coef_tbl <- tryCatch(as.data.frame(sm$CoefTable), error = function(e) NULL)
    if (is.null(coef_tbl) || nrow(coef_tbl) == 0L) {
      return(make_fail(
        spec_id = spec_id,
        model_name = model_name,
        outcome = outcome,
        outcome_family = outcome_family,
        exposure_family = exposure_family,
        exposure_var = exposure_var,
        message = "CoefTable unavailable from SPDM",
        requested_controls = requested_controls,
        usable_controls = usable_controls,
        balanced_controls = spec_controls,
        selected_controls = used_controls
      ))
    }

    coef_tbl$term <- rownames(coef_tbl)
    rownames(coef_tbl) <- NULL
    names(coef_tbl) <- c("estimate", "std.error", "statistic", "p.value", "term")
    coef_tbl <- coef_tbl[, c("term", "estimate", "std.error", "statistic", "p.value")]

    lambda_idx <- which(tolower(coef_tbl$term) == "lambda")
    if (length(lambda_idx) == 0L && !is.null(sm$spat.coef) && length(sm$spat.coef) > 0) {
      coef_tbl <- dplyr::bind_rows(
        tibble::tibble(term = "lambda", estimate = as.numeric(sm$spat.coef[[1]]), std.error = NA_real_, statistic = NA_real_, p.value = NA_real_),
        coef_tbl
      )
    }

    controls_message <- sprintf(
      "controls_used=%s",
      if (length(used_controls) == 0L) "none" else paste(used_controls, collapse = ";")
    )

    coefs <- coef_tbl |>
      dplyr::mutate(
        spec_id = spec_id,
        model_name = model_name,
        outcome = outcome,
        outcome_family = outcome_family,
        exposure_family = exposure_family,
        exposure_var = exposure_var,
        status = "success",
        n_units = as.integer(n_units),
        n_periods = as.integer(n_periods),
        n_obs = as.integer(n_obs),
        message = controls_message,
        .before = 1
      ) |>
      dplyr::select(spec_id, model_name, outcome, outcome_family, exposure_family, exposure_var, term, estimate, std.error, statistic, p.value, status, n_units, n_periods, n_obs, message)

    controls_out <- build_control_rows(
      spec_id = spec_id,
      model_name = model_name,
      outcome = outcome,
      outcome_family = outcome_family,
      exposure_family = exposure_family,
      exposure_var = exposure_var,
      requested_controls = requested_controls,
      usable_controls = usable_controls,
      balanced_controls = spec_controls,
      selected_controls = used_controls,
      status = "success",
      message = controls_message
    )

    if (is.null(attr(mod, "have_factor_preds"))) attr(mod, "have_factor_preds") <- FALSE

    impact_res <- compute_spdm_impacts_row(
      spec_id = spec_id,
      outcome = outcome,
      exposure = exposure_var,
      focal_var = exposure_var,
      mod = mod,
      lw_sub = lw_sub,
      n_periods = n_periods,
      n_units = n_units,
      n_obs = n_obs,
      sample_min_yq = as.character(min(pdat_try$yq, na.rm = TRUE)),
      sample_max_yq = as.character(max(pdat_try$yq, na.rm = TRUE)),
      model_family = "sdm",
      w_type = "queen",
      sim_R = as.integer(value_or(cfg$spdm_impact_sim_R, 1000L)),
      sim_method = as.character(value_or(cfg$spdm_impact_sim_type, "mult")),
      empirical = isTRUE(value_or(cfg$spdm_impact_empirical, FALSE)),
      seed = cfg$esda_seed,
      message = controls_message
    )
    impacts <- impact_res$row |>
      dplyr::mutate(
        model_name = model_name,
        outcome_family = outcome_family,
        exposure_family = exposure_family,
        exposure_var = exposure_var,
        .after = spec_id
      )

    diagnostics <- build_diagnostic_row(
      spec_id = spec_id,
      model_name = model_name,
      outcome = outcome,
      outcome_family = outcome_family,
      exposure_family = exposure_family,
      exposure_var = exposure_var,
      status = "success",
      message = controls_message,
      n_units = n_units,
      n_periods = n_periods,
      n_obs = n_obs
    )

    list(coefs = coefs, impacts = impacts, controls = controls_out, diagnostics = diagnostics)
  }


  #============================================================================
  # 2. Run Models and Save Outputs
  #============================================================================

  empty_coef <- tibble::tibble(
    spec_id = character(), model_name = character(), outcome = character(), outcome_family = character(),
    exposure_family = character(), exposure_var = character(), term = character(),
    estimate = numeric(), std.error = numeric(), statistic = numeric(), p.value = numeric(),
    status = character(), n_units = integer(), n_periods = integer(), n_obs = integer(), message = character()
  )
  empty_imp <- spdm_empty_impacts_tbl() |>
    dplyr::mutate(
      model_name = character(),
      outcome_family = character(),
      exposure_family = character(),
      exposure_var = character(),
      .after = spec_id
    )
  empty_ctrl <- tibble::tibble(
    spec_id = character(), model_name = character(), outcome = character(), outcome_family = character(),
    exposure_family = character(), exposure_var = character(), control_var = character(), control_order = integer(),
    requested = logical(), usable = logical(), balanced_candidate = logical(), selected = logical(),
    status = character(), message = character()
  )
  empty_diag <- tibble::tibble(
    spec_id = character(), model_name = character(), outcome = character(), outcome_family = character(),
    exposure_family = character(), exposure_var = character(), status = character(), message = character(),
    n_units = integer(), n_periods = integer(), n_obs = integer(),
    sales_share_sum_mean_abs_dev = numeric(), sales_share_sum_max_abs_dev = numeric(),
    store_share_sum_mean_abs_dev = numeric(), store_share_sum_max_abs_dev = numeric(),
    finite_n__age60_resident_share = integer(),
    finite_n__age60_floating_share = integer()
  )

  if (length(outcomes) == 0L || nrow(exposure_defs) == 0L) {
    write_csv_safe(empty_coef, path_models)
    write_csv_safe(empty_imp, path_impacts)
    write_csv_safe(empty_ctrl, path_controls)
    write_csv_safe(empty_diag, path_diagnostics)
    write_csv_safe(exposure_relations, path_relations)
    append_log(cfg$logs$model_run, "- SPDM sector-share sidecar skipped: missing outcomes or exposures")
  } else {
    lw <- readRDS(cfg$paths$w_queen)
    w_ids <- attr(lw$neighbours, "region.id")

    if (is.null(w_ids)) {
      write_csv_safe(empty_coef, path_models)
      write_csv_safe(empty_imp, path_impacts)
      write_csv_safe(empty_ctrl, path_controls)
      write_csv_safe(empty_diag, path_diagnostics)
      write_csv_safe(exposure_relations, path_relations)
      append_log(cfg$logs$model_run, "- SPDM sector-share sidecar skipped: region.id missing in W")
    } else {
      w_ids <- as.character(w_ids)

      spec_grid <- tidyr::crossing(
        outcome = outcomes,
        exposure_family = exposure_defs$exposure_family
      ) |>
        dplyr::left_join(exposure_defs, by = "exposure_family") |>
        dplyr::mutate(
          outcome_family = dplyr::if_else(grepl("^sales_share_", outcome), "sales_share", "store_share"),
          model_name = sprintf("%s__%s", exposure_family, outcome)
        ) |>
        dplyr::arrange(outcome_family, outcome, exposure_order) |>
        dplyr::mutate(spec_id = sprintf("S%02d", dplyr::row_number()))

      res <- purrr::pmap(
        list(
          spec_grid$spec_id,
          spec_grid$model_name,
          spec_grid$outcome,
          spec_grid$outcome_family,
          spec_grid$exposure_family,
          spec_grid$exposure_var
        ),
        function(spec_id, model_name, outcome, outcome_family, exposure_family, exposure_var) {
          run_one_spec(
            spec_id = spec_id,
            model_name = model_name,
            outcome = outcome,
            outcome_family = outcome_family,
            exposure_family = exposure_family,
            exposure_var = exposure_var,
            panel = panel,
            lw = lw,
            w_ids = w_ids,
            requested_controls = control_candidates,
            usable_controls = usable_controls
          )
        }
      )

      out_coef <- dplyr::bind_rows(purrr::map(res, "coefs")) |>
        dplyr::arrange(outcome_family, outcome, exposure_family, term)
      out_imp <- dplyr::bind_rows(purrr::map(res, "impacts")) |>
        dplyr::arrange(outcome_family, outcome, exposure_family)
      out_ctrl <- dplyr::bind_rows(purrr::map(res, "controls")) |>
        dplyr::arrange(outcome_family, outcome, exposure_family, control_order)
      out_diag <- dplyr::bind_rows(purrr::map(res, "diagnostics")) |>
        dplyr::arrange(outcome_family, outcome, exposure_family)

      write_csv_safe(out_coef, path_models)
      write_csv_safe(out_imp, path_impacts)
      write_csv_safe(out_ctrl, path_controls)
      write_csv_safe(out_diag, path_diagnostics)
      write_csv_safe(exposure_relations, path_relations)

      n_success <- sum(out_imp$status == "success", na.rm = TRUE)
      n_fail <- sum(out_imp$status != "success", na.rm = TRUE)
      append_log(
        cfg$logs$model_run,
        sprintf("- SPDM sector-share specs attempted: %d (success=%d, failed=%d)", nrow(spec_grid), n_success, n_fail)
      )
    }
  }
}
