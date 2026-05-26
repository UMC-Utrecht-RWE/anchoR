rm(list = ls())
devtools::document()
devtools::load_all(".")
metadata <- picard::load("anchoR_input/study_variables.csv")

metadata <- filter_supported_metadata(metadata)

population <- picard::load("anchoR_input/D4_MSC_nosubpop.fst")
concepts <- "anchoR_input/D3_CONCEPTS_parquet"
anchor_hive_path <- "anchoR_input/anchored_variables_parquet"
anchor_col <- "T0"
keep_all <- FALSE


# Run the anchoring one study variable at a time.
anchor_by_variable(
  population = population,
  metadata = metadata,
  concepts = concepts,
  anchor_col = anchor_col,
  keep_all = keep_all,
  save_parquet_hive_path = anchor_hive_path
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
