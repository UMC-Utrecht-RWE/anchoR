parquet_paths_sql <- function(con, concepts) {
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
    DBI::dbWriteTable(
      con,
      name = "concepts",
      value = concepts,
      overwrite = TRUE
    )
  }
}

write_population_windows <- function(con, population_windows) {
  DBI::dbWriteTable(
    con,
    name = "population_windows",
    value = population_windows[
      ,
      .(
        anchor_row_id,
        person_id,
        concept_id,
        variable_id,
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
