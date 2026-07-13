#==============================================================================
# Script    : 03_open_outputs_for_rstudio_review.R
# Project   : Aging and Neighborhood Commercial Vitality in Seoul
# Purpose   : Provide RStudio-friendly helpers to browse, load, and preview
#             generated outputs under 03_Processed_Data and 03_Output.
# Author    : Junghyun Pyo (Assisted by Codex)
# Created   : 2026-03-11
# Status    : MANUAL_QC / interactive review outside canonical workflow
# Type      : qc / interactive review helper
# Inputs    : generated outputs under 01_Data/03_Processed_Data and 03_Output
# Outputs   : in-memory inventory + helper functions for interactive review
# DependsOn : manual interactive use in RStudio
#==============================================================================

#==============================================================================
# 0. Setup
#==============================================================================

# This is an RStudio review helper, not an analysis-producing script. It indexes
# generated outputs by topic and loads objects only when the user selects them.
source(here::here("02_Code", "00_setup", "config.R"))
source(here::here("02_Code", "00_setup", "packages.R"))
source(here::here("02_Code", "99_utils", "utils_io.R"))
load_project_packages()

output_roots <- c(
  processed = cfg$dir_processed,
  output = cfg$dir_output
)

tabular_exts <- c("parquet", "csv")
text_exts <- c("md", "txt", "log")
browser_exts <- c("html", "htm", "png", "jpg", "jpeg", "pdf")
r_object_exts <- c("rds")

`%||%` <- function(x, y) {
  # Treat NULL, empty values, and all-NA metadata as the same missing case.
  if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x
}

safe_view <- function(x, title = NULL) {
  # Attempt `View()` only in interactive sessions; terminal and batch runs skip
  # the viewer so sourcing this helper remains harmless.
  if (!interactive()) return(invisible(FALSE))

  view_fun <- if (exists("View", mode = "function", inherits = TRUE)) {
    get("View", mode = "function", inherits = TRUE)
  } else {
    NULL
  }

  if (is.null(view_fun)) {
    message("Skipping View(): no available viewer function in this session.")
    return(invisible(FALSE))
  }

  can_try_x11 <- isTRUE(capabilities("X11"))
  is_rstudio <- identical(Sys.getenv("RSTUDIO"), "1")

  if (!is_rstudio && !can_try_x11) {
    message("Skipping View(): no RStudio viewer or X11 backend available in this session.")
    return(invisible(FALSE))
  }

  ok <- tryCatch(
    {
      if (is.null(title)) {
        view_fun(x)
      } else {
        view_fun(x, title = title)
      }
      TRUE
    },
    error = function(e) {
      message(sprintf("View() skipped: %s", e$message))
      FALSE
    }
  )

  invisible(ok)
}


#==============================================================================
# 1. Inventory Helpers
#==============================================================================

# The inventory step does not read file contents. It records paths, extensions,
# topics, and default object names so selected files can be loaded later.
classify_output_type <- function(ext) {
  # Extension classes drive later topic labels and reader selection.
  ext <- tolower(ext)
  dplyr::case_when(
    ext %in% tabular_exts ~ "tabular",
    ext %in% r_object_exts ~ "r_object",
    ext %in% text_exts ~ "text",
    ext %in% browser_exts ~ "browser",
    TRUE ~ "other"
  )
}

classify_output_topic <- function(root, rel_project_path, output_type) {
  rel_project_path <- as.character(rel_project_path %||% "")

  dplyr::case_when(
    stringr::str_detect(rel_project_path, "^01_Data/03_Processed_Data/01_Intermediate/") ~ "intermediate",
    stringr::str_detect(rel_project_path, "^01_Data/03_Processed_Data/02_Analysis_Ready/") ~ "analysis_ready",
    stringr::str_detect(rel_project_path, "^01_Data/03_Processed_Data/03_Panel/") ~ "panel",
    stringr::str_detect(rel_project_path, "^03_Output/04_Logs/") ~ "qc",
    stringr::str_detect(rel_project_path, "^03_Output/01_Tables/") ~ "tables",
    stringr::str_detect(rel_project_path, "^03_Output/02_Figures/") ~ "figures",
    stringr::str_detect(rel_project_path, "^03_Output/03_Maps/") ~ "maps",
    output_type == "browser" ~ "browser_assets",
    root == "output" ~ "other_output",
    TRUE ~ "other"
  )
}

