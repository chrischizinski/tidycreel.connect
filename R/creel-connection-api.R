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
#' ## Failed requests
#'
#' Every request is retried up to three times on a status that suggests the
#' failure is temporary: 408, 425, 429, 500, 502, 503 and 504. Retrying is safe
#' because every request is a `GET`, so a repeat cannot duplicate a side effect.
#' A `Retry-After` header is honoured, so a throttled request waits the interval
#' the server asked for rather than a fixed backoff.
#'
#' Any other status at or above 400 aborts on the first response, carrying the
#' status, the endpoint and the body: a 401 or a 404 will give the same answer
#' three times, and retrying only delays it.
#'
#' A response that returns 200 while carrying an error document rather than
#' records is also refused, quoting what the API said. Nothing is wrong at the
#' HTTP layer there, so the alternative is reading the error object as a record
#' and failing later with a message that blames `api_field_map` for a fault in
#' the request.
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
#' ### Credentials that expire
#'
#' `token` and `key` may each be a **function** returning the credential
#' instead of the credential itself. It is called before every request, and
#' again once if the API answers 401 or 403 -- so a token that ages out
#' part-way through a paginated fetch is renewed rather than aborting the fetch
#' and discarding the pages already collected.
#'
#' ```r
#' auth = list(type = "bearer", token = function() my_oauth_client$token())
#' ```
#'
#' What the function does is entirely yours: an OAuth2 client-credentials
#' exchange, a refresh token, a shell-out to a CLI, a cached value with its own
#' expiry check. This package implements none of them and never will -- a
#' token's lifetime and renewal belong to a provider, not to a creel package,
#' exactly as `endpoints` and `api_field_map` belong to a deployment.
#'
#' A refusal that survives one refresh aborts rather than looping: a credential
#' the provider keeps rejecting is a configuration problem, and retrying it
#' would turn a clear 401 into a hang. A fixed-string credential is never
#' retried at all, because the second attempt would send the same header and
#' get the same answer.
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
#' @param pagination How this API paginates, or `NULL` (default) for an API that
#'   returns every record in one response. A named list whose `style` is one of:
#'   - `"page"` -- a page number in the query string. Requires `page_param`;
#'     `start_page` defaults to `1`.
#'   - `"offset"` -- a row offset in the query string. Requires `offset_param`;
#'     `start_offset` defaults to `0`. The offset advances by the number of rows
#'     actually received, not by an assumed page size.
#'   - `"link"` -- an RFC 8288 `Link` header carrying `rel="next"`. Needs no
#'     other setting.
#'   - `"cursor"` -- a pointer to the next page inside the response *body*.
#'     Requires `next_path` naming the member that holds it, and `records_path`
#'     (a cursor implies an envelope; without one the pointer has nowhere to
#'     live). Add `cursor_param` when the pointer is an opaque token to send
#'     back as a query parameter; omit it when the pointer is a whole URL, which
#'     is then followed the way a `Link` target is, relative targets included.
#'     A token is added to the original request rather than replacing it, so the
#'     uid filter survives the page turn.
#'
#'     The member must be present on the *first* response, `null` included.
#'     Absent there is treated as a mistyped `next_path` and aborts, because
#'     reading it as "no more pages" would return page one as the whole dataset.
#'     On later pages an absent member simply ends the loop.
#'   - `"none"` -- this API is not paginated. Declaring it is the same as
#'     leaving `pagination` `NULL`, but says so on purpose.
#'
#'   Optional for `"page"`, `"offset"` and `"cursor"`: `page_size` (rows per request) and
#'   `page_size_param` (the query parameter to send it as). `page_size` is also
#'   the stop rule -- a page shorter than it is the last one. Supplying it
#'   without `page_size_param` is allowed, for an API with a fixed page size it
#'   does not let you set. `max_pages` (default `1000`) bounds the loop; hitting
#'   it aborts rather than returning what was collected so far.
#'
#'   Like `endpoints` and `api_field_map`, pagination describes one deployment,
#'   so nothing is assumed. What is *not* left to the caller is a truncated
#'   result: with no style declared, a response the connection can prove is
#'   incomplete -- a `Link` header offering a next page, or an `X-Total-Count`
#'   larger than the rows returned -- aborts instead of being returned as the
#'   whole dataset.
#'
#' @param records_path Where the records live in the response body, for an API
#'   that wraps them in an envelope, or `NULL` (default) for one whose body *is*
#'   the JSON array of records.
#'
#'   Give the member name -- `records_path = "results"` for
#'   `{"count": 42, "results": [...]}` -- or a character vector naming each step
#'   for a nested envelope: `records_path = c("data", "items")` for
#'   `{"data": {"items": [...]}}`.
#'
#'   Nothing is guessed. `"results"`, `"data"` and `"value"` are all common and
#'   all wrong for someone, so an envelope is only read when the profile says
#'   where to look. What the connection does do unasked is refuse a body it can
#'   prove is an envelope while no `records_path` is set -- otherwise
#'   `{"data": [...], "meta": {...}}` flattens into columns named `data.x` with
#'   the metadata recycled down every row, and no error is raised.
#' @param total_path Where the record count for the whole query lives in the
#'   envelope, or `NULL` (default). Named relative to the body root, the same
#'   way as `records_path`: `total_path = "count"` for
#'   `{"count": 42, "results": [...]}`.
#'
#'   This is the body-borne twin of the `X-Total-Count` header, and it is used
#'   for one thing: when no `pagination` style is declared and the total exceeds
#'   the rows returned, the fetch aborts rather than handing back page one as
#'   the dataset. Declaring it is optional, but leaving it out does not disable
#'   the check -- an undeclared sibling whose *name* is a conventional total
#'   (`count`, `total`, `total_count`, `totalCount`, `totalResults`) is read for
#'   this refusal too. Such a guess is never used to return data, only to stop.
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
    api_field_map,
    pagination    = NULL,
    records_path  = NULL,
    total_path    = NULL
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
  resolved_pagination <- if (is.null(pagination)) {
    NULL
  } else {
    .validate_api_pagination(pagination, uid_param)
  }
  resolved_records_path <- .validate_api_json_path(records_path, "records_path")
  resolved_total_path   <- .validate_api_json_path(total_path, "total_path")
  if (!is.null(resolved_pagination) &&
        identical(resolved_pagination$style, "cursor") &&
        is.null(resolved_records_path)) {
    cli::cli_abort(c(
      "{.code pagination = list(style = \"cursor\")} needs {.arg records_path}.",
      "x" = "A cursor is carried in the response body, so the body is an envelope \\
             and the records sit inside a member of it.",
      "i" = "Name that member, e.g. {.code records_path = \"results\"}."
    ))
  }
  if (is.null(resolved_records_path) && !is.null(resolved_total_path)) {
    cli::cli_abort(c(
      "{.arg total_path} was given without {.arg records_path}.",
      "x" = "A total inside the response body only has a place to live in an envelope.",
      "i" = "Name the member holding the records, e.g. \\
             {.code records_path = \"results\"}."
    ))
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
      api_field_map = resolved_field_map,
      pagination    = resolved_pagination,
      records_path  = resolved_records_path,
      total_path    = resolved_total_path
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
    .validate_api_credential(auth$token, "auth$token", "bearer")
  } else if (auth$type == "api_key") {
    .validate_api_credential(auth$key, "auth$key", "api_key")
  } else {
    cli::cli_abort(c(
      "{.field auth$type} must be {.val bearer} or {.val api_key}.",
      "x" = "Got: {.val {auth$type}}"
    ))
  }
  invisible(auth)
}

