#' Anchor study variables in batches (deprecated)
#'
#' \strong{Deprecated:} use \code{\link{anchor}(..., by = "variable")}
#' instead. This wrapper forwards to it unchanged.
#'
#' @inheritParams anchor
#'
#' @return Invisibly returns the variable ids that were processed.
#' @export
anchor_by_variable <- function(
  population,
  metadata,
  concepts,
  episodes = NULL,
  anchor_col = "T0",
  anchor_hive_path = NULL,
  chunk_size = 20L,
  staging_dir = NULL,
  staging_mode = c("memory", "disk"),
  publish = c("once", "per_chunk"),
  prepare_con = NULL
) {
  .Deprecated("anchor",
    package = "anchoR", old = "anchor_by_variable",
    msg = "Use 'anchor()' instead with the 'by' argument set to 'variable' to achieve the same effect." # nolint
  )

  staging_mode <- match.arg(staging_mode)
  publish <- match.arg(publish)

  anchor(
    population = population,
    metadata = metadata,
    concepts = concepts,
    episodes = episodes,
    anchor_col = anchor_col,
    anchor_hive_path = anchor_hive_path,
    by = "variable",
    chunk_size = chunk_size,
    staging_dir = staging_dir,
    staging_mode = staging_mode,
    publish = publish,
    prepare_con = prepare_con
  )
}

#' Anchor study variables, one selector at a time (deprecated)
#'
#' \strong{Deprecated:} use \code{\link{anchor}(..., by = "selector")}
#' instead. This wrapper forwards to it unchanged.
#'
#' @inheritParams anchor
#'
#' @return Invisibly returns the selector values that were processed.
#' @export
anchor_by_selector <- function(
  population,
  metadata,
  concepts,
  episodes = NULL,
  anchor_col = "T0",
  anchor_hive_path = NULL,
  prepare_con = NULL
) {
  .Deprecated("anchor",
    package = "anchoR", old = "anchor_by_selector",
    msg = "Use 'anchor()' instead with the 'by' argument set to 'selector' to achieve the same effect." # nolint
  )

  anchor(
    population = population,
    metadata = metadata,
    concepts = concepts,
    episodes = episodes,
    anchor_col = anchor_col,
    anchor_hive_path = anchor_hive_path,
    by = "selector",
    prepare_con = prepare_con
  )
}
