# tidycreel.connect (development version)

## Bug fixes

* The API backend follows pagination, and refuses a response it can prove is
  only part of the data (#330).

  `.api_fetch()` performed one request and returned its body as the complete
  dataset. Against a paginated endpoint that meant page 1 and nothing else:
  fewer interviews and fewer counts reached the design, every total was
  understated in proportion to what was dropped, and nothing errored or warned.
  Measured on a mocked three-page endpoint holding five interviews, the fetch
  returned **two** of them and **4 of 10 effort-hours** — 60% of the effort
  missing, with a believable number in its place.

  `creel_connect_api()` takes a new optional `pagination` argument, also
  settable as a `pagination:` block in a YAML profile. Its `style` is one of
  `"page"` (a page number in the query string), `"offset"` (a row offset, which
  advances by the rows actually received rather than an assumed page size),
  `"link"` (an RFC 8288 `Link` header with `rel="next"`), or `"none"`. A
  declared style is followed to exhaustion.

  Like `endpoints` and `api_field_map`, pagination describes one deployment, so
  nothing is assumed. What is no longer left to the caller is a truncated
  result: with no style declared, a response carrying a `Link` header offering
  a next page, or an `X-Total-Count` larger than the rows returned, now aborts
  rather than being read as the whole dataset. A connection against an
  unpaginated API is unaffected.

  Three ways a paging loop can go wrong also abort rather than return a wrong
  number: two consecutive pages of identical rows (the API is ignoring the
  paging parameter, and binding them would duplicate every record), pages
  describing different fields (binding would align values under the wrong
  names), and `max_pages` being reached (the pages collected so far are *not*
  returned, because a partial dataset understates every total without saying
  so).

  Two settings that would silently disagree are also refused at connection
  time: a paging parameter named the same as `uid_param` (httr2 replaces rather
  than appends, so the paging value would overwrite the survey filter and an
  API reading a missing filter as "every survey" would return other surveys'
  rows), and two paging settings naming the same parameter.

  A cursor style is deliberately not supported: a cursor arrives in a response
  envelope, which this backend does not read. It is refused by name rather than
  accepted and silently reduced to page 1.

## New features

* The DBI backend loads data (#185). SQL Server via ODBC works, and so does any
  other DBI driver.

  Until now a database connection opened, reported itself open, and aborted on
  every `fetch_*()` call. Each fetcher now reads its table by the name the
  schema gives it and puts the rows through the same rename, coercion,
  value-map and validation stages the CSV backend uses — the read is the only
  backend-specific step, so a frame fetched from a database and the same rows
  fetched from CSV come back identical, which the tests assert directly.

  Table names come from `interviews_table`, `counts_table`, `catch_table` and
  `harvest_lengths_table` / `release_lengths_table`. A table the schema does
  not name is refused, naming the setting that is missing: unlike a column,
  there is no canonical table name to fall back on, and guessing would mean
  querying whatever happened to match.

  A table name may be a string or a `DBI::Id()`. `Id()` is what reaches a
  schema-qualified table — `DBI::Id(schema = "dbo", table = "vwInterviews")` —
  since the string `"dbo.vwInterviews"` is one literal name and is not found.

* Database connections now carry the class `creel_connection_dbi`, with
  `creel_connection_sqlserver` kept alongside it (#185). Nothing in the read
  path is SQL Server specific — the test suite exercises it on duckdb — so the
  methods live on the general name. The old name stays in the class vector and
  every method is registered for it too, so existing code that dispatches on it
  is unaffected.

## Breaking changes

* `list_creels()` and `search_creels()` still abort on a database connection,
  but now as a statement rather than a placeholder, with the condition class
  `creel_error_discovery_unavailable` (#185).

  Discovery asks a source which surveys it holds. A database connection is
  already pointed at one set of tables and has no catalogue to enumerate
  without inventing a convention for how an agency names or partitions surveys
  — exactly the organisation-specific knowledge this package does not carry.
  The previous wording, "not supported", read as "not yet" and invited an
  implementation that cannot exist. Use the API backend, whose service defines
  discovery.

## Bug fixes

* A YAML profile setting `harvest_lengths_table` or `release_lengths_table`
  aborted with R's bare "unused arguments" error, naming no cause (#185). The
  loader has offered both keys since #176 and passed them to
  `tidycreel::creel_schema()`, which accepted neither. Both are now schema
  arguments and fall back to `lengths_table`.

* `test-composition-calamus.R` asserted a catch-total SE of 55.7239 for the
  unfiltered fixture, and had been failing since #198 (#185). #198 moved
  bus-route variance onto the day PSU and re-baselined
  `reference-outputs.csv`, but this sibling assertion was missed.

  The behaviour is correct: the two incomplete rows are both zero-catch and
  fall on the same date, so admitting them changes no day's total and the SE
  does not move. The test now asserts that, and additionally gives those rows a
  catch and requires the SE to move — otherwise it would keep passing if the
  variance stopped responding to the data at all.

# tidycreel.connect 0.4.0

## New features

* A YAML profile can declare what the source's columns are called, under a new
  `columns:` block inside `schema:` (#176). The CSV backend resolves every
  canonical column through the schema, so before this a profile only worked
  against a source whose columns already carried tidycreel's names — the one
  case where a schema is not needed at all. Keys are canonical names with no
  `_col` suffix, matching the way `value_maps` is keyed:

  ```yaml
  schema:
    survey_type: instantaneous
    columns:
      interview_uid: InterviewID
      date: SurveyDate
  ```

  A key that is not a canonical column name aborts and names itself, as does
  one written with the `_col` suffix. `backend: api` reads raw JSON keys from
  `field_map` and ignores column mappings, so a `columns:` block there is an
  error rather than a silent no-op. `backend: sqlserver` accepts the block, but
  its loaders are not implemented (see below), so nothing reads it yet.

* A commented CSV profile template ships alongside the API one, at
  `system.file("extdata", "csv-profile-example.yml", package = "tidycreel.connect")`.
  Every column name in it is invented; the package ships none for any
  organisation's export.

* A source that already uses tidycreel's canonical column names no longer needs
  a schema entry for each of them (#168). `fetch_*()` falls back to the
  canonical name when nothing is mapped — the same fallback the strata columns
  already used on the API path — so an already-canonical export loads with
  `creel_schema(survey_type = ...)` alone. Before this, loading a column named
  `date` required writing `date_col = "date"`, which made the one case that
  needs no schema the case that still needed one.

  The columns taken that way are named in a message, because an undeclared
  column is one the caller has not asserted the meaning of. Declaring it
  silences that.

  An entry naming a column the source does not have is **not** rescued by a
  canonically-named one. It stays a drop and is reported as such: a mapping that
  does not match the source is a configuration error, and substituting a
  different column would hide it.

  This narrows the guarantee added in #126, deliberately. That change made an
  unmapped optional column absent rather than `NA`, so that absence could mean
  "this source does not record party size". Absence still means that — but a
  source that records party size in a column called `n_anglers` now has it
  carried through instead of dropped, because dropping a column sitting in plain
  sight under its own canonical name is the failure #126 existed to prevent:
  without `n_anglers`, `add_interviews()` falls back to one angler per interview
  and party-hours are consumed as angler-hours. A column recorded under the
  source's own name is still never guessed at.

## Documentation

* The docs said connections are read-only nowhere, so a user pointed at an
  agency's production database had to read the source to establish it (#169).
  `?creel_connect`, `?creel_connect_api` and the getting-started vignette now
  state it: no table is created, altered, dropped or written to, no row is
  inserted or updated, and no file is written — including the CSV files a
  connection reads. The API backend issues `GET` requests only.

* **The SQL Server backend was described as working, and is not.** All five of
  its `fetch_*()` methods are stubs that abort with "not yet implemented", as do
  `list_creels()` and `search_creels()`, while `DESCRIPTION`, the README and the
  vignette all listed it as a supported source of data. Those now say plainly
  that a SQL Server connection can be constructed but not fetched from. New
  tests pin the five stubs so implementing them fails the tests that describe
  them as missing.

* The README's CSV example built a `creel_schema()` object that it then never
  passed to anything — the #176 gap in miniature. It now shows the mapping
  where it belongs, in the profile's `columns:` block.

## Bug fixes

* A fetch that mapped no columns at all reached its `validate_fetch_*()` abort
  behind two tibble deprecation warnings, because the empty rename set names to
  `NULL`. The abort is unchanged — it is the one that names every required
  column — and now arrives on its own.

# tidycreel.connect 0.3.0

## New features

* The fetch layer translates coded source vocabularies into the canonical ones,
  driven by the new `value_maps` field on `tidycreel::creel_schema()` (#128).
  A source that writes `"1"`/`"2"` for trip status, or `"H"`/`"R"` for catch
  type, declares what its codes mean once in the schema; `fetch_interviews()`,
  `fetch_catch()` and both lengths fetchers then deliver `"complete"`,
  `"harvested"` and the rest — the literals every downstream filter matches.

  Values already canonical for the column pass through untouched, so a source
  mid-migration that codes only some of its rows still arrives whole. A value
  that is neither mapped nor canonical **aborts at the fetch**, naming the
  offending value. The design layer does refuse an unknown vocabulary
  (`validate_trip_metadata()`, `add_catch()`), so this is not what stops a wrong
  number; what it stops is the hand recode that abort otherwise invites, which
  folds an undeclared third code (`"refused"`, `"unknown"`) into whichever of
  the two the caller happened to think of, silently.

  Declaring a map is opt-in and backend-independent: a schema without one
  fetches exactly as before, and the API path reads `value_maps` just as the CSV
  path does, since it maps a column's *values* rather than its field name.

* The ingestion seam is now covered end to end (#130). `test-composition-calamus.R`
  composes the whole path — CSV → `fetch_*()` → `creel_design()` →
  `add_counts()`/`add_interviews()` → estimators — and asserts the result against
  `inst/extdata/calamus-2016/reference-outputs.csv` in tidycreel. Every previous
  test in this package checked a fetched frame's columns, types and values and
  stopped there, which is why #126 through #129 all shipped undetected: each was
  a column that existed upstream and never reached the calculation, and a
  column-level test cannot see that. Standard errors are asserted alongside the
  point estimates, because that is where a dropped component hides.

  All three estimands and all three standard errors now reproduce. `catch_total`'s
  SE at first did not (52.9963 computed against 55.7239 recorded) with its point
  estimate identical, and was held as an explicit skip rather than absorbed into
  a tolerance while #178 established why. It was the reference that was stale:
  v3.0.0 put the bus-route catch total behind `br_complete_trips_only()` and the
  v1.7.0 file predates that. The reference row is re-baselined in tidycreel and
  the skip is replaced by a test that asserts the mechanism — that relabelling
  the fixture's two zero-catch incomplete rows recovers the pre-v3.0.0 SE exactly
  while leaving the point estimate where it was.

* A synthetic boat-count fixture makes the boat→angler seam reachable (#130).
  Every real fixture in the repo is a bank-only fishery, so
  `derive_angler_count()`'s reconstruction path could not be exercised end to
  end. `inst/extdata/synthetic-boat-counts/` is fabricated and says so; it is
  used to assert the seam only — that boat counts survive the fetch and change
  the estimate by exactly `sum(angler_boats) × party_size` — never against a
  reference value, because invented counts validate nothing.

  Exercised on an instantaneous design deliberately: on a bus-route design
  effort comes from the interview-side Horvitz–Thompson estimator, so the counts
  table never enters `estimate_effort()` and bank-only and reconstructed counts
  return the identical total — a seam test built there would pass whatever the
  fetch layer did.

* `creel_connect_from_yaml()` accepts `backend: api`, reading `base_url`,
  `uid_param`, `creel_uids`, `endpoints` and `field_map` from the profile.

* A commented template profile ships with the package, with every name
  invented:
  ```r
  system.file("extdata", "api-profile-example.yml", package = "tidycreel.connect")
  ```

* `fetch_*()` aborts with a clear message when the connection describes no
  endpoint path, or no field names, for the endpoint being fetched -- rather
  than fetching and then discarding every column, which surfaced as a
  "column missing" validation error pointing nowhere near the cause.

## Bug fixes

* The dependency on tidycreel is now declared as `tidycreel (>= 5.0.0)` rather
  than left unversioned. `fetch_*()` calls `tidycreel::creel_vocabulary()`, which
  tidycreel first exported in 5.0.0, so against an older tidycreel the package
  installed cleanly and then aborted at run time with `'creel_vocabulary' is not
  an exported object from 'namespace:tidycreel'` -- and only on the value-map
  path, so everything else looked fine. `derive_angler_count()` is a quieter case
  of the same coupling: 5.0.0 made it drop the columns it consumed, and against
  4.0.0 those columns survive with no error at all.

  Nothing could have caught this. The check workflow installs tidycreel with
  `local::..`, from the repo root at the same commit, so connect is only ever
  tested against the tidycreel beside it and no version skew is reachable in CI.
  The documented install path in `README.md` takes both packages from the default
  branch and stays consistent; the break needs an older tidycreel already
  installed and an `install_github()` of connect alone, which `remotes` will not
  upgrade precisely because no version was required.

* `fetch_counts()` now carries the time of a count, and says so when it cannot
  (#129). A count row is one observation at one moment, not a day's total, and
  a source that records several counts per sampled day distinguishes them by
  time alone. No schema field could name that time and neither counts rename
  map carried it, so the rows arrived indistinguishable: `add_counts()` read
  them as separate sampled days, summing the day's effort instead of averaging
  it to a daily mean, and the within-day variance component was never computed.
  On a two-counts-per-day fixture the effort estimate came out at twice its
  value, with `se_within` reported as `0` where the component had simply never
  been calculated.

  `add_counts()` did warn (CNT-06) and told the caller to supply
  `count_time_col` — a column the fetch layer had just dropped, so the advice
  could not be followed from a fetched frame. Map `count_time_col` (CSV/SQL) or
  the `count_time` field (API field map), and `fetch_counts()` now warns when it
  returns repeat rows on a date and no count time was mapped, keyed on date plus
  strata the way `add_counts()` keys its own sampling unit — two sections
  counted on one day are two units, not a repeat.

  The column is carried as written. `readr` reads `"16:30"` as a time and hands
  back `"16:30:00"`, so a mapped count time is now read as character: the fetch
  must not reinterpret a label whose format belongs to the source.

* `fetch_counts()` documentation no longer recommends `count_col = bank_anglers`
  as the runnable example (#129). On any fishery with boat anglers that silently
  omits an entire component of effort. The example now uses
  `tidycreel::derive_angler_count()`, which #126 made available, and the
  documented return value lists the stratum columns `fetch_counts()` has carried
  since #171.

* `fetch_harvest_lengths()` and `fetch_release_lengths()` now carry a length-bin
  label and its fish count (#127). A source that reports released fish as length
  groups has two quantities per row — the bin and the number of fish in it — and
  the fetch layer carried neither: there was no canonical count column anywhere
  in the package, and the only place to put a label was `length_mm`, where
  `as.numeric()` turned "300-350" into `NA`. A distribution built from a fetched
  binned frame was therefore weighted by **row multiplicity rather than by
  fish**, biasing released length frequencies, mean length, and the biomass of
  released fish toward the bins a crew happened to record most often. Nothing
  errored and nothing warned; the numbers looked ordinary. Bins holding 1 and 5
  fish now total 6, where they previously totalled 2.

  Map `length_bin_col` and `length_count_col` on `tidycreel::creel_schema()` for
  CSV and SQL sources, or `length_bin` and `count` in `api_field_map` for the
  API backend, then pass the fetched `length_bin` as `add_lengths()`'s `length`
  with `release_format = "binned"`. Both are optional and both tables accept
  them, so a source that measures every fish is unaffected. Carrying a bin with
  no count now warns at the fetch, and a lengths table offering neither a
  measurement nor a bin is refused rather than returned empty-handed.

* A YAML profile can now declare `strata_cols` and `value_maps`. The loader
  built its schema from `survey_type` and table names alone, so neither field
  survived the profile — the route the docs recommend for configuring a
  deployment. A profile-configured survey therefore could not be stratified at
  all: the counts frame arrived with no stratum label and any design built with
  `strata =` aborted, which is the failure #171 fixed for a hand-built schema
  and left standing here. Both YAML shapes of `strata_cols` are accepted, the
  mapping `day_type: DayTypeCode` and the bare sequence `[day_type]`.

* `fetch_counts()` and `fetch_interviews()` now carry stratum columns through
  on both backends, driven by the new `strata_cols` field on
  `tidycreel::creel_schema()` (#171). The rename maps previously had no entry
  for a stratum and no schema field named one, so every other column of the
  source counts table was dropped — including the day-type label. A fetched
  counts frame therefore reached `add_counts()` with no stratum, and any design
  built with `strata =` aborted with `Strata column(s) from design not found in
  count data`, making the documented handoff impossible for the ordinary
  stratified case. The caller had to re-join the label from the calendar by
  hand, which is the risky part: a wrong join is the same "information that
  existed upstream never reached the calculation" failure, but silent.

  On the CSV and SQL backends the source column name comes from the schema
  entry's value. On the API backend it comes from `api_field_map`, keyed by the
  design-facing name, so raw JSON field names stay out of `creel_schema()`; a
  stratum absent from the field map falls back to its own name. `strata_cols`
  is consequently the one schema field the API backend does read, and is
  exempt from the "schema column mappings are ignored" warning.

## Breaking changes

* **The API backend no longer ships any organisation's contract.**
  `creel_connect_api()` now requires `uid_param`, `endpoints` and
  `api_field_map`, and aborts without them. Previously all three defaulted to
  one agency's deployment: its query parameter, its endpoint paths and its raw
  JSON field names. Those defaults decoded that service's payload and would
  silently misread any other, and they made the package look as though it were
  written for a single organisation. Nothing about a particular API belongs in a
  general-purpose package.

  Existing API calls must supply the three arguments. Keep them in a YAML
  profile outside your analysis code and load it with
  `creel_connect_from_yaml()` (see below); pointing at a different profile is
  what lets the same script run against a different service.

* `list_creels()` reads discovery field names from `api_field_map$discovery`
  instead of a hardcoded set.

* `summarize_by_zip()` and `summarize_by_county()` (in tidycreel) gain a
  `zip_col` argument, defaulting to `"zip_code"`, in place of a hardcoded raw
  field name.

## Statistical correctness

* `fetch_interviews()` carries six further columns when they are mapped:
  `n_anglers`, `angler_type`, `site`, `circuit`, `n_counted` and
  `n_interviewed` (#126). None of them had an entry in either rename map, so
  they were discarded on the way through with nothing said. Two consequences,
  both silent:

  - Without `n_anglers`, `tidycreel::add_interviews()` falls back to one angler
    per interview, so party-hours are consumed as angler-hours and every rate
    denominator is wrong by the mean party size. `mean_party_size()` and
    `derive_angler_count()` could not be fed from fetched data at all.
  - Without `site` and `circuit`, a bus-route design aborts at the inclusion
    probability join — the documented handoff to `add_interviews()` was
    impossible for the design family the package's own fixture validates.

  CSV sources map them through `creel_schema()`, including its new `site_col`
  and `circuit_col` arguments. API sources name them through `api_field_map`:
  which raw field holds a party size, a site or a circuit is a property of the
  source API, so no default names one.

* Every `fetch_*()` now reports the source columns it did not carry, naming
  them and the table they came from. The closed-map policy is unchanged — the
  defect was that a load-bearing column disappearing in transit looked exactly
  like an extra column nobody wanted.

* Optional columns are type-checked when present rather than accepted
  unexamined: a character `n_anglers` is now refused at the fetch boundary
  instead of failing inside the party-size arithmetic several stages later.

# tidycreel.connect 0.2.0

## Bug fixes and robustness improvements

* `creel_connect_from_yaml()`: guards against NULL/non-list config block after
  `config::get()`; catches missing credential keys (not just empty strings);
  validates `survey_type` against known enum before calling `creel_schema()`;
  wraps `DBI::dbConnect()` in `tryCatch()` to prevent password leaking into
  error tracebacks.
* `creel_connect()`: `creel_connect_csv()` now validates all 5 required path
  keys (`interviews`, `counts`, `catch`, `harvest_lengths`, `release_lengths`)
  before checking file existence, giving a clear error on missing keys.
* `.api_fetch()`: guards against NULL endpoint key with a clear error; wraps
  `as.data.frame()` for non-tabular API JSON responses; `.parse_api_date()`
  now strips ISO 8601 timezone suffixes (`Z`, `+HH:MM`, `-HH:MM`) before
  parsing, preventing silent NA on timezone-aware timestamps.
* `fetch_interviews()`, `fetch_counts()`, `fetch_catch()`,
  `fetch_harvest_lengths()`, `fetch_release_lengths()`: all `as.numeric()` and
  `as.Date()` coercions on data columns now warn when values cannot be parsed
  rather than silently producing `NA` (via new `.coerce_numeric()` and
  `.coerce_date()` internal helpers).
* `list_creels()`: missing discovery fields now trigger a warning and are filled
  with typed `NA` rather than silently producing a short-column data frame;
  return type unified to tibble across empty and non-empty responses.
* Validation (`fetch-validators`): `switch()` default now `stop()`s on unknown
  `expected_type` values rather than silently returning `TRUE`; UID columns
  (`interview_uid`, `catch_uid`, `length_uid`) use new `"uid"` type that
  accepts numeric or character (covers both synthesized row-index UIDs and UUID
  strings), replacing the unchecked `"any"` type.

# tidycreel.connect 0.1.0

## Initial release

* `creel_connect()` — unified connection constructor for CSV and SQL Server
  (DBI/ODBC) backends. Accepts a `creel_schema` column-mapping contract and
  returns a `creel_connection` S3 object.
* `creel_connect_from_yaml()` — YAML-based connection with fail-fast
  validation. Supports `backend: csv` and `backend: sqlserver`. Credentials
  injected via `config` package `!expr Sys.getenv()` tag.
* `auth_type` parameter — platform guard aborts immediately on macOS/Linux
  when `auth_type: windows` is requested, with actionable install instructions.
* `fetch_interviews()`, `fetch_counts()`, `fetch_catch()`,
  `fetch_harvest_lengths()`, `fetch_release_lengths()` — S3-dispatched data
  loaders for CSV and SQL Server backends. All coerce date columns to
  `Date` and species codes to `character` regardless of source type.
* `creel_check_driver()` — diagnostic helper that lists installed ODBC drivers
  and confirms a SQL Server driver is available.
* Getting-started vignette covering YAML config, schema setup, both backends,
  and credential security.
* Platform-specific ODBC driver install instructions in README (Windows,
  macOS, Linux).
