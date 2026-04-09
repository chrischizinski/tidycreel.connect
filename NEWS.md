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
