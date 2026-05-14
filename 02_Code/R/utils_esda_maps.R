#==============================================================================
# Script    : utils_esda_maps.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide reusable choropleth helpers for descriptive ESDA maps.
# Author    : Codex
# Created   : 2026-03-20
# Type      : utility
# Inputs    : sf boundary + numeric cross-section values
# Outputs   : saved png maps and break metadata returned invisibly
# DependsOn : ggplot2, dplyr, tibble
#==============================================================================

format_choropleth_number <- function(x, digits = 3L) {
  if (!is.finite(x)) return(NA_character_)
  trimws(formatC(x, digits = digits, format = "fg", flag = "#"))
}

normalize_choropleth_breaks <- function(breaks, values) {
  vals <- suppressWarnings(as.numeric(values))
  vals <- vals[is.finite(vals)]
  if (length(vals) == 0) return(numeric())

  out <- suppressWarnings(as.numeric(breaks))
  out <- sort(unique(out[is.finite(out)]))

  rng <- range(vals, na.rm = TRUE)
  if (length(out) == 0) out <- rng
  out[1] <- min(out[1], rng[1])
  out[length(out)] <- max(out[length(out)], rng[2])

  if (length(out) < 2 || !is.finite(diff(range(out))) || diff(range(out)) == 0) {
    eps <- if (isTRUE(all.equal(rng[2], 0))) 1e-6 else max(abs(rng[2]) * 1e-6, 1e-6)
    out <- c(rng[1], rng[2] + eps)
  }

  out
}

derive_choropleth_breaks <- function(x, method = c("quantile", "pretty"), n_classes = 5L, center_zero = FALSE) {
  method <- match.arg(method)
  vals <- suppressWarnings(as.numeric(x))
  vals <- vals[is.finite(vals)]
  if (length(vals) == 0) return(numeric())

  if (method == "quantile") {
    probs <- seq(0, 1, length.out = as.integer(n_classes) + 1L)
    raw_breaks <- stats::quantile(vals, probs = probs, na.rm = TRUE, type = 7, names = FALSE)
    return(normalize_choropleth_breaks(raw_breaks, vals))
  }

  if (center_zero) {
    max_abs <- max(abs(vals), na.rm = TRUE)
    raw_breaks <- pretty(c(-max_abs, max_abs), n = as.integer(n_classes))
    raw_breaks <- c(-max_abs, raw_breaks, max_abs)
  } else {
    rng <- range(vals, na.rm = TRUE)
    raw_breaks <- c(rng[1], pretty(rng, n = as.integer(n_classes)), rng[2])
  }

  normalize_choropleth_breaks(raw_breaks, vals)
}

build_choropleth_labels <- function(breaks, style = c("range", "quantile"), digits = 3L) {
  style <- match.arg(style)
  br <- suppressWarnings(as.numeric(breaks))
  br <- br[is.finite(br)]
  if (length(br) < 2) return(character())

  ranges <- purrr::map2_chr(
    head(br, -1),
    tail(br, -1),
    ~ sprintf("%s to %s", format_choropleth_number(.x, digits), format_choropleth_number(.y, digits))
  )

  if (style == "quantile") {
    return(sprintf("Q%d: %s", seq_along(ranges), ranges))
  }

  ranges
}

classify_choropleth_values <- function(x, breaks, style = c("range", "quantile"), digits = 3L, missing_label = "Missing") {
  style <- match.arg(style)
  vals <- suppressWarnings(as.numeric(x))
  br <- normalize_choropleth_breaks(breaks, vals)
  labels <- build_choropleth_labels(br, style = style, digits = digits)

  cut_vals <- cut(
    vals,
    breaks = br,
    include.lowest = TRUE,
    labels = labels,
    ordered_result = TRUE
  )

  out <- as.character(cut_vals)
  out[!is.finite(vals)] <- missing_label
  out[is.na(out)] <- missing_label

  tibble::tibble(
    value = vals,
    map_class = factor(out, levels = c(labels, missing_label), ordered = TRUE)
  )
}

save_distribution_map <- function(boundary,
                                  value_df,
                                  value_col,
                                  out_path,
                                  title,
                                  subtitle,
                                  breaks = NULL,
                                  method = c("quantile", "pretty"),
                                  n_classes = 5L,
                                  center_zero = FALSE,
                                  palette_type = c("sequential", "diverging"),
                                  digits = 3L,
                                  missing_label = "Missing") {
  method <- match.arg(method)
  palette_type <- match.arg(palette_type)

  value_tbl <- tibble::tibble(
    adm_cd = as.character(value_df$adm_cd),
    value = suppressWarnings(as.numeric(value_df[[value_col]]))
  )

  plot_df <- boundary |>
    dplyr::left_join(value_tbl, by = "adm_cd")

  breaks_use <- if (is.null(breaks)) {
    derive_choropleth_breaks(
      plot_df$value,
      method = method,
      n_classes = n_classes,
      center_zero = center_zero
    )
  } else {
    normalize_choropleth_breaks(breaks, plot_df$value)
  }

  label_style <- if (method == "quantile" && is.null(breaks)) "quantile" else "range"
  classified <- classify_choropleth_values(
    plot_df$value,
    breaks_use,
    style = label_style,
    digits = digits,
    missing_label = missing_label
  )
  plot_df$map_class <- classified$map_class

  observed_levels <- setdiff(levels(plot_df$map_class), missing_label)
  palette_vals <- if (length(observed_levels) > 0) {
    if (palette_type == "diverging") {
      grDevices::colorRampPalette(c("#2166ac", "#f7f7f7", "#b2182b"))(length(observed_levels))
    } else {
      grDevices::colorRampPalette(c("#fff7ec", "#fdae6b", "#7f0000"))(length(observed_levels))
    }
  } else {
    character()
  }

  fill_values <- c(stats::setNames(palette_vals, observed_levels), stats::setNames("#f5f5f5", missing_label))

  p <- ggplot2::ggplot(plot_df) +
    ggplot2::geom_sf(ggplot2::aes(fill = map_class), color = "white", linewidth = 0.05) +
    ggplot2::scale_fill_manual(values = fill_values, drop = FALSE) +
    ggplot2::labs(
      title = title,
      subtitle = subtitle,
      fill = NULL
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12),
      plot.subtitle = ggplot2::element_text(size = 10),
      legend.position = "bottom"
    )

  ggplot2::ggsave(out_path, p, width = 8, height = 7, dpi = 300)

  invisible(list(
    path = out_path,
    breaks = breaks_use,
    class_levels = observed_levels
  ))
}
