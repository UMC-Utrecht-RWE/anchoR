generic_window <- function(window_dt) {
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

preg1_window <- function(window_dt) {
  # This is a placeholder for a more complex window definition that might be
  # needed for pregnancy-related variables. For now, it just calls the generic
  # definition, but in the future it could add additional logic specific to
  # pregnancy episodes.
  generic_window(window_dt)
}

#' Cross-join population and metadata for window definition.
#' This helper function performs a cross join between the population and
#' metadata data tables, which is necessary for defining windows for each
#' person-variable combination.
#' It includes an optimization to avoid the overhead of a cartesian merge when
#' the metadata has only one row and there are no overlapping column names
#' between the population and metadata.
#' @param population_dt A data.table containing the study population.
#' @param metadata_dt A data.table containing the metadata for the variables.
#' @return A data.table resulting from the cross join of population_dt and
#' metadata_dt, with an additional column .window_row_id to preserve the
#' original order of rows.
#' @keywords internal
#' @noRd
cross_join_population_metadata <- function(population_dt, metadata_dt) {
  # The single-variable orchestration usually reaches `define_window()` with a
  # one-row metadata slice, so avoid the cartesian merge overhead in that case.
  if (
    nrow(metadata_dt) == 1L &&
      length(intersect(names(population_dt), names(metadata_dt))) == 0L
  ) {
    return(
      cbind(
        population_dt,
        metadata_dt[rep.int(1L, nrow(population_dt))]
      )
    )
  }

  population_dt[, .anchor_join_key := 1L]
  metadata_dt[, .anchor_join_key := 1L]

  # Sorting the cartesian join is wasted work because downstream code keeps its
  # own row id to preserve the original person-major expansion order.
  base::merge(
    population_dt,
    metadata_dt,
    by = ".anchor_join_key",
    allow.cartesian = TRUE,
    sort = FALSE
  )[
    ,
    .anchor_join_key := NULL
  ]
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

  # here we want to build one row for every person-variable combination,
  # because later the package computes:
  ## the window start/end for that combination
  ## whether a concept matched in that window
  ## the final value for that variable for that person
  # Basically we match each person with each variable_id.
  window_dt <- cross_join_population_metadata(population_dt, metadata_dt)
  # Preserve the pre-processing order so later operations can reorder safely
  # and still return rows in the same sequence the cross join produced.
  window_dt[, .window_row_id := .I]


  for (window_fun in unique(window_dt[, window_definition])) {
    fun_name <- tolower(paste0(window_fun, "_window"))
    row_idx <- window_dt[, which(window_definition == window_fun)]

    if (!exists(fun_name, mode = "function")) {
      msg <- sprintf("Window function does not exist: %s", fun_name)
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    tryCatch(
      {
        window_subset <- base::do.call(
          what = get(fun_name, mode = "function"),
          args = list(window_dt = window_dt[row_idx])
        )

        window_dt[
          row_idx,
          `:=`(
            window_start = window_subset$window_start,
            window_end = window_subset$window_end
          )
        ]
      },
      error = function(e) {
        msg <- sprintf(
          "Error while applying window function '%s': %s",
          fun_name,
          conditionMessage(e)
        )
        logger::log_error(msg)
        base::stop(msg, call. = FALSE)
      }
    )
  }

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