safe_object_name <- function(path) {
  # Build a syntactic default R object name from each file basename.
  nm <- tools::file_path_sans_ext(basename(path))
  nm <- gsub("[^A-Za-z0-9]+", "_", nm)
  nm <- gsub("^_+|_+$", "", nm)
  nm <- make.names(nm)
  nm <- gsub("\\.", "_", nm)
  if (!grepl("^[A-Za-z]", nm)) nm <- paste0("obj_", nm)
  nm
}

build_output_inventory <- function() {
  # Index all reviewable outputs under processed data and output roots for the
  # current session.
  rows <- purrr::imap_dfr(output_roots, function(root_path, root_name) {
    paths <- list.files(root_path, recursive = TRUE, full.names = TRUE, all.files = FALSE)
    paths <- paths[file.exists(paths)]
    paths <- paths[!dir.exists(paths)]
    paths <- paths[!grepl("[.]DS_Store$", paths)]

    if (length(paths) == 0) {
      return(tibble::tibble())
    }

    info <- file.info(paths)
    rel_root <- fs::path_rel(paths, start = root_path)
    rel_project <- fs::path_rel(paths, start = cfg$project_root)
    ext <- tolower(tools::file_ext(paths))

    tibble::tibble(
      output_id = seq_along(paths),
      root = root_name,
      rel_root_path = rel_root,
      rel_project_path = rel_project,
      abs_path = normalizePath(paths, winslash = "/", mustWork = TRUE),
      file_name = basename(paths),
      ext = ext,
      output_type = classify_output_type(ext),
      output_topic = classify_output_topic(root_name, rel_project, classify_output_type(ext)),
      size_bytes = as.numeric(info$size),
      size_mb = round(as.numeric(info$size) / (1024 ^ 2), 3),
      mtime = as.character(info$mtime),
      default_object_name = vapply(paths, safe_object_name, character(1))
    )
  })

  if (nrow(rows) == 0) {
    return(tibble::tibble(
      output_id = integer(0),
      root = character(0),
      rel_root_path = character(0),
      rel_project_path = character(0),
      abs_path = character(0),
      file_name = character(0),
      ext = character(0),
      output_type = character(0),
      output_topic = character(0),
      size_bytes = numeric(0),
      size_mb = numeric(0),
      mtime = character(0),
      default_object_name = character(0)
    ))
  }

  rows |>
    dplyr::arrange(root, rel_root_path) |>
    dplyr::mutate(
      output_id = dplyr::row_number(),
      default_object_name = make.unique(default_object_name, sep = "_")
    )
}

output_inventory <- build_output_inventory()
tabular_output_inventory <- output_inventory |>
  dplyr::filter(output_type %in% c("tabular", "r_object", "text"))

core_output_inventory <- output_inventory |>
  dplyr::filter(file_name %in% c(
    "seoul_raw_integrated_wide.parquet",
    "seoul_raw_review.parquet",
    "seoul_quarter_base.parquet",
    "aux_covariates.parquet",
    "land_price_lpi_bjd_adm_crosswalk.parquet",
    "land_price_lpi_factor_adm_quarter.parquet",
    "golmok_survival_rate.parquet",
    "walk_betweenness_local800_len_v1.parquet",
    "medical_source_preagg.parquet",
    "mall_source_preagg.parquet",
    "senior_source_preagg.parquet",
    "bus_stop_source_preagg.parquet",
    "subway_station_source_preagg.parquet",
    "panel_merged_base.parquet",
    "panel_main_pre_vitality.parquet",
    "panel_main.parquet",
    "vitality_components.parquet",
    "processed_parquet_qc_checks.csv",
    "method_dataset_contract_check.csv",
    "missing_data_log.csv",
    "presentation_manifest.csv"
  ))

