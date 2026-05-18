compute_relative_windows <- function(window_dt) {
  window_dt[, window_start := as.Date(NA)]
  window_dt[, window_end := as.Date(NA)]

  # We loop by anchor column name so one metadata table can mix different
  # anchors, such as T0 and pregnancy dates, without falling back to row-wise R.
  for (col in unique(window_dt$anchor_start_col)) {
    window_dt[
      anchor_start_col == col,
      window_start := as.Date(get(col) + window_start_offset)
    ]
  }

  for (col in unique(window_dt$anchor_end_col)) {
    window_dt[
      anchor_end_col == col,
      window_end := as.Date(get(col) + window_end_offset)
    ]
  }

  # The helper returns the same table so `define_window()` can keep its flow
  # linear and avoid carrying multiple temporary objects.
  window_dt[]
}

#' Define Anchoring Windows
#'
#' Cross-joins a population with anchoring metadata and computes one window
#' per population row and study variable.
#'
#' @param population A data frame containing the study population.
#' @param metadata A data frame describing the variables to anchor.
#' @param anchor_col Column to use when metadata does not specify
#'   `anchor_start_col` or `anchor_end_col`.
#'
#' @return A `data.table` with one row per population row and metadata row.
#' @export
define_window <- function(
  population,
  metadata,
  anchor_col = "T0"
) {
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = NULL,
    anchor_col = anchor_col
  )

  population_dt <- validated$population
  metadata_dt <- validated$metadata

  # We add a temporary join key to perform the cross join in data.table.
  population_dt[, .anchor_join_key := 1L]
  metadata_dt[, .anchor_join_key := 1L]

  # here we want to build one row for every person-variable combination,
  # because later the package computes:
  ## the window start/end for that combination
  ## whether a concept matched in that window
  ## the final value for that variable for that person
  # Basically we match each person with each variable_id.
  window_dt <- merge(
    population_dt,
    metadata_dt,
    by = ".anchor_join_key",
    allow.cartesian = TRUE
  )[
    ,
    .anchor_join_key := NULL
  ]
  # Preserve the pre-processing order so later operations can reorder safely
  # and still return rows in the same sequence the cross join produced.
  window_dt[, .window_row_id := .I]

  window_dt <- compute_relative_windows(window_dt)
  data.table::setorder(window_dt, .window_row_id)
  window_dt[, .window_row_id := NULL]

  # Mark invalid windows instead of dropping them here so callers can decide
  # whether they want a sparse anchored result or a full design matrix.
  window_dt[
    ,
    window_valid := !is.na(window_start) &
      !is.na(window_end) &
      window_start <= window_end
  ]

  # This synthetic key gives the SQL layer a stable identifier for each
  # person-variable request, independent of the original population keys.
  window_dt[, anchor_row_id := .I]
  window_dt[]
}
