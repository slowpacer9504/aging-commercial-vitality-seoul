#!/usr/bin/env Rscript

#==============================================================================
# Script    : 04_build_test_inventory.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Count every exposure-side hypothesis test the project publishes and
#             report how many survive a multiplicity adjustment, so the size of
#             the search is a number in the record rather than an impression.
# Author    : Junghyun Pyo (Assisted by Claude)
# Created   : 2026-09-04
# Type      : qc
# Inputs    : 03_Output/01_Tables/*_models.csv, *_impacts.csv, *_path_effects.csv
# Outputs   : model_test_inventory.csv, model_test_inventory_adjusted.csv
# DependsOn : 00_setup/config.R, 00_setup/packages.R, 99_utils/utils_io.R
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# The main text rests on ten coefficients. The published tables carry several
# hundred, spread across appendix families that are searches by construction:
# age-mix, sector-share, vitality components, COVID interactions, spatial model
# families, W variants. Nothing in the project counted them, and no table carried
# an adjusted p-value, so a reader had no way to see how large the search was
# behind any one appendix result.
#
# This step estimates nothing and re-fits nothing. It reads what is already
# published, counts the exposure-side tests, and applies Benjamini-Hochberg both
# within each family and across the whole published surface. The adjusted values
# are reported as context for reading the appendix, not as a replacement for the
# unadjusted p-values the tables carry: the families are not independent, they
# share a panel, an exposure and a control contract, so BH is a conservative
# summary of search size rather than an exact error rate.
options(scipen = 999)

source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
load_project_packages()
source(here::here("02_Code", "99_utils", "utils_io.R"))

ensure_dirs(cfg$required_dirs)
append_log(cfg$logs$data_qc, sprintf("\n## [%s] 02_build_test_inventory", timestamp()))

ALPHA <- 0.05

# Terms that are controls or spatial nuisance rather than a reported exposure
# effect. Counting them would inflate the search size with quantities nobody
# claims anything about.
NUISANCE <- paste(
  "^lag4_ln_", "^lag2_ln_", "^lag4_transit", "^lag4_ln_workplace",
  "^w_lag4_ln_", "^w_lag2_ln_", "^w_lag4_transit", "^w_lag4_ln_workplace",
  "^lambda$", "^rho$", "Intercept",
  sep = "|"
)


#==============================================================================
# 1. Inventory
#==============================================================================

files <- list.files(
  cfg$dir_tables,
  pattern = "^(twfe|spdm)_.*(models|impacts|path_effects)\\.csv$",
  full.names = TRUE
)

# Which column carries the test the table is read for. Impacts tables are read
# for the direct effect; model tables for the coefficient.
p_col_for <- function(nms) {
  for (cand in c("p.value", "direct_p", "p_value", "indirect_p")) {
    if (cand %in% nms) return(cand)
  }
  NA_character_
}

# The main-text surface, so the inventory can separate what the paper claims from
# what the appendix reports.
MAIN_TABLES <- c("twfe_main_models.csv", "spdm_impacts.csv")

inventory <- purrr::map_dfr(files, function(path) {
  tbl <- tryCatch(readr::read_csv(path, show_col_types = FALSE, progress = FALSE),
                  error = function(e) NULL)
  if (is.null(tbl) || nrow(tbl) == 0L) return(NULL)
  pc <- p_col_for(names(tbl))
  if (is.na(pc)) return(NULL)

  keep <- rep(TRUE, nrow(tbl))
  if ("term" %in% names(tbl)) keep <- !grepl(NUISANCE, tbl$term)
  pv <- suppressWarnings(as.numeric(tbl[[pc]][keep]))
  pv <- pv[is.finite(pv)]
  if (length(pv) == 0L) return(NULL)

  tibble::tibble(
    table = basename(path),
    surface = if (basename(path) %in% MAIN_TABLES) "main_text" else "appendix",
    p_column = pc,
    n_tests = length(pv),
    n_sig_unadjusted = sum(pv < ALPHA),
    min_p = min(pv),
    median_p = stats::median(pv),
    p_values = list(pv)
  )
})

if (nrow(inventory) == 0L) {
  stop("[ERROR] no published model tables carry a usable p-value column", call. = FALSE)
}


#==============================================================================
# 2. Adjustment, Within Family and Across the Whole Surface
#==============================================================================

all_p <- unlist(inventory$p_values, use.names = FALSE)
all_p_bh <- stats::p.adjust(all_p, method = "BH")
offsets <- cumsum(c(0L, utils::head(inventory$n_tests, -1L)))

inventory_out <- inventory |>
  dplyr::mutate(
    n_sig_bh_within_table = purrr::map_int(
      .data$p_values, ~ sum(stats::p.adjust(.x, method = "BH") < ALPHA)
    ),
    n_sig_bh_across_all = purrr::map2_int(
      offsets, .data$n_tests, ~ sum(all_p_bh[(.x + 1L):(.x + .y)] < ALPHA)
    ),
    expected_false_positives = .data$n_tests * ALPHA
  ) |>
  dplyr::select(-"p_values") |>
  dplyr::arrange(dplyr::desc(.data$n_tests))

write_csv_safe(inventory_out, cfg$paths$model_test_inventory)

totals <- tibble::tibble(
  scope = c("all_published", "main_text", "appendix"),
  n_tables = c(
    nrow(inventory_out),
    sum(inventory_out$surface == "main_text"),
    sum(inventory_out$surface == "appendix")
  ),
  n_tests = c(
    sum(inventory_out$n_tests),
    sum(inventory_out$n_tests[inventory_out$surface == "main_text"]),
    sum(inventory_out$n_tests[inventory_out$surface == "appendix"])
  ),
  n_sig_unadjusted = c(
    sum(inventory_out$n_sig_unadjusted),
    sum(inventory_out$n_sig_unadjusted[inventory_out$surface == "main_text"]),
    sum(inventory_out$n_sig_unadjusted[inventory_out$surface == "appendix"])
  ),
  n_sig_bh_across_all = c(
    sum(inventory_out$n_sig_bh_across_all),
    sum(inventory_out$n_sig_bh_across_all[inventory_out$surface == "main_text"]),
    sum(inventory_out$n_sig_bh_across_all[inventory_out$surface == "appendix"])
  )
) |>
  dplyr::mutate(
    expected_false_positives = .data$n_tests * ALPHA,
    alpha = ALPHA,
    note = paste(
      "BH across the whole published surface; families share a panel, an exposure",
      "and a control contract, so this is a conservative summary of search size",
      "rather than an exact error rate"
    )
  )

write_csv_safe(totals, cfg$paths$model_test_inventory_adjusted)


#==============================================================================
# 3. Log
#==============================================================================

tot <- totals[totals$scope == "all_published", ]
append_log(cfg$logs$data_qc, sprintf(
  "- Test inventory: %d exposure-side tests across %d published tables; %d significant unadjusted, %d under BH across the whole surface; %.0f expected false positives at alpha = %.2f",
  tot$n_tests, tot$n_tables, tot$n_sig_unadjusted, tot$n_sig_bh_across_all,
  tot$expected_false_positives, ALPHA))

message(sprintf(
  "[DONE] test inventory: %d tests, %d significant unadjusted -> %d under BH across all published tables",
  tot$n_tests, tot$n_sig_unadjusted, tot$n_sig_bh_across_all))
