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
#' @param selector_col Column in `metadata` that contains selector
#'
#' @return A filtered `data.table` with the same columns as the input.
#' @export
filter_supported_metadata <- function(
  metadata, selector_col = "selector"
) {
  metadata_dt <- as_data_table(metadata, "metadata")


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

add_parquet_export <- function(sql_query, anchor_hive_path, selector = NULL) {
  # This helper is for SQL templates that export concept subsets to Parquet
  # files instead of returning them as query results.
  # The `anchor_hive_path` parameter is a path in the SQL environment's
  # filesystem where the template can write Parquet files, and the caller is
  # responsible for making sure the path is accessible and writable by
  # the database backend.
  # `FILENAME_PATTERN` is keyed on the selector so that when a single
  # `variable_id` has windows using more than one selector, the two COPY
  # calls don't collide on the same `{i}`-numbered filename. Callers that
  # export an already-combined, multi-selector result in one COPY (e.g.
  # `publish_accumulated_table()`) have no single selector to key on, so
  # `selector` is optional there.
  filename_prefix <- if (is.null(selector)) {
    "part"
  } else {
    tolower(normalize_selector_name(selector))
  }
  export_query <- sprintf(
    "COPY (%s) TO '%s'
    (FORMAT 'parquet',
    PARTITION_BY (variable_id),
    FILENAME_PATTERN '%s_{i}',
      OVERWRITE_OR_IGNORE TRUE);",
    sql_query,
    anchor_hive_path,
    filename_prefix
  )

  export_query
}

ensure_accumulate_table <- function(con, table_name) {
  # Selector templates don't all select the same columns. For example LATEST and
  # EARLIEST need `anchor_row_id` (to break ties among candidate rows),
  # ALL/COUNT/RANGE_COUNT/COUNT_MORE_THAN_1 don't. Rather than forcing every
  # template to carry a column most of them have no use for, the
  # accumulator table is created upfront with a full column set
  # `anchor_row_id`, `person_id`, `T0`, `variable_id`, `window_name`,
  # plus the fixed `value`/`date`/`n` types and every insert below matches
  # columns by name, leaving `anchor_row_id` NULL for selectors that don't
  # provide it.
  DBI::dbExecute(
    con,
    sprintf(
      "CREATE TABLE IF NOT EXISTS %s AS (
        SELECT
          anchor_row_id,
          person_id,
          T0,
          variable_id,
          window_name,
          CAST(NULL AS VARCHAR) AS value,
          CAST(NULL AS DATE) AS date,
          CAST(NULL AS BIGINT) AS n
        FROM population_windows
        LIMIT 0
      );",
      table_name
    )
  )
}

add_table_accumulation <- function(sql_query, table_name) {
  # Used by `anchor_by_variable()`'s "memory" staging mode: every selector,
  # from every chunk in the run, lands in the same table (see
  # `ensure_accumulate_table()`) instead of its own parquet write, so the
  # whole run's output can be exported to `anchor_hive_path` in one final
  # `COPY` instead of one per chunk. `BY NAME` matches each selector's
  # columns to the table by name instead of position, since not every
  # selector produces the same columns.
  sprintf("INSERT INTO %s BY NAME (%s);", table_name, sql_query)
}

read_selector_sql_query <- function(selector) {
  # Keeping SQL in separate template files makes the selector logic inspectable
  # and editable without embedding large query strings inside R functions.
  paste(
    readLines(selector_sql_path(selector), warn = FALSE),
    collapse = "\n"
  )
}

run_selector_query <- function(
  con,
  selector,
  anchor_hive_path = NULL,
  accumulate_table = NULL
) {
  query <- read_selector_sql_query(selector)
  sql <- if (is.null(accumulate_table)) {
    add_parquet_export(query, anchor_hive_path, selector)
  } else {
    ensure_accumulate_table(con, accumulate_table)
    add_table_accumulation(query, accumulate_table)
  }

  DBI::dbExecute(con, sql)
}

#' @param con An open DBI connection.
#' @param selectors Selector names to run, in order.
#' @param anchor_hive_path Where to write parquet output directly. Ignored
#'   when `accumulate_table` is set.
#' @param accumulate_table If set, every selector's rows are inserted into
#'   this table instead of being written to `anchor_hive_path` -- the
#'   caller is then responsible for exporting the table to parquet itself
#'   (see `add_parquet_export()`).
#' @keywords internal
#' @noRd
run_selector_queries <- function(
  con,
  selectors,
  anchor_hive_path = NULL,
  accumulate_table = NULL
) {
  if (
    is.null(accumulate_table) &&
      (is.null(anchor_hive_path) ||
        !dir.exists(anchor_hive_path))
  ) {
    msg <- "`anchor_hive_path` must be a valid path!"
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

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
          run_selector_query(
            con,
            selector_name,
            anchor_hive_path = anchor_hive_path,
            accumulate_table = accumulate_table
          ),
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
        msg <- sprintf(
          "Error while processing selector %s: %s",
          selector_name,
          conditionMessage(e)
        )
        logger::log_error(msg)
        base::stop(msg, call. = FALSE)
      }
    )
  }

  logger::log_debug(
    sprintf("Finished processing %d selector(s).", length(selectors))
  )
}
