# Create a creel REST API connection

`creel_connect_api()` creates a `creel_connection` object that fetches
data from a REST API returning JSON arrays.

Requests follow the pattern:

    GET {base_url}/{endpoint}?{uid_param}={uid1,uid2,...}

### No API is assumed

The package ships no endpoint paths and no field names for any
organisation's API: both `endpoints` and `api_field_map` are required,
and the call aborts without them. A creel API's paths and JSON keys are
properties of that deployment, not of this package, and a built-in
default would quietly decode one agency's payload while misreading
everyone else's.

Keep the two together in a YAML profile outside your analysis code and
load it with
[`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md).
A commented template ships with the package:

    system.file("extdata", "api-profile-example.yml", package = "tidycreel.connect")

### Requests are read-only

Every request this connection makes is a `GET`. Nothing is posted,
patched or deleted, and no file is written locally, so pointing it at a
production service cannot modify anything there.

### Failed requests

Every request is retried up to three times on a status that suggests the
failure is temporary: 408, 425, 429, 500, 502, 503 and 504. Retrying is
safe because every request is a `GET`, so a repeat cannot duplicate a
side effect. A `Retry-After` header is honoured, so a throttled request
waits the interval the server asked for rather than a fixed backoff.

Any other status at or above 400 aborts on the first response, carrying
the status, the endpoint and the body: a 401 or a 404 will give the same
answer three times, and retrying only delays it.

A response that returns 200 while carrying an error document rather than
records is also refused, quoting what the API said. Nothing is wrong at
the HTTP layer there, so the alternative is reading the error object as
a record and failing later with a message that blames `api_field_map`
for a fault in the request.

### Authentication

Three auth modes are supported via the `auth` argument:

- `NULL` – no authentication (default)

- `list(type = "bearer", token = "...")` – `Authorization: Bearer`
  header

- `list(type = "api_key", key = "...", header = "X-API-Key")` –
  arbitrary header name (defaults to `"X-API-Key"` if `header` is
  omitted)

Credentials should be read from environment variables rather than stored
as plain strings:

    auth = list(type = "bearer", token = Sys.getenv("CREEL_API_TOKEN"))

#### Credentials that expire

`token` and `key` may each be a **function** returning the credential
instead of the credential itself. It is called before every request, and
again once if the API answers 401 or 403 – so a token that ages out
part-way through a paginated fetch is renewed rather than aborting the
fetch and discarding the pages already collected.

    auth = list(type = "bearer", token = function() my_oauth_client$token())

What the function does is entirely yours: an OAuth2 client-credentials
exchange, a refresh token, a shell-out to a CLI, a cached value with its
own expiry check. This package implements none of them and never will –
a token's lifetime and renewal belong to a provider, not to a creel
package, exactly as `endpoints` and `api_field_map` belong to a
deployment.

A refusal that survives one refresh aborts rather than looping: a
credential the provider keeps rejecting is a configuration problem, and
retrying it would turn a clear 401 into a hang. A fixed-string
credential is never retried at all, because the second attempt would
send the same header and get the same answer.

## Usage

``` r
creel_connect_api(
  base_url,
  creel_uids,
  schema,
  uid_param,
  endpoints,
  auth = NULL,
  api_field_map,
  pagination = NULL,
  records_path = NULL,
  total_path = NULL
)
```

## Arguments

- base_url:

  Base URL of the API, with or without a trailing slash. Example:
  `"https://api.example.org/creel/"`.

- creel_uids:

  Character vector of one or more creel UIDs to query.

- schema:

  A `creel_schema` object created by
  [`tidycreel::creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html).

- uid_param:

  Query parameter name for the creel UID list. Example: `"survey_id"`.

- endpoints:

  Named list of endpoint paths, relative to `base_url`. **Required.**
  Valid names: `interviews`, `counts`, `catch`, `harvest_lengths`,
  `release_lengths`, `discovery`. Supply the endpoints you intend to
  fetch; the matching `fetch_*()` aborts for any you omit.

- auth:

  Authentication spec (see Description). Default: `NULL`.

