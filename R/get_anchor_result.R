# Which population columns disagree across rows sharing the same
# person_id/T0, so get_anchor_result()'s error can name them directly.
population_conflict_columns <- function(
  population_dt, duplicate_keys, required_columns
) {
  conflicting_rows <- population_dt[duplicate_keys, on = required_columns]
  other_cols <- setdiff(names(population_dt), required_columns)

  varying <- conflicting_rows[
    ,
    lapply(.SD, data.table::uniqueN),
    .SDcols = other_cols,
    by = required_columns
  ]
  is_varying <- vapply(
    varying[, ..other_cols], function(x) any(x > 1L), logical(1)
  )
  other_cols[is_varying]
}

#' Retrieve and Reshape Anchored Variable Results
#'
#' Reads parquet files from an anchor hive directory via DuckDB, filters to the
#' requested variables, and pivots the long-format result into a wide
#' data.table with one column per variable for both value and
#' date.
#'
#' @param metadata A data frame describing the study variables. Must contain at
#'   least a variable_id column.
#' @param anchor_hive_path A character string giving the path to the directory
#'   that contains the anchored parquet hive. Must be a valid existing
#'   directory.
#' @param population Optional data frame with population rows to be represented
#'   in wide output. When provided, it must contain person_id and
#'   T0 columns. Additional population columns are carried into the
#'   wide result. When multiple rows share the same person_id/T0
#'   key but disagree on other columns (e.g. matching with replacement), the
#'   first row per key is kept, a warning names the conflicting column(s),
#'   and processing continues.
#' @param result_shape A character string specifying the desired shape of the
#'   output. Must be either "wide" or "long".
#' @param impute_missing Logical; when TRUE and
#'   result_shape = "wide", missing value_<variable_id> cells are
#'   imputed using metadata columns is_expected_missing and
#'   variable_type via imputing_missing().
#' @param cast_window Logical; controls wide reshaping formula. When
#'   \code{FALSE} (default), results are cast by
#'   \code{person_id + T0 + window_name ~ variable_id}. When \code{TRUE},
#'   results are cast by \code{person_id + T0 ~ window_name + variable_id}.
#' @param only_date Logical; when \code{TRUE} and
#'   result_shape = "wide", only date columns are cast (no
#'   \code{value_<...>} columns). When \code{FALSE}, both value and date
#'   columns are cast.
#' @param required_population_cols Character vector of column names that must
#' be present in the population data frame when provided.
#' Defaults to \code{c("person_id", "T0")}.
#'
#' @return A data.table with anchored variable results in the specified shape.
#' @export
get_anchor_result <- function(
  metadata,
  anchor_hive_path = NULL,
  population = NULL,
  result_shape = "wide",
  impute_missing = FALSE,
  cast_window = FALSE,
  only_date = FALSE,
  required_population_cols = c("person_id", "T0")
) {
  # Different selectors may return slightly different columns, so the combined
  # result needs a forgiving row bind instead of assuming one rigid shape.
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  metadata_dt <- as_data_table(metadata, "metadata")
  assert_has_columns(
    metadata_dt,
    required = "variable_id",
    arg = "metadata"
  )
  add_column_if_missing(metadata_dt, "window_name", NA_character_)

  population_dt <- NULL
  population_keys_dt <- NULL

  if (!is.null(population)) {
    population_dt <- as_data_table(population, "population")
    missing_population_cols <- setdiff(
      required_population_cols, names(population_dt)
    )
    if (length(missing_population_cols) > 0L) {
      msg <- sprintf(
        paste(
          "`population` is missing required columns:",
          "%s."
        ),
        paste(missing_population_cols, collapse = ", ")
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    # Multiple rows can legitimately share a person_id/T0 key
    population_dt <- unique(population_dt)
    population_dt[, T0 := as.Date(T0)]
    population_keys_dt <- unique(population_dt[, .(person_id, T0)])
  }

  if (is.null(anchor_hive_path) || !dir.exists(anchor_hive_path)) {
    msg <- sprintf("`anchor_hive_path` must be a valid path!")
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

  anchor_hive_path_sql <- as.character(
    DBI::dbQuoteString(
      con,
      normalizePath(anchor_hive_path, winslash = "/", mustWork = TRUE)
    )
  )
  DBI::dbExecute(
    con,
    paste(
      "CREATE VIEW anchored_variables AS",
      "SELECT * FROM read_parquet(",
      anchor_hive_path_sql,
      ", hive_partitioning = true, union_by_name = true);"
    )
  )

  requested_results_dt <- unique(metadata_dt[, .(variable_id, window_name)])
  requested_results_dt[
    is.na(window_name) | trimws(window_name) == "",
    window_name := NA_character_
  ]
  DBI::dbWriteTable(
    con,
    name = "requested_results",
    value = requested_results_dt,
    overwrite = TRUE
  )
  anchored_dt <- data.table::as.data.table(
    DBI::dbGetQuery(
      con,
      paste(
        "SELECT a.* FROM anchored_variables AS a",
        "WHERE EXISTS (",
        "  SELECT 1 FROM requested_results AS r",
        "  WHERE a.variable_id = r.variable_id",
        "    AND (r.window_name IS NULL OR a.window_name = r.window_name)",
        ");"
      )
    )
  )
  if ("date" %in% names(anchored_dt)) {
    # DBI can round-trip DATE columns as character depending on the source, so
    # coerce back here to keep the public output type stable.
    anchored_dt[, date := as.Date(date)]
  }
  if ("T0" %in% names(anchored_dt)) {
    anchored_dt[, T0 := as.Date(T0)]
  }

  data.table::setorder(anchored_dt, variable_id, person_id, T0, window_name)
  if (result_shape == "long") {
    required_long_cols <- c(
      "person_id",
      "T0",
      "variable_id",
      "window_name",
      "date",
      "value"
    )
    missing_cols <- setdiff(required_long_cols, names(anchored_dt))
    if (length(missing_cols) > 0L) {
      msg <- sprintf(
        paste(
          "Anchored results are missing required long-output columns:",
          "%s."
        ),
        paste(missing_cols, collapse = ", ")
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    anchored_dt[
      ,
      ..required_long_cols
    ]
  } else if (result_shape == "wide") {
    if (!is.null(population_keys_dt)) {
      # Restricting to the requested population keeps wide output cardinality
      # anchored to the caller's keys even if the hive contains extra rows.
      anchored_dt <- anchored_dt[
        population_keys_dt,
        on = .(person_id, T0),
        nomatch = 0L
      ]
    }

    required_wide_id_cols <- c("person_id", "T0", "variable_id")
    missing_cols <- setdiff(required_wide_id_cols, names(anchored_dt))
    if (length(missing_cols) > 0L) {
      msg <- sprintf(
        paste(
          "Anchored results are missing required wide-output columns:",
          "%s."
        ),
        paste(missing_cols, collapse = ", ")
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    duplicate_rows <- anchored_dt[
      ,
      .N,
      by = .(person_id, T0, window_name, variable_id)
    ][N > 1L]
    if (nrow(duplicate_rows) > 0L) {
      msg <- sprintf(
        paste(
          "Anchored results contain duplicate rows for the same",
          "`person_id`, `T0`, `window_name`, and `variable_id`,",
          "so wide output is ambiguous. This can happen with selectors that",
          "return multiple events, such as `ALL`; use",
          "`result_shape = \"long\"`."
        )
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    # The dcast formula will create columns in the format value_<variable_id>
    # and date_<variable_id> or if cast_window is TRUE,
    # value_<window_name>_<variable_id> and date_<window_name>_<variable_id>
    formula <- stats::as.formula(if (cast_window) {
      "person_id + T0 ~ window_name + variable_id"
    } else {
      "person_id + T0 + window_name ~ variable_id"
    })
    wide_anchored <- data.table::dcast(
      anchored_dt,
      formula,
      value.var = if (only_date == FALSE) c("value", "date") else c("date"),
      fill = list(value = NA_character_, date = as.Date(NA))
    )

    wildcard_variable_ids <- requested_results_dt[
      is.na(window_name),
      unique(variable_id)
    ]
    expected_window_pairs <- if (cast_window) {
      explicit_window_pairs <- requested_results_dt[!is.na(window_name)]
      wildcard_window_pairs <- anchored_dt[
        variable_id %in% wildcard_variable_ids,
        unique(.(
          variable_id,
          window_name
        ))
      ]
      unique(data.table::rbindlist(
        list(explicit_window_pairs, wildcard_window_pairs),
        use.names = TRUE,
        fill = TRUE
      ))
    } else {
      NULL
    }

    expected_date_cols <- unique(if (cast_window) {
      paste0(
        if (only_date == FALSE) "date_" else "",
        expected_window_pairs$window_name,
        "_",
        expected_window_pairs$variable_id
      )
    } else {
      paste0(
        if (only_date == FALSE) "date_" else "",
        metadata_dt$variable_id
      )
    })
    missing_date_cols <- setdiff(expected_date_cols, names(wide_anchored))
    for (col_name in missing_date_cols) {
      wide_anchored[, (col_name) := as.Date(NA)]
    }

    if (only_date == FALSE) {
      expected_value_cols <- unique(if (cast_window) {
        paste0(
          "value_",
          expected_window_pairs$window_name,
          "_",
          expected_window_pairs$variable_id
        )
      } else {
        paste0("value_", metadata_dt$variable_id)
      })
      missing_value_cols <- setdiff(expected_value_cols, names(wide_anchored))
      for (col_name in missing_value_cols) {
        wide_anchored[, (col_name) := NA_character_]
      }
    }

    if (!is.null(population_keys_dt)) {
      result_key_cols <- if (cast_window) {
        required_population_cols
      } else {
        c(required_population_cols, "window_name")
      }

      expected_keys <- if (cast_window) {
        population_keys_dt
      } else {
        explicit_window_keys <- requested_results_dt[
          !is.na(window_name),
          .(window_name)
        ]
        wildcard_window_keys <- anchored_dt[
          variable_id %in% wildcard_variable_ids,
          unique(.(
            window_name
          ))
        ]
        window_keys <- unique(data.table::rbindlist(
          list(explicit_window_keys, wildcard_window_keys),
          use.names = TRUE,
          fill = TRUE
        ))
        if (nrow(window_keys) == 0L) {
          window_keys <- data.table::data.table(window_name = character())
        }
        population_window_keys <- data.table::copy(population_keys_dt)
        population_window_keys[, .anchor_join_key := 1L]
        window_keys[, .anchor_join_key := 1L]
        data.table::merge.data.table(
          population_window_keys,
          window_keys,
          by = ".anchor_join_key",
          allow.cartesian = TRUE,
          sort = FALSE
        )[
          ,
          .anchor_join_key := NULL
        ]
      }
      expected_keys <- unique(expected_keys[, ..result_key_cols])

      missing_anchored <- data.table::fsetdiff(
        expected_keys,
        unique(wide_anchored[, ..result_key_cols])
      )

      if (nrow(missing_anchored) > 0L) {
        # Filling at the cast key guarantees a deterministic number of rows
        # for the requested population regardless of which variables matched.
        wide_anchored <- data.table::rbindlist(
          list(wide_anchored, missing_anchored),
          use.names = TRUE,
          fill = TRUE
        )
      }
    }

    if (impute_missing == TRUE) {
      wide_anchored <- imputing_missing(wide_anchored, metadata_dt)
    }

    if (!is.null(population_dt)) {
      # Left-join the anchored results onto the *full* population once the wide
      # result shape is stable, so a person_id/T0 that appears more than once in
      # `population` keeps every row
      wide_anchored <- wide_anchored[
        population_dt,
        on = .(person_id, T0),
        allow.cartesian = TRUE
      ]
    }

    wide_anchored
  } else {
    msg <- sprintf("`result_shape` must be either 'wide' or 'long'!")
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }
}


#' Impute Missing Values in Wide Anchor Output
#'
#' Imputes missing value_<variable_id> cells in a wide anchored result
#' using metadata rules for is_expected_missing and
#' variable_type. For non-expected-missing variables, logical/TF types
#' are imputed as FALSE and categorical types as 0. If required
#' metadata columns are only partially available, a warning is raised and
#' imputation is skipped.
#'
#' @param wide_anchored A wide data.table from get_anchor_result
#'   with value_<variable_id> columns.
#' @param metadata A data frame that should include variable_id,
#'   is_expected_missing, and variable_type.
#'
#' @return The updated wide data.table. Returns input unchanged when
#'   required metadata columns are missing.
#' @keywords internal
#'
imputing_missing <- function(wide_anchored, metadata) {
  # Imputing missing values, we will need metadata for this task
  required_imputation_cols <- c(
    "variable_id",
    "is_expected_missing",
    "variable_type"
  )
  present_imputation_cols <- intersect(
    required_imputation_cols, names(metadata)
  )
  missing_imputation_cols <- setdiff(required_imputation_cols, names(metadata))

  # Checking if any requiered imputation column is missing
  if (length(missing_imputation_cols) > 0L) {
    if (length(present_imputation_cols) > 0L) {
      warning(
        sprintf(
          paste(
            "Metadata is partially missing required imputation columns.",
            "Present: %s.",
            "Missing: %s.",
            "Skipping imputation."
          ),
          paste(present_imputation_cols, collapse = ", "),
          paste(missing_imputation_cols, collapse = ", ")
        )
      )
    }
  } else {
    # Imputing values
    for (i in seq_len(nrow(metadata))) {
      i_variable_id <- metadata$variable_id[[i]]
      i_is_expected_missing <- isTRUE(metadata$is_expected_missing[[i]])
      i_variable_type <- metadata$variable_type[[i]]
      value_col <- paste0("value_", i_variable_id)

      if (!value_col %in% names(wide_anchored) || i_is_expected_missing) {
        next
      }

      # Decision logic:
      # If variable is an boolean, then value = FALSE. Outcomes or boolean are
      # by default false since the subject never had an diagnostic of that
      # variable. If variables is a categorical, then value = 0 We use 0 as
      # category for missingness. If variable is an integer, then ignore

      if (i_variable_type %in% c("TF", "BOOL", "BOOLEAN", "LOGICAL")) {
        wide_anchored[is.na(get(value_col)), (value_col) := FALSE]
        wide_anchored[, (value_col) := as.logical(get(value_col))]
      } else if (i_variable_type %in% c("CAT", "FACTOR")) {
        wide_anchored[is.na(get(value_col)), (value_col) := 0]
      }
    }
  }
  wide_anchored
}
