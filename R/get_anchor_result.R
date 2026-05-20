#' Retrieve and Reshape Anchored Variable Results
#'
#' Reads parquet files from an anchor hive directory via DuckDB, filters to the
#' requested variables, and pivots the long-format result into a wide
#' \code{data.table} with one column per variable for both \code{value} and
#' \code{date}.
#'
#' @param population A data frame containing the study population. Used to
#'   determine which variables are relevant.
#' @param metadata A data frame describing the study variables. Must contain at
#'   least a \code{variable_id} column.
#' @param anchor_hive_path A character string giving the path to the directory
#'   that contains the anchored parquet hive. Must be a valid existing
#'   directory.
#'
#' @return A wide \code{data.table} with one row per \code{anchor_row_id} and
#'   one pair of columns (\code{value_<variable_id>}, \code{date_<variable_id>})
#'   per variable in \code{metadata}.
#' @export
get_anchor_result <- function(
    population,
    metadata,
    anchor_hive_path = NULL) {
  # Different selectors may return slightly different columns, so the combined
  # result needs a forgiving row bind instead of assuming one rigid shape.
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  if (!dir.exists(anchor_hive_path) && !is.null(anchor_hive_path)) {
    stop(
      "The `anchor_hive_path` argument must be a valid directory path when parquet export is enabled.",
      call. = FALSE
    )
  } else if (is.null(anchor_hive_path)) {
    stop(
      "The `anchor_hive_path` argument must be a valid directory path when parquet export is enabled.",
      call. = FALSE
    )
  }

  DBI::dbExecute(con, sprintf("CREATE VIEW anchored_variables AS SELECT * FROM read_parquet('%s');", anchor_hive_path))

  variable_id_list <- unique(metadata$variable_id)
  anchored_dt <- data.table::as.data.table(
    DBI::dbGetQuery(
      con,
      paste(
        "SELECT DISTINCT * FROM anchored_variables WHERE variable_id IN ('", paste(variable_id_list, collapse = "', '"), "');"
      )
    )
  )
  if ("date" %in% names(anchored_dt)) {
    # DBI can round-trip DATE columns as character depending on the source, so
    # coerce back here to keep the public output type stable.
    anchored_dt[, date := as.Date(date)]
  }

  data.table::setorder(anchored_dt, anchor_row_id)
  anchored_dt <- data.table::dcast(anchored_dt,
    anchor_row_id ~ variable_id, # change anchor_row_id by person_id + t0
    value.var = c("value", "date"),
    fill = list(value = NA_character_, date = as.Date(NA))
  )
  anchored_dt[]
}