# A credential is a non-empty string, or a function that returns one.
#
# The function form is the whole of this package's refresh support, and it is
# deliberately the whole of it: a token's lifetime and how it is renewed belong
# to a provider, not to a creel package. OAuth2 client-credentials, a refresh
# token, a shell-out to a CLI, a value cached in an environment -- all of them
# reduce to "call this when you need a token", and none of them needs this
# package to know which it is. Same reasoning as `endpoints` and
# `api_field_map`: ship the seam, not one deployment's contract.
#' @noRd
.validate_api_credential <- function(value, arg, type) {
  if (is.function(value)) {
    # `...` absorbs nothing: `function(scope, ...)` is still called as `value()`
    # and still fails on the missing `scope`. Checking the named formals rather
    # than bailing out at the sight of a dots is the difference between
    # refusing here and failing on the first fetch.
    fm       <- formals(value)
    fm       <- fm[names(fm) != "..."]
    required <- names(fm)[vapply(fm, function(d) identical(d, quote(expr = )), logical(1L))]
    if (length(required) > 0L) {
      cli::cli_abort(c(
        "{.field {arg}} is a function that requires {cli::qty(required)}\\
         argument{?s}: {.arg {required}}",
        "i" = "It is called with none, so every argument needs a default."
      ))
    }
    return(invisible(value))
  }
  if (is.null(value) || !is.character(value) || length(value) != 1L || !nzchar(value)) {
    cli::cli_abort(c(
      "{.field {arg}} must be a non-empty string for {.val {type}} auth, \\
       or a function returning one.",
      "i" = "A function is called for every request, so a credential that \\
             expires can be refreshed by whatever your provider requires."
    ))
  }
  invisible(value)
}

# Resolve a credential to the string sent on this request.
#
# WARNING: the return value is a secret. Do not print it, log it, or put it in
# a condition message.
#' @noRd
.api_credential_value <- function(value, arg) {
  if (!is.function(value)) {
    return(value)
  }
  out <- tryCatch(value(), error = function(e) {
    # The message is deliberately NOT forwarded. It comes from the caller's own
    # credential code -- an OAuth client, a CLI, a vault -- and such errors
    # routinely quote the request or the response that failed, which is exactly
    # where a token lives. AGENTS.md: never print raw secrets. The caller can
    # reproduce it by calling their function directly, where no log is involved.
    cli::cli_abort(c(
      "{.field {arg}} raised an error when called for a credential.",
      "i" = "Its message is not shown here: credential code tends to quote the \\
             request or response that failed, and a token can be inside either.",
      "i" = "Call the function yourself to see why it failed.",
      "i" = "It runs before every request, so it has to succeed every time."
    ))
  })
  if (!is.character(out) || length(out) != 1L || is.na(out) || !nzchar(out)) {
    cli::cli_abort(c(
      "{.field {arg}} did not return a non-empty single string.",
      "x" = "Returned {.obj_type_friendly {out}}.",
      "i" = "It must return the credential to send on this request."
    ))
  }
  out
}

# Is this connection's credential refreshable -- i.e. supplied as a function?
#' @noRd
.api_auth_is_callable <- function(auth) {
  if (is.null(auth)) {
    return(FALSE)
  }
  # The ACTIVE credential only. `list(type = "bearer", token = "fixed", key =
  # function() ...)` passes validation, because bearer auth never looks at
  # `key` -- and reading either field would re-send the identical fixed bearer
  # token after a 401 while reporting that a credential function had been
  # retried. Both halves of that are wrong.
  is.function(.api_auth_credential(auth))
}

# The field this auth type actually sends, or NULL.
#' @noRd
.api_auth_credential <- function(auth) {
  if (is.null(auth) || is.null(auth$type)) {
    return(NULL)
  }
  switch(auth$type, bearer = auth$token, api_key = auth$key, NULL)
}

# The pagination styles this backend can follow.
#
# `cursor` was refused by name until the envelope reader landed, because a
# cursor arrives in the response *body* and this backend only read a bare JSON
# array. `records_path` removed that obstacle, so the style is supported now and
# requires `records_path` to be set -- a cursor with no envelope around it is a
# contradiction, not a configuration.
#' @noRd
.api_pagination_styles <- function() {
  c("page", "offset", "link", "cursor", "none")
}

# Settings each style accepts, beyond `style` itself. A name outside its style's
# list is refused rather than ignored: a pagination setting that is silently
# dropped leaves the caller believing the API is being paged when it is not,
# which is the failure this whole feature exists to prevent.
#' @noRd
.api_pagination_keys <- function(style) {
  common <- c("style", "page_size", "page_size_param", "max_pages")
  switch(style,
    page   = c(common, "page_param", "start_page"),
    offset = c(common, "offset_param", "start_offset"),
    link   = c("style", "max_pages"),
    cursor = c(common, "next_path", "cursor_param"),
    none   = "style"
  )
}

