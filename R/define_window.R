#' Generic checks for window constructors
#'
#' @description a helper function to perform common checks
#'
#' @param window_dt A data.table
#' @return TRUE if the checks pass, otherwise an error is raised.
#' @keywords internal
generic_window_check <- function(window_dt) {
  if (!data.table::is.data.table(window_dt)) {
    stop_log("window_dt must be a data.table")
  }

  if (!all(c("constructor") %in% names(window_dt))) {
    stop_log("window_dt is missing mandatory metadata columns")
  }

  invisible(TRUE)
}

#' Make a window constructor
#'
#' Create a window-definition function with required-column checks and
#' optional custom validation.
#'
#' @param transform_fn A function applied to `window_dt`.
#' @param required_cols Character vector of required input columns.
#' @param check_fn Optional validation function.
#' @return A `data.table`.
#' @export
make_constructor <- function(
  transform_fn,
  required_cols = character(),
  check_fn = NULL
) {
  if (!is.function(transform_fn)) {
    stop_log("transform_fn must be a function")
  }

  if (!is.character(required_cols)) {
    stop_log("required_cols must be a character vector")
  }

  if (!is.null(check_fn) && !is.function(check_fn)) {
    stop_log("check_fn must be NULL or a function")
  }

  force(transform_fn)
  force(required_cols)
  force(check_fn)

  function(window_dt) {
    if (!is.null(check_fn)) {
      check_fn(window_dt)
    }

    missing_cols <- setdiff(required_cols, names(window_dt))

    if (length(missing_cols)) {
      stop_log(
        sprintf(
          "window_dt is missing required column(s): %s",
          paste(missing_cols, collapse = ", ")
        )
      )
    }

    transform_fn(window_dt)
  }
}

generic_window <- make_constructor(
  transform_fn = function(window_dt) {
    window_dt[, window_start := as.Date(NA)]
    window_dt[, window_end := as.Date(NA)]

    # We loop by anchor column name so one metadata table can mix different
    # anchors, such as T0 and pregnancy dates, without falling back to row-wise
    for (col in unique(window_dt$anchor_start_col)) {
      window_dt[
        anchor_start_col == col,
        window_start := as.Date(get(col) + start_offset)
      ]
    }

    for (col in unique(window_dt$anchor_end_col)) {
      window_dt[
        anchor_end_col == col,
        window_end := as.Date(get(col) + end_offset)
      ]
    }
    # The helper returns the same table so `define_window()` can keep its flow
    # linear and avoid carrying multiple temporary objects.
    window_dt[]
  },
  required_cols = c(
    "anchor_start_col",
    "anchor_end_col",
    "start_offset",
    "end_offset"
  ),
  check_fn = generic_window_check
)

preg1_window <- make_constructor(
  # This is a placeholder for a more complex window definition that might be
  # needed for pregnancy-related variables. For now, it just calls the generic
  # definition, but in the future it could add additional logic specific to
  # pregnancy episodes.
  transform_fn = function(window_dt) {
    generic_window(window_dt)
  },
  required_cols = c(
    "anchor_start_col",
    "anchor_end_col",
    "start_offset",
    "end_offset"
  ),
  check_fn = generic_window_check
)

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
  window_dt <- cross_join_population_metadata(
    population_dt, metadata_dt
  )
  # Preserve the pre-processing order so later operations can reorder safely
  # and still return rows in the same sequence the cross join produced.
  window_dt[, .window_row_id := .I]


  for (window_fun in unique(window_dt[, constructor])) {
    fun_name <- tolower(paste0(window_fun, "_window"))
    row_idx <- window_dt[, which(constructor == window_fun)]

    if (!exists(fun_name, mode = "function")) {
      stop_log(
        sprintf("Window function does not exist: %s", fun_name)
      )
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
        stop_log(
          sprintf(
            "Error while applying window function '%s': %s",
            fun_name,
            conditionMessage(e)
          )
        )
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
