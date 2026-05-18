selector_sql_root <- function(package = "anchoR") {
  sql_root <- system.file("sql", package = package)

  if (!nzchar(sql_root)) {
    local_root <- file.path(getwd(), "inst", "sql")
    if (dir.exists(local_root)) {
      sql_root <- normalizePath(local_root, winslash = "/")
    }
  }

  if (!nzchar(sql_root) || !dir.exists(sql_root)) {
    stop("Could not locate `inst/sql` for the anchoR package.", call. = FALSE)
  }

  sql_root
}

metadata_selector_column <- function(metadata_dt) {
  if ("selector" %in% names(metadata_dt)) {
    return("selector")
  }

  if ("date_extraction_func" %in% names(metadata_dt)) {
    return("date_extraction_func")
  }

  stop(
    "`metadata` must contain either `selector` or `date_extraction_func`.",
    call. = FALSE
  )
}

#' List Available Selector SQL Templates
#'
#' @param package Package name used to resolve `inst/sql`.
#'
#' @return A character vector of selector names.
#' @export
available_selectors <- function(package = "anchoR") {
  sql_files <- list.files(
    selector_sql_root(package = package),
    pattern = "\\.sql$",
    full.names = FALSE
  )

  toupper(tools::file_path_sans_ext(sql_files))
}

#' Filter Metadata to Selectors Supported by the Package
#'
#' Keeps only metadata rows whose selector has a bundled SQL template in the
#' package. Rows with missing or unsupported selectors are dropped with a
#' warning.
#'
#' @param metadata A data frame containing study-variable metadata.
#' @param package Package name used to resolve `inst/sql`.
#'
#' @return A filtered `data.table` with the same columns as the input.
#' @export
filter_supported_metadata <- function(metadata, package = "anchoR") {
  metadata_dt <- as_data_table(metadata, "metadata")
  selector_col <- metadata_selector_column(metadata_dt)

  raw_selectors <- as.character(metadata_dt[[selector_col]])
  normalized_selectors <- normalize_selector_name(raw_selectors)
  missing_selectors <- is.na(raw_selectors) | trimws(raw_selectors) == ""
  supported_selectors <- available_selectors(package = package)

  keep_rows <- !missing_selectors & normalized_selectors %in% supported_selectors
  dropped_rows <- !keep_rows

  if (any(dropped_rows)) {
    dropped_selector_values <- unique(
      ifelse(missing_selectors[dropped_rows], "<missing>", normalized_selectors[dropped_rows])
    )

    warning_parts <- c(
      sprintf(
        "Dropped %d metadata row(s) with missing or unsupported selectors.",
        sum(dropped_rows)
      ),
      sprintf(
        "Dropped selector value(s): %s.",
        paste(dropped_selector_values, collapse = ", ")
      ),
      sprintf(
        "Available selectors in package `%s`: %s.",
        package,
        paste(supported_selectors, collapse = ", ")
      )
    )

    if ("variable_id" %in% names(metadata_dt)) {
      dropped_variables <- unique(metadata_dt$variable_id[dropped_rows])
      warning_parts <- c(
        warning_parts,
        sprintf(
          "Affected variable_id value(s): %s.",
          paste(dropped_variables, collapse = ", ")
        )
      )
    }

    logger::log_warn(paste(warning_parts, collapse = " "))
  }

  metadata_dt[keep_rows][]
}

#' Get the Path to a Selector SQL Template
#'
#' @param selector Selector name such as `"LATEST"` or `"COUNT"`.
#' @param package Package name used to resolve `inst/sql`.
#'
#' @return An absolute path to the SQL template.
#' @export
selector_sql_path <- function(selector, package = "anchoR") {
  selector <- normalize_selector_name(selector[[1L]])
  sql_path <- file.path(
    selector_sql_root(package = package),
    paste0(tolower(selector), ".sql")
  )

  if (!file.exists(sql_path)) {
    stop(
      sprintf("No SQL template found for selector `%s`.", selector),
      call. = FALSE
    )
  }

  sql_path
}

read_selector_sql <- function(selector, package = "anchoR") {
  paste(
    readLines(selector_sql_path(selector, package = package), warn = FALSE),
    collapse = "\n"
  )
}

run_selector_query <- function(con, selector, package = "anchoR") {
  DBI::dbGetQuery(con, read_selector_sql(selector, package = package))
}

run_selector_queries <- function(con, selectors, package = "anchoR") {
  result_list <- vector("list", length(selectors))

  for (i in seq_along(selectors)) {
    selector_name <- selectors[[i]]
    logger::log_info(
      sprintf("Processing selector: %s", selector_name)
    )

    result_list[[i]] <- tryCatch(
      {
        withCallingHandlers(
          run_selector_query(con, selector_name, package = package),
          warning = function(w) {
            logger::log_warn(
              sprintf(
                "Warning while processing selector %s: %s",
                selector_name,
                conditionMessage(w)
              )
            )
            invokeRestart("muffleWarning")
          }
        )
      },
      error = function(e) {
        logger::log_error(
          sprintf(
            "Error while processing selector %s: %s",
            selector_name,
            conditionMessage(e)
          )
        )
        stop(e)
      }
    )
  }

  result_list
}
