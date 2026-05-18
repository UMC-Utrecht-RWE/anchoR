run_selector_query <- function(con, selector, package = "anchoR") {
  DBI::dbGetQuery(con, read_selector_sql(selector, package = package))
}
