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
#' @param pagination How this API paginates, or `NULL` (default) for an API that
#'   returns every record in one response. A named list whose `style` is one of:
#'   - `"page"` -- a page number in the query string. Requires `page_param`;
#'     `start_page` defaults to `1`.
#'   - `"offset"` -- a row offset in the query string. Requires `offset_param`;
#'     `start_offset` defaults to `0`. The offset advances by the number of rows
#'     actually received, not by an assumed page size.
#'   - `"link"` -- an RFC 8288 `Link` header carrying `rel="next"`. Needs no
#'     other setting.
#'   - `"none"` -- this API is not paginated. Declaring it is the same as
#'     leaving `pagination` `NULL`, but says so on purpose.
#'
#'   Optional for `"page"` and `"offset"`: `page_size` (rows per request) and
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
    pagination    = NULL
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
      pagination    = resolved_pagination
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

# The pagination styles this backend can follow.
#
# `cursor` is deliberately absent. A cursor arrives in the response *body*,
# which means the body is an envelope (`{"items": [...], "next": "..."}`) rather
# than the bare JSON array this backend reads. Envelope support is a separate
# capability and is tracked as its own half of GH #330; refusing the style by
# name is honest, where accepting it and reading page 1 would not be.
#' @noRd
.api_pagination_styles <- function() {
  c("page", "offset", "link", "none")
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
      "i" = "{.val cursor} is not supported: it needs a response envelope, which \\
             this backend does not read."
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
  if (style %in% c("page", "offset")) {
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
  }
  out$max_pages <- .pag_count("max_pages", 1000L, 1L)

  # Two settings naming the same query parameter do not combine: req_url_query()
  # replaces, so `uid_param = "page"` alongside `page_param = "page"` turns
  # `?page=<uid>` into `?page=1` and the survey filter is gone. An API that
  # reads a missing filter as "every survey" then returns other surveys' rows,
  # which is a wrong dataset carrying no sign that it is wrong.
  param_names <- unlist(out[c("page_param", "offset_param", "page_size_param")], use.names = TRUE)
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

  pages    <- list()
  page_no  <- 1L
  n_so_far <- 0L
  next_url <- NULL

  repeat {
    req <- if (is.null(next_url)) {
      .api_page_request(base_req, pag, page_no, n_so_far)
    } else {
      # A next link is an absolute URL the API built, filter included, so the
      # uid query is not re-applied -- only the credentials are.
      httr2::request(next_url)
    }
    req  <- .api_apply_auth(req, con_info$auth)
    req  <- .api_apply_retry(req)
    resp <- httr2::req_perform(req)
    .api_check_status(resp, endpoint)
    df <- .api_page_to_df(resp, endpoint_key)

    if (style == "none") {
      # No style declared: one request, and refuse anything provably partial.
      .api_assert_untruncated(resp, endpoint, nrow(df))
      return(df)
    }

    pages[[page_no]] <- df
    n_so_far <- n_so_far + nrow(df)

    # An empty page is the end of the data on every style.
    if (nrow(df) == 0L) break
    # A page shorter than the declared size is the last one. Without a declared
    # size the only safe stop is an empty page -- guessing from a round row
    # count would drop a final page whose length happened to look full.
    if (!is.null(pag[["page_size"]]) && nrow(df) < pag[["page_size"]]) break

    # The same rows twice means the request did not advance. Binding them would
    # duplicate every record and inflate every total, so stop and say which
    # setting did not take effect rather than return the result. Checked for
    # every style: a `Link` chain that points back at the page it came from
    # repeats just as silently as a paging parameter the API ignores, and if
    # such a chain then ends, the duplicates are bound with nothing said.
    if (page_no > 1L && identical(df, pages[[page_no - 1L]])) {
      cause <- if (style == "link") {
        cli::format_inline("Its {.field Link} header points back at the same page.")
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

    if (style == "link") {
      next_url <- .api_next_link(resp)
      if (is.null(next_url)) break
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
    req <- httr2::req_auth_bearer_token(req, auth$token)
  } else if (auth$type == "api_key") {
    hdr      <- if (!is.null(auth$header) && nzchar(auth$header)) auth$header else "X-API-Key"
    hdr_args <- stats::setNames(list(auth$key), hdr)
    req      <- do.call(httr2::req_headers, c(list(req), hdr_args))
  }
  req
}

# Apply the retry and error policy. Order matters and is the project's httr2
# convention: req_retry() first, req_error() after.
#' @noRd
.api_apply_retry <- function(req) {
  # D-10, D-11: retry on 429/503, max 3 tries; explicit is_transient so retry
  # fires regardless of the req_error policy applied below (httr2 1.2.2 behaviour)
  req <- httr2::req_retry(
    req,
    max_tries    = 3L,
    is_transient = \(resp) httr2::resp_status(resp) %in% c(429L, 503L)
  )
  # D-13: disable httr2 auto-error AFTER retry is wired; manual cli_abort() controls format
  httr2::req_error(req, is_error = \(resp) FALSE)
}

# Abort with a human-readable message on any HTTP error status.
#' @noRd
.api_check_status <- function(resp, endpoint) {
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
  cli::cli_abort(c(
    "API request failed [{status}]",
    "i" = "Endpoint: {endpoint}",
    "x" = body_text
  ))
}

# Parse one response body into a plain data.frame.
#' @noRd
.api_page_to_df <- function(resp, endpoint_key) {
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

# The `rel="next"` URL from an RFC 8288 Link header, or NULL.
#
# Split on a comma only where the next link element starts, because a creel
# request's own query string joins uids with commas and a plain split would cut
# the URL in half.
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

# Refuse a response that can be PROVEN to be one page of several.
#
# This runs only when no pagination style is declared, and it is the half of GH
# #330 that does not need the caller to configure anything. It cannot detect an
# API that paginates while advertising nothing -- no header, no count -- and
# does not pretend to: what it removes is the case where the response says it is
# incomplete and the connection returns it as the whole dataset anyway.
#' @noRd
.api_assert_untruncated <- function(resp, endpoint, n_rows) {
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
.api_page_request <- function(req, pag, page_no, n_so_far) {
  if (is.null(pag)) {
    return(req)
  }
  args <- list()
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
