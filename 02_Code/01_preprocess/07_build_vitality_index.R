#==============================================================================
# Script    : 07_build_vitality_index.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Read the pre-vitality shared panel, build vitality indices, and
#             publish panel_main.parquet as the final shared analysis panel
#             for downstream scripts.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-02-28
# Type      : panel_building
# Inputs    : panel_main_pre_vitality.parquet
# Outputs   : vitality_components.parquet, panel_main.parquet,
#             vitality_component_qc.csv
# DependsOn : 02_Code/01_preprocess/06_build_analysis_panel.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# This step should not re-engineer the shared panel. It reads
# `panel_main_pre_vitality`, adds only approved vitality-index columns, and
# publishes the final canonical `panel_main`.
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "R", "utils_io.R"))
source(here::here("02_Code", "R", "utils_qc.R"))
load_project_packages()

if (!file.exists(cfg$paths$panel_main_pre_vitality)) stop("[ERROR] panel_main_pre_vitality.parquet missing", call. = FALSE)
panel_main_pre <- arrow::read_parquet(cfg$paths$panel_main_pre_vitality) |> tibble::as_tibble()

assert_has_cols <- function(df, cols, label) {
  miss <- setdiff(cols, names(df))
  if (length(miss) > 0) {
    stop(sprintf("[ERROR] %s missing columns: %s", label, paste(miss, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

# Helpers focus on publication-contract validation rather than panel
# engineering. The final panel may add vitality columns, but common
# pre-vitality columns must remain byte-for-byte unchanged.
validate_panel_extension <- function(pre_df, final_df, added_cols) {
  # publication contract:
  # `panel_main` must preserve all pre-vitality columns and add only approved
  # vitality columns.
  added_cols <- unique(added_cols)
  missing_pre <- setdiff(names(pre_df), names(final_df))
  unexpected <- setdiff(names(final_df), c(names(pre_df), added_cols))
  missing_added <- setdiff(added_cols, names(final_df))

  if (length(missing_pre) > 0 || length(unexpected) > 0 || length(missing_added) > 0) {
    stop(
      sprintf(
        "[ERROR] panel_main publication contract failed: missing_pre=%s; missing_added=%s; unexpected=%s",
        if (length(missing_pre) == 0) "none" else paste(missing_pre, collapse = ", "),
        if (length(missing_added) == 0) "none" else paste(missing_added, collapse = ", "),
        if (length(unexpected) == 0) "none" else paste(unexpected, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (nrow(pre_df) != nrow(final_df)) {
    stop(
      sprintf(
        "[ERROR] panel_main publication row mismatch: pre=%d final=%d",
        nrow(pre_df), nrow(final_df)
      ),
      call. = FALSE
    )
  }

  common_cols <- names(pre_df)
  if (!identical(pre_df[, common_cols, drop = FALSE], final_df[, common_cols, drop = FALSE])) {
    stop("[ERROR] panel_main_pre_vitality columns changed while publishing panel_main", call. = FALSE)
  }

  invisible(TRUE)
}

validate_panel_main_views <- function(df, specs) {
  # Separate method-specific panel files were removed, so the single
  # `panel_main` must satisfy every downstream view contract.
  miss <- purrr::imap(specs, function(cols, view_name) {
    missing <- setdiff(cols, names(df))
    if (length(missing) == 0) return(NULL)
    sprintf("%s: %s", view_name, paste(missing, collapse = ", "))
  })
  miss <- miss[!vapply(miss, is.null, logical(1))]
  if (length(miss) > 0) {
    stop(
      sprintf(
        "[ERROR] panel_main method-view contract failed: %s",
        paste(unlist(miss), collapse = "; ")
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

build_entropy_weights <- function(mat) {
  x <- as.matrix(mat)
  if (!is.numeric(x) || nrow(x) < 2L || ncol(x) < 1L) {
    stop("[ERROR] entropy weighting requires a numeric matrix with at least 2 rows", call. = FALSE)
  }

  x_norm <- apply(x, 2, function(col) {
    rng <- range(col, na.rm = TRUE)
    span <- rng[[2]] - rng[[1]]
    if (!is.finite(span) || span <= 0) {
      stop("[ERROR] entropy weighting encountered a non-varying component", call. = FALSE)
    }
    (col - rng[[1]]) / span
  })
  x_norm <- as.matrix(x_norm)
  colnames(x_norm) <- colnames(x)

  col_sums <- colSums(x_norm, na.rm = TRUE)
  if (any(!is.finite(col_sums) | col_sums <= 0)) {
    stop("[ERROR] entropy weighting encountered a component with zero normalized mass", call. = FALSE)
  }

  prob <- sweep(x_norm, 2, col_sums, "/")
  scale_n <- log(nrow(x_norm))
  if (!is.finite(scale_n) || scale_n <= 0) {
    stop("[ERROR] entropy weighting requires at least 2 complete cases", call. = FALSE)
  }

  entropy <- apply(prob, 2, function(col) {
    col_pos <- col[col > 0]
    -sum(col_pos * log(col_pos)) / scale_n
  })
  divergence <- 1 - entropy
  div_sum <- sum(divergence)
  if (any(!is.finite(divergence)) || !is.finite(div_sum) || div_sum <= 0) {
    stop("[ERROR] entropy weighting produced invalid divergence values", call. = FALSE)
  }

  list(
    normalized = x_norm,
    entropy = entropy,
    divergence = divergence,
    weight = divergence / div_sum
  )
}

count_invalid_transformed <- function(df, source_spec, component_name) {
  source_vars <- trimws(unlist(strsplit(source_spec, ";", fixed = TRUE)))
  source_vars <- source_vars[source_vars != ""]
  source_vars <- intersect(source_vars, names(df))
  if (length(source_vars) == 0L) return(0L)

  source_observed <- Reduce("&", lapply(source_vars, function(v) is.finite(df[[v]])))
  sum(source_observed & !is.finite(df[[component_name]]))
}


#==============================================================================
# 1. Define and Validate Vitality Components
#==============================================================================

# Vitality indices are supplementary composites, not replacements for the
# individual outcome dimensions. Define components and QC gates before any
# standardization so failures remain source-specific.
required_vars <- c(
  "ln_sales_count",
  "ln_total_sales",
  "sales_time_entropy",
  "sales_quarter_stability",
  "floating_pop",
  "external_inflow_pop",
  "floating_time_entropy",
  "floating_quarter_stability",
  "diversity_index",
  "survival_3y",
  "operating_months_rel_seoul"
)
time_cols <- c("adm_cd", "year", "quarter", "yq", "quarter_index")
assert_has_cols(panel_main_pre, c(time_cols, required_vars), "panel_main_pre")

component_spec <- tibble::tribble(
  ~component,                    ~source_variable,             ~dimension,   ~transformation,      ~direction_rule,
  "ln_sales_count",              "ln_sales_count",             "economic",   "none",               "as_is",
  "ln_total_sales",              "ln_total_sales",             "economic",   "none",               "as_is",
  "sales_time_entropy",          "sales_time_entropy",         "temporal",   "none",               "as_is",
  "sales_quarter_stability",     "sales_quarter_stability",    "temporal",   "none",               "as_is",
  "ln_floating_pop",             "floating_pop",               "social",     "log1p(max(x,0))",    "as_is",
  "ln_external_inflow_pop",      "external_inflow_pop",        "social",     "log1p(max(x,0))",    "as_is",
  "floating_time_entropy",       "floating_time_entropy",      "temporal",   "none",               "as_is",
  "floating_quarter_stability",  "floating_quarter_stability", "temporal",   "none",               "as_is",
  "diversity_index",             "diversity_index",            "stability",  "none",               "as_is",
  "survival_3y",                 "survival_3y",                "stability",  "none",               "as_is",
  "operating_months_rel_seoul",  "operating_months_rel_seoul", "stability",  "none",               "as_is"
)

# `comp` is an index-building work table. Keeping it separate from
# `panel_main_pre` makes transformation rules auditable and keeps the final
# publication contract simple.
comp <- panel_main_pre |>
  dplyr::select(dplyr::all_of(time_cols), dplyr::all_of(required_vars)) |>
  dplyr::mutate(
    ln_floating_pop = log1p(pmax(floating_pop, 0)),
    ln_external_inflow_pop = log1p(pmax(external_inflow_pop, 0))
  )

analysis_yq <- get_analysis_yq_sequence()
analysis_reference <- as.character(comp$yq) %in% analysis_yq
if (sum(analysis_reference, na.rm = TRUE) < 100L) {
  stop(
    sprintf(
      "[ERROR] vitality analysis reference window has too few rows: %s rows=%d",
      value_or(cfg$analysis_period_label, paste(analysis_yq, collapse = ",")),
      sum(analysis_reference, na.rm = TRUE)
    ),
    call. = FALSE
  )
}

vars <- component_spec$component
standard_subindex_spec <- list(
  vitality_sub_social = c("ln_floating_pop", "ln_external_inflow_pop"),
  vitality_sub_temporal = c("sales_time_entropy", "floating_time_entropy", "sales_quarter_stability", "floating_quarter_stability")
)

economic_axis_spec <- list(
  economic_transaction_scale = c("ln_sales_count", "ln_total_sales")
)

economic_subindex_spec <- list(
  vitality_sub_economic = c("economic_transaction_scale")
)

stability_axis_spec <- list(
  stability_diversity_axis = c("diversity_index"),
  stability_continuity_axis = c("operating_months_rel_seoul", "survival_3y")
)

subindex_source_spec <- c(
  economic_subindex_spec,
  standard_subindex_spec,
  list(vitality_sub_stability = names(stability_axis_spec))
)
subindex_dimensions <- c("economic", "social", "temporal", "stability")

vitality_qc <- component_spec |>
  dplyr::rowwise() |>
  dplyr::mutate(
    finite_n = sum(is.finite(comp[[component]]) & analysis_reference),
    unique_n = dplyr::n_distinct(comp[[component]][is.finite(comp[[component]]) & analysis_reference]),
    sd_value = suppressWarnings(stats::sd(comp[[component]][is.finite(comp[[component]]) & analysis_reference], na.rm = TRUE)),
    invalid_transformed_n = count_invalid_transformed(comp, source_variable, component),
    selected = TRUE
  ) |>
  dplyr::ungroup()

# Component QC checks finite coverage, variation, standard deviation, and
# transform validity together. Any failure blocks composite construction because
# the resulting index would be unstable even if numerically computable.
bad_vars <- vitality_qc |>
  dplyr::filter(
    finite_n < 100L |
      unique_n <= 1L |
      !is.finite(sd_value) |
      sd_value <= 1e-8 |
      invalid_transformed_n > 0L
  )
if (nrow(bad_vars) > 0) {
  write_csv_safe(vitality_qc, cfg$logs$vitality_component_qc)
  stop(
    sprintf(
      "[ERROR] vitality component QC failed: %s",
      paste(
        sprintf(
          "%s(finite=%d,unique=%d,sd=%s,invalid_transformed=%d)",
          bad_vars$component,
          bad_vars$finite_n,
          bad_vars$unique_n,
          bad_vars$sd_value,
          bad_vars$invalid_transformed_n
        ),
        collapse = "; "
      )
    ),
    call. = FALSE
  )
}


#==============================================================================
# 2. Standardize and Build Indices
#==============================================================================

# The base index is an equal-weight z-score mean, while entropy and PCA are
# robustness composites. All are computed on complete cases to keep missingness
# rules explicit.
zvars <- paste0(vars, "_z")
for (i in seq_along(vars)) {
  v <- vars[[i]]
  z <- zvars[[i]]
  v_finite <- is.finite(comp[[v]]) & analysis_reference
  v_mean <- mean(comp[[v]][v_finite], na.rm = TRUE)
  v_sd <- stats::sd(comp[[v]][v_finite], na.rm = TRUE)
  comp[[z]] <- NA_real_
  # Z-scores use the pooled active analysis-period distribution. This scales
  # components without removing within-neighborhood temporal variation.
  comp[[z]][v_finite] <- (comp[[v]][v_finite] - v_mean) / v_sd
}

z_qc <- tibble::tibble(
  component = vars,
  z_variable = zvars,
  z_finite_n = vapply(zvars, function(v) sum(is.finite(comp[[v]])), integer(1))
)
bad_z <- z_qc |>
  dplyr::filter(z_finite_n < 100L)
if (nrow(bad_z) > 0) {
  write_csv_safe(dplyr::left_join(vitality_qc, z_qc, by = "component"), cfg$logs$vitality_component_qc)
  stop(
    sprintf(
      "[ERROR] vitality z-score QC failed: %s",
      paste(sprintf("%s(z_finite=%d)", bad_z$component, bad_z$z_finite_n), collapse = "; ")
    ),
    call. = FALSE
  )
}

for (axis_name in names(economic_axis_spec)) {
  axis_vars <- economic_axis_spec[[axis_name]]
  axis_zvars <- paste0(axis_vars, "_z")
  axis_complete <- stats::complete.cases(comp[, axis_zvars, drop = FALSE])
  comp[[axis_name]] <- NA_real_
  comp[[axis_name]][axis_complete] <- rowMeans(comp[axis_complete, axis_zvars, drop = FALSE])
}

economic_axis_qc <- tibble::tibble(
  component = names(economic_axis_spec),
  source_variable = vapply(economic_axis_spec, function(x) paste(x, collapse = ";"), character(1)),
  dimension = "economic_axis",
  transformation = "mean_of_component_zscores",
  direction_rule = "as_is",
  finite_n = vapply(names(economic_axis_spec), function(v) sum(is.finite(comp[[v]])), integer(1)),
  unique_n = vapply(names(economic_axis_spec), function(v) dplyr::n_distinct(comp[[v]][is.finite(comp[[v]])]), integer(1)),
  sd_value = vapply(names(economic_axis_spec), function(v) suppressWarnings(stats::sd(comp[[v]][is.finite(comp[[v]])], na.rm = TRUE)), numeric(1)),
  invalid_transformed_n = 0L,
  selected = TRUE
)

bad_economic_axis <- economic_axis_qc |>
  dplyr::filter(
    finite_n < 100L |
      unique_n <= 1L |
      !is.finite(sd_value) |
      sd_value <= 1e-8
  )
if (nrow(bad_economic_axis) > 0) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc) |>
      dplyr::left_join(z_qc, by = "component"),
    cfg$logs$vitality_component_qc
  )
  stop(
    sprintf(
      "[ERROR] vitality economic axis QC failed: %s",
      paste(
        sprintf(
          "%s(finite=%d,unique=%d,sd=%s)",
          bad_economic_axis$component,
          bad_economic_axis$finite_n,
          bad_economic_axis$unique_n,
          bad_economic_axis$sd_value
        ),
        collapse = "; "
      )
    ),
    call. = FALSE
  )
}

for (axis_name in names(stability_axis_spec)) {
  axis_vars <- stability_axis_spec[[axis_name]]
  axis_zvars <- paste0(axis_vars, "_z")
  axis_complete <- stats::complete.cases(comp[, axis_zvars, drop = FALSE])
  comp[[axis_name]] <- NA_real_
  comp[[axis_name]][axis_complete] <- rowMeans(comp[axis_complete, axis_zvars, drop = FALSE])
}

stability_axis_qc <- tibble::tibble(
  component = names(stability_axis_spec),
  source_variable = vapply(stability_axis_spec, function(x) paste(x, collapse = ";"), character(1)),
  dimension = "stability_axis",
  transformation = c("pooled_z_component", "mean_of_component_zscores"),
  direction_rule = "as_is",
  finite_n = vapply(names(stability_axis_spec), function(v) sum(is.finite(comp[[v]])), integer(1)),
  unique_n = vapply(names(stability_axis_spec), function(v) dplyr::n_distinct(comp[[v]][is.finite(comp[[v]])]), integer(1)),
  sd_value = vapply(names(stability_axis_spec), function(v) suppressWarnings(stats::sd(comp[[v]][is.finite(comp[[v]])], na.rm = TRUE)), numeric(1)),
  invalid_transformed_n = 0L,
  selected = TRUE
)

bad_axis <- stability_axis_qc |>
  dplyr::filter(
    finite_n < 100L |
      unique_n <= 1L |
      !is.finite(sd_value) |
      sd_value <= 1e-8
  )
if (nrow(bad_axis) > 0) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc) |>
      dplyr::left_join(z_qc, by = "component"),
    cfg$logs$vitality_component_qc
  )
  stop(
    sprintf(
      "[ERROR] vitality stability axis QC failed: %s",
      paste(
        sprintf("%s(finite=%d,unique=%d,sd=%s)", bad_axis$component, bad_axis$finite_n, bad_axis$unique_n, bad_axis$sd_value),
        collapse = "; "
      )
    ),
    call. = FALSE
  )
}

stability_axis_vars <- names(stability_axis_spec)
stability_axis_zvars <- paste0(stability_axis_vars, "_z")
for (i in seq_along(stability_axis_vars)) {
  v <- stability_axis_vars[[i]]
  z <- stability_axis_zvars[[i]]
  v_finite <- is.finite(comp[[v]]) & analysis_reference
  v_mean <- mean(comp[[v]][v_finite], na.rm = TRUE)
  v_sd <- stats::sd(comp[[v]][v_finite], na.rm = TRUE)
  comp[[z]] <- NA_real_
  comp[[z]][v_finite] <- (comp[[v]][v_finite] - v_mean) / v_sd
}

stability_axis_z_qc <- tibble::tibble(
  component = stability_axis_vars,
  z_variable = stability_axis_zvars,
  z_finite_n = vapply(stability_axis_zvars, function(v) sum(is.finite(comp[[v]])), integer(1))
)
bad_axis_z <- stability_axis_z_qc |>
  dplyr::filter(z_finite_n < 100L)
if (nrow(bad_axis_z) > 0) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc), by = "component"),
    cfg$logs$vitality_component_qc
  )
  stop(
    sprintf(
      "[ERROR] vitality stability axis z-score QC failed: %s",
      paste(sprintf("%s(z_finite=%d)", bad_axis_z$component, bad_axis_z$z_finite_n), collapse = "; ")
    ),
    call. = FALSE
  )
}

for (sub_name in names(economic_subindex_spec)) {
  sub_vars <- economic_subindex_spec[[sub_name]]
  sub_complete <- stats::complete.cases(comp[, sub_vars, drop = FALSE])
  comp[[sub_name]] <- NA_real_
  comp[[sub_name]][sub_complete] <- rowMeans(comp[sub_complete, sub_vars, drop = FALSE])
}

for (sub_name in names(standard_subindex_spec)) {
  sub_vars <- standard_subindex_spec[[sub_name]]
  sub_zvars <- paste0(sub_vars, "_z")
  sub_complete <- stats::complete.cases(comp[, sub_zvars, drop = FALSE])
  comp[[sub_name]] <- NA_real_
  comp[[sub_name]][sub_complete] <- rowMeans(comp[sub_complete, sub_zvars, drop = FALSE])
}

stability_sub_complete <- stats::complete.cases(comp[, stability_axis_zvars, drop = FALSE])
comp$vitality_sub_stability <- NA_real_
comp$vitality_sub_stability[stability_sub_complete] <- rowMeans(comp[stability_sub_complete, stability_axis_zvars, drop = FALSE])

subindex_qc <- tibble::tibble(
  component = names(subindex_source_spec),
  source_variable = vapply(subindex_source_spec, function(x) paste(x, collapse = ";"), character(1)),
  dimension = subindex_dimensions,
  transformation = c(
    "mean_of_component_zscores",
    rep("mean_of_component_zscores", length(standard_subindex_spec)),
    "mean_of_axis_zscores"
  ),
  direction_rule = "as_is",
  finite_n = vapply(names(subindex_source_spec), function(v) sum(is.finite(comp[[v]])), integer(1)),
  unique_n = vapply(names(subindex_source_spec), function(v) dplyr::n_distinct(comp[[v]][is.finite(comp[[v]])]), integer(1)),
  sd_value = vapply(names(subindex_source_spec), function(v) suppressWarnings(stats::sd(comp[[v]][is.finite(comp[[v]])], na.rm = TRUE)), numeric(1)),
  invalid_transformed_n = 0L,
  selected = TRUE
)

bad_subindex <- subindex_qc |>
  dplyr::filter(
    finite_n < 100L |
      unique_n <= 1L |
      !is.finite(sd_value) |
      sd_value <= 1e-8
  )
if (nrow(bad_subindex) > 0) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc), by = "component"),
    cfg$logs$vitality_component_qc
  )
  stop(
    sprintf(
      "[ERROR] vitality subindex QC failed: %s",
      paste(
        sprintf("%s(finite=%d,unique=%d,sd=%s)", bad_subindex$component, bad_subindex$finite_n, bad_subindex$unique_n, bad_subindex$sd_value),
        collapse = "; "
      )
    ),
    call. = FALSE
  )
}

