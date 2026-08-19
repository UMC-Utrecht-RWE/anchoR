testthat::test_that("anchor_by_variable() warns and forwards to anchor()", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- minimal_metadata()[variable_id %in% c("cov_latest", "cov_count")]

  testthat::expect_warning(
    processed <- anchor_by_variable(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path,
      chunk_size = 1
    ),
    class = "deprecatedWarning"
  )

  testthat::expect_setequal(processed, c("cov_latest", "cov_count"))

  anchored <- read_anchor_hive(hive_path)
  testthat::expect_setequal(
    unique(anchored$variable_id), c("cov_latest", "cov_count")
  )
})

testthat::test_that("anchor_by_selector() warns and forwards to anchor()", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- minimal_metadata()

  testthat::expect_warning(
    processed <- anchor_by_selector(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    ),
    class = "deprecatedWarning"
  )

  testthat::expect_setequal(processed, c("LATEST", "COUNT", "EARLIEST"))

  anchored <- read_anchor_hive(hive_path)
  # lab_range's concept (LAB_X) never appears in minimal_concepts(), so it
  # never produces a match and gets no partition at all.
  testthat::expect_setequal(
    unique(anchored$variable_id), c("cov_latest", "cov_count")
  )
})