# Validate a pagination declaration and fill in its defaults.
#' @noRd
.validate_api_pagination <- function(pagination, uid_param = NULL) {
  styles <- .api_pagination_styles()
  if (!is.list(pagination) || is.null(pagination$style)) {
    cli::cli_abort(c(
      "{.arg pagination} must be a named list with a {.field style} entry.",
      "i" = "Valid styles: {.val {styles}}.",
      "i" = "Omit {.arg pagination} entirely for an API that returns every record at once."
    ))
  }
  style <- pagination$style
  if (!is.character(style) || length(style) != 1L || !style %in% styles) {
    cli::cli_abort(c(
      "{.field pagination$style} must be one of {.val {styles}}.",
      "x" = "Got: {.val {style}}",
      "i" = "{.val cursor} reads its next pointer from the response body, so it \\
             also needs {.arg records_path}."
    ))
  }

  allowed  <- .api_pagination_keys(style)
  supplied <- names(pagination)
  if (is.null(supplied) || any(!nzchar(supplied))) {
    cli::cli_abort("Every entry in {.arg pagination} must be named.")
  }
  unknown <- setdiff(supplied, allowed)
  if (length(unknown) > 0L) {
    cli::cli_abort(c(
      "Unknown {.field pagination} {cli::qty(unknown)}setting{?s} for style \\
       {.val {style}}: {.field {unknown}}",
      "i" = "Settings accepted by this style: {.field {allowed}}",
      "i" = "Refused rather than ignored -- a dropped setting would read as pagination \\
             that is not happening."
    ))
  }

  .pag_string <- function(name, required) {
    val <- pagination[[name]]
    if (is.null(val)) {
      if (required) {
        cli::cli_abort(c(
          "{.field pagination${name}} is required for style {.val {style}}.",
          "i" = "Name the query parameter your API expects."
        ))
      }
      return(NULL)
    }
    if (!is.character(val) || length(val) != 1L || !nzchar(val)) {
      cli::cli_abort("{.field pagination${name}} must be a non-empty single string.")
    }
    val
  }
  .pag_count <- function(name, default, min_value) {
    val <- pagination[[name]]
    if (is.null(val)) {
      return(default)
    }
    # is.finite() and the upper bound are not pedantry: Inf and 1e12 both pass
    # a trunc() test and then become NA at as.integer(), and the stored NA only
    # surfaces mid-fetch as base R's "missing value where TRUE/FALSE needed".
    if (!is.numeric(val) || length(val) != 1L || !is.finite(val) ||
          val != trunc(val) || val < min_value || val > .Machine$integer.max) {
      cli::cli_abort(c(
        "{.field pagination${name}} must be a single whole number >= {min_value}.",
        "i" = "It must also be finite and within R's integer range."
      ))
    }
    as.integer(val)
  }

  out <- list(style = style)
  if (style %in% c("page", "offset", "cursor")) {
    # Held as locals, not read back off `out`: `$` partial-matches, so
    # `out$page_size` would return `page_size_param`'s value whenever the size
    # itself is absent -- which is exactly the case being checked for.
    size_param <- .pag_string("page_size_param", required = FALSE)
    size       <- .pag_count("page_size", NULL, 1L)
    if (!is.null(size_param) && is.null(size)) {
      cli::cli_abort(c(
        "{.field pagination$page_size_param} was given with no {.field page_size}.",
        "i" = "Name the parameter and the number of rows together, or neither."
      ))
    }
    out$page_size_param <- size_param
    out$page_size       <- size
  }
  if (style == "page") {
    out$page_param <- .pag_string("page_param", required = TRUE)
    out$start_page <- .pag_count("start_page", 1L, 0L)
  } else if (style == "offset") {
    out$offset_param  <- .pag_string("offset_param", required = TRUE)
    out$start_offset  <- .pag_count("start_offset", 0L, 0L)
  } else if (style == "cursor") {
    out$next_path <- .validate_api_json_path(pagination[["next_path"]], "pagination$next_path")
    if (is.null(out$next_path)) {
      cli::cli_abort(c(
        "{.field pagination$next_path} is required for style {.val cursor}.",
        "i" = "Name the response member holding the pointer to the next page, \\
               e.g. {.code next_path = \"next\"}."
      ))
    }
    # Absent means the body holds a whole URL, the way a Link header does.
    # Present means it holds an opaque token to send back as that parameter.
    out$cursor_param <- .pag_string("cursor_param", required = FALSE)
  }
  out$max_pages <- .pag_count("max_pages", 1000L, 1L)

  # Two settings naming the same query parameter do not combine: req_url_query()
  # replaces, so `uid_param = "page"` alongside `page_param = "page"` turns
  # `?page=<uid>` into `?page=1` and the survey filter is gone. An API that
  # reads a missing filter as "every survey" then returns other surveys' rows,
  # which is a wrong dataset carrying no sign that it is wrong.
  param_names <- unlist(
    out[c("page_param", "offset_param", "page_size_param", "cursor_param")],
    use.names = TRUE
  )
  param_names <- param_names[!is.na(param_names)]
  if (!is.null(uid_param)) {
    clash <- names(param_names)[param_names == uid_param]
    if (length(clash) > 0L) {
      cli::cli_abort(c(
        "{.field pagination${clash}} names the same query parameter as \
         {.arg uid_param}: {.val {uid_param}}.",
        "x" = "The paging value would replace the survey filter rather than join it.",
        "i" = "Give the paging parameter the name your API actually uses for it."
      ))
    }
  }
  if (anyDuplicated(param_names) > 0L) {
    dup <- param_names[duplicated(param_names)][1L] # nolint: object_usage_linter
    cli::cli_abort(c(
      "Two {.field pagination} settings name the same query parameter: {.val {dup}}.",
      "x" = "One would replace the other rather than both being sent.",
      "i" = "Settings given: {.field {names(param_names)}} = {.val {param_names}}"
    ))
  }
  out
}

# Perform an authenticated API GET and return a plain data.frame.
#
# Follows the connection's declared pagination style to exhaustion. With no
# style declared, one request is made and the response is checked for proof
# that it is only part of the data -- see .api_assert_untruncated().
#
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
  url <- paste0(con_info$base_url, endpoint)

  base_req <- httr2::request(url)
  if (!no_uid_filter) {
    uid_str    <- paste(con_info$creel_uids, collapse = ",")
    query_args <- stats::setNames(list(uid_str), con_info$uid_param)
    base_req   <- do.call(httr2::req_url_query, c(list(base_req), query_args))
  }

  pag   <- con_info$pagination
  style <- if (is.null(pag)) "none" else pag$style

  pages       <- list()
  page_no     <- 1L
  n_so_far    <- 0L
  next_url    <- NULL
  next_cursor <- NULL

  repeat {
    req <- if (is.null(next_url)) {
      .api_page_request(base_req, pag, page_no, n_so_far, cursor = next_cursor)
    } else {
      # A next link is an absolute URL the API built, filter included, so the
      # uid query is not re-applied -- only the credentials are.
      httr2::request(next_url)
    }
    resp <- .api_perform_with_reauth(req, con_info$auth)
    .api_check_status(
      resp, endpoint,
      auth       = con_info$auth,
      pages_held = length(pages),
      rows_held  = n_so_far
    )
    df <- .api_page_to_df(
      resp, endpoint_key, con_info$records_path,
      expected_fields = as.character(unlist(con_info$api_field_map[[endpoint_key]]))
    )

    if (style == "none") {
      # No style declared: one request, and refuse anything provably partial.
      .api_assert_untruncated(
        resp, endpoint, nrow(df),
        records_path = con_info$records_path,
        total_path   = con_info$total_path
      )
      return(df)
    }

    pages[[page_no]] <- df
    n_so_far <- n_so_far + nrow(df)

    # An empty page is the end of the data on every style.
    if (nrow(df) == 0L) break
    # A page shorter than the declared size is the last one. Without a declared
    # size the only safe stop is an empty page -- guessing from a round row
    # count would drop a final page whose length happened to look full.
    #
    # Not for `cursor`, where the pointer is authoritative: an API is free to
    # return a short page and still offer a next one, and stopping on the length
    # would discard the rest while the response was still saying there is more.
    if (style != "cursor" &&
          !is.null(pag[["page_size"]]) && nrow(df) < pag[["page_size"]]) break

    # The same rows twice means the request did not advance. Binding them would
    # duplicate every record and inflate every total, so stop and say which
    # setting did not take effect rather than return the result. Checked for
    # every style: a `Link` chain that points back at the page it came from
    # repeats just as silently as a paging parameter the API ignores, and if
    # such a chain then ends, the duplicates are bound with nothing said.
    if (page_no > 1L && identical(df, pages[[page_no - 1L]])) {
      cause <- if (style == "link") {
        cli::format_inline("Its {.field Link} header points back at the same page.")
      } else if (style == "cursor") {
        ptr <- paste(pag[["next_path"]], collapse = " > ") # nolint: object_usage_linter
        cli::format_inline(
          "Its {.field {ptr}} pointer leads back to the page it came from."
        )
      } else {
        param <- if (style == "page") pag[["page_param"]] else pag[["offset_param"]] # nolint: object_usage_linter, line_length_linter
        cli::format_inline("It appears to ignore the {.field {param}} parameter.")
      }
      cli::cli_abort(c(
        "The API returned identical rows for two consecutive pages of {.val {endpoint_key}}.",
        "x" = cause,
        "i" = "Check the setting against your API, or set \\
               {.code pagination = list(style = \"none\")} if it does not paginate."
      ))
    }

    if (style == "cursor") {
      ptr <- .api_body_next(resp, pag[["next_path"]], first_page = page_no == 1L)
      if (is.null(ptr)) break
      if (is.null(pag[["cursor_param"]])) {
        # No parameter named: the body holds a whole URL, followed the way a
        # Link target is, relative targets included.
        next_url <- httr2::url_modify_relative(httr2::resp_url(resp), ptr)
      } else {
        # An opaque token, sent back on the original request rather than
        # replacing it -- the uid filter has to survive the page turn.
        next_cursor <- ptr
      }
    }

    if (style == "link") {
      next_url <- .api_next_link(resp)
      if (is.null(next_url)) break
      # RFC 8288 permits a relative target, and servers do emit one. Left as-is
      # it reaches httr2::request() as "/v2/interviews?page=2" and dies in curl
      # with no host -- which no mocked response could ever show, because a mock
      # never performs the follow-up request. Resolving against the URL the page
      # actually came from is a no-op for an absolute target.
      next_url <- httr2::url_modify_relative(httr2::resp_url(resp), next_url)
    }

    page_no <- page_no + 1L
    if (page_no > pag[["max_pages"]]) {
      cli::cli_abort(c(
        "Stopped after {pag[[\"max_pages\"]]} pages of the {.val {endpoint_key}} endpoint.",
        "i" = "Raise {.field pagination$max_pages} if the dataset really is this large.",
        "x" = "The rows fetched so far are not returned: a partial dataset would \\
               understate every total without saying so."
      ))
    }
  }

  .api_rbind_pages(pages, endpoint_key)
}

# Perform a request, and give a refreshable credential one second chance.
#
# A 401 part-way through a paginated fetch is the ordinary shape of an expired
# token: the first pages went through and the credential aged out mid-loop.
# Where the credential is a function, calling it again is exactly what the
# caller supplied it for, so the request is rebuilt -- which re-invokes the
# function -- and tried once more.
#
# Once, not repeatedly. A credential the provider keeps refusing is a
# configuration problem, and looping on it would turn a clear 401 into a hang.
# A fixed-string credential gets no retry at all: the second attempt would send
# the identical header and receive the identical answer.
#' @noRd
.api_perform_with_reauth <- function(req, auth) {
  resp <- httr2::req_perform(.api_apply_retry(.api_apply_auth(req, auth)))
  if (!httr2::resp_status(resp) %in% c(401L, 403L) || !.api_auth_is_callable(auth)) {
    return(resp)
  }
  httr2::req_perform(.api_apply_retry(.api_apply_auth(req, auth)))
}

# Apply the connection's credentials to a request.
#
# WARNING: Do NOT print auth or req objects after this point -- auth$token will
# leak to logs. Use httr2::req_dry_run() for debugging; httr2 redacts auth headers.
#' @noRd
.api_apply_auth <- function(req, auth) {
  if (is.null(auth)) {
    return(req)
  }
  if (auth$type == "bearer") {
    req <- httr2::req_auth_bearer_token(
      req, .api_credential_value(auth$token, "auth$token")
    )
  } else if (auth$type == "api_key") {
    hdr      <- if (!is.null(auth$header) && nzchar(auth$header)) auth$header else "X-API-Key"
    hdr_args <- stats::setNames(
      list(.api_credential_value(auth$key, "auth$key")), hdr
    )
    req      <- do.call(httr2::req_headers, c(list(req), hdr_args))
  }
  req
}

# Apply the retry and error policy. Order matters and is the project's httr2
# convention: req_retry() first, req_error() after.
#' @noRd
.api_apply_retry <- function(req) {
  # D-10, D-11: max 3 tries; explicit is_transient so retry fires regardless of
  # the req_error policy applied below (httr2 1.2.2 behaviour).
  req <- httr2::req_retry(
    req,
    max_tries    = 3L,
    is_transient = \(resp) httr2::resp_status(resp) %in% .api_transient_statuses()
  )
  # D-13: disable httr2 auto-error AFTER retry is wired; manual cli_abort() controls format
  httr2::req_error(req, is_error = \(resp) FALSE)
}

# Statuses worth trying again.
#
# Wider than httr2's own 429/503 default, and safe to be: every request this
# backend makes is a GET (see the read-only guarantee on `creel_connect_api()`),
# so a repeat cannot duplicate a side effect. The cost of retrying a genuinely
# permanent failure is bounded at three tries; the cost of NOT retrying a
# transient one is the whole fetch, and for a paginated fetch that means
# discarding the pages already collected.
#
# 500 is included deliberately. It is the debatable one -- often a real server
# bug that repeating will not fix -- but a flaky backend behind a load balancer
# emits it for exactly the kind of blip a retry absorbs, and an idempotent GET
# makes the attempt free of consequence.
#
# `Retry-After` needs nothing here: httr2 reads it already, and a 429 carrying
# one waits the interval the server asked for rather than the backoff curve.
# Verified against a real server rather than assumed -- see the STATUS tests.
#' @noRd
.api_transient_statuses <- function() {
  c(
    408L, # Request Timeout
    425L, # Too Early
    429L, # Too Many Requests
    500L, # Internal Server Error -- see the note above
    502L, # Bad Gateway
    503L, # Service Unavailable
    504L  # Gateway Timeout
  )
}

# Abort with a human-readable message on any HTTP error status.
#' @noRd
.api_check_status <- function(resp, endpoint, auth = NULL, pages_held = 0L,
                              rows_held = 0L) {
  status <- httr2::resp_status(resp)
  if (status < 400L) {
    return(invisible(NULL))
  }
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
  bullets <- c(
    "API request failed [{status}]",
    "i" = "Endpoint: {endpoint}",
    "x" = body_text
  )
  # A credential failure has three distinct causes and the same status code, so
  # say which one this connection is configured for. Without this a 401 reads
  # the same as a mis-mapped field to anyone who has not seen the config.
  if (status %in% c(401L, 403L)) {
    bullets <- c(bullets, "i" = .api_auth_advice(auth))
  }
  # A fetch that dies part-way through pagination throws away what it already
  # collected. Returning it is not an option -- a partial dataset understates
  # every total without saying so -- but neither is letting the user think one
  # request failed when several succeeded and were discarded.
  if (pages_held > 0L) {
    bullets <- c(bullets, "i" = cli::format_inline(
      "{pages_held} page{?s} ({rows_held} row{?s}) had already been fetched and \\
       {cli::qty(pages_held)}{?is/are} discarded: a partial dataset would \\
       understate every total without saying so."
    ))
  }
  cli::cli_abort(bullets)
}

# What to check when a credential is rejected, given how this connection was
# configured. Never includes the credential itself.
#' @noRd
.api_auth_advice <- function(auth) {
  # No `\\` line continuations below. cli_abort() strips them; format_inline()
  # does NOT, and emits the backslash and the following indentation literally.
  # The first version of this read "cannot be renewed. \\\n     Supply ...".
  if (is.null(auth)) {
    return(cli::format_inline(
      paste0(
        "No credentials are configured for this connection. ",
        "If the API needs them, set {.arg auth} in {.fn creel_connect_api}."
      )
    ))
  }
  if (.api_auth_is_callable(auth)) {
    return(cli::format_inline(
      paste0(
        "The credential function was called again and the API still refused ",
        "the result, so this is not a stale token."
      )
    ))
  }
  field <- if (identical(auth$type, "bearer")) "auth$token" else "auth$key" # nolint: object_usage_linter, line_length_linter
  cli::format_inline(
    paste0(
      "The credential is a fixed string, so an expired one cannot be renewed. ",
      "Supply {.field {field}} as a function to have it fetched again on ",
      "each request."
    )
  )
}

# Member names that conventionally carry an error message.
#
# Read ONLY to refuse, never to decide what to return -- the same licence
# .api_total_key_candidates() takes. A wrong guess here cannot put a value in a
# result; it can only stop a fetch that was going to fail anyway.
#' @noRd
.api_error_key_candidates <- function() {
  c("error", "errors", "message", "detail", "details", "fault", "fault_string")
}

# Refuse a 200 whose body is an error document rather than data.
#
# Some APIs report a bad request with a 200 and an error object, so
# .api_check_status() never sees it. Left alone the object is read as one
# record, every mapped field misses, and the fetch dies at the validator saying
# "date: column missing" -- which accuses the field map of a fault that belongs
# to the request. The API said "invalid survey_id"; the package said "your
# configuration is wrong".
#
# The test is deliberately narrow, because a legitimate record may well have a
# field called `message`. All three must hold: the body is a JSON object rather
# than an array, it carries a conventionally-named error member with something
# in it, and NOT ONE of the raw fields this endpoint was configured to read is
# present. A response containing an error and none of what you asked for is not
# a record by any reading.
#' @noRd
.api_path_exists <- function(body, path) {
  node <- body
  for (key in path) {
    if (!is.list(node) || is.null(names(node)) || !key %in% names(node)) {
      return(FALSE)
    }
    node <- node[[key]]
  }
  TRUE
}

#' @noRd
.api_assert_not_error_doc <- function(body, endpoint_key, expected_fields,
                                      records_path = NULL) {
  if (!is.list(body) || is.data.frame(body) || is.null(names(body))) {
    return(invisible(NULL))
  }
  # An envelope whose records member is present is carrying records, whatever
  # else sits beside them. `{"results": [...], "message": "partial day"}` is a
  # successful response with a note attached, and the mapped fields are INSIDE
  # `results` -- so looking for them at the top level would find none and
  # condemn every enveloped API that annotates its payload.
  if (!is.null(records_path) && .api_path_exists(body, records_path)) {
    return(invisible(NULL))
  }
  if (length(intersect(expected_fields, names(body))) > 0L) {
    return(invisible(NULL))
  }
  hits <- intersect(.api_error_key_candidates(), names(body))
  for (key in hits) {
    val <- body[[key]]
    if (is.null(val) || length(val) == 0L) {
      next
    }
    text <- paste(utils::head(trimws(as.character(unlist(val))), 3L), collapse = "; ")
    if (!nzchar(text) || identical(tolower(text), "na")) {
      next
    }
    cli::cli_abort(c(
      "The {.val {endpoint_key}} endpoint returned an error document with status 200.",
      "x" = "{.field {key}}: {text}",
      "i" = "No field named in {.field api_field_map} for this endpoint is present, \\
             so this is the API reporting a problem rather than returning records.",
      "i" = "Reading it as data would blame the field map for a fault in the request."
    ))
  }
  invisible(NULL)
}

# Validate a body path: NULL, or a character vector of non-empty member names.
#' @noRd
.validate_api_json_path <- function(path, arg) {
  if (is.null(path)) {
    return(NULL)
  }
  if (!is.character(path) || length(path) == 0L || anyNA(path) || !all(nzchar(path))) {
    cli::cli_abort(c(
      "{.arg {arg}} must be a character vector of member names, or {.code NULL}.",
      "i" = "One name for a flat envelope ({.code \"results\"}), or one per level \\
             for a nested one ({.code c(\"data\", \"items\")})."
    ))
  }
  path
}

# Member names that conventionally carry a whole-query record count.
#
# Read ONLY to refuse a response that proves itself partial, never to decide
# what to return -- so a wrong guess here cannot put a number in a result. An
# API whose total is named something else declares it in `total_path`.
#' @noRd
.api_total_key_candidates <- function() {
  c("count", "total", "total_count", "totalCount", "totalResults", "recordCount")
}

# Could this member be a record array, or something around one?
#
# After simplifyVector = TRUE, a JSON array of flat objects arrives as a
# data.frame and any other JSON array as an UNNAMED list. A JSON object arrives
# as a NAMED list, and that distinction is what separates an envelope from an
# ordinary record: `{"SurveyDate": ..., "Audit": {"by": "jd"}}` is one record
# carrying a metadata object, not a wrapper around a table.
#
# A named list still counts when it holds a container itself, because that is a
# nested envelope -- `{"data": {"items": [...]}}` -- and refusing to look one
# level down would let exactly the shape `records_path` exists for slip past.
#' @noRd
.api_is_record_container <- function(m, depth = 2L) {
  if (is.data.frame(m)) {
    return(TRUE)
  }
  if (!is.list(m)) {
    return(FALSE)
  }
  if (is.null(names(m))) {
    # An unnamed list is a JSON array, including the empty one.
    return(TRUE)
  }
  if (depth <= 0L) {
    return(FALSE)
  }
  any(vapply(m, .api_is_record_container, logical(1L), depth = depth - 1L))
}

# Members of a parsed body that could hold the records.
#' @noRd
.api_envelope_candidates <- function(body) {
  if (!is.list(body) || is.data.frame(body) || is.null(names(body))) {
    return(character(0))
  }
  is_container <- vapply(body, .api_is_record_container, logical(1L))
  keys <- names(body)[is_container]
  if (length(keys) == 0L) {
    return(character(0))
  }
  # A member already simplified to a data.frame is the strongest candidate, so
  # name it first in the message the caller has to act on.
  frames <- vapply(body[keys], is.data.frame, logical(1L))
  c(keys[frames], keys[!frames])
}

# Refuse a body that is provably an envelope while no records_path is declared.
#
# The twin of .api_assert_untruncated(), for structure rather than length, and
# for the same reason: `{"data": [...], "meta": {"total": 2}}` does not fail
# under as.data.frame(). It flattens to columns named `data.x` with every
# metadata scalar recycled down the rows, so the misread reaches the field-map
# rename looking like an ordinary set of unfamiliar column names.
#' @noRd
.api_assert_not_envelope <- function(body, endpoint_key) {
  candidates <- .api_envelope_candidates(body)
  if (length(candidates) == 0L) {
    return(invisible(NULL))
  }
  best <- candidates[1L] # nolint: object_usage_linter
  cli::cli_abort(c(
    "The {.val {endpoint_key}} response is a JSON object wrapping the records, \\
     and no {.arg records_path} is configured.",
    "x" = "Member{?s} that could hold the records: {.field {candidates}}",
    "i" = "Reading the object as a table would name the columns after the \\
           wrapper and recycle every sibling value down each row.",
    "i" = "Say where the records are, e.g. {.code records_path = \"{best}\"}."
  ))
}

# Walk `path` into the parsed body and return the member it names.
#' @noRd
.api_extract_records <- function(body, path, endpoint_key, arg = "records_path") {
  node <- body
  for (i in seq_along(path)) {
    key <- path[[i]]
    walked <- if (i == 1L) "the response body" else paste(path[seq_len(i - 1L)], collapse = " > ") # nolint: line_length_linter
    if (!is.list(node) || is.null(names(node))) {
      cli::cli_abort(c(
        "{.arg {arg}} looks past the end of the {.val {endpoint_key}} response.",
        "x" = "{walked} is not a JSON object, so it has no {.field {key}} member.",
        "i" = "Path given: {.field {path}}"
      ))
    }
    if (!key %in% names(node)) {
      present <- names(node) # nolint: object_usage_linter
      cli::cli_abort(c(
        "The {.val {endpoint_key}} response has no {.field {key}} member.",
        "x" = "Looked in {walked}, which holds: {.field {present}}",
        "i" = "Path given: {.field {path}}"
      ))
    }
    node <- node[[key]]
  }
  node
}

# Parse one response body into a plain data.frame.
#
# `records_path` is NULL for an API whose body is the record array, and names
# the enclosing member(s) for one that wraps it.
#' @noRd
.api_page_to_df <- function(resp, endpoint_key, records_path = NULL,
                            expected_fields = character(0)) {
  body <- httr2::resp_body_json(resp, simplifyVector = TRUE)

  # Before anything tries to read this as a table: it may not be one, and the
  # body may already say why. Runs ahead of the records extraction so that an
  # enveloped API reporting an error gets its own words quoted, rather than
  # "no results member".
  .api_assert_not_error_doc(body, endpoint_key, expected_fields, records_path)

  if (is.null(records_path)) {
    .api_assert_not_envelope(body, endpoint_key)
    result <- body
  } else {
    if (is.data.frame(body)) {
      cli::cli_abort(c(
        "{.arg records_path} is configured but the {.val {endpoint_key}} response \\
         is already a bare JSON array.",
        "x" = "There is no envelope to look inside for {.field {records_path}}.",
        "i" = "Drop {.arg records_path} for this API."
      ))
    }
    result <- .api_extract_records(body, records_path, endpoint_key)
  }

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

# The `rel="next"` URL from an RFC 8288 Link header, or NULL.
#
# Split on a comma only where the next link element starts, because a creel
# request's own query string joins uids with commas and a plain split would cut
# the URL in half.
#
# Not httr2::resp_link_url(), which exists and parses the same header: it fails
# on exactly that shape. Given
#   Link: <...?survey_id=u-1,u-2&page=1>; rel="prev", <...&page=2>; rel="next"
# it aborts with "values must be length 1, but FUN(X[[1]]) result is length 0".
# A comma-joined uid list is this package's normal request, so the general
# parser is the wrong one here. Do not simplify this away.
#' @noRd
.api_next_link <- function(resp) {
  link <- tryCatch(httr2::resp_header(resp, "Link"), error = function(e) NULL)
  if (is.null(link) || !nzchar(link)) {
    return(NULL)
  }
  parts <- strsplit(link, ",(?=\\s*<)", perl = TRUE)[[1]]
  for (part in parts) {
    if (grepl("rel\\s*=\\s*[\"']?next[\"']?", part, perl = TRUE)) {
      target <- regmatches(part, regexpr("<[^>]*>", part))
      if (length(target) == 1L) {
        return(substr(target, 2L, nchar(target) - 1L))
      }
    }
  }
  NULL
}

# The pointer to the next page, read from the response body, or NULL at the end.
#
# `first_page` is what keeps a typo from reading as "done". A member that is
# absent on the FIRST response is a configuration error -- the same silent
# truncation a mistyped `total_path` used to cause -- while a member absent on a
# later one is just an API that stops sending the key instead of sending null.
#' @noRd
.api_body_next <- function(resp, next_path, first_page) {
  body <- tryCatch(
    httr2::resp_body_json(resp, simplifyVector = TRUE),
    error = function(e) NULL
  )
  node <- body
  for (i in seq_along(next_path)) {
    key <- next_path[[i]]
    if (!is.list(node) || is.null(names(node)) || !key %in% names(node)) {
      if (!first_page) {
        return(NULL)
      }
      present <- if (is.list(node) && !is.null(names(node))) names(node) else character(0) # nolint: object_usage_linter, line_length_linter
      cli::cli_abort(c(
        "The first response has no {.field {key}} member, but \\
         {.field pagination$next_path} names one.",
        "x" = "Looked in {.code {paste(c('body', next_path[seq_len(i - 1L)]), collapse = ' > ')}}, \\
               which holds: {.field {present}}",
        "i" = "A pointer that is never found would end the fetch after page one \\
               and return it as the complete dataset.",
        "i" = "If this API omits the key when there is only one page, it is not \\
               paginating this query -- use {.code style = \"none\"}."
      ))
    }
    node <- node[[key]]
  }
  # null, absent, or blank all mean the same thing: there is no next page.
  if (is.null(node) || length(node) != 1L || is.na(node)) {
    return(NULL)
  }
  node <- as.character(node)
  if (!nzchar(node)) NULL else node
}

# The record count the API reported for the whole query, or NULL.
#' @noRd
.api_reported_total <- function(resp) {
  val <- tryCatch(httr2::resp_header(resp, "X-Total-Count"), error = function(e) NULL)
  if (is.null(val) || !nzchar(val)) {
    return(NULL)
  }
  n <- suppressWarnings(as.numeric(val))
  if (is.na(n)) NULL else n
}

# The record count the API reported inside an envelope, or NULL.
#
# `total_path` is used when declared. When it is not, a sibling of the records
# whose NAME is a conventional total is read instead -- see
# .api_total_key_candidates() for why a guess is safe in this one direction.
#' @noRd
.api_body_total <- function(resp, records_path, total_path) {
  if (is.null(records_path)) {
    return(NULL)
  }
  body <- tryCatch(
    httr2::resp_body_json(resp, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.null(body)) {
    return(NULL)
  }
  if (!is.null(total_path)) {
    # A DECLARED path is not allowed to quietly resolve to nothing. The caller
    # configured the truncation check; a typo that silently switched it off
    # would leave a profile that looks guarded and is not -- the same reason
    # .validate_api_pagination() refuses an unknown setting rather than
    # ignoring it.
    raw <- .api_extract_records(body, total_path, endpoint_key = "total", arg = "total_path")
    total <- .api_scalar_number(raw)
    if (is.null(total)) {
      cli::cli_abort(c(
        "{.arg total_path} does not name a number.",
        "x" = "{.field {paste(total_path, collapse = ' > ')}} holds \\
               {.obj_type_friendly {raw}}.",
        "i" = "It should name the record count for the whole query, e.g. the \\
               {.field count} in {.code {{\"count\": 42, \"results\": [...]}}}."
      ))
    }
    return(total)
  }
  # Siblings of the records member, one level up from the array itself.
  parent <- if (length(records_path) == 1L) {
    body
  } else {
    tryCatch(
      .api_extract_records(body, records_path[-length(records_path)], "total"),
      error = function(e) NULL
    )
  }
  if (!is.list(parent) || is.null(names(parent))) {
    return(NULL)
  }
  hit <- intersect(.api_total_key_candidates(), names(parent))
  if (length(hit) == 0L) {
    return(NULL)
  }
  # A guessed key is allowed to be something other than a count -- that is what
  # guessing means -- so an unreadable value here is simply not a total.
  .api_scalar_number(raw = parent[[hit[[1L]]]])
}

# A single number, from a JSON value that may have arrived quoted.
#
# `{"count": "9"}` is legal JSON and common from an API whose counts come back
# as strings. The X-Total-Count twin already coerced its header text, so
# refusing the body's quoted total would have made the guard depend on how the
# API happened to type a number.
#' @noRd
.api_scalar_number <- function(raw) {
  if (is.null(raw) || length(raw) != 1L || is.list(raw)) {
    return(NULL)
  }
  if (!is.numeric(raw) && !is.character(raw)) {
    return(NULL)
  }
  n <- suppressWarnings(as.numeric(raw))
  if (is.na(n)) NULL else n
}

# Refuse a response that can be PROVEN to be one page of several.
#
# This runs only when no pagination style is declared, and it is the half of GH
# #330 that does not need the caller to configure anything. It cannot detect an
# API that paginates while advertising nothing -- no header, no count -- and
# does not pretend to: what it removes is the case where the response says it is
# incomplete and the connection returns it as the whole dataset anyway.
#' @noRd
.api_assert_untruncated <- function(resp, endpoint, n_rows,
                                    records_path = NULL, total_path = NULL) {
  advice <- "Declare how this API paginates in {.arg pagination}, e.g. \\
             {.code pagination = list(style = \"link\")}."
  if (!is.null(.api_next_link(resp))) {
    cli::cli_abort(c(
      "The API offered another page and no pagination style is configured.",
      "x" = "Endpoint {endpoint} returned a {.field Link} header with {.code rel=\"next\"}.",
      "i" = "Returning this would treat page 1 as the complete dataset and understate \\
             every total that depends on it.",
      "i" = advice
    ))
  }
  total <- .api_reported_total(resp)
  if (!is.null(total) && total > n_rows) {
    cli::cli_abort(c(
      "The API reported a total of {total} records but returned {n_rows}.",
      "x" = "Endpoint {endpoint} sent an {.field X-Total-Count} larger than the response.",
      "i" = "Returning this would treat a partial response as the complete dataset.",
      "i" = advice
    ))
  }
  # An enveloped API usually carries its count in the body rather than a header,
  # so supporting `records_path` without this would re-open, for exactly those
  # APIs, the silent truncation the header check exists to prevent.
  body_total <- .api_body_total(resp, records_path, total_path)
  if (!is.null(body_total) && body_total > n_rows) {
    cli::cli_abort(c(
      "The API reported a total of {body_total} records but returned {n_rows}.",
      "x" = "Endpoint {endpoint} sent a larger count inside the response body.",
      "i" = "Returning this would treat a partial response as the complete dataset.",
      "i" = advice
    ))
  }
  invisible(NULL)
}

# Bind the fetched pages into one frame.
#
# Pages must describe the same fields. A page carrying a different set is
# refused rather than filled, because rbind() on mismatched names either errors
# or -- worse, when the counts happen to match -- aligns values under the wrong
# column. Order alone is not a mismatch: JSON object key order is free to vary
# between pages, so the pages are reordered to the first page's layout.
#' @noRd
.api_rbind_pages <- function(pages, endpoint_key) {
  filled <- Filter(function(d) nrow(d) > 0L, pages)
  if (length(filled) == 0L) {
    return(data.frame())
  }
  first <- names(filled[[1L]])
  same  <- vapply(filled, function(d) setequal(names(d), first), logical(1L))
  if (!all(same)) {
    bad <- which(!same)[1L] # nolint: object_usage_linter
    cli::cli_abort(c(
      "Pages of the {.val {endpoint_key}} response do not describe the same fields.",
      "x" = "Page {bad} returned: {.field {names(filled[[bad]])}}",
      "i" = "Page 1 returned: {.field {first}}",
      "i" = "Binding them would align values under the wrong names."
    ))
  }
  aligned <- lapply(filled, function(d) d[, first, drop = FALSE])
  out <- do.call(rbind, aligned)
  row.names(out) <- NULL
  out
}

# Build the request for one page under the declared style.
#
# Settings are read with `[[` throughout: `$` partial-matches, and `page_size`
# is a prefix of `page_size_param`, so `pag$page_size` silently returns a
# parameter NAME when no size was declared.
#' @noRd
.api_page_request <- function(req, pag, page_no, n_so_far, cursor = NULL) {
  if (is.null(pag)) {
    return(req)
  }
  args <- list()
  if (!is.null(cursor)) {
    args[[pag[["cursor_param"]]]] <- cursor
  }
  if (pag$style == "page") {
    args[[pag[["page_param"]]]] <- pag[["start_page"]] + (page_no - 1L)
  } else if (pag$style == "offset") {
    # Advance by the rows actually received rather than by an assumed page size,
    # so a short page cannot shift every later offset past real records.
    args[[pag[["offset_param"]]]] <- pag[["start_offset"]] + n_so_far
  }
  if (!is.null(pag[["page_size"]]) && !is.null(pag[["page_size_param"]])) {
    args[[pag[["page_size_param"]]]] <- pag[["page_size"]]
  }
  if (length(args) == 0L) {
    return(req)
  }
  do.call(httr2::req_url_query, c(list(req), args))
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
