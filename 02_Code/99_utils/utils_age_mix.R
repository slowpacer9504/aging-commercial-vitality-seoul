#==============================================================================
# Script    : utils_age_mix.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Shared helpers for quarterly age-mix appendix sidecars.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-04-22
# Type      : utility
# Inputs    : registered_resident_population.parquet,
#             seoul_raw_integrated_wide.parquet, panel views, cfg
# Outputs   : In-memory quarterly age-mix tibbles merged into modeling panels
# DependsOn : utils_io.R, utils_model.R, utils_qc.R, arrow
#==============================================================================

#==============================================================================
# 1. Shared Age-Mix Registry
#==============================================================================

resolve_age_mix_family_registry <- function(domains = c("resident", "floating"),
                                            exposure_mode = c("share", "resident_log_population")) {
  exposure_mode <- match.arg(exposure_mode)
  age_labels <- c("age20", "age30", "age40", "age50", "age60plus")
  domains <- intersect(as.character(domains), c("resident", "floating"))
  if (identical(exposure_mode, "resident_log_population")) {
    domains <- intersect(domains, "resident")
  }
  if (length(domains) == 0L) {
    return(tibble::tibble())
  }

  registry <- tibble::tibble(
    model_family = c("resident_age_mix", "floating_age_mix"),
    domain = c("resident", "floating"),
    source_type = c("resident", "floating"),
    quarterly_step = c(FALSE, FALSE),
    asof_col = c(NA_character_, NA_character_),
    same_domain_total_control = c("ln_resident_pop", NA_character_),
    raw_cols = list(
      c(
        age20 = "연령대_20_상주인구_수",
        age30 = "연령대_30_상주인구_수",
        age40 = "연령대_40_상주인구_수",
        age50 = "연령대_50_상주인구_수",
        age60plus = "연령대_60_이상_상주인구_수"
      ),
      c(
        age20 = "연령대_20_유동인구_수",
        age30 = "연령대_30_유동인구_수",
        age40 = "연령대_40_유동인구_수",
        age50 = "연령대_50_유동인구_수",
        age60plus = "연령대_60_이상_유동인구_수"
      )
    )
  ) |>
    dplyr::filter(domain %in% domains)

  if (identical(exposure_mode, "resident_log_population")) {
    registry <- registry |>
      dplyr::mutate(
        share_cols = purrr::map(domain, ~ sprintf("%s_%s_share", c("young", "middle", "old"), .x)),
        exposure_vars = purrr::map(domain, ~ sprintf("ln_%s_%s_pop", c("young", "middle", "old"), .x)),
        omitted_reference_var = NA_character_,
        exposure_scale = "log_population",
        omitted_reference = "none",
        reference_population = "not_applicable",
        same_domain_total_control = "lag4_ln_resident_pop",
        requested_exposures = purrr::map_chr(exposure_vars, collapse_chr)
      )
  } else {
    registry <- registry |>
      dplyr::mutate(
        share_cols = purrr::map(domain, ~ sprintf("%s_%s_share", age_labels, .x)),
        exposure_vars = purrr::map(domain, ~ sprintf("%s_%s_share", age_labels[1:4], .x)),
        omitted_reference_var = sprintf("age60plus_%s_share", domain),
        exposure_scale = "share",
        omitted_reference = "age60plus",
        reference_population = "age20_to_60plus",
        requested_exposures = purrr::map_chr(exposure_vars, collapse_chr)
      )
  }

  registry
}


#==============================================================================
# 2. Quarterly Age-Share Construction
#==============================================================================

safe_num_age_mix <- function(x) {
  suppressWarnings(as.numeric(x))
}

safe_log1p_age_pop <- function(x) {
  x_num <- safe_num_age_mix(x)
  dplyr::if_else(is.finite(x_num) & x_num >= 0, log1p(x_num), NA_real_)
}

safe_ratio_age_mix <- function(num, den) {
  num <- safe_num_age_mix(num)
  den <- safe_num_age_mix(den)
  dplyr::if_else(is.finite(num) & is.finite(den) & den > 0, num / den, NA_real_)
}

read_age_mix_source <- function(source_value, raw_cols) {
  arrow::open_dataset(cfg$paths$seoul_raw_integrated_wide) |>
    dplyr::filter(source_type == source_value) |>
    dplyr::select(dplyr::all_of(c("adm_cd", "year", "quarter", raw_cols))) |>
    dplyr::collect() |>
    tibble::as_tibble() |>
    standardize_keys()
}