topic_output_inventory <- output_inventory |>
  dplyr::arrange(output_topic, root, rel_root_path)


#==============================================================================
# 2. Loading and Preview Helpers
#==============================================================================

# Resolve, load, and preview helpers share the same flow: find one inventory row,
# read it with the extension-specific reader, then optionally preview it.
resolve_output <- function(target, inventory = output_inventory) {
  # Accept output_id, file name, relative path, or absolute path; exact matching
  # is tried before substring fallback.
  if (missing(target) || length(target) != 1L) {
    stop("[ERROR] target must be a single output_id, file name, or relative path.", call. = FALSE)
  }

  if (is.numeric(target)) {
    hit <- inventory |>
      dplyr::filter(output_id == as.integer(target))
  } else {
    target_chr <- as.character(target)
    hit <- inventory |>
      dplyr::filter(
        rel_project_path == target_chr |
          rel_root_path == target_chr |
          file_name == target_chr |
          abs_path == target_chr
      )

    if (nrow(hit) == 0L) {
      hit <- inventory |>
        dplyr::filter(
          stringr::str_detect(rel_project_path, stringr::fixed(target_chr, ignore_case = TRUE)) |
            stringr::str_detect(file_name, stringr::fixed(target_chr, ignore_case = TRUE))
        )
    }
  }

  if (nrow(hit) == 0L) {
    stop(sprintf("[ERROR] no output matched target: %s", target), call. = FALSE)
  }

  if (nrow(hit) > 1L) {
    msg <- hit |>
      dplyr::transmute(choice = sprintf("[%d] %s", output_id, rel_project_path)) |>
      dplyr::pull(choice) |>
      paste(collapse = "\n")
    stop(sprintf("[ERROR] multiple outputs matched:\n%s", msg), call. = FALSE)
  }

  hit
}

read_text_output <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  tibble::tibble(line_no = seq_along(lines), text = lines)
}

read_output_object <- function(path) {
  # Load only parquet, csv, rds, and text objects directly; browser assets are
  # opened through `browse_output()`.
  ext <- tolower(tools::file_ext(path))

  if (ext == "parquet") {
    return(arrow::read_parquet(path) |> tibble::as_tibble())
  }
  if (ext == "csv") {
    return(readr::read_csv(path, show_col_types = FALSE, progress = FALSE))
  }
  if (ext == "rds") {
    return(readRDS(path))
  }
  if (ext %in% text_exts) {
    return(read_text_output(path))
  }

  stop(sprintf("[ERROR] unsupported load extension for %s", path), call. = FALSE)
}

summarize_loaded_object <- function(obj) {
  if (inherits(obj, c("tbl_df", "tbl", "data.frame"))) {
    return(tibble::tibble(
      metric = c("class", "rows", "cols"),
      value = c(paste(class(obj), collapse = "|"), nrow(obj), ncol(obj))
    ))
  }

  if (inherits(obj, "listw")) {
    neigh_n <- length(obj$neighbours)
    neigh_card <- spdep::card(obj$neighbours)
    return(tibble::tibble(
      metric = c("class", "nodes", "isolates", "avg_neighbors"),
      value = c(
        paste(class(obj), collapse = "|"),
        neigh_n,
        sum(neigh_card == 0L, na.rm = TRUE),
        round(mean(neigh_card), 3)
      )
    ))
  }

  if (inherits(obj, "nb")) {
    neigh_card <- spdep::card(obj)
    return(tibble::tibble(
      metric = c("class", "nodes", "isolates", "avg_neighbors"),
      value = c(
        paste(class(obj), collapse = "|"),
        length(obj),
        sum(neigh_card == 0L, na.rm = TRUE),
        round(mean(neigh_card), 3)
      )
    ))
  }

  if (is.matrix(obj)) {
    return(tibble::tibble(
      metric = c("class", "rows", "cols"),
      value = c(paste(class(obj), collapse = "|"), nrow(obj), ncol(obj))
    ))
  }

  if (is.atomic(obj) && !is.null(length(obj))) {
    return(tibble::tibble(
      metric = c("class", "length"),
      value = c(paste(class(obj), collapse = "|"), length(obj))
    ))
  }

  if (is.list(obj)) {
    return(tibble::tibble(
      metric = c("class", "length"),
      value = c(paste(class(obj), collapse = "|"), length(obj))
    ))
  }

  tibble::tibble(
    metric = "class",
    value = paste(class(obj), collapse = "|")
  )
}

