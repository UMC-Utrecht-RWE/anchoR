#' Validate Anchoring Inputs
#'
#' Standardizes metadata column names and checks that the population,
#' metadata, and concepts objects have the minimum structure required by the
#' package.
#'
#' @param population A data frame containing at least `person_id` and the
#'   anchor columns referenced by the metadata.
#' @param metadata A data frame describing the variables to anchor.
#' @param concepts A concept table as a data frame or a DuckDB file path whose
#'   `concept_table` contains `person_id`, `concept_id`, and `date`.
#' @param default_anchor_col Column to use when metadata does not specify
#'   `anchor_start_col` or `anchor_end_col`.
#'
#' @return Invisibly returns a list with normalized `population`, `metadata`,
#'   and `concepts`.
#' @export
validate_anchor_inputs <- function(
  population,
  metadata,
  concepts = NULL,
  default_anchor_col = "anchor_date"
) {
  population_dt <- as_data_table(population, "population")
  metadata_dt <- normalize_metadata(
    metadata,
    default_anchor_col = default_anchor_col
  )

  assert_has_columns(
    population_dt,
    required = "person_id", arg = "population"
  )

  anchor_cols <- unique(
    c(metadata_dt$anchor_start_col, metadata_dt$anchor_end_col)
  )
  missing_anchor_cols <- setdiff(anchor_cols, names(population_dt))

  if (length(missing_anchor_cols) > 0L) {
    stop(
      sprintf(
        "Population is missing anchor columns referenced by metadata: %s.",
        paste(missing_anchor_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  unsupported_selectors <- setdiff(
    unique(metadata_dt$selector),
    available_selectors()
  )

  if (length(unsupported_selectors) > 0L) {
    stop(
      sprintf(
        "Unsupported selector(s): %s.",
        paste(unsupported_selectors, collapse = ", ")
      ),
      call. = FALSE
    )
  }

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