- api_field_map:

  Named list of raw JSON field names, keyed by endpoint (`interviews`,
  `counts`, `catch`, `harvest_lengths`, `release_lengths`, `discovery`).
  **Required.** Within each endpoint, name the raw field that holds each
  canonical quantity, e.g.
  `list(interviews = list(date = "SurveyDate", n_anglers = "PartySize"))`.
  The optional interview fields – `n_anglers`, `angler_type`, `site`,
  `circuit`, `n_counted`, `n_interviewed`, `angler_method`,
  `species_sought`, `refused`, `zip_code` – are carried only when named
  here; see
  [`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md)
  for what each one is used for.

- pagination:

  How this API paginates, or `NULL` (default) for an API that returns
  every record in one response. A named list whose `style` is one of:

  - `"page"` – a page number in the query string. Requires `page_param`;
    `start_page` defaults to `1`.

  - `"offset"` – a row offset in the query string. Requires
    `offset_param`; `start_offset` defaults to `0`. The offset advances
    by the number of rows actually received, not by an assumed page
    size.

  - `"link"` – an RFC 8288 `Link` header carrying `rel="next"`. Needs no
    other setting.

  - `"cursor"` – a pointer to the next page inside the response *body*.
    Requires `next_path` naming the member that holds it, and
    `records_path` (a cursor implies an envelope; without one the
    pointer has nowhere to live). Add `cursor_param` when the pointer is
    an opaque token to send back as a query parameter; omit it when the
    pointer is a whole URL, which is then followed the way a `Link`
    target is, relative targets included. A token is added to the
    original request rather than replacing it, so the uid filter
    survives the page turn.

    The member must be present on the *first* response, `null` included.
    Absent there is treated as a mistyped `next_path` and aborts,
    because reading it as "no more pages" would return page one as the
    whole dataset. On later pages an absent member simply ends the loop.

  - `"none"` – this API is not paginated. Declaring it is the same as
    leaving `pagination` `NULL`, but says so on purpose.

  Optional for `"page"`, `"offset"` and `"cursor"`: `page_size` (rows
  per request) and `page_size_param` (the query parameter to send it
  as). `page_size` is also the stop rule – a page shorter than it is the
  last one. Supplying it without `page_size_param` is allowed, for an
  API with a fixed page size it does not let you set. `max_pages`
  (default `1000`) bounds the loop; hitting it aborts rather than
  returning what was collected so far.

  Like `endpoints` and `api_field_map`, pagination describes one
  deployment, so nothing is assumed. What is *not* left to the caller is
  a truncated result: with no style declared, a response the connection
  can prove is incomplete – a `Link` header offering a next page, or an
  `X-Total-Count` larger than the rows returned – aborts instead of
  being returned as the whole dataset.

- records_path:

  Where the records live in the response body, for an API that wraps
  them in an envelope, or `NULL` (default) for one whose body *is* the
  JSON array of records.

  Give the member name – `records_path = "results"` for
  `{"count": 42, "results": [...]}` – or a character vector naming each
  step for a nested envelope: `records_path = c("data", "items")` for
  `{"data": {"items": [...]}}`.

  Nothing is guessed. `"results"`, `"data"` and `"value"` are all common
  and all wrong for someone, so an envelope is only read when the
  profile says where to look. What the connection does do unasked is
  refuse a body it can prove is an envelope while no `records_path` is
  set – otherwise `{"data": [...], "meta": {...}}` flattens into columns
  named `data.x` with the metadata recycled down every row, and no error
  is raised.

- total_path:

  Where the record count for the whole query lives in the envelope, or
  `NULL` (default). Named relative to the body root, the same way as
  `records_path`: `total_path = "count"` for
  `{"count": 42, "results": [...]}`.

  This is the body-borne twin of the `X-Total-Count` header, and it is
  used for one thing: when no `pagination` style is declared and the
  total exceeds the rows returned, the fetch aborts rather than handing
  back page one as the dataset. Declaring it is optional, but leaving it
  out does not disable the check – an undeclared sibling whose *name* is
  a conventional total (`count`, `total`, `total_count`, `totalCount`,
  `totalResults`) is read for this refusal too. Such a guess is never
  used to return data, only to stop.

## Value

A `creel_connection` S3 object with subclass `creel_connection_api`.

## Examples

``` r
if (FALSE) { # \dontrun{
schema <- tidycreel::creel_schema(survey_type = "instantaneous")

# Endpoints and field names both describe YOUR API, so both are required.
conn <- creel_connect_api(
  base_url   = "https://api.example.org/creel/",
  creel_uids = "survey-001",
  schema     = schema,
  uid_param  = "survey_id",
  endpoints  = list(
    interviews = "v2/interviews",
    counts     = "v2/counts"
  ),
  api_field_map = list(
    interviews = list(
      interview_uid = "InterviewID",
      date          = "SurveyDate",
      trip_status   = "TripStatus",
      effort_hours  = "HoursFished",
      n_anglers     = "PartySize"
    ),
    counts = list(
      date         = "SurveyDate",
      bank_anglers = "ShoreAnglers"
    )
  )
)

# Usual practice: keep both in a YAML profile outside your code.
conn <- creel_connect_from_yaml("~/.config/tidycreel/my-api.yml")

# Bearer token auth
conn <- creel_connect_api(
  base_url      = "https://api.example.org/creel/",
  creel_uids    = c("uid-1", "uid-2"),
  schema        = schema,
  endpoints     = my_endpoints,
  api_field_map = my_field_map,
  auth          = list(type = "bearer", token = Sys.getenv("CREEL_TOKEN"))
)
} # }
```
