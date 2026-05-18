population_anchor_columns <- function(population_dt, metadata_dt) {
  anchor_cols <- unique(
    c(metadata_dt$anchor_start_col, metadata_dt$anchor_end_col)
  )
  missing_anchor_cols <- setdiff(anchor_cols, names(population_dt))

  if (length(missing_anchor_cols) > 0L) {
    stop(
      sprintf(
        "`population` is missing anchor columns referenced by `metadata`: %s.",
        paste(missing_anchor_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(population_dt)
}

metadata_supported_selectors <- function(metadata_dt, package = "anchoR") {
  supported_selectors <- available_selectors(package = package)
  unsupported_selectors <- setdiff(
    unique(metadata_dt$selector),
    supported_selectors
  )

  if (length(unsupported_selectors) > 0L) {
    stop(
      paste(
        "Unsupported selector(s) in `metadata`:",
        paste(unsupported_selectors, collapse = ", "),
        sprintf(
          "Available selectors in package `%s`: %s.",
          package,
          paste(supported_selectors, collapse = ", ")
        ),
        paste(
          "Pregnancy-specific selectors from the legacy pipeline require",
          "study-specific preprocessing and are not implemented in this",
          "simplified package."
        ),
        paste(
          "Use `filter_supported_metadata()` if you want to drop unsupported",
          "rows before calling `anchor()`."
        )
      ),
      call. = FALSE
    )
  }

  invisible(metadata_dt)
}

normalize_concepts_input <- function(concepts) {
  concepts_type <- concepts_input_type(concepts)

  if (concepts_type == "table") {
    return(concepts_to_data_table(concepts))
  }

  if (concepts_type == "duckdb" && !file.exists(concepts)) {
    stop(
      sprintf("Concept database path does not exist: %s.", concepts),
      call. = FALSE
    )
  }

  if (concepts_type == "parquet") {
    normalize_parquet_sources(concepts)
  }

  concepts
}

#' Validate Anchoring Inputs
#'
#' Standardizes the study-variable metadata shape and checks the minimum
#' structure required by the package.
#'
#' @param population A data frame containing at least `person_id` and the
#'   anchor column used for windowing.
#' @param metadata A data frame in the standard study-variable format.
#' @param concepts A concept table as a data frame, a DuckDB file path whose
#'   `concept_table` contains `person_id`, `concept_id`, and `date`, or parquet
#'   file location(s).
#' @param anchor_col Column to use when metadata does not specify
#'   the anchor column.
#' @param package Package name used to resolve available selector SQL
#'   templates.
#'
#' @return Invisibly returns a list with normalized `population`, `metadata`,
#'   and `concepts`.
#' @export
validate_anchor_inputs <- function(
  population,
  metadata,
  concepts = NULL,
  anchor_col = "T0",
  package = "anchoR"
) {
  population_dt <- as_data_table(population, "population")
  metadata_dt <- normalize_metadata(
    metadata,
    anchor_col = anchor_col
  )

  assert_has_columns(
    population_dt,
    required = "person_id",
    arg = "population"
  )

  assert_has_columns(
    metadata_dt,
    required = c(
      "variable_id",
      "concept_id",
      "selector",
      "window_start_offset",
      "window_end_offset",
      "anchor_start_col",
      "anchor_end_col",
      "range_min",
      "range_max"
    ),
    arg = "metadata"
  )

  population_anchor_columns(population_dt, metadata_dt)
  metadata_supported_selectors(metadata_dt, package = package)

  concepts_obj <- NULL
  if (!is.null(concepts)) {
    concepts_obj <- normalize_concepts_input(concepts)
  }

  invisible(
    list(
      population = population_dt,
      metadata = metadata_dt,
      concepts = concepts_obj
    )
  )
}
