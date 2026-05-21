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

load_concepts_table <- function(con, concepts) {
  concepts_type <- concepts_input_type(concepts)

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
        "FROM concepts_db.concept_table"
      )
    )
  } else if (concepts_type == "parquet") {
    # Parquet is also kept as a view so the package can query raw files
    # directly instead of first materializing them into R memory.
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
        ", hive_partitioning = true, union_by_name = true)"
      )
    )
  } else {
    # Only true in-memory tables are copied into DuckDB, because they already
    # live in R and cannot be queried lazily from the source.
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
  # The selector SQL only needs these columns, so writing a narrow table keeps
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
