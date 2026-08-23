# tidycreel.connect: creel_connection_api subclass, constructor, and HTTP helpers

#' Create a creel REST API connection
#'
#' @description
#' `creel_connect_api()` creates a `creel_connection` object that fetches data
#' from a REST API returning JSON arrays.
#'
#' Requests follow the pattern:
#' ```
#' GET {base_url}/{endpoint}?{uid_param}={uid1,uid2,...}
#' ```
#'
#' ## No API is assumed
#'
#' The package ships no endpoint paths and no field names for any organisation's
#' API: both `endpoints` and `api_field_map` are required, and the call aborts
#' without them. A creel API's paths and JSON keys are properties of that
#' deployment, not of this package, and a built-in default would quietly decode
#' one agency's payload while misreading everyone else's.
#'
#' Keep the two together in a YAML profile outside your analysis code and load
#' it with [creel_connect_from_yaml()]. A commented template ships with the
#' package:
#' ```r
#' system.file("extdata", "api-profile-example.yml", package = "tidycreel.connect")
#' ```
#'
#' ## Requests are read-only
#'
#' Every request this connection makes is a `GET`. Nothing is posted, patched
#' or deleted, and no file is written locally, so pointing it at a production
#' service cannot modify anything there.
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
#'   Example: `"https://api.example.org/creel/"`.
#' @param creel_uids Character vector of one or more creel UIDs to query.
#' @param schema A `creel_schema` object created by [tidycreel::creel_schema()].
#' @param uid_param Query parameter name for the creel UID list. Example:
#'   `"survey_id"`.
#' @param endpoints Named list of endpoint paths, relative to `base_url`.
#'   **Required.** Valid names: `interviews`, `counts`, `catch`,
#'   `harvest_lengths`, `release_lengths`, `discovery`. Supply the endpoints
#'   you intend to fetch; the matching `fetch_*()` aborts for any you omit.
#' @param auth Authentication spec (see Description). Default: `NULL`.
#' @param api_field_map Named list of raw JSON field names, keyed by endpoint
#'   (`interviews`, `counts`, `catch`, `harvest_lengths`, `release_lengths`,
#'   `discovery`). **Required.** Within each endpoint, name the raw field that
#'   holds each canonical quantity, e.g.
#'   `list(interviews = list(date = "SurveyDate", n_anglers = "PartySize"))`.
#'   The optional interview fields -- `n_anglers`, `angler_type`, `site`,
#'   `circuit`, `n_counted`, `n_interviewed` -- are carried only when named
#'   here; see [fetch_interviews()] for what each one is used for.
#'
#' @return A `creel_connection` S3 object with subclass `creel_connection_api`.
#' @export
#' @examples
#' \dontrun{
#' schema <- tidycreel::creel_schema(survey_type = "instantaneous")
#'
#' # Endpoints and field names both describe YOUR API, so both are required.
#' conn <- creel_connect_api(
#'   base_url   = "https://api.example.org/creel/",
#'   creel_uids = "survey-001",
#'   schema     = schema,
#'   uid_param  = "survey_id",
#'   endpoints  = list(
#'     interviews = "v2/interviews",
#'     counts     = "v2/counts"
#'   ),
#'   api_field_map = list(
#'     interviews = list(
#'       interview_uid = "InterviewID",
#'       date          = "SurveyDate",
#'       trip_status   = "TripStatus",
#'       effort_hours  = "HoursFished",
#'       n_anglers     = "PartySize"
#'     ),
#'     counts = list(
#'       date         = "SurveyDate",
#'       bank_anglers = "ShoreAnglers"
#'     )
#'   )
#' )
#'
#' # Usual practice: keep both in a YAML profile outside your code.
#' conn <- creel_connect_from_yaml("~/.config/tidycreel/my-api.yml")
#'
#' # Bearer token auth
#' conn <- creel_connect_api(
#'   base_url      = "https://api.example.org/creel/",
#'   creel_uids    = c("uid-1", "uid-2"),
#'   schema        = schema,
#'   endpoints     = my_endpoints,
#'   api_field_map = my_field_map,
#'   auth          = list(type = "bearer", token = Sys.getenv("CREEL_TOKEN"))
#' )
#' }
creel_connect_api <- function(
    base_url,
    creel_uids,
    schema,
    uid_param,
    endpoints,
    auth          = NULL,
    api_field_map
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
  # uid_param, endpoints and api_field_map all describe one deployment's API.
  # They are required rather than defaulted: a default would be one
  # organisation's contract shipped as though it were everyone's, and it would
  # decode their payload silently while misreading every other.
  if (missing(uid_param) || is.null(uid_param)) {
    cli::cli_abort(c(
      "{.arg uid_param} is required.",
      "i" = "Name the query parameter your API expects, e.g. {.code uid_param = \"survey_id\"}."
    ))
  }
  if (!is.character(uid_param) || length(uid_param) != 1L || !nzchar(uid_param)) {
    cli::cli_abort("{.arg uid_param} must be a non-empty single string.")
  }
  if (missing(endpoints) || is.null(endpoints)) {
    .abort_api_contract_missing("endpoints")
  }
  if (missing(api_field_map) || is.null(api_field_map)) {
    .abort_api_contract_missing("api_field_map")
  }
  if (!is.null(auth)) {
    .validate_api_auth(auth)
  }

  # Schema col-mappings configure CSV/SQL column names, not API JSON field
  # names; the API backend reads api_field_map instead.
  #
  # `strata_cols` is deliberately NOT in this list. It is the one schema field
  # the API backend does read, and it does not name a raw JSON field: its
  # *names* are the caller's own design-facing columns, which `add_counts()`
  # matches on, while the raw field each comes from is looked up in
  # `api_field_map` as usual (GH #171). Adding it here would warn that a
  # working, required declaration is ignored.
  #
  # `value_maps` is out for the same reason: it maps a column's *values*, not
  # its field name, so it is backend-independent and the API path reads it
  # exactly as the CSV path does (GH #128).
  schema_mapping_fields <- c(
    "interview_uid_col", "date_col", "catch_col", "effort_col",
    "trip_status_col", "catch_uid_col", "species_col", "catch_count_col",
    "catch_type_col", "length_uid_col", "length_mm_col", "length_bin_col",
    "length_count_col", "length_type_col",
    "count_time_col",
    "bank_anglers_col", "angler_boats_col", "non_ang_boats_col",
    "n_anglers_col", "angler_type_col", "site_col", "circuit_col",
    "n_counted_col", "n_interviewed_col"
  )
  has_schema_mappings <- any(
    vapply(schema_mapping_fields, function(f) !is.null(schema[[f]]), logical(1L))
  )
  if (has_schema_mappings) {
    cli::cli_warn(c(
      "{.arg schema} column mappings are ignored by the API backend.",
      "i" = "Name the raw JSON fields in {.arg api_field_map} instead."
    ))
  }

  if (!endsWith(base_url, "/")) base_url <- paste0(base_url, "/")

  resolved_endpoints <- .validate_api_endpoints(endpoints)
  resolved_field_map <- .validate_api_field_map(api_field_map)

  new_creel_connection(
    backend  = "api",
    con      = list(
      base_url      = base_url,
      creel_uids    = creel_uids,
      uid_param     = uid_param,
      endpoints     = resolved_endpoints,
      auth          = auth,
      api_field_map = resolved_field_map
    ),
    schema   = schema,
    status   = "ready",
    subclass = "creel_connection_api"
  )
}

