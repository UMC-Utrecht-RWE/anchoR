rm(list = ls())
devtools::install()
devtools::document()
devtools::load_all(".")
study_variable <- picard::load("anchoR_input/study_variables.csv")
d4_msc <- picard::load("anchoR_input/D4_MSC.fst")
con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")

view_name <- "concepts"
DBI::dbExecute(
  con,
  glue::glue(
    "CREATE OR REPLACE VIEW {view_name} AS
      SELECT *
      FROM read_parquet(
        ['anchoR_input/D3_CONCEPTS_parquet/*/*.parquet'],
        hive_partitioning = true,
        union_by_name     = true
      )"
  )
)

DBI::dbListTables(con)
concepts <- DBI::dbReadTable(con, view_name)

# Run the anchor function
result <- anchor(
  population = d4_msc,
  metadata = study_variable,
  concepts = concepts,
  anchor_col = "T0", # Using T0 from d4_msc as the index date
  keep_all = FALSE,
  package = "anchoR"
)

head(result)
