relative_window <- function(window_dt) {
  window_dt[, window_start := as.Date(NA)]
  window_dt[, window_end := as.Date(NA)]

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

  window_dt[]
}

window_function_registry <- function() {
  list(
    RELATIVE = relative_window
  )
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
define_window <- function(population,
                          metadata,
                          anchor_col = "T0") {
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = NULL,
    default_anchor_col = anchor_col
  )

  population_dt <- validated$population
  metadata_dt <- validated$metadata

  population_dt[, .anchor_join_key := 1L]
  metadata_dt[, .anchor_join_key := 1L]

  window_dt <- merge(
    population_dt,
    metadata_dt,
    by = ".anchor_join_key",
    allow.cartesian = TRUE
  )[
    ,
    .anchor_join_key := NULL
  ]
  window_dt[, .window_row_id := .I]

  registry <- window_function_registry()
  unknown_window_defs <- setdiff(
    unique(window_dt$window_definition), names(registry)
  )

  if (length(unknown_window_defs) > 0L) {
    stop(
      sprintf(
        "Unsupported window definition(s): %s.",
        paste(unknown_window_defs, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  window_dt <- data.table::rbindlist(
    lapply(
      unique(window_dt$window_definition),
      function(window_name) {
        registry[[window_name]](
          window_dt[window_definition == window_name]
        )
      }
    ),
    use.names = TRUE,
    fill = TRUE
  )
  data.table::setorder(window_dt, .window_row_id)
  window_dt[, .window_row_id := NULL]

  window_dt[
    ,
    window_valid := !is.na(window_start) &
      !is.na(window_end) &
      window_start <= window_end
  ]

  window_dt[, anchor_row_id := .I]
  window_dt[]
}
