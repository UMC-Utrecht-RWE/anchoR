test_that("validate_anchor_inputs standardizes metadata names", {
  validated <- validate_anchor_inputs(
    population = example_population(),
    metadata = example_metadata(),
    concepts = example_concepts()
  )

  expect_true(all(
    c(
      "selector",
      "window_start_offset",
      "window_end_offset",
      "anchor_start_col",
      "anchor_end_col"
    ) %in% names(validated$metadata)
  ))
})

test_that("validate_anchor_inputs fails on missing anchor columns", {
  metadata <- data.table::data.table(
    variable_id = "x",
    concept_id = "Y",
    selector = "LATEST",
    start_look_back = -1L,
    end_look_back = 0L,
    anchor_date_start = "missing_col",
    anchor_date_end = "anchor_date"
  )

  expect_error(
    validate_anchor_inputs(example_population(), metadata, example_concepts()),
    "missing anchor columns"
  )
})
