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



generic_window <- function(window_dt, multiple_episodes = NULL) {
  window_dt[, window_start := as.Date(NA)]
  window_dt[, window_end := as.Date(NA)]

  # We loop by anchor column name so one metadata table can mix different
  # anchors, such as T0 and pregnancy dates, without falling back to row-wise R.
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
}


require_multiple_episodes <- function(multiple_episodes, constructor) {
  if (is.null(multiple_episodes)) {
    stop(
      sprintf(
        paste(
          "Constructor `%s` requires `multiple_episodes`.",
          "Supply a table with `person_id`, `episode_id`, `episode_start`,",
          "and `episode_end`."
        ),
        constructor
      ),
      call. = FALSE
    )
  }

  multiple_episodes
}

expand_multiple_episode_windows <- function(
  window_dt,
  multiple_episodes,
  constructor,
  keep_episode
) {
  if (!all(c("lmp_date", "pregnancy_end_date") %in% names(window_dt))) {
    stop(
      paste(
        "Pregnancy window constructors require `population` to contain",
        "`lmp_date` and `pregnancy_end_date`."
      ),
      call. = FALSE
    )
  }

  multiple_episodes <- require_multiple_episodes(
    multiple_episodes,
    constructor = constructor
  )
  episode_dt <- data.table::copy(multiple_episodes)
  data.table::setnames(
    episode_dt,
    old = c("episode_id", "episode_start", "episode_end"),
    new = c(
      "matched_episode_id",
      "matched_episode_start",
      "matched_episode_end"
    )
  )

  expanded_dt <- base::merge(
    window_dt,
    episode_dt,
    by = "person_id",
    allow.cartesian = TRUE,
    sort = FALSE
  )
  expanded_dt <- keep_episode(expanded_dt)

  matched_anchor_row_ids <- unique(expanded_dt$anchor_row_id)
  unmatched_dt <- window_dt[!anchor_row_id %in% matched_anchor_row_ids]
  if (nrow(unmatched_dt) > 0L) {
    unmatched_dt[, `:=`(
      matched_episode_id = NA_character_,
      matched_episode_start = as.Date(NA),
      matched_episode_end = as.Date(NA)
    )]
    expanded_dt <- data.table::rbindlist(
      list(expanded_dt, unmatched_dt),
      use.names = TRUE,
      fill = TRUE
    )
  }

  expanded_dt[, `:=`(
    lmp_date = as.Date(matched_episode_start),
    pregnancy_end_date = as.Date(matched_episode_end)
  )]

  expanded_dt <- generic_window(expanded_dt)
  expanded_dt[
    is.na(matched_episode_id),
    `:=`(window_start = as.Date(NA), window_end = as.Date(NA))
  ]

  expanded_dt[]
}

preg1_window <- function(window_dt, multiple_episodes = NULL) {
  # Expand each request into one window per prior pregnancy episode.
  expand_multiple_episode_windows(
    window_dt = window_dt,
    multiple_episodes = multiple_episodes,
    constructor = "PREG1",
    keep_episode = function(expanded_dt) {
      expanded_dt[
        !is.na(matched_episode_end) &
          !is.na(lmp_date) &
          matched_episode_end < lmp_date
      ]
    }
  )
}

preg2_window <- function(window_dt, multiple_episodes = NULL) {
  # Expand each request into one window per pregnancy episode up to and
  # including the anchored pregnancy.
  expand_multiple_episode_windows(
    window_dt = window_dt,
    multiple_episodes = multiple_episodes,
    constructor = "PREG2",
    keep_episode = function(expanded_dt) {
      expanded_dt[
        !is.na(matched_episode_end) &
          !is.na(pregnancy_end_date) &
          matched_episode_end <= pregnancy_end_date
      ]
    }
  )
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
#' @param multiple_episodes Optional episode table used by constructors that
#'   expand one anchor row into multiple separate episodes.
#' @param anchor_col Column to use when metadata does not specify
#'   `anchor_start_col` or `anchor_end_col`.
#'
#' @return A `data.table` with one row per population row and metadata row.
#' @export
define_window <- function(
  population,
  metadata,
  multiple_episodes = NULL,
  anchor_col = "T0"
) {
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = NULL,
    multiple_episodes = multiple_episodes,
    anchor_col = anchor_col
  )

  population_dt <- validated$population
  metadata_dt <- validated$metadata
  multiple_episodes_dt <- validated$multiple_episodes

  # here we want to build one row for every person-variable combination,
  # because later the package computes:
  ## the window start/end for that combination
  ## whether a concept matched in that window
  ## the final value for that variable for that person
  # Basically we match each person with each variable_id.
  window_dt <- cross_join_population_metadata(
    population_dt, metadata_dt
  )
  if (nrow(window_dt) == 0L) {
    window_dt[, `:=`(
      anchor_row_id = integer(),
      window_start = as.Date(character()),
      window_end = as.Date(character()),
      window_valid = logical()
    )]
    return(window_dt[])
  }
  # Preserve the pre-processing order so later operations can reorder safely
  # and still return rows in the same sequence the cross join produced.
  window_dt[, `:=`(
    .window_row_id = .I,
    anchor_row_id = .I
  )]

  window_parts <- vector("list", length(unique(window_dt$constructor)))
  part_index <- 1L
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
          args = list(
            window_dt = window_dt[row_idx],
            multiple_episodes = multiple_episodes_dt
          )
        )
        if (!all(c("window_start", "window_end") %in% names(window_subset))) {
          stop(
            sprintf(
              paste(
                "Window function `%s` must return `window_start`",
                "and `window_end` columns."
              ),
              fun_name
            ),
            call. = FALSE
          )
        }
        window_parts[[part_index]] <- data.table::as.data.table(
          data.table::copy(window_subset)
        )
        part_index <- part_index + 1L
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

  window_dt <- data.table::rbindlist(
    window_parts,
    use.names = TRUE,
    fill = TRUE
  )
  data.table::setorder(window_dt, .window_row_id, window_start, window_end)
  window_dt[, .window_row_id := NULL]

  # Mark invalid windows instead of dropping them here so callers can decide
  # whether they want a sparse anchored result or a full design matrix.
  window_dt[
    ,
    window_valid := !is.na(window_start) &
      !is.na(window_end) &
      window_start <= window_end
  ]
  window_dt[]
}
