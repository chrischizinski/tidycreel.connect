# tidycreel.connect: creel_connection S3 class and creel_connect() constructor
# Phase 67: CONNECT-01, CONNECT-02

#' @noRd
#' @keywords internal
new_creel_connection <- function(backend, con, schema, status, subclass = NULL) {
  stopifnot(is.character(backend), length(backend) == 1L)
  stopifnot(inherits(schema, "creel_schema"))
  cls <- if (!is.null(subclass)) c(subclass, "creel_connection") else "creel_connection"
  structure(
    list(backend = backend, con = con, schema = schema, status = status),
    class = cls
  )
}

#' Create a creel database or file connection
#'
#' @description
#' `creel_connect()` creates a validated `creel_connection` S3 object that
#' `fetch_*()` functions dispatch on. Two backends are supported:
#'
#' - **DBI backend:** pass any `DBIConnection` object (e.g., from
#'   `DBI::dbConnect()` with the `odbc` or `duckdb` driver).
#' - **CSV backend:** pass a named list with keys `interviews`, `counts`,
#'   `catch`, `harvest_lengths`, `release_lengths` pointing to CSV file paths.
#'   File existence is checked immediately at connection creation.
#'
#' @param con A `DBIConnection` object (DBI backend) or a named list of CSV
#'   file paths (CSV backend). For the CSV backend the list must contain keys:
#'   `interviews`, `counts`, `catch`, `harvest_lengths`, `release_lengths`.
#' @param schema A `creel_schema` object created by
#'   [tidycreel::creel_schema()].
#'
#' @return A `creel_connection` S3 object.
#' @export
#' @examples
#' \dontrun{
#' schema <- tidycreel::creel_schema(
#'   survey_type = "instantaneous",
#'   interviews_table = "interviews",
#'   counts_table = "counts"
#' )
#' paths <- list(
#'   interviews      = "data/interviews.csv",
#'   counts          = "data/counts.csv",
#'   catch           = "data/catch.csv",
#'   harvest_lengths = "data/harvest_lengths.csv",
#'   release_lengths = "data/release_lengths.csv"
#' )
#' conn <- creel_connect(paths, schema)
#' }
creel_connect <- function(con, schema) {
  if (!inherits(schema, "creel_schema")) {
    cli::cli_abort(c(
      "{.arg schema} must be a {.cls creel_schema} object.",
      "i" = "Create one with {.fn tidycreel::creel_schema}."
    ))
  }
  if (inherits(con, "DBIConnection")) {
    .creel_connect_dbi(con, schema)
  } else if (is.list(con) && !is.null(names(con))) {
    .creel_connect_csv(con, schema)
  } else {
    cli::cli_abort(c(
      "{.arg con} must be a {.cls DBIConnection} or a named list of file paths.",
      "i" = "For CSV backend, pass a named list: {.code list(interviews = 'path.csv', ...)}.",
      "i" = "For database backend, pass a DBI connection created with {.fn DBI::dbConnect}."
    ))
  }
}

#' @noRd
.creel_connect_dbi <- function(con, schema) {
  new_creel_connection(
    backend  = "dbi",
    con      = con,
    schema   = schema,
    status   = "open", # dynamic: print method re-checks via DBI::dbIsValid()
    subclass = "creel_connection_sqlserver"
  )
}

#' @noRd
.creel_connect_csv <- function(paths, schema) {
  missing_files <- names(paths)[!vapply(paths, file.exists, logical(1L))]
  if (length(missing_files) > 0L) {
    bullets <- stats::setNames(
      paste0("{.file ", unlist(paths[missing_files]), "}"),
      rep("x", length(missing_files))
    )
    cli::cli_abort(c(
      "CSV file{?s} not found for table{?s}: {.val {missing_files}}",
      bullets
    ))
  }
  new_creel_connection(
    backend  = "csv",
    con      = paths,
    schema   = schema,
    status   = "ready",
    subclass = "creel_connection_csv"
  )
}
