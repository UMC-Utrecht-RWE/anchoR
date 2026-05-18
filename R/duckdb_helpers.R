anchor_db_connect <- function(db_dir = NULL) {
  use_memory <- TRUE
  db_path <- ":memory:"

  if (!is.null(db_dir)) {
    if (!dir.exists(db_dir)) {
      warning(
        sprintf(
          "Directory `%s` does not exist. Falling back to in-memory DuckDB.",
          db_dir
        ),
        call. = FALSE
      )
    } else if (file.access(db_dir, 2L) != 0L) {
      warning(
        sprintf(
          "Directory `%s` is not writable. Falling back to in-memory DuckDB.",
          db_dir
        ),
        call. = FALSE
      )
    } else {
      use_memory <- FALSE
      db_path <- file.path(
        db_dir,
        sprintf("anchr_%s_%s.duckdb", Sys.getpid(), as.integer(Sys.time()))
      )
    }
  }

  list(
    con = DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE),
    db_path = db_path,
    use_memory = use_memory
  )
}

anchor_db_disconnect <- function(connection) {
  try(DBI::dbDisconnect(connection$con, shutdown = TRUE), silent = TRUE)

  if (!connection$use_memory && file.exists(connection$db_path)) {
    try(unlink(connection$db_path), silent = TRUE)
  }
}

load_concepts_table <- function(con, concepts) {
  if (is.character(concepts) && length(concepts) == 1L) {
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
        "SELECT person_id, concept_id, CAST(date AS DATE) AS date, value",
        "FROM concepts_db.concept_table"
      )
    )
  } else {
    DBI::dbWriteTable(
      con,
      name = "concepts",
      value = concepts_to_data_table(concepts),
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
