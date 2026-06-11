population_anchor_columns <- function(population_dt, metadata_dt) {
  # Anchor references are stored in metadata, so fail here before window
  # calculation if the population does not actually contain those columns.
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

metadata_supported_selectors <- function(metadata_dt) {
  # Selector validation happens before any SQL runs so unsupported study
  # variables fail with a metadata error instead of a late database error.
  supported_selectors <- available_selectors()
  unsupported_selectors <- setdiff(
    unique(metadata_dt$selector),
    supported_selectors
  )

  if (length(unsupported_selectors) > 0L) {
    msg <- paste(
      "Unsupported selector(s) in `metadata`:",
      paste(unsupported_selectors, collapse = ", "),
      sprintf(
        "Available selectors in package `anchoR`: %s.",
        paste(supported_selectors, collapse = ", ")
      ),
      paste(
        "Use `filter_supported_metadata()` if you want to drop unsupported",
        "rows before calling `anchor()`."
      )
    )
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

  invisible(metadata_dt)
}

normalize_concepts_input <- function(concepts) {
  concepts_type <- concepts_input_type(concepts)

  if (concepts_type == "table") {
    # In-memory tables are normalized immediately because downstream code may
    # mutate and type-cast them by reference.
    return(concepts_to_data_table(concepts))
  }

  if (concepts_type == "duckdb" && !file.exists(concepts)) {
    stop(
      sprintf("Concept database path does not exist: %s.", concepts),
      call. = FALSE
    )
  }

  if (concepts_type == "parquet") {
    # For parquet inputs we only validate the source paths here; the heavy read
    # is deferred so `anchor()` can query parquet directly inside DuckDB.
    normalize_parquet_sources(concepts)
  }

  concepts
}

validate_population_anchor_column <- function(population_dt, anchor_col) {
  anchor_values <- population_dt[[anchor_col]]

  if (inherits(anchor_values, "Date")) {
    return(invisible(population_dt))
  }

  if (!is.character(anchor_values)) {
    stop(
      sprintf(
        "`population$%s` must be a Date column or character values in YYYY-mm-dd format.",
        anchor_col
      ),
      call. = FALSE
    )
  }

  if (any(!is.na(anchor_values) & !grepl("^\\d{4}-\\d{2}-\\d{2}$", anchor_values))) {
    stop(
      sprintf(
        "`population$%s` must use the date format YYYY-mm-dd.",
        anchor_col
      ),
      call. = FALSE
    )
  }

  parsed_values <- as.Date(anchor_values, format = "%Y-%m-%d")
  if (any(!is.na(anchor_values) & is.na(parsed_values))) {
    stop(
      sprintf(
        "`population$%s` contains invalid dates; use the format YYYY-mm-dd.",
        anchor_col
      ),
      call. = FALSE
    )
  }

  population_dt[, (anchor_col) := parsed_values]
  invisible(population_dt)
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
  # Normalization is centralized here so exported functions can stay short and
  # still rely on a consistent metadata schema.
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

  validate_population_anchor_column(population_dt, anchor_col)

  assert_has_columns(
    metadata_dt,
    required = c(
      "variable_id",
      "concept_id",
      "window_name",
      "constructor",
      "selector",
      "start_offset",
      "end_offset",
      "anchor_start_col",
      "anchor_end_col",
      "range_min",
      "range_max"
    ),
    arg = "metadata"
  )
  metadata_dt <- metadata_dt[, c(
    "variable_id",
    "concept_id",
    "window_name",
    "constructor",
    "selector",
    "start_offset",
    "end_offset",
    "anchor_start_col",
    "anchor_end_col",
    "range_min",
    "range_max"
  )]

  population_anchor_columns(population_dt, metadata_dt)
  metadata_supported_selectors(metadata_dt)

  concepts_obj <- NULL
  if (!is.null(concepts)) {
    # Concepts can be large, so normalize just enough to guarantee the later
    # execution path knows if it is dealing with a table, DuckDB, or parquet.
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
