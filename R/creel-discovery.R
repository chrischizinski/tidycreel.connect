# tidycreel.connect: list_creels() discovery generic and S3 methods


#' List all available creel surveys on a connection
#'
#' @description
#' Returns a data frame of all surveys available on the connected REST API.
#' Not supported for CSV or SQL Server connections.
#'
#' @param conn A `creel_connection` object created by [creel_connect_api()].
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with columns:
#'   `creel_uid` (character), `title` (character), `description` (character),
#'   `active` (logical), `data_complete` (logical), `comments` (character).
#' @export
list_creels <- function(conn, ...) UseMethod("list_creels")


#' @export
list_creels.creel_connection_api <- function(conn, ...) {
  # D-01: no UID filter for discovery -- pass no_uid_filter = TRUE to .api_fetch()
  raw_df <- .api_fetch(conn$con, "discovery", no_uid_filter = TRUE)

  # Early return for empty API response -- avoids column-type issues downstream
  if (nrow(raw_df) == 0L) {
    return(tibble::tibble(
      creel_uid     = character(0),
      title         = character(0),
      description   = character(0),
      active        = logical(0),
      data_complete = logical(0),
      comments      = character(0)
    ))
  }

  # Field names come from the connection's api_field_map$discovery, never from
  # creel_schema (D-03): the schema maps CSV/SQL columns, not JSON keys. No
  # default names them -- a discovery payload's shape is a property of the
  # deployment.
  fm <- conn$con$api_field_map$discovery
  api_rename_map <- c(
    creel_uid     = fm$creel_uid,
    title         = fm$title,
    description   = fm$description,
    active        = fm$active,
    data_complete = fm$data_complete,
    comments      = fm$comments
  )
  api_rename_map <- api_rename_map[!is.na(api_rename_map) & nzchar(api_rename_map)]
  # nolint next: object_usage_linter reads the 3-arg call as one argument too
  # many; the helper takes (df, map, table, also_used).
  df <- .rename_api_to_canonical(raw_df, api_rename_map, "discovery") # nolint

  if ("creel_uid"     %in% names(df)) df$creel_uid     <- as.character(df$creel_uid)
  if ("title"         %in% names(df)) df$title         <- as.character(df$title)
  if ("description"   %in% names(df)) df$description   <- as.character(df$description)
  if ("active"        %in% names(df)) df$active        <- as.logical(df$active)
  if ("data_complete" %in% names(df)) df$data_complete <- as.logical(df$data_complete)
  if ("comments"      %in% names(df)) df$comments      <- as.character(df$comments)

  # Ensure all documented columns are present; warn and fill missing ones with typed NA
  expected_cols <- list(
    creel_uid     = NA_character_,
    title         = NA_character_,
    description   = NA_character_,
    active        = NA,
    data_complete = NA,
    comments      = NA_character_
  )
  for (col in names(expected_cols)) {
    if (!col %in% names(df)) {
      cli::cli_warn("API response missing expected field {.field {col}}; filling with NA.")
      df[[col]] <- expected_cols[[col]]
    }
  }

  tibble::as_tibble(df)
}


#' @export
list_creels.creel_connection_csv <- function(conn, ...) {
  cli::cli_abort(c(
    "{.fn list_creels} is not supported for {.cls creel_connection_csv} connections.",
    "i" = "Use {.fn creel_connect_api} to connect to a REST API that supports discovery."
  ))
}


#' @export
list_creels.creel_connection_sqlserver <- function(conn, ...) {
  cli::cli_abort(c(
    "{.fn list_creels} is not supported for {.cls creel_connection_sqlserver} connections.",
    "i" = "Use {.fn creel_connect_api} to connect to a REST API that supports discovery."
  ))
}

#' Search available creel surveys by keyword
#'
#' @description
#' Calls [list_creels()] and filters the result client-side to surveys whose
#' `title` or `description` contains `keyword` (case-insensitive). Not
#' supported for CSV or SQL Server connections.
#'
#' @param conn A `creel_connection` object created by [creel_connect_api()].
#' @param keyword A single non-empty character string to search for.
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with the same column shape as [list_creels()],
#'   filtered to matching surveys.
#' @export
search_creels <- function(conn, keyword, ...) UseMethod("search_creels")


#' @export
search_creels.creel_connection_api <- function(conn, keyword, ...) {
  if (!is.character(keyword) || length(keyword) != 1L || !nzchar(keyword)) {
    cli::cli_abort(c(
      "{.arg keyword} must be a single non-empty character string.",
      "i" = "Received: {.val {keyword}}"
    ))
  }

  df <- list_creels(conn)

  # Client-side filter -- D-04: no extra API round trip
  # D-05: search title and description only; D-06: case-insensitive
  # tolower() + fixed=TRUE: safe with regex metacharacters (ignore.case is silently
  # dropped when fixed=TRUE in R, so we normalise both sides manually)
  kw_lower          <- tolower(keyword)
  match_title       <- grepl(kw_lower, tolower(df$title),       fixed = TRUE)
  match_description <- grepl(kw_lower, tolower(df$description), fixed = TRUE)
  df[match_title | match_description, , drop = FALSE]
}


#' @export
search_creels.creel_connection_csv <- function(conn, keyword, ...) {
  cli::cli_abort(c(
    "{.fn search_creels} is not supported for {.cls creel_connection_csv} connections.",
    "i" = "Use {.fn creel_connect_api} to connect to a REST API that supports discovery."
  ))
}


#' @export
search_creels.creel_connection_sqlserver <- function(conn, keyword, ...) {
  cli::cli_abort(c(
    "{.fn search_creels} is not supported for {.cls creel_connection_sqlserver} connections.",
    "i" = "Use {.fn creel_connect_api} to connect to a REST API that supports discovery."
  ))
}
