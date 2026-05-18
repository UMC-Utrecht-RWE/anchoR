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

normalize_metadata <- function(metadata, anchor_col = "T0") {
  metadata_dt <- as_data_table(metadata, "metadata")

  if (!"selector" %in% names(metadata_dt)) {
    selector_source <- intersect(
      c("date_extraction_func"),
      names(metadata_dt)
    )
    if (length(selector_source) > 0L) {
      data.table::setnames(metadata_dt, selector_source[[1L]], "selector")
    }
  }
  # Rename start_look_back with window_start_offset
  if (!"window_start_offset" %in% names(metadata_dt)) {
    window_start_source <- intersect(
      c("start_look_back"),
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

  # Rename end_look_back with window_end_offset
  if (!"window_end_offset" %in% names(metadata_dt)) {
    window_end_source <- intersect(
      c("end_look_back"),
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

  data.table::set(
    metadata_dt,
    j = "selector",
    value = normalize_selector_name(metadata_dt$selector)
  )
  data.table::set(
    metadata_dt,
    j = "window_start_offset",
    value = as.integer(metadata_dt$window_start_offset)
  )
  data.table::set(
    metadata_dt,
    j = "window_end_offset",
    value = as.integer(metadata_dt$window_end_offset)
  )

  data.table::set(
    metadata_dt,
    j = "anchor_start_col",
    value = rep(anchor_col, nrow(metadata_dt))
  )
  data.table::set(
    metadata_dt,
    j = "anchor_end_col",
    value = rep(anchor_col, nrow(metadata_dt))
  )

  # add window_definition, range_min, and range_max columns
  # with default values for all rows
  # because these are required for downstream processing,
  # even if not provided by the user.
  data.table::set(
    metadata_dt,
    j = "window_definition",
    value = rep("RELATIVE", nrow(metadata_dt))
  )
  data.table::set(
    metadata_dt,
    j = "range_min", value =
      rep(NA_real_, nrow(metadata_dt))
  )
  data.table::set(
    metadata_dt,
    j = "range_max", value =
      rep(NA_real_, nrow(metadata_dt))
  )

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