sub_names <- names(subindex_source_spec)
sub_zvars <- paste0(sub_names, "_z")
for (i in seq_along(sub_names)) {
  v <- sub_names[[i]]
  z <- sub_zvars[[i]]
  v_finite <- is.finite(comp[[v]]) & analysis_reference
  v_mean <- mean(comp[[v]][v_finite], na.rm = TRUE)
  v_sd <- stats::sd(comp[[v]][v_finite], na.rm = TRUE)
  comp[[z]] <- NA_real_
  comp[[z]][v_finite] <- (comp[[v]][v_finite] - v_mean) / v_sd
}

sub_z_qc <- tibble::tibble(
  component = sub_names,
  z_variable = sub_zvars,
  z_finite_n = vapply(sub_zvars, function(v) sum(is.finite(comp[[v]])), integer(1))
)

bad_sub_z <- sub_z_qc |>
  dplyr::filter(z_finite_n < 100L)
if (nrow(bad_sub_z) > 0) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc, sub_z_qc), by = "component"),
    cfg$logs$vitality_component_qc
  )
  stop(
    sprintf(
      "[ERROR] vitality subindex z-score QC failed: %s",
      paste(sprintf("%s(z_finite=%d)", bad_sub_z$component, bad_sub_z$z_finite_n), collapse = "; ")
    ),
    call. = FALSE
  )
}