build_domain_age_shares <- function(source_value,
                                    domain,
                                    quarterly_step = FALSE,
                                    raw_cols,
                                    asof_col = NA_character_) {
  age_labels <- c("age20", "age30", "age40", "age50", "age60plus")

  if (identical(domain, "resident") || identical(source_value, "resident")) {
    resident_df <- arrow::read_parquet(cfg$paths$registered_resident_population) |>
      tibble::as_tibble() |>
      standardize_keys()

    required_cols <- c(
      "adm_cd", "year", "quarter", "yq", "quarter_index",
      "age20_resident_pop", "age30_resident_pop", "age40_resident_pop",
      "age50_resident_pop", "age60_resident_pop",
      "age20_resident_share", "age30_resident_share", "age40_resident_share",
      "age50_resident_share", "age60plus_resident_share"
    )
    assert_required_cols(resident_df, required_cols, name = "registered_resident_age_mix_source")

    return(
      resident_df |>
        dplyr::transmute(
          adm_cd,
          year,
          quarter,
          yq,
          quarter_index,
          age_mix_total = age20_resident_pop + age30_resident_pop +
            age40_resident_pop + age50_resident_pop + age60_resident_pop,
          age20_resident_pop,
          age30_resident_pop,
          age40_resident_pop,
          age50_resident_pop,
          age60_resident_pop,
          young_resident_pop = age20_resident_pop + age30_resident_pop,
          middle_resident_pop = age40_resident_pop + age50_resident_pop,
          old_resident_pop = age60_resident_pop,
          ln_young_resident_pop = safe_log1p_age_pop(young_resident_pop),
          ln_middle_resident_pop = safe_log1p_age_pop(middle_resident_pop),
          ln_old_resident_pop = safe_log1p_age_pop(old_resident_pop),
          age20_resident_share,
          age30_resident_share,
          age40_resident_share,
          age50_resident_share,
          age60plus_resident_share,
          young_resident_share = safe_ratio_age_mix(young_resident_pop, age_mix_total),
          middle_resident_share = safe_ratio_age_mix(middle_resident_pop, age_mix_total),
          old_resident_share = safe_ratio_age_mix(old_resident_pop, age_mix_total)
        ) |>
        dplyr::arrange(adm_cd, quarter_index)
    )
  }

  source_df <- read_age_mix_source(source_value, unname(raw_cols))
  assert_required_cols(
    source_df,
    c("adm_cd", "year", "quarter", unname(raw_cols)),
    name = sprintf("%s_age_mix_source", domain)
  )

  quarter_counts <- source_df |>
    dplyr::transmute(
      adm_cd,
      year,
      quarter,
      yq = make_yq(year, quarter),
      age20 = safe_num_age_mix(.data[[raw_cols[["age20"]]]]),
      age30 = safe_num_age_mix(.data[[raw_cols[["age30"]]]]),
      age40 = safe_num_age_mix(.data[[raw_cols[["age40"]]]]),
      age50 = safe_num_age_mix(.data[[raw_cols[["age50"]]]]),
      age60plus = safe_num_age_mix(.data[[raw_cols[["age60plus"]]]])
    ) |>
    dplyr::group_by(adm_cd, year, quarter, yq) |>
    dplyr::summarise(
      dplyr::across(
        dplyr::all_of(age_labels),
        ~ if (all(!is.finite(.x))) NA_real_ else mean(.x, na.rm = TRUE)
      ),
      .groups = "drop"
    )

  quarter_counts <- quarter_counts |>
    dplyr::left_join(
      cfg$quarter_sequence |>
        dplyr::select(year, quarter, yq, quarter_index),
      by = c("year", "quarter", "yq")
    )

  age_matrix <- as.matrix(dplyr::select(quarter_counts, dplyr::all_of(age_labels)))
  quarter_counts$age_mix_total <- rowSums(age_matrix, na.rm = TRUE)
  quarter_counts$age_mix_total[rowSums(is.finite(age_matrix)) == 0L] <- NA_real_

  share_cols <- sprintf("%s_%s_share", age_labels, domain)
  for (ii in seq_along(age_labels)) {
    age_col <- age_labels[[ii]]
    share_col <- share_cols[[ii]]
    quarter_counts[[share_col]] <- dplyr::if_else(
      is.finite(quarter_counts$age_mix_total) & quarter_counts$age_mix_total > 0,
      quarter_counts[[age_col]] / quarter_counts$age_mix_total,
      NA_real_
    )
  }

  quarter_counts |>
    dplyr::select(adm_cd, year, quarter, yq, quarter_index, age_mix_total, dplyr::all_of(share_cols)) |>
    dplyr::arrange(adm_cd, quarter_index)
}

add_current_age_shares <- function(base_panel, domain_df, domain) {
  join_keys <- c("adm_cd", "year", "quarter", "yq", "quarter_index")
  domain_cols <- setdiff(names(domain_df), join_keys)

  base_panel |>
    dplyr::select(-dplyr::any_of(domain_cols)) |>
    dplyr::left_join(domain_df, by = c("adm_cd", "year", "quarter", "yq", "quarter_index")) |>
    dplyr::relocate(dplyr::any_of(domain_cols), .after = "quarter_index")
}
