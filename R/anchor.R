#' Anchor Study Variables to an Index Date
#'
#' Applies metadata-driven windowing and selector rules to a concept table,
#' producing one anchored value and event date per person-variable combination.
#'
#' @param population A data frame containing the study population. Must include
#'   a \code{person_id} column and the anchor date column specified by
#'   \code{anchor_col}.
#' @param metadata A data frame describing the variables to anchor. Must contain
#'   the columns required by \code{validate_anchor_inputs()}.
#' @param concepts A concept table as a data frame, a DuckDB file path whose
#'   \code{concept_table} contains \code{person_id}, \code{concept_id}, and
#'   \code{date}, or parquet file location(s).
#' @param anchor_col Character. Name of the column in \code{population} to use
#'   as the index date when metadata does not specify an anchor column.
#'   Defaults to \code{"T0"}.
#' @param keep_all Logical. If \code{TRUE}, keeps the full
#'   population-by-metadata cross join and fills unmatched rows with missing
#'   values. If \code{FALSE} (default), returns only rows with at least one
#'   matching concept record.
#' @param save_parquet_hive_path Character. Path to an existing (or creatable)
#'   directory where selector query results are written as a partitioned parquet
#'   hive. Must not be \code{NULL}.
#'
#' @return Invisibly, the function writes parquet files to
#'   \code{save_parquet_hive_path}. When no valid windows exist and
#'   \code{keep_all = TRUE}, a \code{data.table} with missing anchored values
#'   is returned directly.
#' @export
anchor <- function(
  population,
  metadata,
  concepts,
  anchor_col = "T0",
  keep_all = FALSE,
  save_parquet_hive_path = NULL
) {
  # Normalize inputs at the beginning so the rest
  # of the workflow has stable input.
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = concepts,
    anchor_col = anchor_col
  )

  # Define windows for all person-variable combinations.
  # Impossible anchors will be marked and filtered out later.
  window_dt <- define_window(
    population = validated$population,
    metadata = validated$metadata,
    anchor_col = anchor_col
  )

  if (!dir.exists(save_parquet_hive_path) && !is.null(save_parquet_hive_path)) {
    dir.create(save_parquet_hive_path, recursive = TRUE)
  } else if (is.null(save_parquet_hive_path)) {
    msg <- sprintf(
      "`save_parquet_hive_path` must be a valid path!"
    )
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }
  # Remove impossible anchors.
  valid_windows <- window_dt[window_valid == TRUE]
  if (nrow(valid_windows) == 0L) {
    if (keep_all) {
      # Some downstream code expects one row per person-variable pair even when
      # nothing can be anchored, so keep the design matrix and mark it missing.
      window_dt[
        , `:=`(value = NA_character_, date = as.Date(NA), n = NA_integer_)
      ]
      return(window_dt[])
    }

    # When sparse output is requested, an empty typed table is clearer than
    # returning the full cross join filled with missing values.
    return(
      window_dt[0][
        , `:=`(value = character(), date = as.Date(character()), n = integer())
      ]
    )
  }

  # Prepare to work in a SQL enviroment.
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  load_concepts_table(con, validated$concepts)
  # Only valid windows are written because invalid ones can never match and
  # would only make the SQL side do unnecessary work.
  write_population_windows(con, valid_windows)

  run_selector_queries(
    con = con,
    selectors = unique(valid_windows$selector),
    save_parquet_hive_path = save_parquet_hive_path
  )
}
