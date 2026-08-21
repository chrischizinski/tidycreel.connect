# tidycreel.connect 0.3.0

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