zmat <- comp[, sub_zvars]
complete_idx <- stats::complete.cases(zmat)
comp$vitality_index_base <- NA_real_
comp$vitality_index_base[complete_idx] <- rowMeans(zmat[complete_idx, , drop = FALSE])
comp$vitality_index_entropy <- NA_real_
comp$vitality_index_pca <- NA_real_
complete_n <- sum(complete_idx)
if (complete_n < 100L) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc, sub_z_qc), by = "component") |>
      dplyr::mutate(complete_case_n = complete_n),
    cfg$logs$vitality_component_qc
  )
  stop(sprintf("[ERROR] vitality index QC failed: complete cases=%d", complete_n), call. = FALSE)
}

entropy_fit <- tryCatch(
  build_entropy_weights(comp[complete_idx, sub_names, drop = FALSE]),
  error = function(e) e
)
if (inherits(entropy_fit, "error")) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc, sub_z_qc), by = "component") |>
      dplyr::mutate(
        complete_case_n = complete_n,
        entropy_message = entropy_fit$message
      ),
    cfg$logs$vitality_component_qc
  )
  stop(sprintf("[ERROR] vitality entropy QC failed: %s", entropy_fit$message), call. = FALSE)
}

entropy_weight_tbl <- tibble::tibble(
  component = sub_names,
  entropy_value = as.numeric(entropy_fit$entropy),
  entropy_divergence = as.numeric(entropy_fit$divergence),
  entropy_weight = as.numeric(entropy_fit$weight)
)
entropy_raw <- as.vector(entropy_fit$normalized %*% entropy_fit$weight)
entropy_sd <- stats::sd(entropy_raw, na.rm = TRUE)
if (!is.finite(entropy_sd) || entropy_sd <= 1e-8) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc, sub_z_qc), by = "component") |>
      dplyr::left_join(entropy_weight_tbl, by = "component") |>
      dplyr::mutate(
        complete_case_n = complete_n,
        entropy_raw_sd = entropy_sd
      ),
    cfg$logs$vitality_component_qc
  )
  stop(sprintf("[ERROR] vitality entropy output invalid: sd=%s", entropy_sd), call. = FALSE)
}
entropy_score <- as.numeric(scale(entropy_raw))
comp$vitality_index_entropy[complete_idx] <- entropy_score