# The endpoint keys this package knows how to fetch. Paths and field names for
# any actual deployment are the caller's to supply -- this is the vocabulary,
# not a configuration.
#' @noRd
.api_endpoint_names <- function() {
  c("interviews", "counts", "catch", "harvest_lengths", "release_lengths", "discovery")
}

# Shared abort for a missing half of the API contract.
#' @noRd
.abort_api_contract_missing <- function(arg) {
  template <- "system.file(\"extdata\", \"api-profile-example.yml\", package = \"tidycreel.connect\")" # nolint: object_usage_linter, line_length_linter
  cli::cli_abort(c(
    "{.arg {arg}} is required.",
    "i" = "This package ships no endpoint paths or field names for any API: \\
           both describe one deployment, and a built-in default would decode \\
           one payload while silently misreading others.",
    "i" = "Start from the template profile: {.code {template}}",
    "i" = "Or load a saved profile with {.fn creel_connect_from_yaml}."
  ))
}

# Validate the endpoint list: known names, single non-empty strings.
#' @noRd
.validate_api_endpoints <- function(endpoints) {
  if (!is.list(endpoints) || length(endpoints) == 0L || is.null(names(endpoints))) {
    cli::cli_abort("{.arg endpoints} must be a non-empty named list of endpoint paths.")
  }
  valid_names <- .api_endpoint_names()
  bad_names   <- setdiff(names(endpoints), valid_names)
  if (length(bad_names) > 0L) {
    cli::cli_abort(c(
      "Unknown endpoint name{?s} in {.arg endpoints}: {.val {bad_names}}",
      "i" = "Valid names: {.val {valid_names}}"
    ))
  }
  bad_paths <- names(endpoints)[!vapply(endpoints, function(p) {
    is.character(p) && length(p) == 1L && nzchar(p)
  }, logical(1L))]
  if (length(bad_paths) > 0L) {
    cli::cli_abort(
      "Endpoint path{?s} must be a non-empty single string: {.field {bad_paths}}"
    )
  }
  endpoints
}

