#' Anchor Study Variables to an Index Date
#'
#' Applies metadata-driven windowing and selector rules to a concept table.
#'
#' @param population A data frame containing the study population.
#' @param metadata A data frame describing the variables to anchor.
#' @param concepts A concept table as a data frame or a DuckDB file path.
#' @param default_anchor_col Column to use when metadata does not specify
#'   `anchor_start_col` or `anchor_end_col`.
#' @param keep_all If `TRUE`, keep the full population-by-metadata cross join
#'   and fill unmatched rows with missing values. If `FALSE`, return only rows
#'   with at least one matching concept record.
#' @param db_dir Optional writable directory for a temporary DuckDB database.
#' @param package Package name used to resolve selector SQL templates.
#'
#' @return A long `data.table` containing anchored values and event dates.
#' @export
anchor <- function(
  population,
  metadata,
  concepts,
  default_anchor_col = "anchor_date",
  keep_all = FALSE,
  db_dir = NULL,
  package = "anchoR"
) {
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = concepts,
    default_anchor_col = default_anchor_col
  )

  window_dt <- define_window(
    population = validated$population,
    metadata = validated$metadata,
    default_anchor_col = default_anchor_col
  )

  valid_windows <- window_dt[window_valid == TRUE]
  if (nrow(valid_windows) == 0L) {
    if (keep_all) {
      window_dt[
        , `:=`(value = NA_character_, date = as.Date(NA), n = NA_integer_)
      ]
      return(window_dt[])
    }

    return(
      window_dt[0][
        , `:=`(value = character(), date = as.Date(character()), n = integer())
      ]
    )
  }

  db <- anchor_db_connect(db_dir = db_dir)
  on.exit(anchor_db_disconnect(db), add = TRUE)

  load_concepts_table(db$con, concepts)
  write_population_windows(db$con, valid_windows)

  result_list <- lapply(
    unique(valid_windows$selector),
    function(selector_name) {
      run_selector_query(db$con, selector_name, package = package)
    }
  )

  result_dt <- data.table::rbindlist(
    lapply(result_list, data.table::as.data.table),
    use.names = TRUE,
    fill = TRUE
  )

  if (keep_all) {
    anchored_dt <- merge(
      window_dt,
      result_dt,
      by = c("anchor_row_id", "variable_id"),
      all.x = TRUE,
      sort = FALSE
    )
  } else {
    anchored_dt <- merge(
      valid_windows,
      result_dt,
      by = c("anchor_row_id", "variable_id"),
      all = FALSE,
      sort = FALSE
    )
  }

  if ("date" %in% names(anchored_dt)) {
    anchored_dt[, date := as.Date(date)]
  }

  data.table::setorder(anchored_dt, anchor_row_id)
  anchored_dt[]
}
