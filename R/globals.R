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
      "tmp",
      "constructor",
      ".anchor_join_key",
      ".anchor_row_id",
      ".window_end",
      ".window_row_id",
      ".window_start",
      "..required_long_cols",
      "anchor_end_col",
      "anchor_row_id",
      "anchor_start_col",
      "concept_date",
      "concept_end",
      "concept_id",
      "episode_end",
      "episode_id",
      "episode_start",
      "i.derived_t0",
      "lmp_date",
      "matched_episode_end",
      "matched_episode_id",
      "matched_episode_start",
      "person_id",
      "pregnancy_end_date",
      "pregnancy_id",
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
      "..result_key_cols"
    )
  )
}