base_complete <- comp$vitality_index_base[complete_idx]
entropy_corr <- suppressWarnings(stats::cor(entropy_score, base_complete))
if (!is.finite(entropy_corr) || entropy_corr <= 0) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc, sub_z_qc), by = "component") |>
      dplyr::left_join(entropy_weight_tbl, by = "component") |>
      dplyr::mutate(
        complete_case_n = complete_n,
        entropy_finite_n = sum(is.finite(comp$vitality_index_entropy)),
        entropy_alignment_corr = entropy_corr
      ),
    cfg$logs$vitality_component_qc
  )
  stop(sprintf("[ERROR] vitality entropy sign check failed: corr=%s", entropy_corr), call. = FALSE)
}

pca <- stats::prcomp(zmat[complete_idx, , drop = FALSE], scale. = FALSE)
pc1 <- pca$x[, 1]
pc1_corr <- suppressWarnings(stats::cor(pc1, base_complete))
if (!is.finite(pc1_corr)) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc, sub_z_qc), by = "component") |>
      dplyr::left_join(entropy_weight_tbl, by = "component") |>
      dplyr::mutate(
        complete_case_n = complete_n,
        entropy_finite_n = sum(is.finite(comp$vitality_index_entropy)),
        entropy_alignment_corr = entropy_corr,
        pca_finite_n = sum(is.finite(pc1)),
        pca_alignment_corr = pc1_corr
      ),
    cfg$logs$vitality_component_qc
  )
  stop("[ERROR] vitality PCA sign alignment failed: non-finite correlation", call. = FALSE)
}
# PCA signs are arbitrary, so align PC1 to have positive correlation with the
# base index before saving it as an interpretable robustness composite.
if (pc1_corr < 0) pc1 <- -pc1
comp$vitality_index_pca[complete_idx] <- pc1
if (sum(is.finite(comp$vitality_index_pca)) < 100L) {
  write_csv_safe(
    dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
      dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc, sub_z_qc), by = "component") |>
      dplyr::left_join(entropy_weight_tbl, by = "component") |>
      dplyr::mutate(
        complete_case_n = complete_n,
        entropy_finite_n = sum(is.finite(comp$vitality_index_entropy)),
        entropy_alignment_corr = entropy_corr,
        pca_finite_n = sum(is.finite(comp$vitality_index_pca)),
        pca_alignment_corr = pc1_corr
      ),
    cfg$logs$vitality_component_qc
  )
  stop(
    sprintf(
      "[ERROR] vitality PCA output invalid: finite scores=%d",
      sum(is.finite(comp$vitality_index_pca))
    ),
    call. = FALSE
  )
}


