parquet_paths_sql <- function(con, concepts) {
  # Quote file paths once here so parquet-backed SQL can stay readable and does
  # not have to worry about path escaping in every caller.
  parquet_paths <- normalize_parquet_sources(concepts)
  quoted_paths <- vapply(
    parquet_paths,
    function(path) as.character(DBI::dbQuoteString(con, path)),
    character(1)
  )

  paste0("[", paste(quoted_paths, collapse = ", "), "]")
}

concept_id_filter_sql <- function(con, concept_ids) {
  # Quoted once here so both the duckdb- and parquet-backed view definitions
  # can reuse the same `WHERE concept_id IN (...)` clause.
  quoted_ids <- vapply(
    concept_ids,
    function(id) as.character(DBI::dbQuoteString(con, id)),
    character(1)
  )

  sprintf("WHERE concept_id IN (%s)", paste(quoted_ids, collapse = ", "))
}

#' Load/register the concepts source for selector queries.
#'
#' @param con An open DBI connection.
#' @param concepts A concept table, DuckDB path, or parquet source (see
#'   [anchor()]).
#' @param concept_ids Optional character vector. When supplied, `concepts` is
#'   restricted to these `concept_id` values. The selector SQL only ever
#'   joins on `concept_id` values that come from `metadata`, so anything else
#'   in `concepts` can never match and is safe (and cheaper) to exclude
#'   upfront rather than relying on the query planner to prune it later.
#' @keywords internal
#' @noRd
load_concepts_table <- function(con, concepts, concept_ids = NULL) {
  concepts_type <- concepts_input_type(concepts)
  filter_sql <- if (is.null(concept_ids)) {
    ""
  } else {
    concept_id_filter_sql(con, concept_ids)
  }

  if (concepts_type == "duckdb") {
    # A DuckDB source can be queried in place, which avoids copying a large
    # concept table into the temporary analysis database.
    DBI::dbExecute(
      con,
      sprintf(
        "ATTACH '%s' AS concepts_db (READ_ONLY);",
        normalizePath(concepts, winslash = "/")
      )
    )
    DBI::dbExecute(con, "DROP VIEW IF EXISTS concepts;")
    DBI::dbExecute(
      con,
      paste(
        "CREATE VIEW concepts AS",
        "SELECT
        person_id,
        concept_id,
        CAST(date AS DATE) AS date,
        value",
        "FROM concepts_db.concept_table",
        filter_sql
      )
    )
  } else if (concepts_type == "parquet") {
    # Parquet is also kept as a view so the package can query raw files
    # directly instead of first materializing them into R memory. The
    # `WHERE` filter (when supplied) lets DuckDB's parquet reader prune whole
    # files/row-groups that can't contain a match, e.g. via hive partition
    # pruning if `concepts` happens to be partitioned by `concept_id`.
    DBI::dbExecute(con, "DROP VIEW IF EXISTS concepts;")
    DBI::dbExecute(
      con,
      paste(
        "CREATE VIEW concepts AS",
        "SELECT
        person_id,
        concept_id,
        CAST(date AS DATE) AS date,
        value",
        "FROM read_parquet(",
        parquet_paths_sql(con, concepts),
        ", hive_partitioning = true, union_by_name = true)",
        filter_sql
      )
    )
  } else {
    # Only true in-memory tables are copied into DuckDB, because they already
    # live in R and cannot be queried lazily from the source. Filtering here,
    # before the copy, keeps irrelevant rows from ever being materialized
    # into DuckDB at all.
    if (!is.null(concept_ids)) {
      concepts <- concepts[concepts$concept_id %in% concept_ids, ]
    }

    DBI::dbWriteTable(
      con,
      name = "concepts",
      value = concepts,
      overwrite = TRUE
    )
  }
}

write_population_windows <- function(
  con, population_windows, anchor_col = "T0"
) {
  # The selector SQL only needs these columns, so writing a long table keeps
  # the temporary database smaller and the SQL templates easier to reason about.
  if (!anchor_col %in% names(population_windows)) {
    stop(
      sprintf(
        "Anchor column `%s` was not found in `population_windows`.",
        anchor_col
      ),
      call. = FALSE
    )
  }

  DBI::dbWriteTable(
    con,
    name = "population_windows",
    value = population_windows[
      ,
      .(
        anchor_row_id,
        person_id,
        T0 = get(anchor_col),
        concept_id,
        variable_id,
        window_name,
        selector,
        window_start,
        window_end,
        range_min,
        range_max
      )
    ],
    overwrite = TRUE
  )
}
