# tidycreel.connect: creel_connection_api subclass, constructor, and HTTP helpers

#' Create a creel REST API connection
#'
#' @description
#' `creel_connect_api()` creates a `creel_connection` object that fetches data
#' from a REST API returning JSON arrays. The default endpoint paths match the
#' UNL/AGENCY creel survey API, but every path can be overridden to work with any
#' compatible service.
#'
#' Requests follow the pattern:
#' ```
#' GET {base_url}/{endpoint}?{uid_param}={uid1,uid2,...}
#' ```
#'
#' ## Authentication
#'
#' Three auth modes are supported via the `auth` argument:
#' - `NULL` -- no authentication (default)
#' - `list(type = "bearer", token = "...")` -- `Authorization: Bearer` header
#' - `list(type = "api_key", key = "...", header = "X-API-Key")` -- arbitrary
#'   header name (defaults to `"X-API-Key"` if `header` is omitted)
#'
#' Credentials should be read from environment variables rather than stored
#' as plain strings:
#' ```r
#' auth = list(type = "bearer", token = Sys.getenv("CREEL_API_TOKEN"))
#' ```
#'
#' @param base_url Base URL of the API, with or without a trailing slash.
#'   Example: `"http://api.example.org/api/"`.
#' @param creel_uids Character vector of one or more creel UIDs to query.
#' @param schema A `creel_schema` object created by [tidycreel::creel_schema()].
#' @param uid_param Query parameter name for the creel UID list.
#'   Default: `"Creel_UIDs"`.
#' @param endpoints Named list of endpoint path overrides. Valid names:
#'   `interviews`, `counts`, `catch`, `harvest_lengths`, `release_lengths`.
#'   Unspecified names retain their defaults.
#' @param auth Authentication spec (see Description). Default: `NULL`.
#'
#' @return A `creel_connection` S3 object with subclass `creel_connection_api`.
#' @export
#' @examples
#' \dontrun{
#' schema <- tidycreel::creel_schema(survey_type = "instantaneous")
#'
#' # No auth
#' conn <- creel_connect_api(
#'   base_url   = "http://api.example.org/api/",
#'   creel_uids = "90f5375c-afe0-e511-80bf-0050568372f9",
#'   schema     = schema
#' )
#'
#' # Bearer token auth, two surveys
#' conn <- creel_connect_api(
#'   base_url   = "https://api.example.com/creel/",
#'   creel_uids = c("uid-1", "uid-2"),
#'   schema     = schema,
#'   auth       = list(type = "bearer", token = Sys.getenv("CREEL_TOKEN"))
#' )
#'
#' # Custom endpoint paths (non-AGENCY API)
#' conn <- creel_connect_api(
#'   base_url  = "https://api.example.com/",
#'   creel_uids = "survey-001",
#'   schema    = schema,
#'   uid_param = "survey_id",
#'   endpoints = list(
#'     interviews = "v2/interviews",
#'     counts     = "v2/counts"
#'   )
#' )
#' }
creel_connect_api <- function(
    base_url,
    creel_uids,
    schema,
    uid_param = "Creel_UIDs",
    endpoints = NULL,
    auth      = NULL
) {
  if (!inherits(schema, "creel_schema")) {
    cli::cli_abort(c(
      "{.arg schema} must be a {.cls creel_schema} object.",
      "i" = "Create one with {.fn tidycreel::creel_schema}."
    ))
  }
  if (!is.character(base_url) || length(base_url) != 1L || !nzchar(base_url)) {
    cli::cli_abort("{.arg base_url} must be a non-empty single string.")
  }
  if (!is.character(creel_uids) || length(creel_uids) == 0L || !all(nzchar(creel_uids))) {
    cli::cli_abort("{.arg creel_uids} must be a non-empty character vector with no blank entries.")
  }
  if (!is.character(uid_param) || length(uid_param) != 1L || !nzchar(uid_param)) {
    cli::cli_abort("{.arg uid_param} must be a non-empty single string.")
  }
  if (!is.null(auth)) {
    .validate_api_auth(auth)
  }

  if (!endsWith(base_url, "/")) base_url <- paste0(base_url, "/")

  resolved_endpoints <- .default_api_endpoints()
  if (!is.null(endpoints)) {
    valid_names <- names(resolved_endpoints)
    bad_names   <- setdiff(names(endpoints), valid_names)
    if (length(bad_names) > 0L) {
      cli::cli_abort(c(
        "Unknown endpoint name{?s} in {.arg endpoints}: {.val {bad_names}}",
        "i" = "Valid names: {.val {valid_names}}"
      ))
    }
    resolved_endpoints[names(endpoints)] <- endpoints
  }

  new_creel_connection(
    backend  = "api",
    con      = list(
      base_url   = base_url,
      creel_uids = creel_uids,
      uid_param  = uid_param,
      endpoints  = resolved_endpoints,
      auth       = auth
    ),
    schema   = schema,
    status   = "ready",
    subclass = "creel_connection_api"
  )
}