preview_loaded_object <- function(obj, title = NULL, n = 20L, view = interactive()) {
  if (inherits(obj, c("tbl_df", "tbl", "data.frame"))) {
    print(utils::head(obj, n = n))
    if (isTRUE(view)) safe_view(obj, title = title)
    return(invisible(obj))
  }

  summary_tbl <- summarize_loaded_object(obj)
  print(summary_tbl)
  if (isTRUE(view)) safe_view(summary_tbl, title = paste0(title %||% "output", "_summary"))
  invisible(obj)
}

#==============================================================================
# 3. Public Interactive Helpers
#==============================================================================

# Public helpers are designed for direct use from the RStudio Environment and
# console, standardizing the project review workflow behind simple calls.
list_outputs <- function(pattern = NULL, types = NULL, roots = NULL) {
  out <- output_inventory
  if (!is.null(pattern) && nzchar(pattern)) {
    out <- out |>
      dplyr::filter(
        stringr::str_detect(rel_project_path, stringr::fixed(pattern, ignore_case = TRUE)) |
          stringr::str_detect(file_name, stringr::fixed(pattern, ignore_case = TRUE))
      )
  }
  if (!is.null(types)) {
    out <- out |>
      dplyr::filter(output_type %in% types)
  }
  if (!is.null(roots)) {
    out <- out |>
      dplyr::filter(root %in% roots)
  }
  out
}

list_outputs_by_topic <- function(topic = NULL, pattern = NULL, types = NULL, roots = NULL) {
  out <- list_outputs(pattern = pattern, types = types, roots = roots)
  if (!is.null(topic)) {
    out <- out |>
      dplyr::filter(output_topic %in% topic)
  }
  out |>
    dplyr::arrange(output_topic, root, rel_root_path)
}

load_output <- function(target, assign = TRUE, view = interactive(), preview = TRUE) {
  hit <- resolve_output(target)
  obj <- read_output_object(hit$abs_path[[1]])

  if (isTRUE(assign)) {
    assign(hit$default_object_name[[1]], obj, envir = .GlobalEnv)
  }

  if (isTRUE(preview)) {
    preview_loaded_object(obj, title = hit$file_name[[1]], view = view)
  }

  invisible(obj)
}

view_output <- function(target) {
  load_output(target, assign = TRUE, view = TRUE, preview = TRUE)
}

browse_output <- function(target) {
  hit <- resolve_output(target)
  if (!hit$output_type[[1]] %in% c("browser", "text")) {
    message(sprintf("Output type '%s' is better opened with load_output().", hit$output_type[[1]]))
  }
  utils::browseURL(hit$abs_path[[1]])
  invisible(hit$abs_path[[1]])
}

load_all_tabular_outputs <- function(
  max_size_mb = Inf,
  assign_list_name = "loaded_outputs",
  assign_individually = FALSE,
  view_first = FALSE
) {
  hits <- tabular_output_inventory |>
    dplyr::filter(size_mb <= max_size_mb)

  out <- rlang::set_names(
    purrr::map(hits$abs_path, read_output_object),
    nm = hits$default_object_name
  )

  if (isTRUE(assign_individually) && length(out) > 0) {
    purrr::walk2(names(out), out, ~ assign(.x, .y, envir = .GlobalEnv))
  }

  assign(assign_list_name, out, envir = .GlobalEnv)
  if (length(out) > 0 && isTRUE(view_first)) {
    first_name <- names(out)[[1]]
    preview_loaded_object(out[[first_name]], title = first_name, view = TRUE)
  }

  invisible(out)
}

