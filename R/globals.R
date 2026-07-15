.datatable.aware <- TRUE # nolint: object_name_linter.

if (getRversion() >= "2.15.1") {
  # Register NSE symbols once so package checks understand the column names
  # that data.table evaluates lazily inside `:=`, `get()`, and joins.
  utils::globalVariables(
    c(
      ".",
      ".I",
      ":=",
      "N",
      ".N",
      "T0",
      "SD",
      ".SD",
      "tmp",
      "constructor",
      ".anchor_join_key",
      ".anchor_row_id",
      ".window_end",
      ".window_row_id",
      ".window_start",
      "..other_cols",
      "..required_long_cols",
      "..required_population_cols",
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
      "end_offset",
      "window_start",
      "start_offset",
      "window_valid",
      "window_name",
      "..result_key_cols",
      "event_start",
      "event_end",
      "event_col",
      "end_cap_offset",
      "start_look_back",
      "end_look_back"
    )
  )
}