# Default endpoint paths matching the UNL/AGENCY creel survey API
#' @noRd
.default_api_endpoints <- function() {
  list(
    interviews      = "AnalysisData/InterviewRecords",
    counts          = "AnalysisData/CountRecords",
    catch           = "AnalysisData/CatchRecords",
    harvest_lengths = "AnalysisData/HarvestLengthRecords",
    release_lengths = "AnalysisData/ReleaseLengthRecords",
    discovery       = "AnalysisData/CreelList" # TODO: confirm endpoint path with live API
  )
}

# Validate an auth spec list -- aborts on any invalid configuration
#' @noRd
.validate_api_auth <- function(auth) {
  if (!is.list(auth) || is.null(auth$type)) {
    cli::cli_abort(c(
      "{.arg auth} must be a named list with a {.field type} entry.",
      "i" = "Valid types: {.val bearer}, {.val api_key}."
    ))
  }
  if (auth$type == "bearer") {
    if (is.null(auth$token) || !nzchar(auth$token)) {
      cli::cli_abort("{.field auth$token} must be a non-empty string for bearer auth.")
    }
  } else if (auth$type == "api_key") {
    if (is.null(auth$key) || !nzchar(auth$key)) {
      cli::cli_abort("{.field auth$key} must be a non-empty string for api_key auth.")
    }
  } else {
    cli::cli_abort(c(
      "{.field auth$type} must be {.val bearer} or {.val api_key}.",
      "x" = "Got: {.val {auth$type}}"
    ))
  }
  invisible(auth)
}

# Perform a single authenticated API GET and return a plain data.frame.
# Returns a 0-row data.frame if the API returns an empty array.
#' @noRd
.api_fetch <- function(con_info, endpoint_key, no_uid_filter = FALSE) {
  endpoint <- con_info$endpoints[[endpoint_key]]
  url      <- paste0(con_info$base_url, endpoint)

  req <- httr2::request(url)
  if (!no_uid_filter) {
    uid_str    <- paste(con_info$creel_uids, collapse = ",")
    query_args <- stats::setNames(list(uid_str), con_info$uid_param)
    req        <- do.call(httr2::req_url_query, c(list(req), query_args))
  }

  auth <- con_info$auth
  # WARNING: Do NOT print auth or req objects after this point -- auth$token will
  # leak to logs. Use httr2::req_dry_run() for debugging; httr2 redacts auth headers.
  if (!is.null(auth)) {
    if (auth$type == "bearer") {
      req <- httr2::req_auth_bearer_token(req, auth$token)
    } else if (auth$type == "api_key") {
      hdr      <- if (!is.null(auth$header) && nzchar(auth$header)) auth$header else "X-API-Key"
      hdr_args <- stats::setNames(list(auth$key), hdr)
      req      <- do.call(httr2::req_headers, c(list(req), hdr_args))
    }
  }

  # D-10, D-11: retry on 429/503, max 3 tries; explicit is_transient so retry
  # fires regardless of the req_error policy applied below (httr2 1.2.2 behaviour)
  req  <- httr2::req_retry(
    req,
    max_tries    = 3L,
    is_transient = \(resp) httr2::resp_status(resp) %in% c(429L, 503L)
  )
  # D-13: disable httr2 auto-error AFTER retry is wired; manual cli_abort() controls format
  req  <- httr2::req_error(req, is_error = \(resp) FALSE)
  resp <- httr2::req_perform(req)

  status <- httr2::resp_status(resp)
  if (status >= 400L) {
    # D-12: human-readable error with status, endpoint path, and body
    body_text <- tryCatch(
      {
        raw <- httr2::resp_body_raw(resp)
        if (length(raw) == 0L) {
          ""
        } else {
          b <- httr2::resp_body_json(resp, simplifyVector = FALSE)
          paste(utils::capture.output(utils::str(b)), collapse = "\n")
        }
      },
      error = function(e) tryCatch(httr2::resp_body_string(resp), error = function(e2) "")
    )
    cli::cli_abort(c(
      "API request failed [{status}]",
      "i" = "Endpoint: {endpoint}",
      "x" = body_text
    ))
  }

  result <- httr2::resp_body_json(resp, simplifyVector = TRUE)

  if (is.null(result) || (is.list(result) && length(result) == 0L)) {
    return(data.frame())
  }
  df <- as.data.frame(result)
  names(df) <- trimws(names(df))
  df
}

# Parse a date column that may arrive as "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM:SS"
#' @noRd
.parse_api_date <- function(x) {
  result  <- suppressWarnings(as.Date(x, tryFormats = c("%Y-%m-%d", "%m/%d/%Y")))
  na_mask <- is.na(result) & !is.na(x)
  if (any(na_mask)) {
    result[na_mask] <- as.Date(strptime(x[na_mask], "%Y-%m-%dT%H:%M:%S"))
  }
  result
}
