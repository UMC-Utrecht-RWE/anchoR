#' Anchor Study Variables to an Index Date
#'
#' Applies metadata-driven windowing and selector rules to a concept table.
#'
#' @param population A data frame containing the study population.
#' @param metadata A data frame describing the variables to anchor.
#' @param concepts A concept table as a data frame, a DuckDB file path, or
#'   parquet file location(s).
#' @param anchor_col Column representing T0
#' @param keep_all If `TRUE`, keep the full population-by-metadata cross join
#'   and fill unmatched rows with missing values. If `FALSE`, return only rows
#'   with at least one matching concept record.
#' @param package Package name used to resolve selector SQL templates.
#'
#' @return A long `data.table` containing anchored values and event dates.
#' @export
anchor <- function(
  population,
  metadata,
  concepts,
  anchor_col = "T0",
  keep_all = FALSE,
  package = "anchoR"
) {
  # Normalize inputs at the beginning so the rest
  # of the workflow has stable input.
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = concepts,
    anchor_col = anchor_col,
    package = package
  )

  # Define windows for all person-variable combinations.
  # Impossible anchors will be marked and filtered out later.
  window_dt <- define_window(
    population = validated$population,
    metadata = validated$metadata,
    anchor_col = anchor_col
  )

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

  result_list <- run_selector_queries(
    con = con,
    selectors = unique(valid_windows$selector),
    package = package
  )

  # Different selectors may return slightly different columns, so the combined
  # result needs a forgiving row bind instead of assuming one rigid shape.
  result_dt <- data.table::rbindlist(
    lapply(result_list, data.table::as.data.table),
    use.names = TRUE,
    fill = TRUE
  )

  if (keep_all) {
    # Keep the full design matrix when the caller wants explicit missing rows
    # for unmatched variables.
    anchored_dt <- merge(
      window_dt,
      result_dt,
      by = c("anchor_row_id", "variable_id"),
      all.x = TRUE,
      sort = FALSE
    )
  } else {
    # Sparse output is useful when the caller only cares about rows that
    # produced at least one anchored concept record.
    anchored_dt <- merge(
      valid_windows,
      result_dt,
      by = c("anchor_row_id", "variable_id"),
      all = FALSE,
      sort = FALSE
    )
  }

  if ("date" %in% names(anchored_dt)) {
    # DBI can round-trip DATE columns as character depending on the source, so
    # coerce back here to keep the public output type stable.
    anchored_dt[, date := as.Date(date)]
  }

  data.table::setorder(anchored_dt, anchor_row_id)
  anchored_dt[]
}