load_tabular_outputs_by_topic <- function(
  max_size_mb = Inf,
  assign_grouped_name = "loaded_outputs",
  assign_topic_lists = TRUE
) {
  # Grouped loading creates topic-specific nested lists such as
  # `loaded_outputs$panel` and `loaded_outputs$qc` for interactive exploration.
  hits <- tabular_output_inventory |>
    dplyr::filter(size_mb <= max_size_mb) |>
    dplyr::arrange(output_topic, root, rel_root_path)

  if (nrow(hits) == 0L) {
    grouped <- list()
    assign(assign_grouped_name, grouped, envir = .GlobalEnv)
    return(invisible(grouped))
  }

  flat <- rlang::set_names(
    purrr::map(hits$abs_path, read_output_object),
    nm = hits$default_object_name
  )

  grouped <- split(seq_len(nrow(hits)), hits$output_topic) |>
    purrr::imap(function(idx, topic_nm) {
      rlang::set_names(flat[idx], hits$default_object_name[idx])
    })

  assign(assign_grouped_name, grouped, envir = .GlobalEnv)

  if (isTRUE(assign_topic_lists)) {
    purrr::walk(names(grouped), function(topic_nm) {
      assign(
        sprintf("loaded_outputs_%s", topic_nm),
        grouped[[topic_nm]],
        envir = .GlobalEnv
      )
    })
  }

  invisible(grouped)
}

output_review_help <- function() {
  cat(
    paste(
      "Available objects/functions after source():",
      "- `output_inventory`: all generated outputs under 01_Data/03_Processed_Data and 03_Output",
      "- `topic_output_inventory`: inventory with `output_topic` classification",
      "- `core_output_inventory`: main analysis outputs only",
      "- `list_outputs(pattern = 'aux_covariates')`: filter inventory",
      "- `list_outputs_by_topic('intermediate')`: filter inventory by topic",
      "- `load_output('aux_covariates.parquet')`: load one output and assign it into .GlobalEnv",
      "- `view_output('medical_source_preagg.parquet')`: inspect one auxiliary pre-aggregation source directly",
      "- `view_output('seoul_raw_review.parquet')`: open the review-friendly Seoul raw companion",
      "- `view_output('panel_main_pre_vitality.parquet')`: inspect the shared derived panel before vitality publication",
      "- `view_output('panel_main.parquet')`: inspect the final canonical shared analysis panel used by ESDA/TWFE/SPDM/GTWR",
      "- `browse_output('twfe_main_coefplot.png')`: open image/html/pdf outputs",
      "- `loaded_outputs`: grouped list of tabular/text outputs by topic (`intermediate`, `analysis_ready`, `panel`, `qc`, ...)",
      "- `loaded_outputs_intermediate`, `loaded_outputs_analysis_ready`, `loaded_outputs_panel`, `loaded_outputs_qc`: topic-specific lists in .GlobalEnv",
      "- `load_all_tabular_outputs()`: bulk-load tabular/text outputs into one flat list object when needed",
      "- `load_tabular_outputs_by_topic()`: bulk-load tabular/text outputs into grouped topic lists",
      "- `load_all_tabular_outputs(assign_individually = TRUE)`: expand each output into .GlobalEnv only when needed",
      sep = "\n"
    ),
    "\n"
  )
}


#==============================================================================
# 4. Interactive Startup Behavior
#==============================================================================

# In interactive sessions, print the helper guide after sourcing and create the
# initial inventory/grouped objects as the review starting point.
output_review_help()

if (interactive() && nrow(output_inventory) > 0) {
  output_file_paths <- stats::setNames(output_inventory$abs_path, output_inventory$default_object_name)
  non_tabular_output_inventory <- output_inventory |>
    dplyr::filter(!output_type %in% c("tabular", "r_object", "text"))
  loaded_outputs <- load_tabular_outputs_by_topic(
    max_size_mb = Inf,
    assign_grouped_name = "loaded_outputs",
    assign_topic_lists = TRUE
  )
  safe_view(output_inventory, title = "output_inventory")
}
