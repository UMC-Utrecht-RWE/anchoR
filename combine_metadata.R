rm(list = ls())
library(data.table)
# wrangling different metadatas into the same format
metadata <- picard::load("documentation/examples/study_variables.csv")
aesi_metadata <- picard::load(
  "documentation/examples/aesi_windows_metadata.csv",
  sep = ";"
)

# change column names of metadata to be shorter, match aesi_metadata
names(metadata)[
  names(metadata) == "variable_description"
] <- "label"
names(metadata)[
  names(metadata) == "start_look_back"
] <- "start"
names(metadata)[
  names(metadata) == "end_look_back"
] <- "end"

# make explicit any information which is typically implicit in study_variables;
# lookback, anchor
if (!"window_name" %in% names(metadata)) {
  metadata$window_name <- "covariate"
}
if (!"anchor" %in% names(metadata)) {
  metadata$anchor <- "T0"
}


# check if all aesi's are present in study variables already, if not remove them
missing_vars <- setdiff(
  unique(aesi_metadata$variable_id), metadata$variable_id
)
if (length(missing_vars > 0)) {
  warning(
    "the following variables are not present in study and so are removed:",
    paste(missing_vars, collapse = ",")
  )
}

aesi_metadata <- aesi_metadata[!aesi_metadata$variable_id %in% missing_vars, ]

# now, add the aesi_metadata additional rows to study variables
# first, inherit missing columns from study variables
data.table::setDT(aesi_metadata)
data.table::setDT(metadata)

# fix type mismatches
for (col in c("start_offset", "end_offset")) {
  metadata[, (col) := as.numeric(get(col))]
  aesi_metadata[, (col) := as.numeric(get(col))]
}

# merge objects together
tmp <- metadata[
  aesi_metadata,
  on = "variable_id",
  allow.cartesian = TRUE
]

# tidy up merged object
delete_cols <- c(
  "start_offset", "end_offset", "date_extraction_func", "label", "anchor"
)
tmp[, (delete_cols) := NULL]
setnames(tmp, paste0("i.", delete_cols), delete_cols, skip_absent = TRUE)

# ensure that non-lookback data-types are set to DATE
tmp[!window %in% c("lookback", "covariate"), data_type := "DATE"]

metadata <- rbindlist(
  list(metadata, tmp),
  use.names = TRUE,
  fill = TRUE
)

picard::save(
  metadata,
  "documentation/examples/study_variables_multiwindow.csv"
)
