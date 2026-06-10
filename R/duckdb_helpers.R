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

prepare_selector_context <- function(
  con,
  valid_windows,
  selectors,
  multiple_episodes,
  anchor_col = "T0"
) {
  write_population_windows(
    con,
    valid_windows,
    anchor_col = anchor_col
  )

  if ("LATEST_EXCL_PRIOR_PREG" %in% selectors) {
    write_prior_pregnancy_episodes(
      con = con,
      population_windows = valid_windows,
      multiple_episodes = multiple_episodes
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

write_prior_pregnancy_episodes <- function(
  con, population_windows, multiple_episodes
) {
  empty_dt <- data.table::data.table(
    anchor_row_id = integer(),
    person_id = character(),
    lmp_date = as.Date(character()),
    pregnancy_end_date = as.Date(character())
  )

  if (is.null(multiple_episodes)) {
    DBI::dbWriteTable(
      con,
      name = "prior_pregnancy_episodes",
      value = empty_dt,
      overwrite = TRUE
    )
    return(invisible(empty_dt))
  }

  latest_excl_windows <- unique(
    population_windows[
      selector == "LATEST_EXCL_PRIOR_PREG",
      .(anchor_row_id, person_id, lmp_date)
    ]
  )

  if (nrow(latest_excl_windows) == 0L) {
    DBI::dbWriteTable(
      con,
      name = "prior_pregnancy_episodes",
      value = empty_dt,
      overwrite = TRUE
    )
    return(invisible(empty_dt))
  }

  prior_dt <- multiple_episodes[
    latest_excl_windows,
    on = .(person_id, episode_end < lmp_date),
    nomatch = 0L,
    .(
      anchor_row_id,
      person_id = x.person_id,
      lmp_date = x.episode_start,
      pregnancy_end_date = x.episode_end
    )
  ]
  prior_dt <- unique(prior_dt)

  DBI::dbWriteTable(
    con,
    name = "prior_pregnancy_episodes",
    value = prior_dt,
    overwrite = TRUE
  )

  invisible(prior_dt)
}
