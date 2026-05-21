library(data.table)
# wrangling different metadatas into the same format
metadata <- picard::load("anchoR_input/study_variables.csv")
aesi_metadata <- picard::load(
  "anchoR_input/aesi_windows_metadata 1.csv",
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
if (!"window" %in% names(metadata)) {
  metadata$window <- "lookback"
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
for (col in c("start", "end")) {
  metadata[, (col) := as.numeric(get(col))]
  aesi_metadata[, (col) := as.numeric(get(col))]
}

tmp <- metadata[
  aesi_metadata,
  on = "variable_id",
  allow.cartesian = TRUE
]

# check if lookback windows defined differently, throw warning,
# inherit aesi definition
tmp_lookback <- tmp[window == "lookback"]

start_diff <- !is.na(tmp_lookback$start) & !is.na(tmp_lookback$i.start) &
  tmp_lookback$start != tmp_lookback$i.start
end_diff <- !is.na(tmp_lookback$end) & !is.na(tmp_lookback$i.end) &
  tmp_lookback$end != tmp_lookback$i.end


if (any(start_diff | end_diff, na.rm = TRUE)) {
  warning(
    "Mismatch detected between metadata and
    aesi_metadata for start/end for \n",
    paste(
      c(unique(tmp[start_diff | end_diff, "variable_id"]))$variable_id,
      collapse = ","
    ),
    "\n ovewriting with aesi_windows_metadata version"
  )
}
delete_cols <- c(
  "start", "end", "date_extraction_func", "label", "anchor", "window"
)
tmp[, (delete_cols) := NULL]
setnames(tmp, paste0("i.", delete_cols), delete_cols, skip_absent = TRUE)

# ensure that non-lookback data-types are set to DATE
tmp[window != "lookback", data_type := "DATE"]

# replace aesi rows in study variables with processed aesi rows
metadata <- metadata[
  !variable_id %in% tmp$variable_id
]

metadata <- rbindlist(
  list(metadata, tmp),
  use.names = TRUE,
  fill = TRUE
)

picard::save(
  metadata,
  "anchoR_input/study_variables_multiwindow.csv"
)
