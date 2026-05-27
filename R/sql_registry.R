selector_sql_root <- function() {
  # `system.file()` is the installed-package path; the fallback keeps the same
  # code working under `devtools::load_all()` from the source tree.
  sql_root <- system.file("sql", package = "anchoR")

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
  # This keeps one compatibility bridge for legacy metadata names instead of
  # forcing every selector-related helper to know both column conventions.
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
#' @return A character vector of selector names.
#' @export
available_selectors <- function() {
  sql_files <- list.files(
    selector_sql_root(),
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
#'
#' @return A filtered `data.table` with the same columns as the input.
#' @export
filter_supported_metadata <- function(metadata) {
  metadata_dt <- as_data_table(metadata, "metadata")
  selector_col <- metadata_selector_column(metadata_dt)

  # This helper is intentionally permissive: it is meant for exploratory or
  # mixed metadata files where dropping unsupported rows is more useful than
  # failing the whole run immediately.
  raw_selectors <- as.character(metadata_dt[[selector_col]])
  normalized_selectors <- normalize_selector_name(raw_selectors)
  missing_selectors <- is.na(raw_selectors) | trimws(raw_selectors) == ""
  supported_selectors <- available_selectors()

  keep_rows <- !missing_selectors &
    normalized_selectors %in% supported_selectors
  dropped_rows <- !keep_rows

  if (any(dropped_rows)) {
    dropped_selector_values <- unique(
      ifelse(
        missing_selectors[dropped_rows],
        "<missing>",
        normalized_selectors[dropped_rows]
      )
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
        "Available selectors in package `anchoR`: %s.",
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
#'
#' @return An absolute path to the SQL template.
#' @export
selector_sql_path <- function(selector) {
  selector <- normalize_selector_name(selector[[1L]])
  # Selector names and SQL filenames are kept in sync by convention so adding a
  # new selector mostly means dropping one new template into `inst/sql`.
  sql_path <- file.path(
    selector_sql_root(),
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

add_parquet_export <- function(sql_query, save_parquet_hive_path) {
  # This helper is for SQL templates that export concept subsets to Parquet
  # files instead of returning them as query results.
  # The `save_parquet_hive_path` parameter is a path in the SQL environment's
  # filesystem where the template can write Parquet files, and the caller is
  # responsible for making sure the path is accessible and writable by
  # the database backend.
  export_query <- sprintf(
    "COPY (%s) TO '%s'
    (FORMAT 'parquet',
    PARTITION_BY (variable_id),
      APPEND TRUE);",
    sql_query,
    save_parquet_hive_path
  )

  export_query
}

read_selector_sql <- function(selector, save_parquet_hive_path) {
  # Keeping SQL in separate template files makes the selector logic inspectable
  # and editable without embedding large query strings inside R functions.
  query <- paste(
    readLines(selector_sql_path(selector), warn = FALSE),
    collapse = "\n"
  )
  add_parquet_export(query, save_parquet_hive_path)
}

run_selector_query <- function(con, selector, save_parquet_hive_path) {
  DBI::dbExecute(con, read_selector_sql(selector, save_parquet_hive_path))
}

run_selector_queries <- function(con, selectors, save_parquet_hive_path) {
  result_list <- vector("list", length(selectors))

  # The loop is over selector types, not metadata rows, because each SQL
  # template processes all matching person-variable windows in one batch.
  for (i in seq_along(selectors)) {
    selector_name <- selectors[[i]]
    logger::log_info(
      sprintf("\tProcessing selector: %s", selector_name)
    )

    tryCatch(
      {
        # Warnings are logged and muffled so one noisy backend message does not
        # interrupt a full selector batch that still produced usable results.
        withCallingHandlers(
          run_selector_query(con, selector_name, save_parquet_hive_path),
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
        # Errors are logged with selector context before being rethrown so the
        # caller still gets a failing run and a useful breadcrumb trail.
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
}