# Validate the field map: known endpoint names, each a named list of single
# non-empty strings. Which canonical fields must be present is decided per
# fetch by the validators, not here -- an API that serves only counts should
# not have to describe an interviews endpoint it does not have.
#' @noRd
.validate_api_field_map <- function(field_map) {
  if (!is.list(field_map) || length(field_map) == 0L || is.null(names(field_map))) {
    cli::cli_abort(c(
      "{.arg api_field_map} must be a non-empty list keyed by endpoint.",
      "i" = "For example {.code list(interviews = list(date = \"SurveyDate\"))}."
    ))
  }
  valid_names   <- .api_endpoint_names()
  bad_endpoints <- setdiff(names(field_map), valid_names)
  if (length(bad_endpoints) > 0L) {
    cli::cli_abort(c(
      "Unknown endpoint{?s} in {.arg api_field_map}: {.val {bad_endpoints}}",
      "i" = "Valid endpoint names: {.val {valid_names}}"
    ))
  }
  for (ep in names(field_map)) {
    entry <- field_map[[ep]]
    if (!is.list(entry) || is.null(names(entry))) {
      cli::cli_abort(
        "{.arg api_field_map}${.field {ep}} must be a named list of raw field names."
      )
    }
    bad_fields <- names(entry)[!vapply(entry, function(f) {
      is.character(f) && length(f) == 1L && nzchar(f)
    }, logical(1L))]
    if (length(bad_fields) > 0L) {
      cli::cli_abort(c(
        "Every raw field name must be a non-empty single string.",
        "x" = "In {.arg api_field_map}${ep}: {.field {bad_fields}}"
      ))
    }
  }
  field_map
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
  if (is.null(endpoint)) {
    cli::cli_abort(c(
      "No {.val {endpoint_key}} endpoint is configured for this connection.",
      "i" = "Add it to {.arg endpoints} in {.fn creel_connect_api}, or to the \\
             {.field endpoints} block of your YAML profile."
    ))
  }
  # Refused rather than fetched-and-dropped: with no field names for this
  # endpoint every column would be discarded by the rename and the failure would
  # surface as "column missing" from a validator, pointing nowhere near the
  # cause.
  if (is.null(con_info$api_field_map[[endpoint_key]])) {
    cli::cli_abort(c(
      "No field names are configured for the {.val {endpoint_key}} endpoint.",
      "i" = "Add an {.field {endpoint_key}} block to {.arg api_field_map} naming \\
             the raw JSON fields this endpoint returns."
    ))
  }
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
  df <- tryCatch(
    as.data.frame(result),
    error = function(e) {
      cli::cli_abort(c(
        "API returned non-tabular JSON for endpoint {.val {endpoint_key}}.",
        "i" = "Expected a JSON array of flat objects.",
        "x" = conditionMessage(e)
      ))
    }
  )
  names(df) <- trimws(names(df))
  df
}

# Parse a date column that may arrive as "YYYY-MM-DD", "YYYY-MM-DDTHH:MM:SS",
# or ISO 8601 with timezone suffix ("...Z" or "...+HH:MM" / "...-HH:MM").
#' @noRd
.parse_api_date <- function(x) {
  # Strip trailing timezone suffix from datetime strings before parsing
  x_clean <- sub("T(\\d{2}:\\d{2}:\\d{2})([Zz]|[+-]\\d{2}:\\d{2})$", "T\\1", x)
  result  <- suppressWarnings(as.Date(x_clean, tryFormats = c("%Y-%m-%d", "%m/%d/%Y")))
  na_mask <- is.na(result) & !is.na(x_clean)
  if (any(na_mask)) {
    result[na_mask] <- as.Date(strptime(x_clean[na_mask], "%Y-%m-%dT%H:%M:%S"))
  }
  result
}
