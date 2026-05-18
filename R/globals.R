.datatable.aware <- TRUE

if (getRversion() >= "2.15.1") {
  # Register NSE symbols once so package checks understand the column names
  # that data.table evaluates lazily inside `:=`, `get()`, and joins.
  utils::globalVariables(
    c(
      ".",
      ".I",
      ":=",
      ".anchor_join_key",
      ".anchor_row_id",
      ".window_end",
      ".window_row_id",
      ".window_start",
      "anchor_end_col",
      "anchor_row_id",
      "anchor_start_col",
      "concept_date",
      "concept_end",
      "concept_id",
      "i.derived_t0",
      "person_id",
      "range_max",
      "range_min",
      "selector",
      "value",
      "variable_id",
      "window_end",
      "window_end_offset",
      "window_start",
      "window_start_offset",
      "window_valid"
    )
  )
}
