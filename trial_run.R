rm(list = ls())
devtools::document()
devtools::load_all(".")
metadata <- picard::load("documentation/examples/study_variables.csv")
# metadata <- picard::load("documentation/examples/study_variables_multiwindow.csv") #nolint
metadata <- filter_supported_metadata(metadata)

population <- picard::load("anchoR_input/D4_MSC_nosubpop.fst")
concepts <- "anchoR_input/D3_CONCEPTS_parquet"
save_parquet_hive_path <- "anchoR_input/anchored_variables_parquet"
anchor_col <- "T0"


if (!"window_name" %in% names(metadata)) {
  metadata[, window_name := ""]
}
# Run the anchoring one study variable at a time.
anchor_by_variable(
  population = population,
  metadata = metadata,
  concepts = concepts,
  anchor_col = anchor_col,
  save_parquet_hive_path = save_parquet_hive_path
)

result <- get_anchor_result(
  metadata = metadata[1:20, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "wide"
)

new_metadata <- metadata[, is_expected_missing := FALSE]
new_metadata <- metadata[1:5, is_expected_missing := TRUE]
new_metadata <- metadata[, variable_type := "TF"]
new_metadata <- metadata[1:2, variable_type := "BOOLEAN"]
new_metadata <- metadata[5:10, variable_type := "CAT"]

result2 <- get_anchor_result(
  metadata = new_metadata[1:20, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "wide"
)

result3 <- get_anchor_result(
  metadata = new_metadata[1:20, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "wide",
  impute_missing = TRUE
)

result4 <- get_anchor_result(
  metadata = new_metadata[1:20, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "wide",
  impute_missing = TRUE,
  population = population
)

result5 <- get_anchor_result(
  metadata = new_metadata[1:20, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "wide",
  impute_missing = TRUE,
  population = population,
  cast_window = TRUE
)

result6 <- get_anchor_result(
  metadata = new_metadata[1:20, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "wide",
  impute_missing = TRUE,
  population = population,
  only_date = TRUE
)

result7 <- get_anchor_result(
  metadata = new_metadata[1:20, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "wide",
  impute_missing = TRUE,
  population = population,
  only_date = TRUE,
  cast_window = TRUE
)

result8 <- get_anchor_result(
  metadata = new_metadata[19, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "narrow"
)

# Run the anchoring one study variable at a time.
anchor_by_variable(
  population = population,
  metadata = metadata,
  concepts = concepts,
  anchor_col = anchor_col,
  save_parquet_hive_path = anchor_hive_path
)
result9 <- get_anchor_result(
  metadata = new_metadata[37, ],
  anchor_hive_path = anchor_hive_path,
  result_shape = "narrow"
)
