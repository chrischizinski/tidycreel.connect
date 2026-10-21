# Changelog

## tidycreel.connect (development version)

- A YAML profile can name the water’s time zone with a top-level `tz:`
  key
  ([\#5](https://github.com/chrischizinski/tidycreel.connect/issues/5)),
  one IANA name from
  [`OlsonNames()`](https://rdrr.io/r/base/timezones.html), which night
  designs need (tidycreel#407).
  [`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md)
  checks it when the profile is read, keeps it on the connection as
  `conn$tz`, and sets `options(tidycreel.tz)` for the session when that
  option is unset, with a one-line message
  (`creel_message_tz_option_set`). An option already set to a different
  zone is kept, with a warning (`creel_warning_tz_option_differs`):
  replacing it could move another water’s night designs into this one’s
  zone. A `tz =` argument to
  [`tidycreel::creel_design()`](https://chrischizinski.com/tidycreel/reference/creel_design.html)
  still wins over both.

- Date parsing no longer depends on row order
  ([\#13](https://github.com/chrischizinski/tidycreel.connect/issues/13)).
  An unreadable date in the first row aborted the fetch with an
  unclassed “character string is not in a standard unambiguous format”,
  because [`as.Date()`](https://rdrr.io/r/base/as.Date.html) takes its
  format from the first value; the same value further down became `NA`
  with a warning. The format is now taken from the first value that
  reads, so an unreadable value is `NA` with
  `creel_warning_dates_coerced_na` wherever it sits. Columns that
  already parsed are read exactly as before. On the API backend an
  unreadable date below the first row used to become `NA` with no
  warning at all; it now warns too.

- [`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md)
  warns when the fetch itself makes rows exact duplicates
  ([\#1](https://github.com/chrischizinski/tidycreel.connect/issues/1)),
  with class `creel_warning_fetch_created_duplicates`. A long-format
  source, one row per interview and questionnaire answer, keeps the
  answer in columns nothing maps; dropping them left identical rows, and
  because tidycreel keeps a repeated `interview_uid`, each copy counted
  that interview’s effort and catch again. The warning gives the row
  counts and names the source columns that told the rows apart, saying
  which were dropped and which were carried but coerced or mapped to the
  same value. Nested JSON columns are compared too. Rows already
  identical in the source are not counted. The rows are returned
  unchanged: collapse them, or map the distinguishing column, before
  [`add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html).

- The note naming the source columns a fetch did not carry through (“Map
  what you need downstream via `api_field_map`…”) now prints once per
  connection for each table, not on every fetch. It describes the
  source, which is the same on every fetch, and repeated on every table
  it buried the warnings that matter. A later fetch that drops different
  columns, or a new connection, prints it again. The note about columns
  taken by canonical name follows the same rule.

- Every warning and message has a class, following tidycreel’s
  ([\#496](https://github.com/chrischizinski/tidycreel.connect/issues/496)):
  each warning `creel_warning_<fact>` with parent `creel_warning`, each
  note `creel_message_<fact>` with parent `creel_message`.
  [`?connect_warnings`](https://chrischizinski.com/tidycreel.connect/reference/connect_warnings.md)
  lists them with their tiers. Handle one with
  [`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html)
  instead of silencing everything with
  [`suppressMessages()`](https://rdrr.io/r/base/message.html). Facts
  tidycreel also raises use tidycreel’s class
  (`creel_warning_dates_coerced_na`,
  `creel_warning_repeated_sampling_units`,
  `creel_message_argument_ignored`).

- [`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md)’s
  note that `schema` column mappings are ignored is now a message
  (`creel_message_argument_ignored`), not a warning: an argument with no
  effect is information, as in tidycreel. Code that caught it with
  `expect_warning()` or
  [`suppressWarnings()`](https://rdrr.io/r/base/warning.html) needs
  `expect_message()` or
  [`suppressMessages()`](https://rdrr.io/r/base/message.html).

- A `value_maps` entry for `angler_method` or `species_sought` is
  applied at the fetch instead of aborting
  (chrischizinski/tidycreel#532). tidycreel accepts a map for either
  from the version that closes
  [\#532](https://github.com/chrischizinski/tidycreel.connect/issues/532);
  until now the translation step asked
  [`tidycreel::creel_vocabulary()`](https://chrischizinski.com/tidycreel/reference/creel_vocabulary.html)
  for the column’s vocabulary, which aborts for both. A free-label map’s
  own labels are the column’s vocabulary: values already labelled pass
  through, and a code the map does not declare is still refused.

- [`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md)
  carries `angler_method`, `species_sought`, `refused` and `zip_code`,
  the columns tidycreel’s interview summaries read
  ([`summarize_by_method()`](https://chrischizinski.com/tidycreel/reference/summarize_by_method.html),
  [`summarize_by_species_sought()`](https://chrischizinski.com/tidycreel/reference/summarize_by_species_sought.html),
  [`summarize_refusals()`](https://chrischizinski.com/tidycreel/reference/summarize_refusals.html),
  [`summarize_by_zip()`](https://chrischizinski.com/tidycreel/reference/summarize_by_zip.html))
  ([\#3](https://github.com/chrischizinski/tidycreel.connect/issues/3)).

  Before, a field named under one of these in `api_field_map` was still
  dropped, so a report needed a second, raw fetch. They are optional,
  opt-in columns like `n_anglers`: map them through `api_field_map` on
  the API, or `angler_method_col`, `species_sought_col` and
  `refused_col` in
  [`tidycreel::creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html)
  on CSV and SQL.
  [`creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html)
  has no `zip_code_col`, so there `zip_code` is carried only from a
  source column already named `zip_code`.

  `refused` arrives as logical. TRUE/FALSE, T/F, yes/no, Y/N and 1/0 are
  read in any case; any other code aborts, because a refusal read as
  `NA` drops out of
  [`summarize_refusals()`](https://chrischizinski.com/tidycreel/reference/summarize_refusals.html)
  silently. Pass it to `add_interviews(refused =)` so a refused
  interview is not taken for a no-catch party. `zip_code` arrives as
  text, with a whole number padded back to five digits so a ZIP parsed
  as a number keeps its leading zero.

  `angler_method` and `species_sought` are carried as the source codes
  them; a free-label `value_maps` entry translates them (see above).

## tidycreel.connect 0.5.0

### Breaking changes

- Requires `tidycreel (>= 7.0.0)`, raised from `>= 5.0.0`.

  Two things in this release depend on tidycreel 7.0.0 specifically, and
  neither fails in a way that would point at the version. The character
  identifier normalisation below is applied on both sides — this package
  coerces `fetch_*()` output, tidycreel coerces again at
  [`add_catch()`](https://chrischizinski.com/tidycreel/reference/add_catch.html)
  — and against tidycreel 6.0.0 the design side still produces numeric
  ids, so a join that looks fine here breaks downstream. And
  `test-composition-calamus.R` resolves its fixture through
  `system.file("calamus-2016", package = "tidycreel")`, which only
  exists from 7.0.0; on 6.0.0 those eight tests skip rather than fail,
  reporting a green run that asserted nothing.

  The floor had sat at 5.0.0 since that release and was never exercised,
  so it had stopped describing what this package actually needs.

- `fetch_*()` returns character identifier columns from every backend.

  The CSV reader inferred a bare integer id as numeric while the API
  served the same ids as strings, so the backend a caller chose decided
  the type of their join key. `interview_uid`, `catch_uid`, `length_uid`
  and `age_uid` are now character everywhere, matching the normalisation
  tidycreel applies at
  [`add_catch()`](https://chrischizinski.com/tidycreel/reference/add_catch.html),
  [`add_lengths()`](https://chrischizinski.com/tidycreel/reference/add_lengths.html)
  and
  [`add_ages()`](https://chrischizinski.com/tidycreel/reference/add_ages.html).

  Two related inconsistencies went with it: the empty-lengths and
  empty-catch frames declared `integer(0)` ids beside `character(0)`
  ones, so a quiet day returned different types from a busy one; and a
  synthesised `catch_uid` was a row index rather than a label.

- [`list_creels()`](https://chrischizinski.com/tidycreel.connect/reference/list_creels.md)
  and
  [`search_creels()`](https://chrischizinski.com/tidycreel.connect/reference/search_creels.md)
  still abort on a database connection, but now as a statement rather
  than a placeholder, with the condition class
  `creel_error_discovery_unavailable`
  ([\#185](https://github.com/chrischizinski/tidycreel.connect/issues/185)).

  Discovery asks a source which surveys it holds. A database connection
  is already pointed at one set of tables and has no catalogue to
  enumerate without inventing a convention for how an agency names or
  partitions surveys — exactly the organisation-specific knowledge this
  package does not carry. The previous wording, “not supported”, read as
  “not yet” and invited an implementation that cannot exist. Use the API
  backend, whose service defines discovery.

### New features

- `auth$token` and `auth$key` may be a **function**, for credentials
  that expire
  ([\#349](https://github.com/chrischizinski/tidycreel.connect/issues/349)).

  A paginated fetch can outlive a short-lived token. Until now page
  three would answer 401, the fetch would abort, and pages one and two
  were discarded with nothing said about them.

  ``` r

  auth = list(type = "bearer", token = function() my_oauth_client$token())
  ```

  The function is called before every request, and once more if the API
  answers 401 or 403 — so an expired token is renewed rather than ending
  the fetch. What it does is entirely yours: an OAuth2 exchange, a
  refresh token, a shell-out to a CLI, a cached value with its own
  expiry check. This package implements none of them, for the same
  reason it ships no endpoint paths or field names: a token’s lifetime
  belongs to a provider, not to a creel package.

  A refusal that survives one refresh aborts rather than looping — a
  credential the provider keeps rejecting is a configuration problem,
  and retrying it would turn a clear 401 into a hang. A fixed-string
  credential is never retried at all, because the second attempt would
  send the same header and get the same answer.

- A rejected credential says which shape is configured, and a mid-fetch
  failure says what it is discarding.

  A 401 used to read exactly like a mis-mapped field to anyone who had
  not seen the configuration. It now names what the connection was set
  up with — no credentials at all, a fixed string that cannot be
  renewed, or a function whose result the API still refused — and what
  to change.

  Separately, an **HTTP failure** part-way through a paginated fetch now
  reports how many pages and rows had already been collected and are
  being thrown away. Returning them is not an option, because a partial
  dataset understates every total without saying so; but neither is
  letting the reader think one request failed when several succeeded.

  That note is carried on the HTTP status path only. A mid-loop abort
  from somewhere else — an unreadable body, an error document on page
  two — still discards the earlier pages without mentioning them.
  Narrowed deliberately after review pointed out that the first wording
  claimed more than the code does; widening it means threading page
  context through the parse path, which belongs with that code rather
  than with this change.

- HTTP status handling covers more than the 429/503 pair
  ([\#349](https://github.com/chrischizinski/tidycreel.connect/issues/349)).

  Only 429 and 503 were treated as worth retrying. A 502 from a load
  balancer, a 504 from a slow upstream, a 408 — each aborted the whole
  fetch on its first response, and for a paginated fetch that discards
  the pages already collected. The transient set is now 408, 425, 429,
  500, 502, 503 and 504.

  Retrying is safe here because every request this backend makes is a
  `GET`, so a repeat cannot duplicate a side effect, and the cost of
  retrying a genuinely permanent failure is bounded at three tries.
  Anything else at or above 400 still aborts on the first response: a
  401 or a 404 gives the same answer three times, and retrying only
  delays it.

- A 200 response carrying an error document is refused, quoting the API.

  Some APIs report a bad request with a 200 and an error object, so the
  status check never sees it. Read as data, the object became one
  record, every mapped field missed, and the fetch died at the validator
  saying `date: column missing` — blaming `api_field_map` for a fault in
  the request. The API said `invalid survey_id`; the package said your
  configuration was wrong.

  The test is deliberately narrow, because `message` is an ordinary
  field name. All three must hold: the body is a JSON object rather than
  an array, it carries a conventionally-named error member with
  something in it, and **not one** of the raw fields configured for that
  endpoint is present.

  A fourth condition came out of the pre-push review, which caught the
  first version refusing a perfectly good enveloped response. With
  `records_path` set the mapped fields live *inside* the envelope, so
  none of them appears at the top level and
  `{"results": [...], "message": "partial day"}` looked like an error —
  which would have broken exactly the enveloped and cursor APIs the
  previous two entries added. A records member that resolves is now
  proof the body carries records, whatever sits beside them.

  `Retry-After` needed no work: **httr2 already honours it.**
  [\#349](https://github.com/chrischizinski/tidycreel.connect/issues/349)
  recorded it as unhandled and that was wrong — timed at 4.08s for two
  2s waits against a real server. A test pins it so the claim is not
  inherited again.

- `pagination` gains `style = "cursor"`, now that there is an envelope
  to read it from.

  A cursor arrives in the response *body*, so while this backend read
  only a bare JSON array the style had nowhere to look and was refused
  by name. The `records_path` work in the same release removed that
  obstacle, and leaving the refusal in place would have meant shipping a
  message that said a capability was impossible while the code to do it
  sat one function away.

  ``` r

  # the body holds a whole URL — followed the way a Link target is
  pagination = list(style = "cursor", next_path = "next")

  # the body holds an opaque token — sent back as ?cursor=...
  pagination = list(style = "cursor", next_path = "next", cursor_param = "cursor")
  ```

  `records_path` is required: a cursor with no envelope around it is a
  contradiction rather than a configuration, and the constructor says
  so. A token is **added to** the original request rather than replacing
  it, so the uid filter survives every page turn — a replacement would
  drop it, and an API that reads a missing filter as “every survey”
  would return other surveys’ rows, which is a wrong dataset carrying no
  sign that it is wrong.

  `next_path` must resolve on the **first** response, `null` included.
  Absent there is treated as a typo and aborts, because reading it as
  “no more pages” would return page one as the complete dataset — the
  same silent truncation the review caught in `total_path`. On later
  pages an absent member just ends the loop, since plenty of APIs stop
  sending the key rather than sending null.

  `page_size` / `page_size_param` work for a cursor too — found by the
  pre-push review, which caught them being accepted by the validator and
  then dropped, the exact “silently ignored setting” this validator
  refuses everywhere else. The short-page **stop rule** is deliberately
  not applied to a cursor: the pointer is authoritative, and an API may
  return a short page while still offering a next one.

- [`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md)
  gains `records_path` and `total_path`, for an API that wraps its
  records in an envelope
  ([\#330](https://github.com/chrischizinski/tidycreel.connect/issues/330)
  item 2, schema half).

  Until now the connection assumed the response body *was* the JSON
  array of records. That is one convention among several: Django REST
  Framework returns `{"count": 42, "results": [...]}`, JSON:API and
  Laravel use `data`, OData uses `value`, and some APIs nest a level
  further. Pointed at any of them this package could not fetch at all —
  and the reason it gave was misleading, since
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  flattens `{"data": [...], "meta": {...}}` into columns named
  `data.SurveyDate` with the metadata recycled down every row, so the
  failure surfaced from the validator as “column missing” and pointed at
  the field map.

  Say where the records are and they are read:

  ``` r

  creel_connect_api(..., records_path = "results")       # {"results": [...]}
  creel_connect_api(..., records_path = c("data", "items"))
  ```

  Nothing is guessed — `"results"`, `"data"` and `"value"` are each
  right for some deployment and wrong for the rest, so an envelope is
  only read when the profile says where to look. What *is* automatic is
  the refusal: a body that can be proven to be an envelope now aborts
  naming the member that looks like the records, instead of being
  flattened.

  `total_path` names the whole-query count an envelope usually carries
  in place of an `X-Total-Count` header. With no pagination style
  declared, a total larger than the rows returned aborts rather than
  passing page one off as the dataset — the same guard the header
  already had, which supporting envelopes without it would have left
  open for exactly the enveloped APIs. Declaring it is optional: a
  sibling conventionally named `count`, `total`, `total_count`,
  `totalCount`, `totalResults` or `recordCount` is read for that refusal
  too. Such a guess is only ever used to stop, never to decide what to
  return.

  Both keys are settable from a YAML profile.

- A mapped field that arrives as nested JSON is refused by name.

  `{"ShoreAnglers": {"bank": 4, "pier": 1}}` parses to a data.frame
  column and a ragged `{"ShoreAnglers": [4, 1]}` to a list column.
  Neither is a measurement, and both used to fail somewhere downstream
  with a base-R message — `replacement has 2 rows, data has 1`, or
  `'list' object cannot be coerced to type 'double'` — that named
  neither the field nor the endpoint. The fetch now aborts saying which
  raw field, which canonical name it was mapped to, and whether it held
  an object or an array. A nested member the field map never asks for is
  still dropped, as any other unmapped column is.

- The test suite now runs against a real HTTP server
  ([\#330](https://github.com/chrischizinski/tidycreel.connect/issues/330)
  item 2, transport half).

  Every other API test here uses
  [`httr2::local_mocked_responses()`](https://httr2.r-lib.org/reference/with_mocked_responses.html),
  which intercepts **below** `req_perform()` — so until now nothing in
  this package had ever performed a request. The field mapping and
  validators were well covered; the transport was not covered at all.
  The retry and error policies, the JSON deserialisation, the `Link`
  header parser, the pagination loop and the auth header had only ever
  been asserted against responses this package constructed for itself.

  `test-live-http.R` stands up a `webfakes` server that serves the
  `calamus-2016` fixture as JSON over a real socket, and asserts the
  whole chain: request, parse, rename, coercion. The payload is real
  survey data, and one test asserts that the same rows fetched over HTTP
  and off disk are identical once canonical — so anything the transport
  could corrupt shows up as a difference.

  `webfakes` is a `Suggests`; the file skips cleanly without it.

  A local server cannot tell you that a real deployment named a field
  something you did not expect. What it closes is the transport half,
  which is most of what “nothing has ever run against a real endpoint”
  was costing.

- The response *shapes* an arbitrary API may return are now enumerated
  in a test matrix.

  `test-api-shapes.R` points the connection at one `webfakes` server
  that returns the same three records under twenty different wrappers:
  bare array, four envelope conventions, a nested envelope, a single
  object instead of a one-element array, quoted numbers, an explicit
  `null` beside an absent key, nested members mapped and unmapped, an
  empty array, an empty envelope, and two body-carried truncations. Each
  shape is either read correctly or refused with a message naming what
  to change.

  The payload is deliberately synthetic and three rows wide: when a
  shape test fails it should be the shape that failed, not the
  arithmetic. `test-live-http.R` keeps the calamus fixture for the
  end-to-end assertion.

  Eleven of these pass against the previous release and fifteen do not,
  which is the measurement worth keeping: the shapes that already worked
  are the ones that still work.

  Five more shapes were added after the pre-push review, which found
  three real defects in the first version of this work – two of them
  independently, by two different models. A body total arriving quoted
  (`{"count": "9"}`) was ignored rather than acted on, so the new
  truncation guard did nothing for an API that types its counts as
  strings. A `total_path` that resolved to nothing was swallowed,
  leaving a profile that looked guarded and was not. And the envelope
  check first asked only whether a member held a container, which is
  true of an ordinary metadata object – so a single record returned as
  `{"SurveyDate": ..., "Audit": {...}}` was refused as a wrapper, a
  shape that reads correctly on the previous release.

- The DBI backend loads data
  ([\#185](https://github.com/chrischizinski/tidycreel.connect/issues/185)).
  SQL Server via ODBC works, and so does any other DBI driver.

  Until now a database connection opened, reported itself open, and
  aborted on every `fetch_*()` call. Each fetcher now reads its table by
  the name the schema gives it and puts the rows through the same
  rename, coercion, value-map and validation stages the CSV backend uses
  — the read is the only backend-specific step, so a frame fetched from
  a database and the same rows fetched from CSV come back identical,
  which the tests assert directly.

  Table names come from `interviews_table`, `counts_table`,
  `catch_table` and `harvest_lengths_table` / `release_lengths_table`. A
  table the schema does not name is refused, naming the setting that is
  missing: unlike a column, there is no canonical table name to fall
  back on, and guessing would mean querying whatever happened to match.

  A table name may be a string or a
  [`DBI::Id()`](https://dbi.r-dbi.org/reference/Id.html).
  [`Id()`](https://dbi.r-dbi.org/reference/Id.html) is what reaches a
  schema-qualified table —
  `DBI::Id(schema = "dbo", table = "vwInterviews")` — since the string
  `"dbo.vwInterviews"` is one literal name and is not found.

- Database connections now carry the class `creel_connection_dbi`, with
  `creel_connection_sqlserver` kept alongside it
  ([\#185](https://github.com/chrischizinski/tidycreel.connect/issues/185)).
  Nothing in the read path is SQL Server specific — the test suite
  exercises it on duckdb — so the methods live on the general name. The
  old name stays in the class vector and every method is registered for
  it too, so existing code that dispatches on it is unaffected.

### Bug fixes

- A relative `Link` target is resolved against the request URL before
  being followed
  ([\#330](https://github.com/chrischizinski/tidycreel.connect/issues/330)
  item 2 work).

  RFC 8288 permits a relative target and servers emit one. Left as-is it
  reached
  [`httr2::request()`](https://httr2.r-lib.org/reference/request.html)
  as `"/v2/interviews?page=2"` and died inside curl with no host — so
  `pagination = list(style = "link")` worked only against servers that
  happened to return absolute URLs.

  **No mocked test could have caught this**, and none did: a mocked
  response is never actually requested, so a target that cannot be
  turned into a request looks perfectly healthy. It was found within
  minutes of pointing the package at a real server. Guarded now in both
  suites.

- `test-composition-calamus.R` runs. All eight of its tests had been
  skipping on every run, CI included, because the fixture they need
  lived under tidycreel’s `inst/extdata/` — which that package
  `.Rbuildignore`s, so it never reached an installed copy and
  [`system.file()`](https://rdrr.io/r/base/system.file.html) returned
  nothing.

  These are this package’s only end-to-end assertions against real
  reference numbers: CSV through `fetch_*()`,
  [`creel_design()`](https://chrischizinski.com/tidycreel/reference/creel_design.html),
  [`add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html)
  and
  [`add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html)
  to the estimators, compared against Calamus 2016. The most valuable
  tests here were the ones silently not executing.

  That change took the suite from **437 passing with 9 skips** to **461
  with 1**. (Stated as the delta rather than a running total: a current
  count written into a release note is wrong by the next release.)
  Nothing in this package changed to achieve it beyond the fixture path;
  the code under those tests was correct the whole time.

- The API backend follows pagination, and refuses a response it can
  prove is only part of the data
  ([\#330](https://github.com/chrischizinski/tidycreel.connect/issues/330)).

  `.api_fetch()` performed one request and returned its body as the
  complete dataset. Against a paginated endpoint that meant page 1 and
  nothing else: fewer interviews and fewer counts reached the design,
  every total was understated in proportion to what was dropped, and
  nothing errored or warned. Measured on a mocked three-page endpoint
  holding five interviews, the fetch returned **two** of them and **4 of
  10 effort-hours** — 60% of the effort missing, with a believable
  number in its place.

  [`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md)
  takes a new optional `pagination` argument, also settable as a
  `pagination:` block in a YAML profile. Its `style` is one of `"page"`
  (a page number in the query string), `"offset"` (a row offset, which
  advances by the rows actually received rather than an assumed page
  size), `"link"` (an RFC 8288 `Link` header with `rel="next"`), or
  `"none"`. A declared style is followed to exhaustion.

  Like `endpoints` and `api_field_map`, pagination describes one
  deployment, so nothing is assumed. What is no longer left to the
  caller is a truncated result: with no style declared, a response
  carrying a `Link` header offering a next page, or an `X-Total-Count`
  larger than the rows returned, now aborts rather than being read as
  the whole dataset. A connection against an unpaginated API is
  unaffected.

  Three ways a paging loop can go wrong also abort rather than return a
  wrong number: two consecutive pages of identical rows (the API is
  ignoring the paging parameter, and binding them would duplicate every
  record), pages describing different fields (binding would align values
  under the wrong names), and `max_pages` being reached (the pages
  collected so far are *not* returned, because a partial dataset
  understates every total without saying so).

  Two settings that would silently disagree are also refused at
  connection time: a paging parameter named the same as `uid_param`
  (httr2 replaces rather than appends, so the paging value would
  overwrite the survey filter and an API reading a missing filter as
  “every survey” would return other surveys’ rows), and two paging
  settings naming the same parameter.

  A cursor style was refused by name at this point, because a cursor
  arrives in a response envelope this backend did not read. That reason
  expired when `records_path` shipped; `style = "cursor"` is supported
  now (see below).

- A YAML profile setting `harvest_lengths_table` or
  `release_lengths_table` aborted with R’s bare “unused arguments”
  error, naming no cause
  ([\#185](https://github.com/chrischizinski/tidycreel.connect/issues/185)).
  The loader has offered both keys since
  [\#176](https://github.com/chrischizinski/tidycreel.connect/issues/176)
  and passed them to
  [`tidycreel::creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html),
  which accepted neither. Both are now schema arguments and fall back to
  `lengths_table`.

- `test-composition-calamus.R` asserted a catch-total SE of 55.7239 for
  the unfiltered fixture, and had been failing since
  [\#198](https://github.com/chrischizinski/tidycreel.connect/issues/198)
  ([\#185](https://github.com/chrischizinski/tidycreel.connect/issues/185)).
  [\#198](https://github.com/chrischizinski/tidycreel.connect/issues/198)
  moved bus-route variance onto the day PSU and re-baselined
  `reference-outputs.csv`, but this sibling assertion was missed.

  The behaviour is correct: the two incomplete rows are both zero-catch
  and fall on the same date, so admitting them changes no day’s total
  and the SE does not move. The test now asserts that, and additionally
  gives those rows a catch and requires the SE to move — otherwise it
  would keep passing if the variance stopped responding to the data at
  all.

### Documentation

- The example field names in the profile templates, README, vignette and
  tests no longer reuse a real agency’s API field names.

  Three catch, length and trip field names were carried over from the
  source survey this package was first written against, and they were
  still shipped in `api-profile-example.yml`, `csv-profile-example.yml`,
  the README and the getting-started vignette as though invented. They
  are now `CatchCategory`, `LengthBand` and `TripKind`, which belong to
  no one.

  Every raw name in this package’s examples describes an imaginary API.
  That is the point of them: the package ships no organisation’s field
  names, and a template that quietly carried three real ones undercut
  the rule it exists to demonstrate. Example values only — no behaviour
  changes, and anyone using a profile of their own is unaffected.

## tidycreel.connect 0.4.0

### New features

- A YAML profile can declare what the source’s columns are called, under
  a new `columns:` block inside `schema:`
  ([\#176](https://github.com/chrischizinski/tidycreel.connect/issues/176)).
  The CSV backend resolves every canonical column through the schema, so
  before this a profile only worked against a source whose columns
  already carried tidycreel’s names — the one case where a schema is not
  needed at all. Keys are canonical names with no `_col` suffix,
  matching the way `value_maps` is keyed:

  ``` yaml
  schema:
    survey_type: instantaneous
    columns:
      interview_uid: InterviewID
      date: SurveyDate
  ```

  A key that is not a canonical column name aborts and names itself, as
  does one written with the `_col` suffix. `backend: api` reads raw JSON
  keys from `field_map` and ignores column mappings, so a `columns:`
  block there is an error rather than a silent no-op.
  `backend: sqlserver` accepts the block, but its loaders are not
  implemented (see below), so nothing reads it yet.

- A commented CSV profile template ships alongside the API one, at
  `system.file("extdata", "csv-profile-example.yml", package = "tidycreel.connect")`.
  Every column name in it is invented; the package ships none for any
  organisation’s export.

- A source that already uses tidycreel’s canonical column names no
  longer needs a schema entry for each of them
  ([\#168](https://github.com/chrischizinski/tidycreel.connect/issues/168)).
  `fetch_*()` falls back to the canonical name when nothing is mapped —
  the same fallback the strata columns already used on the API path — so
  an already-canonical export loads with
  `creel_schema(survey_type = ...)` alone. Before this, loading a column
  named `date` required writing `date_col = "date"`, which made the one
  case that needs no schema the case that still needed one.

  The columns taken that way are named in a message, because an
  undeclared column is one the caller has not asserted the meaning of.
  Declaring it silences that.

  An entry naming a column the source does not have is **not** rescued
  by a canonically-named one. It stays a drop and is reported as such: a
  mapping that does not match the source is a configuration error, and
  substituting a different column would hide it.

  This narrows the guarantee added in
  [\#126](https://github.com/chrischizinski/tidycreel.connect/issues/126),
  deliberately. That change made an unmapped optional column absent
  rather than `NA`, so that absence could mean “this source does not
  record party size”. Absence still means that — but a source that
  records party size in a column called `n_anglers` now has it carried
  through instead of dropped, because dropping a column sitting in plain
  sight under its own canonical name is the failure
  [\#126](https://github.com/chrischizinski/tidycreel.connect/issues/126)
  existed to prevent: without `n_anglers`,
  [`add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html)
  falls back to one angler per interview and party-hours are consumed as
  angler-hours. A column recorded under the source’s own name is still
  never guessed at.

### Documentation

- The docs said connections are read-only nowhere, so a user pointed at
  an agency’s production database had to read the source to establish it
  ([\#169](https://github.com/chrischizinski/tidycreel.connect/issues/169)).
  [`?creel_connect`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect.md),
  [`?creel_connect_api`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md)
  and the getting-started vignette now state it: no table is created,
  altered, dropped or written to, no row is inserted or updated, and no
  file is written — including the CSV files a connection reads. The API
  backend issues `GET` requests only.

- **The SQL Server backend was described as working, and is not.** All
  five of its `fetch_*()` methods are stubs that abort with “not yet
  implemented”, as do
  [`list_creels()`](https://chrischizinski.com/tidycreel.connect/reference/list_creels.md)
  and
  [`search_creels()`](https://chrischizinski.com/tidycreel.connect/reference/search_creels.md),
  while `DESCRIPTION`, the README and the vignette all listed it as a
  supported source of data. Those now say plainly that a SQL Server
  connection can be constructed but not fetched from. New tests pin the
  five stubs so implementing them fails the tests that describe them as
  missing.

- The README’s CSV example built a
  [`creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html)
  object that it then never passed to anything — the
  [\#176](https://github.com/chrischizinski/tidycreel.connect/issues/176)
  gap in miniature. It now shows the mapping where it belongs, in the
  profile’s `columns:` block.

### Bug fixes

- A fetch that mapped no columns at all reached its `validate_fetch_*()`
  abort behind two tibble deprecation warnings, because the empty rename
  set names to `NULL`. The abort is unchanged — it is the one that names
  every required column — and now arrives on its own.

## tidycreel.connect 0.3.0

### New features

- The fetch layer translates coded source vocabularies into the
  canonical ones, driven by the new `value_maps` field on
  [`tidycreel::creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html)
  ([\#128](https://github.com/chrischizinski/tidycreel.connect/issues/128)).
  A source that writes `"1"`/`"2"` for trip status, or `"H"`/`"R"` for
  catch type, declares what its codes mean once in the schema;
  [`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md),
  [`fetch_catch()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_catch.md)
  and both lengths fetchers then deliver `"complete"`, `"harvested"` and
  the rest — the literals every downstream filter matches.

  Values already canonical for the column pass through untouched, so a
  source mid-migration that codes only some of its rows still arrives
  whole. A value that is neither mapped nor canonical **aborts at the
  fetch**, naming the offending value. The design layer does refuse an
  unknown vocabulary (`validate_trip_metadata()`,
  [`add_catch()`](https://chrischizinski.com/tidycreel/reference/add_catch.html)),
  so this is not what stops a wrong number; what it stops is the hand
  recode that abort otherwise invites, which folds an undeclared third
  code (`"refused"`, `"unknown"`) into whichever of the two the caller
  happened to think of, silently.

  Declaring a map is opt-in and backend-independent: a schema without
  one fetches exactly as before, and the API path reads `value_maps`
  just as the CSV path does, since it maps a column’s *values* rather
  than its field name.

- The ingestion seam is now covered end to end
  ([\#130](https://github.com/chrischizinski/tidycreel.connect/issues/130)).
  `test-composition-calamus.R` composes the whole path — CSV →
  `fetch_*()` →
  [`creel_design()`](https://chrischizinski.com/tidycreel/reference/creel_design.html)
  →
  [`add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html)/[`add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html)
  → estimators — and asserts the result against
  `inst/extdata/calamus-2016/reference-outputs.csv` in tidycreel. Every
  previous test in this package checked a fetched frame’s columns, types
  and values and stopped there, which is why
  [\#126](https://github.com/chrischizinski/tidycreel.connect/issues/126)
  through
  [\#129](https://github.com/chrischizinski/tidycreel.connect/issues/129)
  all shipped undetected: each was a column that existed upstream and
  never reached the calculation, and a column-level test cannot see
  that. Standard errors are asserted alongside the point estimates,
  because that is where a dropped component hides.

  All three estimands and all three standard errors now reproduce.
  `catch_total`’s SE at first did not (52.9963 computed against 55.7239
  recorded) with its point estimate identical, and was held as an
  explicit skip rather than absorbed into a tolerance while
  [\#178](https://github.com/chrischizinski/tidycreel.connect/issues/178)
  established why. It was the reference that was stale: v3.0.0 put the
  bus-route catch total behind `br_complete_trips_only()` and the v1.7.0
  file predates that. The reference row is re-baselined in tidycreel and
  the skip is replaced by a test that asserts the mechanism — that
  relabelling the fixture’s two zero-catch incomplete rows recovers the
  pre-v3.0.0 SE exactly while leaving the point estimate where it was.

- A synthetic boat-count fixture makes the boat→angler seam reachable
  ([\#130](https://github.com/chrischizinski/tidycreel.connect/issues/130)).
  Every real fixture in the repo is a bank-only fishery, so
  [`derive_angler_count()`](https://chrischizinski.com/tidycreel/reference/derive_angler_count.html)’s
  reconstruction path could not be exercised end to end.
  `inst/extdata/synthetic-boat-counts/` is fabricated and says so; it is
  used to assert the seam only — that boat counts survive the fetch and
  change the estimate by exactly `sum(angler_boats) × party_size` —
  never against a reference value, because invented counts validate
  nothing.

  Exercised on an instantaneous design deliberately: on a bus-route
  design effort comes from the interview-side Horvitz–Thompson
  estimator, so the counts table never enters
  [`estimate_effort()`](https://chrischizinski.com/tidycreel/reference/estimate_effort.html)
  and bank-only and reconstructed counts return the identical total — a
  seam test built there would pass whatever the fetch layer did.

- [`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md)
  accepts `backend: api`, reading `base_url`, `uid_param`, `creel_uids`,
  `endpoints` and `field_map` from the profile.

- A commented template profile ships with the package, with every name
  invented:

  ``` r

  system.file("extdata", "api-profile-example.yml", package = "tidycreel.connect")
  ```

- `fetch_*()` aborts with a clear message when the connection describes
  no endpoint path, or no field names, for the endpoint being fetched –
  rather than fetching and then discarding every column, which surfaced
  as a “column missing” validation error pointing nowhere near the
  cause.

### Bug fixes

- The dependency on tidycreel is now declared as `tidycreel (>= 5.0.0)`
  rather than left unversioned. `fetch_*()` calls
  [`tidycreel::creel_vocabulary()`](https://chrischizinski.com/tidycreel/reference/creel_vocabulary.html),
  which tidycreel first exported in 5.0.0, so against an older tidycreel
  the package installed cleanly and then aborted at run time with
  `'creel_vocabulary' is not an exported object from 'namespace:tidycreel'`
  – and only on the value-map path, so everything else looked fine.
  [`derive_angler_count()`](https://chrischizinski.com/tidycreel/reference/derive_angler_count.html)
  is a quieter case of the same coupling: 5.0.0 made it drop the columns
  it consumed, and against 4.0.0 those columns survive with no error at
  all.

  Nothing could have caught this. The check workflow installs tidycreel
  with `local::..`, from the repo root at the same commit, so connect is
  only ever tested against the tidycreel beside it and no version skew
  is reachable in CI. The documented install path in `README.md` takes
  both packages from the default branch and stays consistent; the break
  needs an older tidycreel already installed and an `install_github()`
  of connect alone, which `remotes` will not upgrade precisely because
  no version was required.

- [`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md)
  now carries the time of a count, and says so when it cannot
  ([\#129](https://github.com/chrischizinski/tidycreel.connect/issues/129)).
  A count row is one observation at one moment, not a day’s total, and a
  source that records several counts per sampled day distinguishes them
  by time alone. No schema field could name that time and neither counts
  rename map carried it, so the rows arrived indistinguishable:
  [`add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html)
  read them as separate sampled days, summing the day’s effort instead
  of averaging it to a daily mean, and the within-day variance component
  was never computed. On a two-counts-per-day fixture the effort
  estimate came out at twice its value, with `se_within` reported as `0`
  where the component had simply never been calculated.

  [`add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html)
  did warn (CNT-06) and told the caller to supply `count_time_col` — a
  column the fetch layer had just dropped, so the advice could not be
  followed from a fetched frame. Map `count_time_col` (CSV/SQL) or the
  `count_time` field (API field map), and
  [`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md)
  now warns when it returns repeat rows on a date and no count time was
  mapped, keyed on date plus strata the way
  [`add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html)
  keys its own sampling unit — two sections counted on one day are two
  units, not a repeat.

  The column is carried as written. `readr` reads `"16:30"` as a time
  and hands back `"16:30:00"`, so a mapped count time is now read as
  character: the fetch must not reinterpret a label whose format belongs
  to the source.

- [`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md)
  documentation no longer recommends `count_col = bank_anglers` as the
  runnable example
  ([\#129](https://github.com/chrischizinski/tidycreel.connect/issues/129)).
  On any fishery with boat anglers that silently omits an entire
  component of effort. The example now uses
  [`tidycreel::derive_angler_count()`](https://chrischizinski.com/tidycreel/reference/derive_angler_count.html),
  which
  [\#126](https://github.com/chrischizinski/tidycreel.connect/issues/126)
  made available, and the documented return value lists the stratum
  columns
  [`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md)
  has carried since
  [\#171](https://github.com/chrischizinski/tidycreel.connect/issues/171).

- [`fetch_harvest_lengths()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_harvest_lengths.md)
  and
  [`fetch_release_lengths()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_release_lengths.md)
  now carry a length-bin label and its fish count
  ([\#127](https://github.com/chrischizinski/tidycreel.connect/issues/127)).
  A source that reports released fish as length groups has two
  quantities per row — the bin and the number of fish in it — and the
  fetch layer carried neither: there was no canonical count column
  anywhere in the package, and the only place to put a label was
  `length_mm`, where
  [`as.numeric()`](https://rdrr.io/r/base/numeric.html) turned “300-350”
  into `NA`. A distribution built from a fetched binned frame was
  therefore weighted by **row multiplicity rather than by fish**,
  biasing released length frequencies, mean length, and the biomass of
  released fish toward the bins a crew happened to record most often.
  Nothing errored and nothing warned; the numbers looked ordinary. Bins
  holding 1 and 5 fish now total 6, where they previously totalled 2.

  Map `length_bin_col` and `length_count_col` on
  [`tidycreel::creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html)
  for CSV and SQL sources, or `length_bin` and `count` in
  `api_field_map` for the API backend, then pass the fetched
  `length_bin` as
  [`add_lengths()`](https://chrischizinski.com/tidycreel/reference/add_lengths.html)’s
  `length` with `release_format = "binned"`. Both are optional and both
  tables accept them, so a source that measures every fish is
  unaffected. Carrying a bin with no count now warns at the fetch, and a
  lengths table offering neither a measurement nor a bin is refused
  rather than returned empty-handed.

- A YAML profile can now declare `strata_cols` and `value_maps`. The
  loader built its schema from `survey_type` and table names alone, so
  neither field survived the profile — the route the docs recommend for
  configuring a deployment. A profile-configured survey therefore could
  not be stratified at all: the counts frame arrived with no stratum
  label and any design built with `strata =` aborted, which is the
  failure
  [\#171](https://github.com/chrischizinski/tidycreel.connect/issues/171)
  fixed for a hand-built schema and left standing here. Both YAML shapes
  of `strata_cols` are accepted, the mapping `day_type: DayTypeCode` and
  the bare sequence `[day_type]`.

- [`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md)
  and
  [`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md)
  now carry stratum columns through on both backends, driven by the new
  `strata_cols` field on
  [`tidycreel::creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html)
  ([\#171](https://github.com/chrischizinski/tidycreel.connect/issues/171)).
  The rename maps previously had no entry for a stratum and no schema
  field named one, so every other column of the source counts table was
  dropped — including the day-type label. A fetched counts frame
  therefore reached
  [`add_counts()`](https://chrischizinski.com/tidycreel/reference/add_counts.html)
  with no stratum, and any design built with `strata =` aborted with
  `Strata column(s) from design not found in count data`, making the
  documented handoff impossible for the ordinary stratified case. The
  caller had to re-join the label from the calendar by hand, which is
  the risky part: a wrong join is the same “information that existed
  upstream never reached the calculation” failure, but silent.

  On the CSV and SQL backends the source column name comes from the
  schema entry’s value. On the API backend it comes from
  `api_field_map`, keyed by the design-facing name, so raw JSON field
  names stay out of
  [`creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html);
  a stratum absent from the field map falls back to its own name.
  `strata_cols` is consequently the one schema field the API backend
  does read, and is exempt from the “schema column mappings are ignored”
  warning.

### Breaking changes

- **The API backend no longer ships any organisation’s contract.**
  [`creel_connect_api()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_api.md)
  now requires `uid_param`, `endpoints` and `api_field_map`, and aborts
  without them. Previously all three defaulted to one agency’s
  deployment: its query parameter, its endpoint paths and its raw JSON
  field names. Those defaults decoded that service’s payload and would
  silently misread any other, and they made the package look as though
  it were written for a single organisation. Nothing about a particular
  API belongs in a general-purpose package.

  Existing API calls must supply the three arguments. Keep them in a
  YAML profile outside your analysis code and load it with
  [`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md)
  (see below); pointing at a different profile is what lets the same
  script run against a different service.

- [`list_creels()`](https://chrischizinski.com/tidycreel.connect/reference/list_creels.md)
  reads discovery field names from `api_field_map$discovery` instead of
  a hardcoded set.

- [`summarize_by_zip()`](https://chrischizinski.com/tidycreel/reference/summarize_by_zip.html)
  and
  [`summarize_by_county()`](https://chrischizinski.com/tidycreel/reference/summarize_by_county.html)
  (in tidycreel) gain a `zip_col` argument, defaulting to `"zip_code"`,
  in place of a hardcoded raw field name.

### Statistical correctness

- [`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md)
  carries six further columns when they are mapped: `n_anglers`,
  `angler_type`, `site`, `circuit`, `n_counted` and `n_interviewed`
  ([\#126](https://github.com/chrischizinski/tidycreel.connect/issues/126)).
  None of them had an entry in either rename map, so they were discarded
  on the way through with nothing said. Two consequences, both silent:

  - Without `n_anglers`,
    [`tidycreel::add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html)
    falls back to one angler per interview, so party-hours are consumed
    as angler-hours and every rate denominator is wrong by the mean
    party size.
    [`mean_party_size()`](https://chrischizinski.com/tidycreel/reference/mean_party_size.html)
    and
    [`derive_angler_count()`](https://chrischizinski.com/tidycreel/reference/derive_angler_count.html)
    could not be fed from fetched data at all.
  - Without `site` and `circuit`, a bus-route design aborts at the
    inclusion probability join — the documented handoff to
    [`add_interviews()`](https://chrischizinski.com/tidycreel/reference/add_interviews.html)
    was impossible for the design family the package’s own fixture
    validates.

  CSV sources map them through
  [`creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html),
  including its new `site_col` and `circuit_col` arguments. API sources
  name them through `api_field_map`: which raw field holds a party size,
  a site or a circuit is a property of the source API, so no default
  names one.

- Every `fetch_*()` now reports the source columns it did not carry,
  naming them and the table they came from. The closed-map policy is
  unchanged — the defect was that a load-bearing column disappearing in
  transit looked exactly like an extra column nobody wanted.

- Optional columns are type-checked when present rather than accepted
  unexamined: a character `n_anglers` is now refused at the fetch
  boundary instead of failing inside the party-size arithmetic several
  stages later.

## tidycreel.connect 0.2.0

### Bug fixes and robustness improvements

- [`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md):
  guards against NULL/non-list config block after
  [`config::get()`](https://rstudio.github.io/config/reference/get.html);
  catches missing credential keys (not just empty strings); validates
  `survey_type` against known enum before calling
  [`creel_schema()`](https://chrischizinski.com/tidycreel/reference/creel_schema.html);
  wraps
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  in [`tryCatch()`](https://rdrr.io/r/base/conditions.html) to prevent
  password leaking into error tracebacks.
- [`creel_connect()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect.md):
  `creel_connect_csv()` now validates all 5 required path keys
  (`interviews`, `counts`, `catch`, `harvest_lengths`,
  `release_lengths`) before checking file existence, giving a clear
  error on missing keys.
- `.api_fetch()`: guards against NULL endpoint key with a clear error;
  wraps [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  for non-tabular API JSON responses; `.parse_api_date()` now strips ISO
  8601 timezone suffixes (`Z`, `+HH:MM`, `-HH:MM`) before parsing,
  preventing silent NA on timezone-aware timestamps.
- [`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md),
  [`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md),
  [`fetch_catch()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_catch.md),
  [`fetch_harvest_lengths()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_harvest_lengths.md),
  [`fetch_release_lengths()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_release_lengths.md):
  all [`as.numeric()`](https://rdrr.io/r/base/numeric.html) and
  [`as.Date()`](https://rdrr.io/r/base/as.Date.html) coercions on data
  columns now warn when values cannot be parsed rather than silently
  producing `NA` (via new `.coerce_numeric()` and `.coerce_date()`
  internal helpers).
- [`list_creels()`](https://chrischizinski.com/tidycreel.connect/reference/list_creels.md):
  missing discovery fields now trigger a warning and are filled with
  typed `NA` rather than silently producing a short-column data frame;
  return type unified to tibble across empty and non-empty responses.
- Validation (`fetch-validators`):
  [`switch()`](https://rdrr.io/r/base/switch.html) default now
  [`stop()`](https://rdrr.io/r/base/stop.html)s on unknown
  `expected_type` values rather than silently returning `TRUE`; UID
  columns (`interview_uid`, `catch_uid`, `length_uid`) use new `"uid"`
  type that accepts numeric or character (covers both synthesized
  row-index UIDs and UUID strings), replacing the unchecked `"any"`
  type.

## tidycreel.connect 0.1.0

### Initial release

- [`creel_connect()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect.md)
  — unified connection constructor for CSV and SQL Server (DBI/ODBC)
  backends. Accepts a `creel_schema` column-mapping contract and returns
  a `creel_connection` S3 object.
- [`creel_connect_from_yaml()`](https://chrischizinski.com/tidycreel.connect/reference/creel_connect_from_yaml.md)
  — YAML-based connection with fail-fast validation. Supports
  `backend: csv` and `backend: sqlserver`. Credentials injected via
  `config` package `!expr Sys.getenv()` tag.
- `auth_type` parameter — platform guard aborts immediately on
  macOS/Linux when `auth_type: windows` is requested, with actionable
  install instructions.
- [`fetch_interviews()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_interviews.md),
  [`fetch_counts()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_counts.md),
  [`fetch_catch()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_catch.md),
  [`fetch_harvest_lengths()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_harvest_lengths.md),
  [`fetch_release_lengths()`](https://chrischizinski.com/tidycreel.connect/reference/fetch_release_lengths.md)
  — S3-dispatched data loaders for CSV and SQL Server backends. All
  coerce date columns to `Date` and species codes to `character`
  regardless of source type.
- [`creel_check_driver()`](https://chrischizinski.com/tidycreel.connect/reference/creel_check_driver.md)
  — diagnostic helper that lists installed ODBC drivers and confirms a
  SQL Server driver is available.
- Getting-started vignette covering YAML config, schema setup, both
  backends, and credential security.
- Platform-specific ODBC driver install instructions in README (Windows,
  macOS, Linux).
