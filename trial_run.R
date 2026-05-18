rm(list = ls())
devtools::document()
devtools::load_all(".")
metadata <- picard::load("anchoR_input/study_variables.csv")
metadata <- filter_supported_metadata(metadata)


population <- picard::load("anchoR_input/D4_MSC.fst")
concepts <- "anchoR_input/D3_CONCEPTS_parquet"
anchor_col <- "T0"


# Run the anchor function
result <- anchor(
  population = population,
  metadata = metadata,
  concepts = concepts,
  anchor_col = anchor_col,
  keep_all = FALSE,
  package = "anchoR"
)

head(result)
