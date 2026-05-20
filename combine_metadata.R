library(data.table)
# wrangling different metadatas into the same format
study_variables_meta <- picard::load("anchoR_input/study_variables.csv")
aesi_meta <- picard::load("anchoR_input/aesi_windows_metadata.csv", sep = ";")

# change column names of study_variables_meta to be shorter, match aesi_meta
names(study_variables_meta)[names(study_variables_meta) == "variable_description"] <- "label"
names(study_variables_meta)[names(study_variables_meta) == "start_look_back"] <- "start"
names(study_variables_meta)[names(study_variables_meta) == "end_look_back"] <- "end"

# make explicit any information which is typically implicit in study_variables; lookback, anchor
if(!"window" %in% names(study_variables_meta)){ study_variables_meta$window <- "lookback" }
if(!"anchor" %in% names(study_variables_meta)){ study_variables_meta$anchor <- "T0" }


# check if all aesi's are present in study variables already, if not, remove them
missing_vars <- setdiff(unique(aesi_meta$variable_id), study_variables_meta$variable_id )
if(length(missing_vars > 0)){
  warning("the following variables are not present in study variables and so are removed:",
          paste(missing_vars, collapse = ","))
}

aesi_meta <- aesi_meta[!aesi_meta$variable_id %in% missing_vars,]

# now, add the aesi_meta additional rows to study variables
# first, inherit missing columns from study variables
setDT(aesi_meta)
setDT(study_variables_meta)

# fix type mismatches
for(col in c("start","end")){
    study_variables_meta[, (col) := as.numeric(get(col))]
    aesi_meta[, (col) := as.numeric(get(col))]
}

tmp <- study_variables_meta[
  aesi_meta,
  on = "variable_id",
  allow.cartesian = TRUE
]

# check if lookback windows defined differently, throw warning, inherit aesi definition
tmp_lookback <- tmp[window == "lookback"]
start_diff <- !is.na(tmp_lookback$start) & !is.na(tmp_lookback$i.start) & tmp_lookback$start != tmp_lookback$i.start
end_diff   <- !is.na(tmp_lookback$end)   & !is.na(tmp_lookback$i.end)   & tmp_lookback$end   != tmp_lookback$i.end


if (any(start_diff | end_diff, na.rm = TRUE)) {
  warning("Mismatch detected between study_variables_meta and aesi_meta for start/end for \n",
          paste(c(unique(tmp[start_diff | end_diff, "variable_id"]))$variable_id, collapse = ","),
          "\n ovewriting with aesi_windows_metadata version")
}
delete_cols <- c("start","end","date_extraction_func","label","anchor", "window")
tmp[,(delete_cols) := NULL]
setnames(tmp, paste0("i.",delete_cols),delete_cols, skip_absent = TRUE)

# replace aesi rows in study variables with processed aesi rows
study_variables_meta <- study_variables_meta[
  !variable_id %in% tmp$variable_id
]

study_variables_meta <- rbindlist(
  list(study_variables_meta, tmp),
  use.names = TRUE,
  fill = TRUE
)

picard::save(study_variables_meta, "anchoR_input/study_variables_multiwindow.csv")
