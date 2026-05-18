#' Derive an Index Date From Concept Records
#'
#' Finds the earliest or latest occurrence of one or more concept IDs within an
#' optional per-row search window and appends the derived date to the
#' population.
#'
#' @param population A data frame containing at least `person_id`.
#' @param concepts A concept table as a data frame or a DuckDB file path.
#' @param concept_id One or more concept IDs used to derive the index date.
#' @param selector Either `"EARLIEST"` or `"LATEST"`.
#' @param window_start_col Optional population column containing the earliest
#'   eligible date for the search.
#' @param window_end_col Optional population column containing the latest
#'   eligible date for the search.
#' @param output_col Name of the output column that will contain the derived
#'   index date.
#'
#' @return The input population with an added date column.
#' @export
derive_t0 <- function(
  population,
  concepts,
  concept_id,
  selector = c("EARLIEST", "LATEST"),
  window_start_col = NULL,
  window_end_col = NULL,
  output_col = "anchor_date"
) {
  population_dt <- as_data_table(population, "population")
  concepts_dt <- concepts_to_data_table(concepts)

  assert_has_columns(population_dt, required = "person_id", arg = "population")

  if (!is.null(window_start_col)) {
    assert_has_columns(
      population_dt,
      required = window_start_col,
      arg = "population"
    )
  }
  if (!is.null(window_end_col)) {
    assert_has_columns(
      population_dt,
      required = window_end_col,
      arg = "population"
    )
  }

  selector <- normalize_selector_name(selector[[1L]])
  if (!selector %in% c("EARLIEST", "LATEST")) {
    stop("`selector` must be either 'EARLIEST' or 'LATEST'.", call. = FALSE)
  }

  concept_ids <- as.character(concept_id)
  population_dt[, .anchor_row_id := .I]
  population_dt[
    ,
    .window_start := if (is.null(window_start_col)) {
      as.Date("1900-01-01")
    } else {
      as.Date(get(window_start_col))
    }
  ]
  population_dt[
    ,
    .window_end := if (is.null(window_end_col)) {
      as.Date("9999-12-31")
    } else {
      as.Date(get(window_end_col))
    }
  ]

  eligible_concepts <- concepts_dt[concept_id %in% concept_ids]
  if (nrow(eligible_concepts) == 0L) {
    population_dt[, (output_col) := as.Date(NA)]
    population_dt[
      , c(".anchor_row_id", ".window_start", ".window_end") := NULL
    ]
    return(population_dt[])
  }
  eligible_concepts <- eligible_concepts[
    ,
    .(person_id, concept_date = as.Date(date))
  ]
  eligible_concepts[, concept_end := concept_date]

  population_windows <- population_dt[
    ,
    .(.anchor_row_id, person_id, .window_start, .window_end)
  ]

  data.table::setkey(population_windows, person_id, .window_start, .window_end)
  data.table::setkey(eligible_concepts, person_id, concept_date, concept_end)

  matches <- data.table::foverlaps(
    eligible_concepts,
    population_windows,
    by.x = c("person_id", "concept_date", "concept_end"),
    by.y = c("person_id", ".window_start", ".window_end"),
    nomatch = 0L
  )

  if (selector == "EARLIEST") {
    derived_dt <- matches[
      , .(derived_t0 = min(concept_date)),
      by = .anchor_row_id
    ]
  } else {
    derived_dt <- matches[
      , .(derived_t0 = max(concept_date)),
      by = .anchor_row_id
    ]
  }

  population_dt[, (output_col) := as.Date(NA)]
  population_dt[
    derived_dt,
    on = ".anchor_row_id",
    (output_col) := i.derived_t0
  ]

  population_dt[, c(".anchor_row_id", ".window_start", ".window_end") := NULL]
  population_dt[]
}
