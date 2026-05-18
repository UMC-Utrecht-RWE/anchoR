`%||%` <- function(lhs, rhs) {
  if (is.null(lhs)) {
    return(rhs)
  }

  lhs
}

as_data_table <- function(x, arg) {
  if (!is.data.frame(x)) {
    stop(sprintf("`%s` must be a data frame.", arg), call. = FALSE)
  }

  data.table::as.data.table(data.table::copy(x))
}

assert_has_columns <- function(x, required, arg) {
  missing_cols <- setdiff(required, names(x))

  if (length(missing_cols) > 0L) {
    stop(
      sprintf(
        "`%s` is missing required columns: %s.",
        arg,
        paste(missing_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(x)
}

normalize_selector_name <- function(x) {
  toupper(trimws(as.character(x)))
}

normalize_metadata <- function(metadata, default_anchor_col = "anchor_date") {
  metadata_dt <- as_data_table(metadata, "metadata")

  if (!"selector" %in% names(metadata_dt)) {
    selector_source <- intersect(
      c("date_extraction_func", "anchoring_function"),
      names(metadata_dt)
    )
    if (length(selector_source) > 0L) {
      data.table::setnames(metadata_dt, selector_source[[1L]], "selector")
    }
  }

  if (!"window_start_offset" %in% names(metadata_dt)) {
    window_start_source <- intersect(
      c("start_look_back", "window_start", "window_start_days"),
      names(metadata_dt)
    )
    if (length(window_start_source) > 0L) {
      data.table::setnames(
        metadata_dt,
        window_start_source[[1L]],
        "window_start_offset"
      )
    }
  }

  if (!"window_end_offset" %in% names(metadata_dt)) {
    window_end_source <- intersect(
      c("end_look_back", "window_end", "window_end_days"),
      names(metadata_dt)
    )
    if (length(window_end_source) > 0L) {
      data.table::setnames(
        metadata_dt,
        window_end_source[[1L]],
        "window_end_offset"
      )
    }
  }

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

  metadata_dt[
    ,
    selector := normalize_selector_name(selector)
  ][
    ,
    window_start_offset := as.integer(window_start_offset)
  ][
    ,
    window_end_offset := as.integer(window_end_offset)
  ]

  metadata_dt[, anchor_start_col := default_anchor_col]
  metadata_dt[, anchor_end_col := default_anchor_col]
  metadata_dt[, window_definition := "RELATIVE"]
  metadata_dt[, range_min := NA_real_]
  metadata_dt[, range_max := NA_real_]

  metadata_dt[]
}

concepts_to_data_table <- function(concepts) {
  if (is.character(concepts) && length(concepts) == 1L) {
    if (!file.exists(concepts)) {
      stop(
        sprintf("Concept database path does not exist: %s.", concepts),
        call. = FALSE
      )
    }

    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    DBI::dbExecute(
      con,
      sprintf(
        "ATTACH '%s' AS concepts_db (READ_ONLY);",
        normalizePath(concepts, winslash = "/")
      )
    )

    concepts_dt <- data.table::as.data.table(
      DBI::dbGetQuery(
        con,
        paste(
          "SELECT person_id, concept_id, CAST(date AS DATE) AS date, value",
          "FROM concepts_db.concept_table"
        )
      )
    )
  } else {
    concepts_dt <- as_data_table(concepts, "concepts")
  }

  assert_has_columns(
    concepts_dt,
    required = c("person_id", "concept_id", "date"),
    arg = "concepts"
  )

  if (!"value" %in% names(concepts_dt)) {
    concepts_dt[, value := NA_character_]
  }

  concepts_dt[, date := as.Date(date)]
  concepts_dt[]
}
