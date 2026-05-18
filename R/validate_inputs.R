#' Validate Anchoring Inputs
#'
#' Standardizes the study-variable metadata shape and checks the minimum
#' structure required by the package.
#'
#' @param population A data frame containing at least `person_id` and the
#'   anchor column used for windowing.
#' @param metadata A data frame in the standard study-variable format.
#' @param concepts A concept table as a data frame or a DuckDB file path whose
#'   `concept_table` contains `person_id`, `concept_id`, and `date`.
#' @param anchor_col Column to use when metadata does not specify
#'   the anchor column.
#'
#' @return Invisibly returns a list with normalized `population`, `metadata`,
#'   and `concepts`.
#' @export
validate_anchor_inputs <- function(
  population,
  metadata,
  concepts = NULL,
  anchor_col = "T0"
) {
  population_dt <- as_data_table(population, "population")
  metadata_dt <- normalize_metadata(
    metadata,
    anchor_col = anchor_col
  )

  assert_has_columns(
    population_dt,
    required = "person_id", arg = "population"
  )

  assert_has_columns(
    metadata_dt,
    required = c(
      "variable_id",
      "concept_id",
      "selector",
      "window_start_offset",
      "window_end_offset"
    ),
    arg = "metadata"
  )

  anchor_cols <- unique(
    c(metadata_dt$anchor_start_col, metadata_dt$anchor_end_col)
  )

  # unsupported_selectors <- setdiff(
  #   unique(metadata_dt$selector),
  #   available_selectors()
  # )

  # if (length(unsupported_selectors) > 0L) {
  #   stop(
  #     sprintf(
  #       "Unsupported selector(s): %s.",
  #       paste(unsupported_selectors, collapse = ", ")
  #     ),
  #     call. = FALSE
  #   )
  # }

  concepts_obj <- NULL
  if (!is.null(concepts)) {
    concepts_obj <- concepts_to_data_table(concepts)
  }

  invisible(
    list(
      population = population_dt,
      metadata = metadata_dt,
      concepts = concepts_obj
    )
  )
}
