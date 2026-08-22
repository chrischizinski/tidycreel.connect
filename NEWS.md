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

  Two of the three estimands and two of the three standard errors reproduce
  bit-for-bit. `catch_total`'s SE does not (52.9963 computed against 55.7239
  recorded) with its point estimate identical; that is filed as #178 and left as
  an explicit skip rather than absorbed into a tolerance, and the reference file
  has deliberately not been regenerated to match current output.

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

## Bug fixes

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

## New features

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