#==============================================================================
# 3. Build Final Shared Panel
#==============================================================================

# Final `panel_main` must be the pre-vitality panel plus vitality-only columns.
# Any mutation of common columns would break downstream model inputs.
vitality_cols <- c(
  "vitality_sub_economic", "vitality_sub_social", "vitality_sub_temporal",
  "vitality_sub_stability", "vitality_index_base", "vitality_index_entropy", "vitality_index_pca"
)

panel_main_view_specs_quarterly <- cfg$panel_main_view_specs

panel_main <- panel_main_pre |>
  dplyr::select(-dplyr::any_of(vitality_cols)) |>
  dplyr::left_join(
    comp |> dplyr::select(dplyr::all_of(time_cols), dplyr::all_of(vitality_cols)),
    by = time_cols
  )

validate_panel_extension(panel_main_pre, panel_main, vitality_cols)
validate_panel_main_views(panel_main, panel_main_view_specs_quarterly)


#==============================================================================
# 4. Persist Outputs
#==============================================================================

# `vitality_components` is a QC/provenance companion. Downstream models read
# `panel_main`, while this file explains how the index scores were built.
write_csv_safe(
  dplyr::bind_rows(vitality_qc, economic_axis_qc, stability_axis_qc, subindex_qc) |>
    dplyr::left_join(dplyr::bind_rows(z_qc, stability_axis_z_qc, sub_z_qc), by = "component") |>
    dplyr::left_join(entropy_weight_tbl, by = "component") |>
    dplyr::mutate(
      analysis_period = value_or(cfg$analysis_period_label, NA_character_),
      analysis_reference_row_n = sum(analysis_reference, na.rm = TRUE),
      complete_case_n = complete_n,
      base_finite_n = sum(is.finite(comp$vitality_index_base)),
      entropy_finite_n = sum(is.finite(comp$vitality_index_entropy)),
      entropy_alignment_corr = entropy_corr,
      pca_finite_n = sum(is.finite(comp$vitality_index_pca)),
      pca_alignment_corr = pc1_corr,
      panel_pre_row_n = nrow(panel_main_pre),
      panel_main_row_n = nrow(panel_main),
      pre_only_cols = "none",
      main_only_cols = paste(vitality_cols, collapse = ", "),
      pre_panel_match = TRUE
    ),
  cfg$logs$vitality_component_qc
)

write_parquet_safe(comp, cfg$paths$vitality_components)
write_parquet_safe(panel_main, cfg$paths$panel_main)
unlink(cfg$obsolete_panel_paths[file.exists(cfg$obsolete_panel_paths)])
write_csv_safe(summarize_missing(panel_main), cfg$logs$missing_data)

append_log(cfg$logs$data_qc, sprintf("\n## [%s] 07_build_vitality_index", timestamp()))
append_log(cfg$logs$data_qc, "- Vitality indices created: base, entropy, pca")
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Vitality component QC: %s (complete_n=%d, base_finite_n=%d, entropy_finite_n=%d, pca_finite_n=%d)",
    basename(cfg$logs$vitality_component_qc),
    complete_n,
    sum(is.finite(comp$vitality_index_base)),
    sum(is.finite(comp$vitality_index_entropy)),
    sum(is.finite(comp$vitality_index_pca))
  )
)
append_log(
  cfg$logs$data_qc,
  sprintf(
    "- Final panel published: panel_main rows=%d, cols=%d; obsolete panel files removed=%d",
    nrow(panel_main),
    ncol(panel_main),
    sum(!file.exists(cfg$obsolete_panel_paths))
  )
)
